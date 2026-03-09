#!/bin/bash
# pkgbuild.sh — полный пример использования pkgbuild для создания macOS .pkg
#
# pkgbuild входит в Xcode Command Line Tools (macOS native), доп. установка не нужна.
# Создаёт компонентные .pkg файлы для:
#   - тихой установки в CI/CD
#   - корпоративного деплоя через MDM
#   - объединения через productbuild в финальный дистрибутивный пакет
#
# ВНИМАНИЕ: pkgbuild работает ТОЛЬКО на macOS (нативный инструмент Apple).
#
# Полный workflow:
#   pkgbuild → component.pkg → productbuild → installer.pkg → notarytool → stapler
#
# Использование:
#   chmod +x pkgbuild.sh && ./pkgbuild.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e  # прерваться при любой ошибке
set -u  # ошибка при использовании неинициализированной переменной

# ═══════════════════════════════════════════════════════════════════════════════
# КОНФИГУРАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════

APP_NAME="myapp"
VERSION="1.2.3"
ARCH="${ARCH:-arm64}"  # arm64 или amd64 (можно передать через переменную окружения)

# Обратный DNS-идентификатор пакета.
# ПРАВИЛО: стабилен между версиями — одинаков для 1.0, 2.0, 3.0.
# macOS использует его для проверки установленных пакетов (pkgutil --info).
IDENTIFIER="com.powertech.${APP_NAME}.pkg"

# Исходный бинарник (результат Go-сборки)
BINARY_SRC="dist/${APP_NAME}-darwin-${ARCH}"

# Выходной .pkg файл
PKG_OUTPUT="dist/${APP_NAME}-darwin-${ARCH}.pkg"

# Временные директории (очищаются в конце)
PAYLOAD_DIR="/tmp/${APP_NAME}-pkg-payload"
SCRIPTS_DIR="/tmp/${APP_NAME}-pkg-scripts"
COMPONENT_PKG="/tmp/${APP_NAME}-component.pkg"

# ═══════════════════════════════════════════════════════════════════════════════
# ПОДГОТОВКА PAYLOAD
# ═══════════════════════════════════════════════════════════════════════════════
#
# Payload — дерево файлов, которое будет скопировано на диск.
# ВАРИАНТ 1: структура соответствует абсолютным путям (--install-location /)
#   payload/usr/local/bin/myapp → установится в /usr/local/bin/myapp
#   payload/etc/myapp/config.yaml → установится в /etc/myapp/config.yaml
#
# ВАРИАНТ 2: структура для конкретной директории (--install-location /usr/local/bin)
#   payload/myapp → установится в /usr/local/bin/myapp

echo "Preparing payload for ${APP_NAME} ${VERSION} (${ARCH})..."

# Создать структуру, соответствующую абсолютным путям (Вариант 1)
mkdir -p "${PAYLOAD_DIR}/usr/local/bin"
mkdir -p "${PAYLOAD_DIR}/usr/share/doc/${APP_NAME}"
mkdir -p "${PAYLOAD_DIR}/usr/share/man/man1"
mkdir -p "${PAYLOAD_DIR}/etc/${APP_NAME}"
mkdir -p "${PAYLOAD_DIR}/var/lib/${APP_NAME}"
mkdir -p "${PAYLOAD_DIR}/var/log/${APP_NAME}"

# Основной бинарник
cp "${BINARY_SRC}" "${PAYLOAD_DIR}/usr/local/bin/${APP_NAME}"

# Права файлов устанавливаются ДО упаковки.
# pkgbuild с --ownership recommended:
#   - системные пути (/usr, /etc) → root:wheel автоматически
#   - 755 для бинарников, 644 для конфигов
chmod 755 "${PAYLOAD_DIR}/usr/local/bin/${APP_NAME}"

# Документация
if [ -f "README.md" ]; then
  cp "README.md" "${PAYLOAD_DIR}/usr/share/doc/${APP_NAME}/README.md"
  chmod 644 "${PAYLOAD_DIR}/usr/share/doc/${APP_NAME}/README.md"
fi

# Man-страница (сжатая)
if [ -f "man/${APP_NAME}.1" ]; then
  gzip -c "man/${APP_NAME}.1" > "${PAYLOAD_DIR}/usr/share/man/man1/${APP_NAME}.1.gz"
  chmod 644 "${PAYLOAD_DIR}/usr/share/man/man1/${APP_NAME}.1.gz"
fi

# Конфигурационный файл по умолчанию
cat > "${PAYLOAD_DIR}/etc/${APP_NAME}/config.yaml" << 'EOF'
# Default configuration for myapp
output_dir: ./dist
verbose: false
EOF
chmod 644 "${PAYLOAD_DIR}/etc/${APP_NAME}/config.yaml"

# Права на директории данных
# ВАЖНО: pkgbuild с --ownership recommended назначит root:wheel для системных путей.
# Для кастомного владельца нужно использовать --ownership preserve и явно задать uid/gid,
# или менять права в postinstall скрипте.
chmod 755 "${PAYLOAD_DIR}/var/lib/${APP_NAME}"
chmod 755 "${PAYLOAD_DIR}/var/log/${APP_NAME}"


# ═══════════════════════════════════════════════════════════════════════════════
# ПОДГОТОВКА СКРИПТОВ
# ═══════════════════════════════════════════════════════════════════════════════
#
# preinstall  — выполняется ДО копирования файлов (с правами root)
# postinstall — выполняется ПОСЛЕ копирования файлов (с правами root)
#
# Аргументы при вызове скрипта:
#   $1 — полный путь к .pkg файлу
#   $2 — полный путь к директории назначения (install-location, обычно /)
#   $3 — полный путь к тому (обычно /, иногда /Volumes/ExtDisk)
#   $4 — имя скрипта (preinstall или postinstall)
#
# ВАЖНО: скрипты выполняются без пользовательского окружения.
#   Нельзя использовать: $HOME, ~, пользовательский $PATH, переменные .bashrc
#   Используйте абсолютные пути: /usr/local/bin/myapp, /bin/bash, /usr/bin/env

mkdir -p "${SCRIPTS_DIR}"

# ── preinstall ──────────────────────────────────────────────────────────────
cat > "${SCRIPTS_DIR}/preinstall" << 'PREINSTALL'
#!/bin/bash
# Выполняется ДО копирования файлов.
# Код возврата != 0 → установка прерывается.
set -e

PACKAGE_PATH="$1"     # путь к .pkg (информационно)
INSTALL_LOCATION="$2" # директория назначения (обычно /)
TARGET_VOLUME="$3"    # том (обычно /)

echo "Starting preinstall for myapp..."

# Остановить запущенный процесс (если есть)
if pgrep -x "myapp" > /dev/null 2>&1; then
    echo "Stopping running myapp process..."
    pkill -x "myapp" || true
    sleep 1
fi

# Проверить наличие системных зависимостей
if ! command -v curl >/dev/null 2>&1; then
    echo "Warning: curl not found, some features may not work"
fi

exit 0
PREINSTALL
chmod 755 "${SCRIPTS_DIR}/preinstall"

# ── postinstall ─────────────────────────────────────────────────────────────
cat > "${SCRIPTS_DIR}/postinstall" << 'POSTINSTALL'
#!/bin/bash
# Выполняется ПОСЛЕ копирования файлов.
# Код возврата != 0 → предупреждение, но файлы уже установлены.
set -e

PACKAGE_PATH="$1"
INSTALL_LOCATION="$2"
TARGET_VOLUME="$3"

# Итоговые пути (TARGET_VOLUME обычно "/")
BINARY="${TARGET_VOLUME}usr/local/bin/myapp"
CONFIG_DIR="${TARGET_VOLUME}etc/myapp"
DATA_DIR="${TARGET_VOLUME}var/lib/myapp"
LOG_DIR="${TARGET_VOLUME}var/log/myapp"

echo "Running postinstall for myapp..."

# Убедиться что бинарник исполняемый
if [ -f "${BINARY}" ]; then
    chmod 755 "${BINARY}"
    echo "Binary installed: ${BINARY}"
fi

# Настроить права на директории (если нужен специфичный владелец)
# chmod 750 "${DATA_DIR}"
# chown myapp:myapp "${DATA_DIR}" 2>/dev/null || true  # может не работать без создания пользователя

# Очистить кеш для command lookup (обновить базу команд)
if [ -x "/usr/bin/mandb" ]; then
    /usr/bin/mandb -q 2>/dev/null || true
fi

echo "myapp ${VERSION} installed successfully!"
echo "Run 'myapp --help' to get started."

exit 0
POSTINSTALL
chmod 755 "${SCRIPTS_DIR}/postinstall"


# ═══════════════════════════════════════════════════════════════════════════════
# COMPONENT PLIST (опционально, для приложений-бандлов)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Component plist описывает поведение .app/.framework/.plugin бандлов при установке.
# Для консольных утилит (просто бинарник) — не нужен.
#
# Генерация шаблона:
#   pkgbuild --analyze --root payload/ components.plist
#
# Ключевые параметры:
#   RootRelativeBundlePath — путь к бандлу относительно root (обязателен)
#   BundleIsRelocatable    — разрешить пользователю перемещать приложение (bool)
#   BundleIsVersionChecked — не устанавливать если установлена более новая версия (bool)
#   BundleHasStrictIdentifier — строгое совпадение Bundle ID (bool)
#   BundleOverwriteAction  — поведение при перезаписи:
#                             upgrade (только если новее), downgrade (только если старее),
#                             newer (новее или одинаково), root (всегда перезаписывать)
#
# Пример components.plist для .app:
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <array>
#   <dict>
#     <key>RootRelativeBundlePath</key>
#     <string>Applications/MyApp.app</string>
#     <key>BundleIsRelocatable</key>
#     <false/>
#     <key>BundleIsVersionChecked</key>
#     <true/>
#     <key>BundleHasStrictIdentifier</key>
#     <true/>
#     <key>BundleOverwriteAction</key>
#     <string>upgrade</string>
#   </dict>
# </array>
# </plist>


# ═══════════════════════════════════════════════════════════════════════════════
# СБОРКА КОМПОНЕНТНОГО ПАКЕТА (pkgbuild)
# ═══════════════════════════════════════════════════════════════════════════════

echo "Building component package..."

pkgbuild \
    \
    --root "${PAYLOAD_DIR}" \
    \
    --identifier "${IDENTIFIER}" \
    \
    --version "${VERSION}" \
    \
    --install-location "/" \
    \
    --scripts "${SCRIPTS_DIR}" \
    \
    --ownership "recommended" \
    \
    --filter '\.DS_Store$' \
    --filter '.*\.dSYM$' \
    --filter '.*\.o$' \
    --filter '.*__pycache__.*' \
    \
    "${COMPONENT_PKG}"

# Описание флагов pkgbuild:
#
# --root <path>
#   Корневая директория с файлами для установки.
#   Структура директории соответствует итоговой структуре на диске.
#
# --component <path>
#   Альтернатива --root для одиночного бандла (.app, .framework, .plugin).
#   Используется когда нужно упаковать одно приложение с его bundle-структурой.
#
# --identifier <id>
#   Уникальный идентификатор в обратном DNS-формате: com.company.product.pkg
#   Стабилен между версиями (1.0, 2.0, 3.0 — один идентификатор).
#   macOS использует его для: pkgutil --info, проверки установленных пакетов.
#
# --version <version>
#   Версия пакета. Используется macOS для версионирования при обновлении.
#
# --install-location <path>
#   Директория назначения. Обычно "/" для абсолютного layout payload.
#   Или "/usr/local/bin" для простого layout с одним бинарником.
#
# --scripts <dir>
#   Директория со скриптами preinstall и postinstall.
#   Файлы должны быть исполняемыми (chmod 755).
#
# --component-plist <plist>
#   XML plist для описания поведения бандлов (только для .app/.framework/.plugin).
#   Генерируется командой: pkgbuild --analyze --root <root> output.plist
#
# --nopayload
#   Создать пакет только со скриптами, без файлов.
#   Полезно для настройки системы: создание symlink, настройка PATH и т.д.
#
# --filter <regex>
#   Исключить файлы, соответствующие регулярному выражению.
#   Можно указывать несколько раз. Применяется к относительному пути в payload.
#
# --ownership <mode>
#   recommended     — системные пути → root:wheel, /Users → текущий пользователь.
#                     Рекомендуется для большинства случаев.
#   preserve        — копировать точные uid/gid с диска.
#                     Проблема: uid/gid могут отличаться на разных машинах.
#   preserve-other  — recommended для своих файлов, preserve для остальных.
#
# --sign <identity>
#   Подписать пакет. Для дистрибуции: "Developer ID Installer: Name (TEAM_ID)"
#   Требует наличия сертификата в keychain.
#   ВАЖНО: всегда добавлять --timestamp при подписи!
#
# --keychain <path>
#   Альтернативный keychain для поиска сертификата.
#   Полезно в CI/CD: pkgbuild --keychain ci.keychain --sign "..."
#
# --timestamp
#   Добавить временную метку Apple (Secure Timestamp).
#   Обязательно при подписи — без неё подпись станет невалидной
#   после истечения сертификата.
#
# --quiet
#   Подавить вывод статуса (полезно в CI/CD для чистых логов).

echo "Component package created: ${COMPONENT_PKG}"


# ═══════════════════════════════════════════════════════════════════════════════
# ОПЦИОНАЛЬНО: СБОРКА ФИНАЛЬНОГО ДИСТРИБУТИВНОГО ПАКЕТА (productbuild)
# ═══════════════════════════════════════════════════════════════════════════════
#
# productbuild объединяет компонентные пакеты в финальный installer.pkg
# с wizard-интерфейсом, лицензией, фоном и т.д.
# Для консольных утилит обычно используется напрямую component.pkg.
#
# Шаг 1: Синтезировать distribution.xml из компонентного пакета:
#   productbuild --synthesize --package myapp-component.pkg distribution.xml
#
# Шаг 2 (опционально): Отредактировать distribution.xml (см. ниже)
#
# Шаг 3: Собрать финальный пакет:
#   productbuild \
#       --distribution distribution.xml \
#       --resources resources/ \      # директория с фоном, лицензией, readme
#       --package-path /tmp/ \        # где искать component.pkg
#       --sign "Developer ID Installer: Name (TEAM_ID)" \
#       --timestamp \
#       installer.pkg
#
# Пример distribution.xml:
# <?xml version="1.0" encoding="utf-8"?>
# <installer-gui-script minSpecVersion="1">
#     <title>MyApp</title>
#
#     <!-- Минимальная версия macOS -->
#     <os-version type="minimum" value="11.0"/>
#
#     <!-- Фон инсталлятора -->
#     <background file="background.png" alignment="bottomleft" scaling="none"/>
#     <background-darkAqua file="background-dark.png" alignment="bottomleft" scaling="none"/>
#
#     <!-- Лицензионное соглашение (пользователь должен принять) -->
#     <license file="LICENSE.txt" mime-type="text/plain"/>
#
#     <!-- README (показывается до установки) -->
#     <readme file="README.txt"/>
#
#     <!-- Документация (показывается вместо README) -->
#     <!-- <welcome file="Welcome.html" mime-type="text/html"/> -->
#
#     <!-- Пакеты -->
#     <pkg-ref id="com.powertech.myapp.pkg">myapp-component.pkg</pkg-ref>
#
#     <!-- Выбор компонентов -->
#     <choices-outline>
#         <line choice="default"/>
#     </choices-outline>
#     <choice id="default" visible="false">
#         <pkg-ref id="com.powertech.myapp.pkg"/>
#     </choice>
# </installer-gui-script>

BUILD_DISTRIBUTION=false  # установить в true для сборки дистрибутивного пакета

if [ "${BUILD_DISTRIBUTION}" = "true" ]; then
    DIST_XML="/tmp/${APP_NAME}-distribution.xml"
    RESOURCES_DIR="resources"

    # Сгенерировать distribution.xml
    productbuild \
        --synthesize \
        --package "${COMPONENT_PKG}" \
        "${DIST_XML}"

    # Собрать финальный дистрибутивный пакет
    productbuild \
        --distribution "${DIST_XML}" \
        --resources "${RESOURCES_DIR}" \
        --package-path "$(dirname "${COMPONENT_PKG}")" \
        "${PKG_OUTPUT}"

    echo "Distribution package created: ${PKG_OUTPUT}"
else
    # Для консольных утилит используем компонентный пакет напрямую
    cp "${COMPONENT_PKG}" "${PKG_OUTPUT}"
    echo "Component package copied to: ${PKG_OUTPUT}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ОПЦИОНАЛЬНО: ПОДПИСЬ И НОТАРИЗАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════
#
# На macOS:
#   pkgbuild --sign "Developer ID Installer: Name (TEAM_ID)" --timestamp ...
#   xcrun notarytool submit installer.pkg --wait ...
#   xcrun stapler staple installer.pkg
#
# На Linux/Windows (через rcodesign):
#   # rcodesign sign --p12-file cert.p12 --p12-password-file pass.txt installer.pkg
#   # rcodesign notary-submit --api-key-path key.json installer.pkg --wait --staple

SIGN_PACKAGE=false  # установить в true для подписи

if [ "${SIGN_PACKAGE}" = "true" ]; then
    TEAM_ID="${APPLE_TEAM_ID:?APPLE_TEAM_ID not set}"
    APPLE_ID="${APPLE_ID:?APPLE_ID not set}"
    APP_PASSWORD="${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD not set}"
    CERT_NAME="Developer ID Installer: PowerTech Center (${TEAM_ID})"

    SIGNED_PKG="${PKG_OUTPUT%.pkg}-signed.pkg"

    # Подпись через productsign (для дистрибутивных пакетов)
    # или через pkgbuild --sign (встроена в сборку)
    productsign \
        --sign "${CERT_NAME}" \
        --timestamp \
        "${PKG_OUTPUT}" \
        "${SIGNED_PKG}"

    # Нотаризация
    xcrun notarytool submit "${SIGNED_PKG}" \
        --apple-id "${APPLE_ID}" \
        --password "${APP_PASSWORD}" \
        --team-id "${TEAM_ID}" \
        --wait \
        --output-format json

    # Staple — встраивание нотаризационного тикета в пакет
    # После staple пакет можно установить без интернета
    xcrun stapler staple "${SIGNED_PKG}"

    # Проверка
    spctl -a -t install "${SIGNED_PKG}"

    mv "${SIGNED_PKG}" "${PKG_OUTPUT}"
    echo "Signed and notarized: ${PKG_OUTPUT}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ОЧИСТКА
# ═══════════════════════════════════════════════════════════════════════════════

rm -rf "${PAYLOAD_DIR}" "${SCRIPTS_DIR}" "${COMPONENT_PKG}"

echo ""
echo "Done! Package: ${PKG_OUTPUT}"
echo ""
echo "Diagnostic commands:"
echo "  pkgutil --expand ${PKG_OUTPUT} /tmp/expanded/"
echo "  pkgutil --pkgs | grep ${APP_NAME}"
echo "  pkgutil --info ${IDENTIFIER}"
echo "  pkgutil --files ${IDENTIFIER}"
echo "  sudo pkgutil --forget ${IDENTIFIER}  # для тестирования переустановки"

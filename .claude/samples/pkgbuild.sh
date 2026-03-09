#!/bin/bash
# pkgbuild.sh — полный пример создания macOS .pkg через pkgbuild + productbuild
#
# pkgbuild и productbuild входят в Xcode Command Line Tools (macOS native).
# Работают ТОЛЬКО на macOS.
#
# Workflow:
#   pkgbuild  → component.pkg  (компонентный пакет с файлами и скриптами)
#   productbuild → installer.pkg  (дистрибутивный пакет с GUI-wizard)
#   productsign  → подписать готовый пакет
#   notarytool   → нотаризировать
#   stapler      → приложить тикет нотаризации
#
# Использование:
#   chmod +x pkgbuild.sh && ./pkgbuild.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="myapp"
VERSION="${VERSION:-1.2.3}"
ARCH="${ARCH:-arm64}"

IDENTIFIER="com.powertech.${APP_NAME}.pkg"
BINARY_SRC="dist/${APP_NAME}-darwin-${ARCH}"

PAYLOAD_DIR="/tmp/${APP_NAME}-pkg-payload"
SCRIPTS_DIR="/tmp/${APP_NAME}-pkg-scripts"
COMPONENT_PKG="/tmp/${APP_NAME}-component.pkg"
DIST_XML="/tmp/${APP_NAME}-distribution.xml"
OUTPUT_PKG="dist/${APP_NAME}-darwin-${ARCH}.pkg"

mkdir -p "$(dirname "${OUTPUT_PKG}")"


# ═══════════════════════════════════════════════════════════════════════════════
# ПОДГОТОВКА PAYLOAD
# ═══════════════════════════════════════════════════════════════════════════════
#
# Payload — дерево файлов, которое будет скопировано на диск при установке.
# Структура payload соответствует итоговой структуре на диске.
#
# Два варианта:
#   --install-location /  + абсолютный layout:
#     payload/usr/local/bin/myapp → /usr/local/bin/myapp
#   --install-location /usr/local/bin  + плоский layout:
#     payload/myapp → /usr/local/bin/myapp

mkdir -p "${PAYLOAD_DIR}/usr/local/bin"
mkdir -p "${PAYLOAD_DIR}/usr/share/doc/${APP_NAME}"
mkdir -p "${PAYLOAD_DIR}/usr/share/man/man1"
mkdir -p "${PAYLOAD_DIR}/etc/${APP_NAME}"

cp "${BINARY_SRC}" "${PAYLOAD_DIR}/usr/local/bin/${APP_NAME}"
chmod 755 "${PAYLOAD_DIR}/usr/local/bin/${APP_NAME}"

[ -f "README.md" ] && cp "README.md" "${PAYLOAD_DIR}/usr/share/doc/${APP_NAME}/"
[ -f "man/${APP_NAME}.1" ] && gzip -c "man/${APP_NAME}.1" \
    > "${PAYLOAD_DIR}/usr/share/man/man1/${APP_NAME}.1.gz"

cat > "${PAYLOAD_DIR}/etc/${APP_NAME}/config.yaml" << 'EOF'
output_dir: ./dist
verbose: false
EOF
chmod 644 "${PAYLOAD_DIR}/etc/${APP_NAME}/config.yaml"


# ═══════════════════════════════════════════════════════════════════════════════
# ПОДГОТОВКА СКРИПТОВ
# ═══════════════════════════════════════════════════════════════════════════════
#
# Аргументы скриптов при вызове:
#   $1 — путь к .pkg файлу
#   $2 — install-location (директория назначения, напр. /)
#   $3 — путь к тому (обычно /, иногда /Volumes/...)
#   $4 — имя скрипта (preinstall / postinstall)
#
# ВАЖНО:
#   - Скрипты выполняются от root БЕЗ пользовательского окружения
#   - Нельзя использовать: $HOME, ~, пользовательский $PATH, .bashrc
#   - Только абсолютные пути: /usr/bin/env, /usr/local/bin/myapp
#   - preinstall: код != 0 → установка прерывается
#   - postinstall: код != 0 → предупреждение (файлы уже скопированы)
#   - Файлы должны называться именно preinstall/postinstall (без расширения)
#     или другие файлы доступны через переменную $PACKAGE_SCRIPTS

mkdir -p "${SCRIPTS_DIR}"

cat > "${SCRIPTS_DIR}/preinstall" << 'PREINSTALL'
#!/bin/bash
set -e
PACKAGE_PATH="$1"
INSTALL_LOCATION="$2"
TARGET_VOLUME="$3"

# Остановить запущенный процесс
if /usr/bin/pgrep -x "myapp" > /dev/null 2>&1; then
    /usr/bin/pkill -x "myapp" || true
    sleep 1
fi

exit 0
PREINSTALL
chmod 755 "${SCRIPTS_DIR}/preinstall"

cat > "${SCRIPTS_DIR}/postinstall" << 'POSTINSTALL'
#!/bin/bash
set -e
TARGET_VOLUME="$3"
BINARY="${TARGET_VOLUME}usr/local/bin/myapp"

[ -f "${BINARY}" ] && chmod 755 "${BINARY}"

echo "myapp installed. Run: myapp --help"
exit 0
POSTINSTALL
chmod 755 "${SCRIPTS_DIR}/postinstall"


# ═══════════════════════════════════════════════════════════════════════════════
# PKGBUILD — СОЗДАНИЕ КОМПОНЕНТНОГО ПАКЕТА
# ═══════════════════════════════════════════════════════════════════════════════

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
    \
    "${COMPONENT_PKG}"

# ── Справочник всех флагов pkgbuild ───────────────────────────────────────────
#
# ИСТОЧНИК СОДЕРЖИМОГО (взаимоисключающие):
#
# --root <path>
#   Упаковать всё дерево директории в payload.
#   Структура директории соответствует итоговой на диске.
#
# --component <path>
#   Упаковать отдельный бандл (.app, .framework, .plugin).
#   Лучше чем --root для приложений с bundle-структурой.
#   Нельзя совмещать с --root.
#
# --nopayload
#   Пакет только со скриптами, без файлов.
#   Полезно для: создания symlink, настройки PATH, регистрации в launchd.
#
# ИДЕНТИФИКАЦИЯ:
#
# --identifier <id>
#   Уникальный идентификатор в reverse DNS: com.company.app.pkg
#   Стабилен между версиями (1.0, 2.0, 3.0 — один идентификатор).
#   macOS использует для: pkgutil --info, проверки установленных пакетов.
#
# --version <version>
#   Версия пакета. Используется macOS для версионирования при обновлении.
#
# --install-location <path>
#   Директория назначения. Обычно "/" для абсолютного layout.
#   Или "/usr/local/bin" для плоского layout с одним бинарником.
#
# --prior <pkg-path>
#   Наследовать identifier, version, install-location из предыдущего пакета.
#   Используется в incremental update workflows.
#
# СКРИПТЫ И БАНДЛЫ:
#
# --scripts <dir>
#   Директория со скриптами. Распознаёт: preinstall, postinstall.
#   Остальные файлы доступны в скриптах через $PACKAGE_SCRIPTS.
#   Файлы должны быть исполняемыми (chmod 755).
#
# --component-plist <plist>
#   XML plist для описания поведения бандлов (.app/.framework/.plugin).
#   Только для режима --root и --component (не --nopayload).
#   Генерация шаблона: pkgbuild --analyze --root <root> components.plist
#
# ФИЛЬТРАЦИЯ:
#
# --filter <regex>
#   Исключить файлы по extended regex относительно payload.
#   Переопределяет встроенные фильтры pkgbuild.
#   Можно указывать несколько раз.
#   Встроенные фильтры: .DS_Store, .svn, CVS и другие мусорные файлы.
#
# ПРАВА:
#
# --ownership <mode>
#   recommended    — системные пути → root:wheel; /Users → текущий пользователь.
#                    Рекомендуется для большинства случаев.
#   preserve       — копировать точные uid/gid с диска.
#                    Проблема: uid/gid могут отличаться на разных машинах.
#   preserve-other — recommended для своих файлов, preserve для остальных.
#
# АНАЛИЗ:
#
# --analyze
#   Создать шаблон component plist вместо сборки пакета.
#   Пример: pkgbuild --analyze --root payload/ components.plist
#
# ПОДПИСЬ:
#
# --sign <identity>
#   Подписать пакет. Для дистрибуции: "Developer ID Installer: Name (TEAM_ID)"
#
# --keychain <path>
#   Альтернативный keychain для поиска сертификата.
#   Полезно в CI/CD: --keychain /tmp/ci.keychain
#
# --cert <cert-name>
#   Встроить промежуточный сертификат в пакет (для цепочки доверия).
#   Можно указывать несколько раз.
#
# --timestamp
#   Доверенная временная метка Apple (Secure Timestamp).
#   Автоматически включается для Developer ID.
#   Обязательна: без неё подпись станет невалидной после истечения сертификата.
#
# --timestamp=none
#   Явно отключить временную метку (для разработки/тестирования).
#
# ПРОЧЕЕ:
#
# --quiet
#   Подавить stdout. Ошибки всё равно выводятся в stderr.


# ═══════════════════════════════════════════════════════════════════════════════
# COMPONENT PLIST — конфигурация поведения бандлов
# ═══════════════════════════════════════════════════════════════════════════════
#
# Нужен только для .app/.framework/.plugin (не для CLI-утилит).
# Генерация шаблона:
#   pkgbuild --analyze --root payload/ components.plist
#
# Параметры:
#   RootRelativeBundlePath  — путь к бандлу относительно root (обязателен)
#   BundleIsRelocatable     — разрешить пользователю переместить приложение
#   BundleIsVersionChecked  — не устанавливать если установлена более новая версия
#   BundleHasStrictIdentifier — строгое совпадение Bundle ID
#   BundleOverwriteAction   — поведение при перезаписи:
#     upgrade   — только если новее текущей
#     downgrade — только если старее текущей
#     newer     — новее или одинаково
#     root      — всегда перезаписывать
#
# Пример:
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
# PRODUCTBUILD — СОЗДАНИЕ ДИСТРИБУТИВНОГО ПАКЕТА
# ═══════════════════════════════════════════════════════════════════════════════
#
# productbuild объединяет компонентные пакеты в финальный installer.pkg
# с GUI-wizard: лицензия, readme, welcome-экран, выбор компонентов.
#
# Для CLI-утилит обычно достаточно компонентного пакета напрямую.
# Дистрибутивный пакет нужен если требуется: UI wizard, несколько компонентов,
# проверки совместимости, кастомный фон/лицензия.

BUILD_DIST=false

if [ "${BUILD_DIST}" = "true" ]; then

    # ── Шаг 1: Синтезировать distribution.xml ─────────────────────────────
    productbuild \
        --synthesize \
        --package "${COMPONENT_PKG}" \
        "${DIST_XML}"

    # ── (Опционально) Отредактировать distribution.xml ────────────────────
    # Добавить: заголовок, лицензию, минимальную версию ОС, фон и т.д.

    # ── Шаг 2: Собрать финальный пакет ────────────────────────────────────
    productbuild \
        --distribution "${DIST_XML}" \
        --resources "resources/" \
        --package-path "$(dirname "${COMPONENT_PKG}")" \
        "${OUTPUT_PKG}"

    # ── Справочник всех флагов productbuild ───────────────────────────────
    #
    # РЕЖИМЫ РАБОТЫ:
    #
    # --distribution <dist-path>
    #   Использовать distribution.xml для описания установки.
    #
    # --synthesize
    #   Синтезировать distribution.xml из --package вместо создания пакета.
    #   Используется как первый шаг для получения шаблона.
    #
    # ИСТОЧНИКИ СОДЕРЖИМОГО:
    #
    # --package <pkg-path> [install-path]
    #   Добавить компонентный пакет. install-path переопределяет install-location.
    #   Можно указывать несколько раз.
    #
    # --component <path> [install-path]
    #   Добавить бандл с опциональным путём установки.
    #
    # --root <root-path> <install-path>
    #   Добавить дерево директории (destination root от xcodebuild).
    #
    # --content <content-path>
    #   Добавить содержимое директории в продукт-архив.
    #
    # --package-path <search-path>
    #   Директория поиска компонентных пакетов (ссылаемых из distribution.xml).
    #   Можно указывать несколько раз.
    #
    # РЕСУРСЫ:
    #
    # --resources <rsrc-dir>
    #   Скопировать нелокализованные и локализованные ресурсы в архив.
    #   Здесь лежат: welcome.html, readme.html, license.html, background.png
    #   и их локализованные варианты в подпапках (en.lproj/, ru.lproj/ и т.д.)
    #
    # --scripts <scripts-path>
    #   Добавить содержимое для system.run() JavaScript в distribution.
    #
    # --plugins <plugins-path>
    #   Добавить содержимое для механизма плагинов macOS Installer.
    #
    # ИДЕНТИФИКАЦИЯ:
    #
    # --identifier <product-identifier>
    #   Уникальный идентификатор продукта верхнего уровня.
    #
    # --version <product-version>
    #   Версия продукта верхнего уровня.
    #
    # --product <requirements-plist>
    #   Plist с предустановочными требованиями при синтезировании distribution.
    #
    # --ui <interface-type>
    #   Выбор choices-outline если в distribution.xml их несколько.
    #
    # ПОДПИСЬ (те же флаги что у pkgbuild):
    # --sign <identity>, --keychain <path>, --cert <name>
    # --timestamp, --timestamp=none, --quiet

else
    cp "${COMPONENT_PKG}" "${OUTPUT_PKG}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# DISTRIBUTION.XML — полный пример со всеми элементами
# ═══════════════════════════════════════════════════════════════════════════════
#
# distribution.xml описывает GUI-wizard macOS Installer.
# Создаётся вручную или синтезируется через: productbuild --synthesize
#
# Полный пример:
# ─────────────────────────────────────────────────────────────────────────────
# <?xml version="1.0" encoding="utf-8"?>
# <installer-gui-script minSpecVersion="2">
#     <!--
#       minSpecVersion:
#         1 — до macOS 10.6.6
#         2 — macOS 10.6.6+ (рекомендуется)
#     -->
#
#     <!-- Заголовок окна Installer -->
#     <title>MyApp</title>
#
#     <!-- Экраны wizard (файлы из --resources директории) -->
#     <!-- welcome: показывается перед выбором компонентов -->
#     <welcome file="welcome.html" mime-type="text/html"/>
#     <!-- readme: показывается перед лицензией -->
#     <readme file="readme.rtf" mime-type="text/rtf"/>
#     <!-- license: пользователь должен принять -->
#     <license file="license.html" mime-type="text/html"/>
#     <!-- conclusion: показывается после установки -->
#     <conclusion file="conclusion.html" mime-type="text/html"/>
#     <!-- uti: альтернатива mime-type, напр. public.rtf -->
#
#     <!-- Фон окна Installer -->
#     <background
#         file="background.png"
#         mime-type="image/png"
#         alignment="bottomleft"    <!-- center|left|right|top|bottom|topleft|topright|bottomleft|bottomright -->
#         scaling="proportional"    <!-- tofit|none|proportional -->
#     />
#     <!-- Отдельный фон для тёмной темы macOS (те же атрибуты) -->
#     <background-darkAqua file="background-dark.png" mime-type="image/png"
#         alignment="bottomleft" scaling="proportional"/>
#
#     <!-- Минимальная версия macOS -->
#     <!-- type: minimum или maximum -->
#     <os-version type="minimum" value="11.0"/>
#     <!-- Или более детально через allowed-os-versions: -->
#     <!-- <allowed-os-versions>
#              <os-version min="11.0" before="14.0"/>
#          </allowed-os-versions> -->
#
#     <!-- Требования к RAM (macOS 10.6.6+) -->
#     <ram min-gb="2"/>
#
#     <!-- JavaScript для проверок совместимости -->
#     <script><![CDATA[
#         function installationCheck() {
#             // Вернуть true если можно устанавливать
#             return true;
#         }
#         function volumeCheck() {
#             return true;
#         }
#         // Доступны: system.version, system.sysctl(), installer и др.
#     ]]></script>
#
#     <!-- Проверка хоста (вызывает installationCheck() или встроенные проверки) -->
#     <installation-check script="installationCheck()"/>
#
#     <!-- Проверка тома назначения -->
#     <volume-check script="volumeCheck()"/>
#
#     <!-- Требования к GPU (10.7+) -->
#     <!-- <required-graphics description="OpenCL GPU required">
#              <required-cl-device/>
#          </required-graphics> -->
#
#     <!-- Домены установки -->
#     <domains
#         enable_anywhere="true"          <!-- разрешить установку в /Volumes/... -->
#         enable_currentUserHome="false"  <!-- разрешить установку в ~/... -->
#         enable_localSystem="true"       <!-- разрешить в / (по умолчанию) -->
#     />
#
#     <!-- Идентификатор и версия продукта верхнего уровня -->
#     <product id="com.powertech.myapp" version="1.2.3"/>
#
#     <!-- Опции установщика -->
#     <options
#         customize="allow"            <!-- allow|always|never — показывать ли экран кастомизации -->
#         allow-external-scripts="no"  <!-- разрешить system.run() -->
#         rootVolumeOnly="false"       <!-- только в корневой том -->
#     />
#
#     <!-- Пакеты (ссылки на component .pkg файлы) -->
#     <pkg-ref id="com.powertech.myapp.pkg"
#              version="1.2.3"
#              installKBytes="1024"
#              onConclusion="None"       <!-- None|RequireLogout|RequireRestart|RequireShutdown -->
#              auth="root">             <!-- root|none -->
#         myapp-component.pkg
#     </pkg-ref>
#
#     <!-- Иерархия выборов (что показывать на экране кастомизации) -->
#     <choices-outline>
#         <line choice="main"/>
#     </choices-outline>
#
#     <choice id="main"
#             title="MyApp"
#             description="Installs MyApp"
#             start_selected="true"      <!-- выбрано по умолчанию -->
#             start_enabled="true"       <!-- можно изменить выбор -->
#             start_visible="true"       <!-- показывать в списке -->
#             selected="installationCheck()"  <!-- JS для динамического управления -->
#             enabled="true"
#             visible="true"
#             customLocation="/usr/local">   <!-- разрешить пользователю выбрать путь -->
#         <pkg-ref id="com.powertech.myapp.pkg"/>
#     </choice>
# </installer-gui-script>


# ═══════════════════════════════════════════════════════════════════════════════
# ПОДПИСЬ И НОТАРИЗАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════

SIGN_PKG="${SIGN_PKG:-false}"

if [ "${SIGN_PKG}" = "true" ]; then
    TEAM_ID="${APPLE_TEAM_ID:?}"
    APPLE_ID="${APPLE_ID:?}"
    APP_PASSWORD="${APPLE_APP_PASSWORD:?}"
    CERT_NAME="Developer ID Installer: PowerTech Center (${TEAM_ID})"
    SIGNED_PKG="${OUTPUT_PKG%.pkg}-signed.pkg"

    # productsign — подпись готового пакета (дистрибутивного или компонентного)
    productsign \
        --sign "${CERT_NAME}" \
        --timestamp \
        "${OUTPUT_PKG}" \
        "${SIGNED_PKG}"
    # Флаги productsign:
    #   --sign <identity>   — сертификат подписи
    #   --keychain <path>   — альтернативный keychain
    #   --cert <name>       — встроить промежуточный сертификат
    #   --timestamp         — доверенная временная метка
    #   --timestamp=none    — отключить временную метку

    # Нотаризация
    xcrun notarytool submit "${SIGNED_PKG}" \
        --apple-id "${APPLE_ID}" \
        --password "${APP_PASSWORD}" \
        --team-id "${TEAM_ID}" \
        --wait \
        --output-format json

    # Staple — встроить нотаризационный тикет в пакет
    # После staple пакет устанавливается без интернета (Gatekeeper проверяет локально)
    xcrun stapler staple "${SIGNED_PKG}"

    # Проверка подписи и нотаризации
    spctl -a -t install "${SIGNED_PKG}"
    pkgutil --check-signature "${SIGNED_PKG}"

    mv "${SIGNED_PKG}" "${OUTPUT_PKG}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ОЧИСТКА И ДИАГНОСТИКА
# ═══════════════════════════════════════════════════════════════════════════════

rm -rf "${PAYLOAD_DIR}" "${SCRIPTS_DIR}" "${COMPONENT_PKG}"
[ -f "${DIST_XML}" ] && rm -f "${DIST_XML}"

echo "Done: ${OUTPUT_PKG}"
echo ""
echo "Diagnostic commands:"
echo "  pkgutil --expand ${OUTPUT_PKG} /tmp/expanded-pkg/"
echo "  pkgutil --pkgs | grep ${APP_NAME}"
echo "  pkgutil --info ${IDENTIFIER}"
echo "  pkgutil --files ${IDENTIFIER}"
echo "  sudo pkgutil --forget ${IDENTIFIER}"
echo "  spctl -a -t install ${OUTPUT_PKG}"

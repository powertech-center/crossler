#!/bin/bash
# xar-bomutils.sh — полный пример создания macOS .pkg на Linux/Windows
#                   без pkgbuild, через xar + bomutils (mkbom)
#
# НАЗНАЧЕНИЕ:
#   Этот скрипт воспроизводит то, что pkgbuild делает на macOS, но на Linux/Windows.
#   Используется когда нет доступа к нативным macOS-инструментам.
#
# ЗАВИСИМОСТИ:
#   xar     — архиватор для формата XAR (macOS .pkg это XAR-архив)
#             Linux:   apt install xar / apk add xar / собрать из исходников
#             Windows: собрать из исходников или WSL
#   mkbom   — из bomutils (создаёт Bill of Materials)
#             Linux:   https://github.com/hogliux/bomutils
#             macOS:   homebrew: brew install bomutils (или нативный mkbom)
#   cpio    — входит в GNU coreutils
#   gzip    — входит в большинство дистрибутивов
#
# ВНУТРЕННЯЯ СТРУКТУРА .pkg (XAR-архив):
#
#   MyApp.pkg/               ← XAR-архив
#   ├── PackageInfo          ← XML-метаданные пакета
#   ├── Bom                  ← бинарный Bill of Materials (mkbom)
#   ├── Payload              ← gzip(cpio(файлы для установки))
#   └── Scripts              ← gzip(cpio(preinstall + postinstall))  [опционально]
#
# ДИСТРИБУТИВНЫЙ ПАКЕТ (плоская структура):
#
#   MyApp.pkg/               ← внешний XAR-архив
#   ├── Distribution         ← XML описание wizard-установщика
#   ├── base.pkg/            ← вложенный компонентный XAR-архив
#   │   ├── PackageInfo
#   │   ├── Bom
#   │   ├── Payload
#   │   └── Scripts
#   └── Resources/
#       ├── en.lproj/
#       │   ├── welcome.html
#       │   ├── readme.html
#       │   └── license.html
#       └── background.png
#
# КРИТИЧЕСКИЕ ОСОБЕННОСТИ:
#   1. cpio ТОЛЬКО в формате odc — macOS Installer принимает только его
#   2. --owner 0:80 — macOS gid=80 (admin), не 0 (root как на Linux)
#   3. xar --compression none — Payload уже gzip; двойное сжатие сломает установщик
#   4. Скрипты без расширений: файл preinstall, НЕ preinstall.sh
#   5. numberOfFiles в PackageInfo считает и директории (find . | wc -l)
#
# Использование:
#   chmod +x xar-bomutils.sh && ./xar-bomutils.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="myapp"
VERSION="${VERSION:-1.2.3}"
ARCH="${ARCH:-arm64}"
IDENTIFIER="com.powertech.${APP_NAME}.pkg"
INSTALL_LOCATION="/"
BINARY_SRC="dist/${APP_NAME}-darwin-${ARCH}"
OUTPUT_PKG="dist/${APP_NAME}-darwin-${ARCH}.pkg"

WORK_DIR="/tmp/${APP_NAME}-pkg-work"
INSTALL_ROOT="${WORK_DIR}/install-root"
SCRIPTS_DIR="${WORK_DIR}/scripts"
PKG_STAGE="${WORK_DIR}/pkg-stage"

mkdir -p "$(dirname "${OUTPUT_PKG}")"
rm -rf "${WORK_DIR}"
mkdir -p "${INSTALL_ROOT}" "${SCRIPTS_DIR}" "${PKG_STAGE}"


# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 1: ПОДГОТОВКА INSTALL ROOT (структура файлов)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Install root — дерево файлов, которое будет скопировано на диск при установке.
# Структура должна соответствовать итоговой структуре на диске macOS.
# При INSTALL_LOCATION="/" пути начинаются с usr/, etc/ и т.д. (без ведущего /).

echo "Step 1: Preparing install root..."

mkdir -p "${INSTALL_ROOT}/usr/local/bin"
mkdir -p "${INSTALL_ROOT}/usr/share/doc/${APP_NAME}"
mkdir -p "${INSTALL_ROOT}/usr/share/man/man1"
mkdir -p "${INSTALL_ROOT}/etc/${APP_NAME}"

# Скопировать бинарник и установить права
cp "${BINARY_SRC}" "${INSTALL_ROOT}/usr/local/bin/${APP_NAME}"
chmod 755 "${INSTALL_ROOT}/usr/local/bin/${APP_NAME}"

# Документация и man-страница
[ -f "README.md" ] && cp "README.md" "${INSTALL_ROOT}/usr/share/doc/${APP_NAME}/"
[ -f "man/${APP_NAME}.1" ] && gzip -c "man/${APP_NAME}.1" \
    > "${INSTALL_ROOT}/usr/share/man/man1/${APP_NAME}.1.gz"

# Конфиг по умолчанию
cat > "${INSTALL_ROOT}/etc/${APP_NAME}/config.yaml" << 'EOF'
output_dir: ./dist
verbose: false
EOF
chmod 644 "${INSTALL_ROOT}/etc/${APP_NAME}/config.yaml"

# Права на директории (macOS ожидает root:wheel для системных путей)
# Фактические права задаются через mkbom + cpio --owner
chmod 755 "${INSTALL_ROOT}/usr/local/bin"
chmod 755 "${INSTALL_ROOT}/usr/share/doc/${APP_NAME}"


# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 2: ПОДГОТОВКА СКРИПТОВ
# ═══════════════════════════════════════════════════════════════════════════════
#
# Скрипты ОБЯЗАТЕЛЬНО без расширений: preinstall, postinstall
# Скрипты выполняются от root на macOS без пользовательского окружения
#
# Аргументы при вызове:
#   $1 — путь к .pkg файлу
#   $2 — install-location (директория назначения, обычно /)
#   $3 — путь к тому (обычно /, иногда /Volumes/...)
#   $4 — имя скрипта

echo "Step 2: Preparing scripts..."

cat > "${SCRIPTS_DIR}/preinstall" << 'PREINSTALL'
#!/bin/bash
set -e
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
# ШАГ 3: СОЗДАНИЕ Payload (gzip(cpio(файлы)))
# ═══════════════════════════════════════════════════════════════════════════════
#
# Payload — это gzip-сжатый cpio-архив файлов для установки.
#
# КРИТИЧЕСКИ ВАЖНО: только формат cpio odc (old character format)
# Другие форматы (newc, bin, crc) macOS Installer НЕ принимает.
#
# --owner 0:80 — uid=0 (root), gid=80 (admin на macOS, не 0 как на Linux!)
# Без этого файлы могут установиться с неправильными правами.

echo "Step 3: Creating Payload..."

NUM_FILES=$(find "${INSTALL_ROOT}" | wc -l | tr -d ' ')
INSTALL_KB=$(du -sk "${INSTALL_ROOT}" | cut -f1)

( cd "${INSTALL_ROOT}" && \
  find . | \
  cpio \
    --create \
    --format odc \
    --owner 0:80 \
    --quiet \
) | gzip -c > "${PKG_STAGE}/Payload"

# Флаги cpio:
#   --create (-o)       — режим создания архива
#   --format odc        — формат: odc (старый ASCII), newc (SVR4), bin (бинарный)
#                         macOS принимает ТОЛЬКО odc
#   --owner uid:gid     — uid и gid для всех файлов в архиве
#                         На macOS: uid=0 (root), gid=80 (admin group)
#   --quiet             — подавить статистику
#   --verbose (-v)      — вывести список файлов (для отладки)
#   --dereference (-L)  — следовать символическим ссылкам
#   --no-absolute-filenames — убрать ведущий / из путей (для extract)


# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 4: СОЗДАНИЕ Scripts (gzip(cpio(скрипты)))
# ═══════════════════════════════════════════════════════════════════════════════
#
# Scripts создаётся аналогично Payload, но только для скриптов.
# Если скриптов нет — Scripts не нужен.

echo "Step 4: Creating Scripts archive..."

( cd "${SCRIPTS_DIR}" && \
  find . | \
  cpio \
    --create \
    --format odc \
    --owner 0:80 \
    --quiet \
) | gzip -c > "${PKG_STAGE}/Scripts"


# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 5: СОЗДАНИЕ Bom (Bill of Materials)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Bom — бинарный файл с информацией о каждом файле пакета:
# путь, тип (файл/директория/ссылка), размер, права, контрольная сумма.
# macOS использует Bom для:
#   - проверки целостности при установке
#   - отслеживания установленных файлов (pkgutil --files)
#   - обнаружения конфликтов между пакетами
#
# mkbom из bomutils: https://github.com/hogliux/bomutils
#
# Флаги mkbom:
#   mkbom [-u uid] [-g gid] <source-dir> <output.bom>
#     -u <uid>  — uid для всех файлов (должен совпадать с cpio --owner uid)
#     -g <gid>  — gid для всех файлов (должен совпадать с cpio --owner gid)
#               На macOS: -u 0 -g 80 (root:admin)
#
#   mkbom -i <filelist> <output.bom>
#     -i <file> — список файлов в формате lsbom (несовместим с -u/-g)
#
# Нативный macOS mkbom (если доступен):
#   mkbom <source-dir> <output.bom>   (без явных uid/gid — берёт с диска)
#
# ВАЖНО: bomutils mkbom и нативный macOS mkbom имеют разный синтаксис!

echo "Step 5: Creating Bom..."

# Linux: mkbom из bomutils
if command -v mkbom >/dev/null 2>&1; then
    mkbom \
        -u 0 \
        -g 80 \
        "${INSTALL_ROOT}" \
        "${PKG_STAGE}/Bom"
else
    echo "ERROR: mkbom not found. Install bomutils: https://github.com/hogliux/bomutils"
    exit 1
fi

# Альтернатива — нативный macOS (если скрипт запускается на macOS):
# /usr/bin/mkbom "${INSTALL_ROOT}" "${PKG_STAGE}/Bom"


# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 6: СОЗДАНИЕ PackageInfo XML
# ═══════════════════════════════════════════════════════════════════════════════
#
# PackageInfo — XML-файл с метаданными пакета. Читается macOS Installer.
#
# Атрибуты элемента <pkg-info>:
#
#   format-version="2"
#     Всегда 2 для современных плоских пакетов.
#
#   identifier="com.company.app.pkg"
#     Уникальный идентификатор в reverse DNS формате.
#     macOS использует для pkgutil --info, проверки установки.
#
#   version="1.2.3"
#     Версия пакета.
#
#   install-location="/"
#     Путь установки. Совпадает с тем, как организован install root:
#     "/" — абсолютный layout (usr/, etc/ в корне install root)
#     "/usr/local/bin" — плоский layout (бинарник прямо в install root)
#
#   auth="root"
#     Требуемый уровень привилегий для установки:
#     "root" — требует root/sudo (стандартно для системных инструментов)
#     "none" — может установить любой пользователь (в ~/Library и т.д.)
#
#   overwrite-permissions="true"
#     Перезаписать права файлов при обновлении даже если пользователь их изменил.
#
#   relocatable="false"
#     Разрешить пользователю изменить путь установки.
#     false — фиксированный install-location.
#
#   postinstall-action="none"
#     Действие после установки:
#     "none"     — ничего (стандартно)
#     "logout"   — потребовать выход из системы
#     "restart"  — потребовать перезагрузку
#     "shutdown" — потребовать выключение
#
#   generator-version="..."
#     Версия инструмента-генератора (информационно).
#
# Дочерние элементы:
#
#   <payload numberOfFiles="N" installKBytes="N"/>
#     Статистика Payload: количество файлов (включая директории) и размер в KB.
#
#   <scripts>
#     <preinstall file="./preinstall"/>
#     <postinstall file="./postinstall"/>
#   </scripts>
#     Пути к скриптам внутри Scripts-архива.
#
#   <bundle-version/>
#     Список бандлов (.app/.framework) для защиты от downgrade.
#     Для CLI-утилит — пустой элемент.
#
#   <upgrade-bundle/>
#     Список бандлов для обновления на месте (in-place upgrade).
#
#   <update-bundle/>
#     Список бандлов для patch-обновления.
#
#   <atomic-update-bundle/>
#     Список бандлов для атомарного обновления.
#
#   <strict-identifier/>
#     Запрет установки если install-location уже занят другим identifier.
#
#   <relocate/>
#     Пустой — запрет перемещения.
#     С <bundle id="..."/> — разрешить перемещение для конкретного бандла.

echo "Step 6: Creating PackageInfo..."

# Подсчёт файлов (включая директории — как это делает pkgbuild)
NUM_FILES=$(find "${INSTALL_ROOT}" | wc -l | tr -d ' ')
INSTALL_KB=$(du -sk "${INSTALL_ROOT}" | cut -f1)

cat > "${PKG_STAGE}/PackageInfo" << EOF
<?xml version="1.0" encoding="utf-8" standalone="no"?>
<pkg-info
    format-version="2"
    identifier="${IDENTIFIER}"
    version="${VERSION}"
    install-location="${INSTALL_LOCATION}"
    auth="root"
    overwrite-permissions="true"
    relocatable="false"
    postinstall-action="none"
    generator-version="crossler-1.0">

    <!-- Статистика Payload -->
    <payload numberOfFiles="${NUM_FILES}" installKBytes="${INSTALL_KB}"/>

    <!-- Скрипты жизненного цикла (убрать если скриптов нет) -->
    <scripts>
        <preinstall file="./preinstall"/>
        <postinstall file="./postinstall"/>
    </scripts>

    <!-- Защита от downgrade бандлов (пустой для CLI-утилит) -->
    <bundle-version/>

    <!-- Обновление бандлов на месте (пустой для CLI-утилит) -->
    <upgrade-bundle/>

    <!-- Patch-обновление бандлов (пустой для CLI-утилит) -->
    <update-bundle/>

    <!-- Атомарное обновление бандлов (пустой для CLI-утилит) -->
    <atomic-update-bundle/>

</pkg-info>
EOF


# ═══════════════════════════════════════════════════════════════════════════════
# ШАГ 7: СБОРКА .pkg ЧЕРЕЗ XAR
# ═══════════════════════════════════════════════════════════════════════════════
#
# xar — утилита создания XAR-архивов (eXtensible ARchive format).
# Исходники: https://mackyle.github.io/xar/
# macOS .pkg — это XAR-архив с фиксированной структурой.
#
# Флаги xar:
#
# РЕЖИМЫ РАБОТЫ:
#   -c, --create            — создать архив
#   -x, --extract           — извлечь архив
#   -t, --list              — список файлов
#
# ФАЙЛ АРХИВА:
#   -f <file>               — имя архива (обязателен)
#   -C <dir>                — директория для извлечения (с -x)
#
# СЖАТИЕ (КРИТИЧНО для .pkg):
#   --compression <alg>     — алгоритм сжатия файлов в архиве:
#     none   — БЕЗ сжатия (ОБЯЗАТЕЛЬНО для .pkg: Payload уже gzip)
#     gzip   — gzip сжатие (по умолчанию)
#     bzip2  — bzip2 сжатие
#     lzma   — lzma сжатие
#   --compression-args <N>  — уровень сжатия (1-9 для gzip/bzip2)
#   --no-compress <regex>   — не сжимать файлы, соответствующие regex
#
# TOC (Table of Contents — XML-оглавление внутри XAR):
#   --toc-cksum=<alg>       — алгоритм хэша TOC:
#     sha1   (по умолчанию)
#     sha256 (рекомендуется для современных систем)
#     sha512
#     md5    (устарел)
#     none
#   --dump-toc=<file>       — сохранить TOC в XML-файл (для отладки)
#   --dump-header           — вывести заголовок XAR
#
# ХЭШИ ФАЙЛОВ:
#   --extract-nocsum        — не проверять контрольные суммы при извлечении
#
# ИСКЛЮЧЕНИЯ:
#   --exclude <regex>       — исключить файлы по regex (расширенный синтаксис)
#                             Пример: --exclude '\.DS_Store$' --exclude '.*\.o$'
#
# СПИСОК ФАЙЛОВ:
#   -n, --verbose           — подробный вывод
#   --print-toc             — вывести TOC в XML (аналог --dump-toc)
#
# ПОДПИСЬ (двухшаговый процесс):
#   --sign                  — включить подпись в архив
#   --sig-size <N>          — размер подписи в байтах (RSA-2048=256, RSA-4096=512)
#   --cert-loc <file>       — добавить сертификат в архив (цепочка доверия)
#   --digestinfo-to-sign <file> — сохранить digest для внешней подписи
#   --inject-sig <file>     — внедрить внешнюю подпись в уже созданный архив
#
# ПРОЧЕЕ:
#   -p                      — сохранить права файлов при извлечении (с -x)
#   -l                      — следовать символическим ссылкам (с -c)
#   -s <file>               — файл со списком файлов для добавления

echo "Step 7: Creating .pkg with xar..."

( cd "${PKG_STAGE}" && \
  xar \
    --create \
    --file "${PWD}/../../$(basename "${OUTPUT_PKG}")" \
    --compression none \
    --toc-cksum=sha256 \
    . \
)
# ВАЖНО: xar создаётся из директории PKG_STAGE.
# Сначала переходим в неё (cd), затем архивируем текущую директорию (.).
# Это гарантирует что в архиве будут относительные пути (Bom, Payload, PackageInfo),
# а не абсолютные (/tmp/myapp-pkg-work/pkg-stage/Bom и т.д.)

# Переместить в финальное место
mv "${WORK_DIR}/$(basename "${OUTPUT_PKG}")" "${OUTPUT_PKG}" 2>/dev/null || true

# Если xar создал в текущей директории:
[ -f "$(basename "${OUTPUT_PKG}")" ] && mv "$(basename "${OUTPUT_PKG}")" "${OUTPUT_PKG}"


# ═══════════════════════════════════════════════════════════════════════════════
# СОЗДАНИЕ ДИСТРИБУТИВНОГО ПАКЕТА (опционально)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Дистрибутивный пакет — это внешний XAR-архив, содержащий:
#   - Distribution XML (описание GUI-wizard)
#   - один или несколько вложенных компонентных .pkg
#   - Resources/ (welcome, readme, license, background)
#
# Структура создаётся вручную, затем упаковывается в XAR.

BUILD_DIST="${BUILD_DIST:-false}"

if [ "${BUILD_DIST}" = "true" ]; then
    echo "Building distribution package..."

    DIST_STAGE="${WORK_DIR}/dist-stage"
    mkdir -p "${DIST_STAGE}/Resources/en.lproj"

    # Скопировать компонентный пакет как вложенный
    COMP_PKG_NAME="${APP_NAME}-component.pkg"
    cp "${OUTPUT_PKG}" "${DIST_STAGE}/${COMP_PKG_NAME}"

    # Ресурсы для GUI (опционально)
    # [ -f "resources/welcome.html" ] && cp "resources/welcome.html" "${DIST_STAGE}/Resources/en.lproj/"
    # [ -f "resources/readme.html" ] && cp "resources/readme.html" "${DIST_STAGE}/Resources/en.lproj/"
    # [ -f "resources/license.html" ] && cp "resources/license.html" "${DIST_STAGE}/Resources/en.lproj/"
    # [ -f "resources/background.png" ] && cp "resources/background.png" "${DIST_STAGE}/Resources/"

    # Distribution XML — описание GUI-wizard macOS Installer
    # (полный формат см. в pkgbuild.sh)
    cat > "${DIST_STAGE}/Distribution" << DIST_XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>${APP_NAME}</title>
    <os-version type="minimum" value="11.0"/>
    <domains enable_anywhere="true" enable_currentUserHome="false" enable_localSystem="true"/>
    <product id="${IDENTIFIER%-pkg}" version="${VERSION}"/>
    <options customize="never" rootVolumeOnly="false"/>

    <pkg-ref id="${IDENTIFIER}"
             version="${VERSION}"
             onConclusion="None"
             auth="root">
        ${COMP_PKG_NAME}
    </pkg-ref>

    <choices-outline>
        <line choice="default"/>
    </choices-outline>

    <choice id="default" title="${APP_NAME}" start_selected="true">
        <pkg-ref id="${IDENTIFIER}"/>
    </choice>
</installer-gui-script>
DIST_XML

    DIST_OUTPUT="${OUTPUT_PKG%.pkg}-installer.pkg"

    ( cd "${DIST_STAGE}" && \
      xar \
        --create \
        --file "${DIST_OUTPUT}" \
        --compression none \
        --toc-cksum=sha256 \
        . \
    )

    echo "Distribution package: ${DIST_OUTPUT}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ПОДПИСЬ ЧЕРЕЗ RCODESIGN (Linux/Windows альтернатива codesign)
# ═══════════════════════════════════════════════════════════════════════════════
#
# rcodesign — open-source реализация Apple Code Signing, работает без macOS.
# GitHub: https://github.com/indygreg/apple-platform-rs
# Установка: cargo install apple-codesign
#            или скачать бинарник с GitHub Releases
#
# Для подписи .pkg нужен:
#   - P12 файл с сертификатом "Developer ID Installer: Name (TEAM_ID)"
#   - пароль к P12 файлу
#
# ВАЖНО: rcodesign sign для .pkg работает только с flat packages (XAR).
# Компонентные пакеты нужно подписывать через: rcodesign sign --for-notarization

SIGN_PKG="${SIGN_PKG:-false}"

if [ "${SIGN_PKG}" = "true" ]; then
    P12_FILE="${APPLE_P12_FILE:?Set APPLE_P12_FILE}"
    P12_PASS_FILE="${APPLE_P12_PASSWORD_FILE:?Set APPLE_P12_PASSWORD_FILE}"

    echo "Signing with rcodesign..."

    rcodesign sign \
        --p12-file "${P12_FILE}" \
        --p12-password-file "${P12_PASS_FILE}" \
        --for-notarization \
        "${OUTPUT_PKG}"

    # Флаги rcodesign sign:
    #   --p12-file <file>           — P12/PFX файл с сертификатом и ключом
    #   --p12-password-file <file>  — файл с паролем P12 (безопаснее чем --p12-password)
    #   --p12-password <pass>       — пароль P12 (не рекомендуется для CI)
    #   --pem-source <file>         — PEM файл с сертификатом
    #   --for-notarization          — подписать с опциями для нотаризации
    #   --code-signature-flags <f>  — дополнительные флаги подписи
    #   --entitlements-xml-file <f> — файл entitlements
    #   --timestamp-url <url>       — URL TSA сервера временной метки
    #   --no-timestamp              — без временной метки
    #   --team-name <team-id>       — явный Team ID
    #   --signing-key-source <src>  — источник ключа: p12, pem, smartcard
    #   --smartcard-slot <slot>     — слот смарт-карты
    #   --remote-sign-url <url>     — URL для удалённой подписи
    #   --remote-public-key <file>  — публичный ключ удалённого подписанта
    #   <path>                      — файл для подписи

    echo "Signed: ${OUTPUT_PKG}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# НОТАРИЗАЦИЯ ЧЕРЕЗ RCODESIGN (Linux/Windows)
# ═══════════════════════════════════════════════════════════════════════════════
#
# После подписи можно нотаризировать напрямую с Linux/Windows через rcodesign.
# Нужен Apple API key (App Store Connect → Users → Keys → Developer).

NOTARIZE="${NOTARIZE:-false}"

if [ "${NOTARIZE}" = "true" ]; then
    API_KEY_FILE="${APPLE_API_KEY_FILE:?Set APPLE_API_KEY_FILE}"

    echo "Notarizing with rcodesign..."

    # Отправить на нотаризацию и дождаться результата
    rcodesign notary-submit \
        --api-key-path "${API_KEY_FILE}" \
        --wait \
        --staple \
        "${OUTPUT_PKG}"

    # Флаги rcodesign notary-submit:
    #   --api-key-path <file>       — JSON файл с API ключом (из App Store Connect)
    #                                 Содержит: {"issuer_id": "...", "key_id": "...", "private_key": "..."}
    #   --api-issuer <issuer-id>    — Issuer ID (альтернатива api-key-path)
    #   --api-key <key-id>          — Key ID (альтернатива api-key-path)
    #   --api-private-key <file>    — приватный ключ .p8 файл
    #   --wait                      — ждать завершения нотаризации (polling)
    #   --max-wait-seconds <N>      — таймаут ожидания (по умолчанию 600)
    #   --staple                    — автоматически staple после нотаризации
    #   --team-id <id>              — явный Team ID

    echo "Notarized and stapled: ${OUTPUT_PKG}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ОЧИСТКА
# ═══════════════════════════════════════════════════════════════════════════════

rm -rf "${WORK_DIR}"

echo ""
echo "Done: ${OUTPUT_PKG}"
echo ""
echo "Diagnostic commands (на macOS):"
echo "  xar -tf ${OUTPUT_PKG}                   # список файлов в архиве"
echo "  xar --dump-toc=/dev/stdout -f ${OUTPUT_PKG}  # TOC XML"
echo "  pkgutil --expand ${OUTPUT_PKG} /tmp/expanded/ # распаковать"
echo "  lsbom /tmp/expanded/${APP_NAME}.pkg/Bom  # содержимое Bom"
echo "  pkgutil --pkgs | grep ${APP_NAME}        # проверить установку"
echo "  pkgutil --info ${IDENTIFIER}"
echo "  sudo installer -pkg ${OUTPUT_PKG} -target / -verbose  # установить"

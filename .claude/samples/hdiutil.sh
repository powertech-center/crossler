#!/bin/bash
# hdiutil.sh — полный пример использования hdiutil для создания macOS .dmg
#
# hdiutil входит в macOS (нативный инструмент Apple), доп. установка не нужна.
# Создаёт .dmg дисковые образы для дистрибуции macOS-приложений.
#
# ВНИМАНИЕ: hdiutil работает ТОЛЬКО на macOS.
#
# DMG — стандарт де-факто для GUI-приложений: пользователь скачивает .dmg,
# видит окно Finder с приложением и ярлыком Applications, перетаскивает.
# Для CLI-утилит предпочтительнее .pkg, но DMG тоже допустим.
#
# Инструменты автоматизации (опциональные):
#   create-dmg  — bash-обёртка над hdiutil (brew install create-dmg)
#   dmgbuild    — Python-инструмент для CI/CD без Finder (pip install dmgbuild)
#
# Использование:
#   chmod +x hdiutil.sh && ./hdiutil.sh
# ─────────────────────────────────────────────────────────────────────────────

set -e
set -u

# ═══════════════════════════════════════════════════════════════════════════════
# КОНФИГУРАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════

APP_NAME="MyApp"
VERSION="1.2.3"
ARCH="${ARCH:-arm64}"

# Имя тома — отображается в Finder как имя диска при монтировании
VOLUME_NAME="${APP_NAME} ${VERSION}"

# Формат образа — влияет на размер, скорость, совместимость:
#   UDRW  — Read/Write, без сжатия, для staging/редактирования
#   UDRO  — Read-Only, без сжатия
#   UDZO  — zlib-сжатие, максимальная совместимость (все версии macOS)
#   UDBZ  — bzip2-сжатие, лучше чем UDZO, macOS 10.4+
#   ULFO  — lzfse-сжатие, быстрая распаковка + хорошее сжатие, macOS 10.11+  ← РЕКОМЕНДУЕТСЯ
#   ULMO  — lzma-сжатие, максимальное сжатие, macOS 10.15+
#   UDSP  — Sparse (растущий), для разработки и staging
#   UDSB  — Sparse Bundle (директория, растущий), macOS 10.5+
DMG_FORMAT="ULFO"

# Файловая система образа:
#   HFS+  — максимальная совместимость (все версии macOS)
#   APFS  — только macOS 10.13+
DMG_FS="HFS+"

OUTPUT_DMG="dist/${APP_NAME}-${VERSION}-darwin-${ARCH}.dmg"
TEMP_DMG="/tmp/${APP_NAME}-temp.dmg"
STAGING_DIR="/tmp/${APP_NAME}-staging"

# Опциональные ресурсы (раскомментируйте если используете)
# APP_BUNDLE="dist/${APP_NAME}.app"      # для GUI-приложений
# BACKGROUND_IMG="resources/background.png"  # фон DMG-окна
# VOLUME_ICON="resources/app.icns"       # иконка тома

mkdir -p "$(dirname "${OUTPUT_DMG}")"


# ═══════════════════════════════════════════════════════════════════════════════
# СПРАВОЧНИК: hdiutil create — все флаги
# ═══════════════════════════════════════════════════════════════════════════════
#
# hdiutil create [OPTIONS] <imagepath>
#
# -volname <name>
#   Имя тома (видно в Finder как имя диска при монтировании).
#   Не влияет на имя .dmg файла.
#
# -srcfolder <path>
#   Скопировать содержимое директории в образ.
#   hdiutil автоматически определит нужный размер.
#   НЕЛЬЗЯ комбинировать с -size.
#
# -srcdevice <device>
#   Создать образ из устройства (/dev/disk1 и т.д.).
#
# -format <format>
#   Формат образа (UDZO, ULFO, UDRW и т.д. — см. выше).
#
# -size <size>
#   Размер образа: 100m (мегабайт), 1g (гигабайт), 500k (килобайт).
#   Используется когда нужен writable образ для дальнейшего наполнения.
#   С -srcfolder НЕ используется (размер определяется автоматически).
#
# -fs <filesystem>
#   Файловая система: HFS+, APFS, ExFAT, FAT32, UDF.
#   По умолчанию HFS+ для совместимости.
#
# -ov
#   Overwrite — перезаписать если файл уже существует.
#   Без этого флага hdiutil вернёт ошибку при существующем файле.
#
# -quiet
#   Подавить вывод статуса (progress bar). Полезно в CI/CD.
#
# -verbose
#   Подробный вывод для отладки.
#
# -encryption <alg>
#   Шифрование: AES-128 или AES-256.
#   При создании потребует ввод пароля (или -passphrase).
#
# -passphrase <string>
#   Пароль для шифрованного образа (для скриптов; небезопасно через CLI).
#
# -type <type>
#   Тип образа: UDIF (по умолчанию), SPARSE, SPARSEBUNDLE.


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ А: Простейший DMG (для CLI-утилиты)
# ═══════════════════════════════════════════════════════════════════════════════
#
# hdiutil create -srcfolder скопирует содержимое директории напрямую.
# Один вызов — один DMG. Минимум шагов.

echo "=== Variant A: Simple DMG for CLI utility ==="

# Подготовить staging-директорию с содержимым DMG
mkdir -p "${STAGING_DIR}"

# Скопировать бинарник
cp "dist/myapp-darwin-${ARCH}" "${STAGING_DIR}/myapp"
chmod 755 "${STAGING_DIR}/myapp"

# Добавить README в DMG
cat > "${STAGING_DIR}/README.txt" << 'EOF'
# MyApp

To install, copy the binary to /usr/local/bin/:
  sudo cp myapp /usr/local/bin/

Or run from the current directory:
  ./myapp --help

Documentation: https://github.com/powertech-center/myapp
EOF

# Создать DMG из директории
# hdiutil автоматически определит нужный размер
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format "${DMG_FORMAT}" \
    -fs "${DMG_FS}" \
    -quiet \
    "${OUTPUT_DMG}"

# Удалить staging
rm -rf "${STAGING_DIR}"

echo "Created: ${OUTPUT_DMG}"


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ Б: "Красивый" DMG с кастомизацией через AppleScript
# ═══════════════════════════════════════════════════════════════════════════════
#
# Стандартный подход для GUI-приложений:
# 1. Создать writable образ (UDRW)
# 2. Смонтировать его
# 3. Скопировать содержимое + кастомизировать через AppleScript
# 4. Демонтировать
# 5. Конвертировать в read-only сжатый формат (ULFO)
#
# ВАЖНО: требует запущенный Finder с GUI. В headless CI использовать dmgbuild.

make_fancy_dmg() {
    local app_bundle="${1}"
    local output_dmg="${2}"
    local background_img="${3:-}"
    local volume_icon="${4:-}"

    local temp_dmg="/tmp/${APP_NAME}-fancy-temp.dmg"
    local mount_point="/Volumes/${VOLUME_NAME}"

    echo "=== Variant B: Fancy DMG with AppleScript customization ==="

    # Вычислить нужный размер (приложение × 2 + запас)
    local app_size
    app_size=$(du -sm "${app_bundle}" | cut -f1)
    local image_size=$(( app_size * 2 + 50 ))

    # ── Шаг 1: Создать writable образ ────────────────────────────────────────
    # Нужен UDRW для записи и кастомизации
    hdiutil create \
        -size "${image_size}m" \
        -fs "${DMG_FS}" \
        -volname "${VOLUME_NAME}" \
        -ov \
        "${temp_dmg}"

    # ── Шаг 2: Смонтировать образ ────────────────────────────────────────────
    # attach флаги:
    #   -noautoopen — не открывать Finder окно автоматически
    #   -noverify   — не проверять образ при монтировании (быстрее для доверенных)
    #   -quiet      — подавить вывод
    hdiutil attach \
        -noautoopen \
        -noverify \
        "${temp_dmg}" \
        -mountpoint "${mount_point}"

    # ── Шаг 3: Заполнить образ ───────────────────────────────────────────────

    # Скопировать приложение
    cp -R "${app_bundle}" "${mount_point}/"

    # Ярлык на папку Applications (drag-and-drop installation UX)
    ln -s /Applications "${mount_point}/Applications"

    # Добавить фоновое изображение (в скрытую папку)
    if [ -n "${background_img}" ] && [ -f "${background_img}" ]; then
        mkdir -p "${mount_point}/.background"
        cp "${background_img}" "${mount_point}/.background/background.png"
    fi

    # Иконка тома
    if [ -n "${volume_icon}" ] && [ -f "${volume_icon}" ]; then
        cp "${volume_icon}" "${mount_point}/.VolumeIcon.icns"
        # Установить флаг кастомной иконки тома
        SetFile -a C "${mount_point}" 2>/dev/null || true
    fi

    # ── Шаг 4: Кастомизация через AppleScript ────────────────────────────────
    # Настраивает вид окна Finder: расположение иконок, размер, фон
    # ТРЕБУЕТ: запущенный Finder (не работает в headless CI)
    local app_bundle_name
    app_bundle_name=$(basename "${app_bundle}")

    osascript << APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open

        -- Переключить на отображение иконок
        set current view of container window to icon view

        -- Скрыть toolbar и statusbar для чистого вида
        set toolbar visible of container window to false
        set statusbar visible of container window to false

        -- Размер и позиция окна: {left, top, right, bottom}
        set bounds of container window to {200, 120, 1000, 520}

        -- View options
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged   -- иконки не выстраиваются автоматически
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 12

        -- Фоновое изображение (если есть)
        if exists file ".background:background.png" of container window then
            set background picture of theViewOptions to file ".background:background.png"
        end if

        -- Позиции иконок
        set position of item "${app_bundle_name}" of container window to {200, 200}
        set position of item "Applications" of container window to {600, 200}

        -- Скрыть расширение файла
        set extension hidden of item "${app_bundle_name}" of container window to true

        -- Применить изменения
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

    # ── Шаг 5: Sync файловой системы ─────────────────────────────────────────
    # Обязательно перед демонтированием для сохранения DS_Store
    sync

    # ── Шаг 6: Демонтировать ─────────────────────────────────────────────────
    # detach флаги:
    #   -force — принудительно, даже если том занят
    hdiutil detach "${mount_point}" -quiet || \
    hdiutil detach "${mount_point}" -force -quiet

    # ── Шаг 7: Конвертировать в финальный сжатый формат ──────────────────────
    # convert флаги:
    #   -format — целевой формат
    #   -ov     — перезаписать если уже существует
    #   -o      — выходной файл
    hdiutil convert \
        "${temp_dmg}" \
        -format "${DMG_FORMAT}" \
        -ov \
        -quiet \
        -o "${output_dmg}"

    # ── Шаг 8: Очистить ───────────────────────────────────────────────────────
    rm -f "${temp_dmg}"

    echo "Created: ${output_dmg}"
}

# Раскомментировать для GUI-приложений:
# make_fancy_dmg \
#     "dist/${APP_NAME}.app" \
#     "${OUTPUT_DMG}" \
#     "resources/dmg-background.png" \
#     "resources/app.icns"


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ В: create-dmg (bash-обёртка, рекомендуется для простоты)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Установка: brew install create-dmg
# Документация: https://github.com/create-dmg/create-dmg
#
# Плюсы: декларативный API, не нужно управлять монтированием вручную
# Минусы: требует Finder (как AppleScript-подход)

make_create_dmg() {
    local app_bundle="${1}"
    local output_dmg="${2}"

    echo "=== Variant C: create-dmg ==="

    create-dmg \
        \
        --volname "${VOLUME_NAME}" \
        \
        --volicon "resources/app.icns" \
        \
        --background "resources/dmg-background.png" \
        \
        --window-pos 200 120 \
        \
        --window-size 800 400 \
        \
        --icon-size 96 \
        \
        --text-size 12 \
        \
        --icon "$(basename "${app_bundle}")" 200 200 \
        \
        --hide-extension "$(basename "${app_bundle}")" \
        \
        --app-drop-link 600 200 \
        \
        --add-file "README.txt" "README.txt" 400 350 \
        \
        --no-internet-enable \
        \
        --format "${DMG_FORMAT}" \
        \
        --hdiutil-quiet \
        \
        "${output_dmg}" \
        "${app_bundle}"

    # Описание флагов create-dmg:
    #
    # --volname <name>            Имя тома (видно в Finder)
    # --volicon <file>            .icns файл для иконки тома
    # --background <file>         Фоновое изображение DMG-окна
    # --window-pos X Y            Позиция окна на экране
    # --window-size W H           Размер окна в пикселях
    # --icon-size N               Размер иконок (пиксели)
    # --text-size N               Размер текста подписей
    # --icon "NAME" X Y           Позиция конкретной иконки по имени файла
    # --hide-extension "NAME"     Скрыть расширение файла в DMG
    # --app-drop-link X Y         Добавить ярлык Applications в указанную позицию
    # --add-file "NAME" "SRC" X Y Добавить произвольный файл в DMG
    # --add-symlink "NAME" "TGT" X Y Добавить символическую ссылку
    # --no-internet-enable        Отключить auto-open (интернет-загрузка)
    # --format FORMAT             Формат финального образа (ULFO, UDZO и т.д.)
    # --hdiutil-quiet             Тихий режим hdiutil
    # --skip-jenkins              Для CI без Finder (ограниченная кастомизация)

    echo "Created: ${output_dmg}"
}

# Раскомментировать для GUI-приложений с create-dmg:
# make_create_dmg "dist/${APP_NAME}.app" "${OUTPUT_DMG}"


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ Г: dmgbuild (Python, рекомендуется для CI/CD без Finder)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Установка: pip install dmgbuild
# Документация: https://dmgbuild.readthedocs.io/
#
# Плюсы: не требует Finder, работает в headless CI, Python API
# Минусы: требует Python и pip

make_dmgbuild() {
    local app_bundle="${1}"
    local output_dmg="${2}"
    local settings_file="/tmp/${APP_NAME}-dmgbuild-settings.py"

    echo "=== Variant D: dmgbuild (headless CI) ==="

    local app_bundle_name
    app_bundle_name=$(basename "${app_bundle}")

    # Создать конфигурационный файл Python
    cat > "${settings_file}" << SETTINGS
# -*- coding: utf-8 -*-
# dmgbuild settings — https://dmgbuild.readthedocs.io/
import os

# Входное приложение (может быть переопределено через -D app=...)
application = defines.get('app', '${app_bundle}')
appname = os.path.basename(application)

# ── Основные параметры ─────────────────────────────────────────────────────

# Имя тома (видно в Finder)
volname = defines.get('volname', '${VOLUME_NAME}')

# Формат образа: ULFO, UDZO, UDRW, UDBZ, ULMO и т.д.
format = defines.get('format', '${DMG_FORMAT}')

# Filesystem: HFS+ или APFS
filesystem = 'HFS+'

# ── Содержимое DMG ─────────────────────────────────────────────────────────

# Файлы для добавления в DMG
files = [application]

# Символические ссылки в DMG
symlinks = {
    'Applications': '/Applications',
}

# Иконка тома (badge_icon = наложить на дефолтную иконку диска)
# badge_icon = 'resources/app.icns'
# Или полностью заменить иконку тома:
# icon = 'resources/volume.icns'

# ── Внешний вид окна ───────────────────────────────────────────────────────

# Фоновое изображение
# background = 'resources/dmg-background.png'

# Позиция и размер окна: ((left, top), (width, height))
window_rect = ((200, 120), (800, 400))

# Расположение иконок: {'имя_файла': (x, y)}
icon_locations = {
    appname: (200, 200),
    'Applications': (600, 200),
}

# Размер иконок в пикселях
icon_size = 96

# Размер текста подписей
text_size = 12

# Скрыть расширения файлов
# show_icon_preview = False

# ── Дополнительные настройки ───────────────────────────────────────────────

# Скрытые файлы (не показывать в Finder)
# hide = ['.background', '.DS_Store']

# Дополнительные файлы которые нужно скрыть
# hide_extensions = [appname]
SETTINGS

    # Запустить dmgbuild
    dmgbuild \
        -s "${settings_file}" \
        -D "app=${app_bundle}" \
        -D "volname=${VOLUME_NAME}" \
        -D "format=${DMG_FORMAT}" \
        "${VOLUME_NAME}" \
        "${output_dmg}"

    # Флаги dmgbuild:
    #   -s <settings.py>   файл конфигурации
    #   -D KEY=VALUE       переопределить переменную (defines['KEY'] в settings.py)
    #   <volname>          имя тома (1-й позиционный аргумент)
    #   <output.dmg>       выходной файл (2-й позиционный аргумент)

    rm -f "${settings_file}"

    echo "Created: ${output_dmg}"
}

# Раскомментировать для dmgbuild:
# make_dmgbuild "dist/${APP_NAME}.app" "${OUTPUT_DMG}"


# ═══════════════════════════════════════════════════════════════════════════════
# СПРАВОЧНИК: другие команды hdiutil
# ═══════════════════════════════════════════════════════════════════════════════

show_hdiutil_reference() {
    cat << 'EOF'
# ── hdiutil attach — монтирование ──────────────────────────────────────────
hdiutil attach MyApp.dmg
hdiutil attach MyApp.dmg -mountpoint /Volumes/MyApp    # явная точка монтирования
hdiutil attach MyApp.dmg -noautoopen                   # не открывать Finder
hdiutil attach MyApp.dmg -noverify                     # без проверки целостности
hdiutil attach -quiet -noautoopen MyApp.dmg            # тихий режим для скриптов

# Получить точку монтирования программно:
MOUNT_POINT=$(hdiutil attach -noautoopen -quiet MyApp.dmg \
    | grep "/Volumes" | awk '{print $NF}')

# ── hdiutil detach — демонтирование ────────────────────────────────────────
hdiutil detach /Volumes/MyApp
hdiutil detach /dev/disk4
hdiutil detach -force /Volumes/MyApp    # принудительно (если том занят)

# ── hdiutil convert — конвертация форматов ─────────────────────────────────
hdiutil convert temp.dmg -format ULFO -ov -o final.dmg    # UDRW → ULFO
hdiutil convert temp.dmg -format UDZO -ov -o compat.dmg   # максимальная совместимость
hdiutil convert installer.iso -format ULFO -o installer.dmg  # ISO → DMG

# ── hdiutil verify — проверка целостности ──────────────────────────────────
hdiutil verify MyApp.dmg

# ── hdiutil imageinfo — метаданные образа ──────────────────────────────────
hdiutil imageinfo MyApp.dmg

# ── hdiutil info — смонтированные образы ───────────────────────────────────
hdiutil info

# ── hdiutil compact — оптимизация sparse-образа ────────────────────────────
hdiutil compact dev.sparseimage
EOF
}


# ═══════════════════════════════════════════════════════════════════════════════
# ОПЦИОНАЛЬНО: ПОДПИСЬ DMG И НОТАРИЗАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════
#
# С macOS 10.15 (Catalina) Gatekeeper блокирует неподписанные образы.
# Необходимо подписать содержимое DMG ДО создания образа, и/или подписать сам DMG.

sign_and_notarize_dmg() {
    local dmg_file="${1}"

    TEAM_ID="${APPLE_TEAM_ID:?APPLE_TEAM_ID not set}"
    APPLE_ID="${APPLE_ID:?APPLE_ID not set}"
    APP_PASSWORD="${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD not set}"
    CERT_NAME="Developer ID Application: PowerTech Center (${TEAM_ID})"

    echo "Signing DMG..."

    # Подписать сам DMG (опционально, для доп. доверия)
    codesign \
        --sign "${CERT_NAME}" \
        --timestamp \
        "${dmg_file}"

    echo "Submitting for notarization..."

    # Нотаризация
    xcrun notarytool submit "${dmg_file}" \
        --apple-id "${APPLE_ID}" \
        --password "${APP_PASSWORD}" \
        --team-id "${TEAM_ID}" \
        --wait \
        --output-format json | tee /tmp/notarization.json

    # Staple — встраивание нотаризационного тикета в DMG
    # После staple пользователь может установить без интернета
    xcrun stapler staple "${dmg_file}"

    # Проверка
    spctl -a -t open --context context:primary-signature -v "${dmg_file}"

    echo "Notarized: ${dmg_file}"
}

SIGN_DMG=false
if [ "${SIGN_DMG}" = "true" ]; then
    sign_and_notarize_dmg "${OUTPUT_DMG}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ВЕРИФИКАЦИЯ РЕЗУЛЬТАТА
# ═══════════════════════════════════════════════════════════════════════════════

if [ -f "${OUTPUT_DMG}" ]; then
    echo ""
    echo "Verifying: ${OUTPUT_DMG}"
    hdiutil verify "${OUTPUT_DMG}" && echo "Verification: OK"

    echo ""
    echo "Image info:"
    hdiutil imageinfo "${OUTPUT_DMG}" | grep -E "Format|Size|Sectors" || true

    echo ""
    echo "Done! DMG: ${OUTPUT_DMG}"
    echo "Size: $(du -sh "${OUTPUT_DMG}" | cut -f1)"
fi

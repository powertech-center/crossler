#!/bin/bash
# hdiutil.sh — полный пример создания macOS .dmg через hdiutil + create-dmg + dmgbuild
#
# hdiutil входит в macOS, установка не нужна. Работает ТОЛЬКО на macOS.
# create-dmg: brew install create-dmg  (bash-обёртка над hdiutil)
# dmgbuild:   pip install dmgbuild     (Python, без Finder — для headless CI)
#
# DMG — стандарт для GUI-приложений: пользователь видит .app и ярлык Applications,
# перетаскивает для установки. Для CLI-утилит предпочтительнее .pkg.
#
# Использование:
#   chmod +x hdiutil.sh && ./hdiutil.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_NAME="MyApp"
VERSION="${VERSION:-1.2.3}"
ARCH="${ARCH:-arm64}"
VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG_FORMAT="${DMG_FORMAT:-ULFO}"
OUTPUT_DMG="dist/${APP_NAME}-${VERSION}-darwin-${ARCH}.dmg"

mkdir -p "$(dirname "${OUTPUT_DMG}")"


# ═══════════════════════════════════════════════════════════════════════════════
# СПРАВОЧНИК: hdiutil create — все флаги
# ═══════════════════════════════════════════════════════════════════════════════
#
# Синтаксис: hdiutil create [OPTIONS] <imagepath>
#
# ── Источник содержимого ──────────────────────────────────────────────────────
#
# -srcfolder <path>
#   Скопировать содержимое директории в образ.
#   hdiutil автоматически определит нужный размер.
#   НЕЛЬЗЯ совмещать с -size.
#
# -srcdevice <device>
#   Создать образ из устройства (/dev/disk1 и т.д.).
#
# ── Размер ────────────────────────────────────────────────────────────────────
#
# -size <N>[b|k|m|g|t|p|e]
#   Размер: байты (b), кило (k), мега (m), гига (g), тера (t).
#   Нужен для пустых writable образов; с -srcfolder НЕ указывается.
#
# -sectors <N>
#   Размер в 512-байтных секторах.
#
# -megabytes <N>
#   Размер в мегабайтах (1024×1024).
#
# ── Формат и файловая система ─────────────────────────────────────────────────
#
# -format <FORMAT>
#   UDRW  — Read/Write, без сжатия (для staging/редактирования)
#   UDRO  — Read-Only, без сжатия
#   UDZO  — zlib-сжатие, максимальная совместимость (все версии macOS)
#   UDBZ  — bzip2-сжатие, лучше чем UDZO, macOS 10.4+
#   ULFO  — lzfse-сжатие, быстрая распаковка + хорошее сжатие, macOS 10.11+ ← РЕКОМЕНДУЕТСЯ
#   ULMO  — lzma-сжатие, максимальное сжатие, macOS 10.15+
#   UDSP  — Sparse Image (один файл, растущий), для разработки
#   UDSB  — Sparse Bundle (директория, растущий), macOS 10.5+
#   UDTO  — DVD/CD master
#
# -fs <filesystem>
#   HFS+   — максимальная совместимость (рекомендуется)
#   APFS   — только macOS 10.13+
#   ExFAT  — для кросс-платформенного содержимого
#   FAT32  — для максимальной совместимости с Windows
#   UDF    — для DVD/CD
#
# -type <type>
#   UDIF        — стандартный образ (по умолчанию)
#   SPARSE      — sparse image
#   SPARSEBUNDLE — sparse bundle
#
# -layout <layout>
#   Схема разделов:
#   NONE    — без таблицы разделов (только один том)
#   SPUD    — Apple Partition Map (legacy)
#   GPTSPUD — GUID Partition Table (современный, рекомендуется для APFS)
#   MBRSPUD — MBR (для совместимости с Windows)
#   ISOCD   — для CD/DVD образов
#
# -partitionType <type>
#   Тип раздела (по умолчанию Apple_HFS).
#
# -fsargs <args>
#   Дополнительные аргументы для newfs (форматирования файловой системы).
#
# ── Имя тома ──────────────────────────────────────────────────────────────────
#
# -volname <name>
#   Имя тома в Finder при монтировании. Не влияет на имя .dmg файла.
#
# ── Права на корень тома ──────────────────────────────────────────────────────
#
# -uid <uid>      — владелец корневой директории тома
# -gid <gid>      — группа корневой директории тома
# -mode <octal>   — права корневой директории тома
#
# ── Поведение ─────────────────────────────────────────────────────────────────
#
# -ov
#   Overwrite — перезаписать если файл уже существует.
#
# -attach
#   Смонтировать образ сразу после создания.
#
# -[no]crossdev
#   Пересекать ли границы устройств при копировании источника.
#
# -[no]scrub
#   Пропускать временные файлы (.DS_Store, .Trashes и т.д.) при создании.
#
# -[no]anyowners
#   Продолжать если права собственности непроверяемы.
#
# -skipunreadable
#   Пропускать нечитаемые файлы без аутентификации.
#
# -[no]atomic
#   Использовать атомарное копирование файлов.
#
# -copyuid <user>
#   Выполнять копирование от имени указанного пользователя.
#
# -align <alignment>
#   Выравнивание раздела данных (по умолчанию 4K).
#
# -stretch <max>
#   Максимальный размер для HFS+ stretch (для sparse).
#
# -imagekey sparse-band-size=<N>
#   Шаг роста sparse-образа в секторах (по умолчанию 2048 = 1MB).
#
# ── Шифрование ────────────────────────────────────────────────────────────────
#
# -encryption [AES-128|AES-256]
#   Шифрование образа.
#
# -stdinpass
#   Читать пароль из stdin (null-terminated string).
#
# -agentpass
#   Интерактивный ввод пароля через диалог.
#
# -recover <keychain>
#   Keychain для доступа к образу по сертификату.
#
# -certificate <cert>
#   Вторичный сертификат доступа (DER-encoded).
#
# -pubkey <PK1,PK2,...>
#   Список публичных ключей для шифрования (comma-separated).
#
# ── Вывод ─────────────────────────────────────────────────────────────────────
#
# -quiet        — подавить stdout (progress bar)
# -verbose      — подробный вывод
# -debug        — отладочный вывод
# -puppetstrings — машиночитаемый вывод прогресса (для CI-интеграций)
# -plist        — вывести результаты в формате plist


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ А: Простейший DMG (один вызов, для CLI-утилит)
# ═══════════════════════════════════════════════════════════════════════════════

echo "=== Variant A: Simple DMG (single call) ==="

STAGING_A="/tmp/${APP_NAME}-dmg-simple"
mkdir -p "${STAGING_A}"
cp "dist/myapp-darwin-${ARCH}" "${STAGING_A}/myapp"
chmod 755 "${STAGING_A}/myapp"
printf '# %s\n\nsudo cp myapp /usr/local/bin/\n' "${APP_NAME}" > "${STAGING_A}/README.txt"

hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_A}" \
    -ov \
    -format "${DMG_FORMAT}" \
    -fs "HFS+" \
    -quiet \
    "${OUTPUT_DMG}"

rm -rf "${STAGING_A}"
echo "Created: ${OUTPUT_DMG}"


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ Б: Ручной workflow с кастомизацией через AppleScript
# ═══════════════════════════════════════════════════════════════════════════════
#
# Используется для GUI-приложений (.app):
#   1. Создать writable UDRW образ
#   2. Смонтировать
#   3. Скопировать содержимое
#   4. Кастомизировать через AppleScript (расположение иконок, фон, размер окна)
#   5. Демонтировать
#   6. Конвертировать в сжатый read-only формат
#
# ТРЕБУЕТ запущенный Finder с GUI. В headless CI → использовать dmgbuild.

make_fancy_dmg() {
    local app_bundle="$1"
    local out_dmg="$2"
    local background="${3:-}"
    local vol_icon="${4:-}"

    local app_name
    app_name=$(basename "${app_bundle}")
    local temp_dmg="/tmp/${APP_NAME}-fancy-temp.dmg"
    local mount_point="/Volumes/${VOLUME_NAME}"

    # Вычислить размер с запасом 2x + 50MB
    local app_mb
    app_mb=$(du -sm "${app_bundle}" | cut -f1)
    local img_mb=$(( app_mb * 2 + 50 ))

    echo "=== Variant B: Fancy DMG with AppleScript ==="

    # ── Шаг 1: Создать writable образ ────────────────────────────────────────
    hdiutil create \
        -size "${img_mb}m" \
        -fs "HFS+" \
        -volname "${VOLUME_NAME}" \
        -ov \
        "${temp_dmg}"

    # ── Шаг 2: Смонтировать ───────────────────────────────────────────────────
    # attach флаги:
    #   -noautoopen — не открывать Finder автоматически
    #   -noverify   — не верифицировать образ при монтировании (быстрее)
    #   -mountpoint — явная точка монтирования
    #   -quiet      — подавить вывод
    #   -plist      — вывод в plist (для парсинга device-имени в скриптах)
    #   -readonly   — монтировать только для чтения
    #   -shadow     — shadow file для copy-on-write (не изменяет исходный образ)
    hdiutil attach \
        -noautoopen \
        -noverify \
        -mountpoint "${mount_point}" \
        "${temp_dmg}"

    # ── Шаг 3: Заполнить образ ───────────────────────────────────────────────
    cp -R "${app_bundle}" "${mount_point}/"
    ln -s /Applications "${mount_point}/Applications"

    if [ -n "${background}" ] && [ -f "${background}" ]; then
        mkdir -p "${mount_point}/.background"
        cp "${background}" "${mount_point}/.background/background.png"
    fi

    if [ -n "${vol_icon}" ] && [ -f "${vol_icon}" ]; then
        cp "${vol_icon}" "${mount_point}/.VolumeIcon.icns"
        SetFile -a C "${mount_point}" 2>/dev/null || true
    fi

    # ── Шаг 4: Кастомизация через AppleScript ────────────────────────────────
    osascript << APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 1000, 520}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 12
        if exists file ".background:background.png" of container window then
            set background picture of theViewOptions to file ".background:background.png"
        end if
        set position of item "${app_name}" of container window to {200, 200}
        set position of item "Applications" of container window to {600, 200}
        set extension hidden of item "${app_name}" of container window to true
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

    # ── Шаг 5: Sync и демонтирование ─────────────────────────────────────────
    sync

    # detach флаги:
    #   -force — принудительно, даже если том занят
    #   -quiet — подавить вывод
    hdiutil detach "${mount_point}" -quiet || \
    hdiutil detach "${mount_point}" -force -quiet

    # ── Шаг 6: Конвертация в сжатый формат ───────────────────────────────────
    # convert флаги:
    #   -format — целевой формат
    #   -ov     — перезаписать если существует
    #   -o      — выходной файл
    #   -quiet  — подавить вывод
    #   -encryption [AES-128|AES-256] — зашифровать результат
    hdiutil convert \
        "${temp_dmg}" \
        -format "${DMG_FORMAT}" \
        -ov \
        -quiet \
        -o "${out_dmg}"

    rm -f "${temp_dmg}"
    echo "Created: ${out_dmg}"
}

# Пример вызова для GUI-приложения:
# make_fancy_dmg "dist/${APP_NAME}.app" "${OUTPUT_DMG}" \
#     "resources/dmg-background.png" "resources/app.icns"


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ В: create-dmg — все флаги
# ═══════════════════════════════════════════════════════════════════════════════
#
# brew install create-dmg
# Документация: https://github.com/create-dmg/create-dmg
#
# Плюсы: декларативный API, управляет монтированием автоматически
# Минусы: требует Finder (headless CI → dmgbuild)

make_create_dmg() {
    local app_bundle="$1"
    local out_dmg="$2"

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
        --add-file "README.txt" "README.txt" 400 320 \
        \
        --eula "LICENSE.txt" \
        \
        --no-internet-enable \
        \
        --format "${DMG_FORMAT}" \
        \
        --filesystem "HFS+" \
        \
        --hdiutil-quiet \
        \
        --hdiutil-retries 5 \
        \
        --applescript-sleep-duration 5 \
        \
        "${out_dmg}" \
        "${app_bundle}"

    # ── Справочник всех флагов create-dmg ─────────────────────────────────
    #
    # --volname <name>              Имя тома в Finder
    # --volicon <file.icns>         Иконка тома (.icns)
    # --background <file>           Фоновое изображение (png, gif, jpg)
    # --window-pos <x> <y>          Позиция окна на экране
    # --window-size <w> <h>         Размер окна в пикселях
    # --icon-size <N>               Размер иконок (до 128)
    # --text-size <N>               Размер текста (10–16)
    # --icon <file> <x> <y>         Позиция иконки конкретного файла
    # --hide-extension <file>       Скрыть расширение файла в DMG
    # --app-drop-link <x> <y>       Добавить ярлык папки Applications
    # --ql-drop-link <x> <y>        Добавить ярлык QuickLook
    # --add-file <name> <src> <x> <y>  Добавить произвольный файл
    # --add-symlink <name> <tgt> <x> <y>  Добавить символическую ссылку
    # --eula <file>                 Лицензионное соглашение (показывается при монтировании)
    # --no-internet-enable          Отключить auto-mount поведение
    # --format <FORMAT>             Формат финального образа (ULFO, UDZO, UDBZ, ULMO)
    # --filesystem <FS>             Файловая система (HFS+, APFS)
    # --disk-image-size <N>         Ручной размер образа в MB (вместо автоопределения)
    # --encrypt                     Шифрование AES-256
    # --encrypt-aes128              Шифрование AES-128
    # --codesign <identity>         Подписать disk image
    # --notarize <credentials>      Нотаризировать и приложить staple
    # --hdiutil-verbose             Подробный вывод hdiutil
    # --hdiutil-quiet               Подавить вывод hdiutil
    # --hdiutil-retries <N>         Повторы при "Resource busy" (по умолчанию 5)
    # --applescript-sleep-duration <N>  Задержка перед AppleScript (сек, по умолчанию 5)
    # --skip-jenkins                Пропустить AppleScript-кастомизацию (headless CI)
    # --sandbox-safe                Режим совместимости с sandbox
    # --rez <path>                  Путь к нестандартному Rez

    echo "Created: ${out_dmg}"
}

# Пример вызова:
# make_create_dmg "dist/${APP_NAME}.app" "${OUTPUT_DMG}"


# ═══════════════════════════════════════════════════════════════════════════════
# ВАРИАНТ Г: dmgbuild — полный settings.py + все настройки
# ═══════════════════════════════════════════════════════════════════════════════
#
# pip install dmgbuild
# Документация: https://dmgbuild.readthedocs.io/
#
# РЕКОМЕНДУЕТСЯ для CI/CD: не требует Finder, работает headless.

make_dmgbuild() {
    local app_bundle="$1"
    local out_dmg="$2"
    local settings_file="/tmp/${APP_NAME}-dmgbuild-settings.py"
    local app_name
    app_name=$(basename "${app_bundle}")

    echo "=== Variant D: dmgbuild (headless CI) ==="

    cat > "${settings_file}" << SETTINGS
# -*- coding: utf-8 -*-
# dmgbuild settings.py — https://dmgbuild.readthedocs.io/
import os

# Входное приложение. Переопределяется через -D app=...
application = defines.get('app', '${app_bundle}')
appname = os.path.basename(application)

# ── ОБРАЗ ──────────────────────────────────────────────────────────────────

# Имя тома (видно в Finder при монтировании)
volname = defines.get('volname', '${VOLUME_NAME}')

# Формат финального образа:
#   UDZO — zlib, максимальная совместимость
#   ULFO — lzfse, быстрая распаковка (macOS 10.11+) ← рекомендуется
#   ULMO — lzma, максимальное сжатие (macOS 10.15+)
#   UDRW — writable, для staging
format = defines.get('format', '${DMG_FORMAT}')

# Файловая система: HFS+ (рекомендуется) или APFS
filesystem = 'HFS+'

# Явный размер файловой системы внутри образа ('100m', '1g').
# Если не задан — определяется автоматически.
# size = None

# Сжать файловую систему до минимума после копирования файлов.
shrink = True

# ── СОДЕРЖИМОЕ ─────────────────────────────────────────────────────────────

# Файлы и директории для копирования в DMG
files = [application]

# Символические ссылки в DMG
symlinks = {
    'Applications': '/Applications',
}

# Файлы, скрытые от пользователя в Finder (но присутствующие в образе)
hide = ['.background', '.DS_Store', '.Trashes', '.fseventsd']

# Файлы с скрытым расширением в Finder
hide_extensions = [appname]

# Иконка тома — полная замена дефолтной иконки диска
# icon = 'resources/volume.icns'

# Badge icon — наложить поверх дефолтной иконки диска
badge_icon = 'resources/app.icns'

# ── ВНЕШНИЙ ВИД ОКНА ───────────────────────────────────────────────────────

# Фоновое изображение или цвет:
#   строка с путём к файлу: 'resources/background.png'
#   CSS-цвет:               '#3a3a3a'
#   None:                   стандартный фон Finder
background = 'resources/dmg-background.png'

# Позиция и размер окна: ((left, top), (width, height))
window_rect = ((200, 120), (800, 400))

# Показывать строку состояния Finder
show_status_bar = False

# Показывать вкладки
show_tab_view = False

# Показывать toolbar
show_toolbar = False

# Показывать path bar
show_pathbar = False

# Показывать sidebar
show_sidebar = False

# Ширина sidebar в точках
sidebar_width = 180

# Вид по умолчанию: 'icon-view' или 'list-view'
default_view = 'icon-view'

# Показывать превью иконок (Quick Look thumbnail)
show_icon_preview = False

# Принудительно записать настройки icon view (даже если default_view != icon-view)
include_icon_view_settings = True

# Принудительно записать настройки list view
include_list_view_settings = False

# ── ICON VIEW ──────────────────────────────────────────────────────────────

# Позиции иконок: {'имя_в_dmg': (x, y)}
icon_locations = {
    appname: (200, 200),
    'Applications': (600, 200),
}

# Автоупорядочивание иконок:
#   None       — ручное расположение (используются icon_locations)
#   'name'     — по имени
#   'date-modified', 'date-created', 'date-added', 'date-last-opened'
#   'size', 'kind', 'label'
arrange_by = None

# Смещение сетки (x, y)
grid_offset = (0, 0)

# Шаг сетки (макс. 100)
grid_spacing = 100

# Позиция прокрутки (x, y)
scroll_position = (0, 0)

# Позиция подписи иконок: 'bottom' или 'right'
label_pos = 'bottom'

# Размер текста подписей в точках
text_size = 12

# Размер иконок в точках
icon_size = 96

# ── LIST VIEW ──────────────────────────────────────────────────────────────

# Размер иконок в list view
list_icon_size = 16

# Размер текста в list view
list_text_size = 12

# Позиция прокрутки list view
list_scroll_position = (0, 0)

# Столбец сортировки по умолчанию
list_sort_by = 'name'

# Относительные даты ("Сегодня", "Вчера")
list_use_relative_dates = True

# Вычислять размеры всех элементов
list_calculate_all_sizes = False

# Список столбцов по порядку
list_columns = ('name', 'date-modified', 'size', 'kind')

# Ширина столбцов
list_column_widths = {
    'name': 300,
    'date-modified': 180,
    'size': 100,
    'kind': 100,
}

# Направление сортировки по столбцам: 'ascending' или 'descending'
list_column_sort_directions = {
    'name': 'ascending',
    'date-modified': 'descending',
}

# ── ЛИЦЕНЗИЯ ───────────────────────────────────────────────────────────────
# Показывается при монтировании DMG. Пользователь должен принять.

license = {
    'default-language': 'en_US',
    'licenses': {
        'en_US': 'LICENSE.txt',
        # 'ru_RU': 'LICENSE_ru.txt',  # локализованные варианты
    },
    'buttons': {
        # Порядок: язык, кнопка согласия, отказа, печати, сохранения, подсказка
        'en_US': (
            'English',
            'Agree',
            'Disagree',
            'Print',
            'Save',
            'If you agree with the terms of this license, click Agree.',
        ),
    },
}
SETTINGS

    dmgbuild \
        -s "${settings_file}" \
        -D "app=${app_bundle}" \
        -D "volname=${VOLUME_NAME}" \
        -D "format=${DMG_FORMAT}" \
        "${VOLUME_NAME}" \
        "${out_dmg}"
    # Флаги dmgbuild:
    #   -s <settings.py>     файл конфигурации
    #   -D <key=value>       переменная (доступна в settings.py через defines['key'])
    #   <volname>            имя тома (1-й аргумент)
    #   <output.dmg>         выходной файл (2-й аргумент)

    rm -f "${settings_file}"
    echo "Created: ${out_dmg}"
}

# Пример вызова:
# make_dmgbuild "dist/${APP_NAME}.app" "${OUTPUT_DMG}"


# ═══════════════════════════════════════════════════════════════════════════════
# СПРАВОЧНИК: другие команды hdiutil
# ═══════════════════════════════════════════════════════════════════════════════

# ── hdiutil attach ─────────────────────────────────────────────────────────
# hdiutil attach [OPTIONS] <image>
#
#   -mountpoint <path>   — явная точка монтирования
#   -noautoopen          — не открывать Finder окно
#   -noverify            — без проверки целостности (быстрее)
#   -quiet               — подавить вывод
#   -readonly            — монтировать только для чтения
#   -shadow [<file>]     — shadow file: изменения в overlay-файл, исходник не трогается
#   -encryption          — запросить пароль для шифрованного образа
#   -stdinpass           — читать пароль из stdin
#   -plist               — вывод в plist (содержит dev-entry и mount-point)
#   -owners on|off       — включить/выключить проверку прав собственности
#   -imagekey <key=val>  — параметры для конкретных форматов

# Получить точку монтирования программно:
# MOUNT=$(hdiutil attach -noautoopen -quiet -plist image.dmg \
#     | plutil -extract "system-entities.0.mount-point" raw -)

# ── hdiutil detach ─────────────────────────────────────────────────────────
# hdiutil detach [OPTIONS] <mount-point|device>
#
#   -force   — принудительно, даже если том занят
#   -quiet   — подавить вывод

# ── hdiutil convert ────────────────────────────────────────────────────────
# hdiutil convert <input> -format <FORMAT> -o <output> [OPTIONS]
#
#   -format <FORMAT>   — целевой формат (ULFO, UDZO, UDRW, ...)
#   -o <file>          — выходной файл
#   -ov                — перезаписать
#   -quiet             — подавить вывод
#   -encryption        — зашифровать результат

# ── hdiutil verify ─────────────────────────────────────────────────────────
# hdiutil verify <image>   — проверить контрольные суммы

# ── hdiutil imageinfo ──────────────────────────────────────────────────────
# hdiutil imageinfo <image>   — метаданные (формат, размер, файловая система)

# ── hdiutil info ───────────────────────────────────────────────────────────
# hdiutil info   — список всех смонтированных образов

# ── hdiutil compact ────────────────────────────────────────────────────────
# hdiutil compact <sparseimage>   — оптимизировать sparse-образ

# ── hdiutil resize ─────────────────────────────────────────────────────────
# hdiutil resize -size <N>[m|g] <image>   — изменить размер UDRW или sparse


# ═══════════════════════════════════════════════════════════════════════════════
# ПОДПИСЬ DMG И НОТАРИЗАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════
#
# С macOS 10.15 Gatekeeper блокирует неподписанные образы.
# Порядок: подписать содержимое (.app) → создать DMG → подписать DMG → нотаризировать → staple

SIGN_DMG="${SIGN_DMG:-false}"

if [ "${SIGN_DMG}" = "true" ]; then
    TEAM_ID="${APPLE_TEAM_ID:?}"
    APPLE_ID="${APPLE_ID:?}"
    APP_PASSWORD="${APPLE_APP_PASSWORD:?}"
    APP_CERT="Developer ID Application: PowerTech Center (${TEAM_ID})"

    # Подписать сам DMG
    codesign \
        --sign "${APP_CERT}" \
        --timestamp \
        "${OUTPUT_DMG}"

    # Нотаризация
    xcrun notarytool submit "${OUTPUT_DMG}" \
        --apple-id "${APPLE_ID}" \
        --password "${APP_PASSWORD}" \
        --team-id "${TEAM_ID}" \
        --wait \
        --output-format json

    # Staple — встроить тикет нотаризации (офлайн-проверка Gatekeeper)
    xcrun stapler staple "${OUTPUT_DMG}"

    # Проверка
    spctl -a -t open --context context:primary-signature -v "${OUTPUT_DMG}"
fi


# ═══════════════════════════════════════════════════════════════════════════════
# ВЕРИФИКАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════

if [ -f "${OUTPUT_DMG}" ]; then
    hdiutil verify "${OUTPUT_DMG}" && echo "Verification: OK"
    echo "Size: $(du -sh "${OUTPUT_DMG}" | cut -f1)"
    echo "Done: ${OUTPUT_DMG}"
fi

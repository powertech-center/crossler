# hdiutil — создание macOS образов (.dmg)

## Что такое hdiutil

**hdiutil** — утилита командной строки macOS для управления дисковыми образами. Входит в стандартную поставку macOS, дополнительная установка не требуется. Работает с фреймворком DiskImages.

DMG-формат — стандарт де-факто для дистрибуции macOS-приложений. Пользователь скачивает `.dmg`, монтирует его (двойным кликом), видит открытое окно Finder с приложением и ярлыком папки Applications — и перетаскивает приложение для установки.

### Основные операции

| Команда | Описание |
|---------|---------|
| `hdiutil create` | Создать новый образ |
| `hdiutil attach` | Смонтировать образ |
| `hdiutil detach` | Демонтировать образ |
| `hdiutil convert` | Конвертировать между форматами |
| `hdiutil verify` | Проверить целостность образа |
| `hdiutil compact` | Оптимизировать sparse-образ |
| `hdiutil info` | Информация о смонтированных образах |
| `hdiutil imageinfo` | Метаданные образа |

### Установка

hdiutil входит в macOS и не требует установки. Проверка:
```bash
hdiutil --version
```

---

## Команда create — создание образа

### Синтаксис

```bash
hdiutil create [options] <imagepath>
```

### Основные флаги

| Флаг | Описание |
|------|---------|
| `-volname <name>` | Имя тома (видно в Finder как имя диска) |
| `-srcfolder <path>` | Скопировать содержимое директории в образ |
| `-srcdevice <device>` | Создать образ из устройства |
| `-format <format>` | Формат образа (UDZO, ULFO, UDRW и др.) |
| `-size <size>` | Размер образа (100m, 1g, 500k) |
| `-fs <fs>` | Файловая система: `HFS+`, `APFS`, `ExFAT` |
| `-ov` | Перезаписать если файл уже существует |
| `-quiet` | Подавить вывод статуса |
| `-verbose` | Подробный вывод |
| `-encryption <alg>` | Шифрование: `AES-128` или `AES-256` |
| `-type <type>` | Тип образа: `UDIF`, `SPARSE`, `SPARSEBUNDLE` |

### Примеры создания

```bash
# Создать DMG из папки (самый простой способ)
hdiutil create -volname "CrosslerApp" -srcfolder ./MyApp.app -ov -format ULFO MyApp.dmg

# Создать пустой writable образ для последующей настройки
hdiutil create -size 200m -fs HFS+ -volname "MyApp" -ov temp.dmg

# Создать sparse-образ (растущий) для разработки
hdiutil create -size 1g -fs HFS+ -type SPARSE -volname "Dev" -ov dev.sparseimage

# С шифрованием
hdiutil create -size 100m -fs HFS+ -volname "Secure" -encryption AES-256 secure.dmg
```

---

## Форматы образов

| Формат | Описание | Сжатие | Совместимость | Использование |
|--------|---------|--------|---|---|
| `UDRW` | Read/Write | Нет | Все версии | Редактирование, staging |
| `UDRO` | Read-Only | Нет | Все версии | Архивирование |
| `UDZO` | zlib compressed | zlib | Все версии | Стандарт, широкая совместимость |
| `UDBZ` | bzip2 compressed | bzip2 | 10.4+ | Лучшее сжатие чем UDZO |
| `ULFO` | lzfse compressed | lzfse | 10.11+ | Быстрая распаковка, хорошее сжатие |
| `ULMO` | lzma compressed | lzma | 10.15+ | Максимальное сжатие |
| `UDSP` | Sparse Image | — | Все версии | Разработка (один файл, растущий) |
| `UDSB` | Sparse Bundle | — | 10.5+ | Разработка (директория, растущий) |
| `UDTO` | DVD/CD master | — | Для CD/DVD | DVD/CD мастер |

### Рекомендации по выбору формата

- **Для дистрибуции приложений:** `ULFO` — быстрая распаковка, хорошее сжатие, macOS 10.11+
- **Для максимальной совместимости:** `UDZO` — работает на всех версиях macOS
- **Для максимального сжатия:** `ULMO` — только для macOS 10.15+
- **Для разработки и staging:** `UDSP` — не нужно задавать размер заранее
- **Для тестирования:** `UDRW` — можно монтировать и изменять

---

## Команды attach и detach

### attach — монтирование образа

```bash
# Базовое монтирование
hdiutil attach MyApp.dmg

# С указанием точки монтирования
hdiutil attach MyApp.dmg -mountpoint /Volumes/MyApp

# Без автоматического открытия Finder
hdiutil attach MyApp.dmg -noautoopen

# Без верификации (быстрее для доверенных образов)
hdiutil attach MyApp.dmg -noverify

# Тихое монтирование для скриптов
hdiutil attach -quiet -noautoopen MyApp.dmg
```

Вывод содержит device-имя и точку монтирования:
```
/dev/disk4    Apple_partition_scheme
/dev/disk4s1  Apple_partition_map
/dev/disk4s2  Apple_HFS    /Volumes/MyApp
```

Для скриптов — получить точку монтирования:
```bash
MOUNT_POINT=$(hdiutil attach -noautoopen -quiet MyApp.dmg | grep "^/Volumes" | awk '{print $NF}')
echo "Mounted at: $MOUNT_POINT"
```

### detach — демонтирование

```bash
# По имени тома
hdiutil detach /Volumes/MyApp

# По device
hdiutil detach /dev/disk4

# Force (если том занят)
hdiutil detach -force /Volumes/MyApp

# Все смонтированные образы (осторожно!)
# hdiutil info | grep "^/dev/disk" | awk '{print $1}' | xargs -I{} hdiutil detach {}
```

---

## Команда convert — конвертация форматов

```bash
# UDRW → ULFO (для дистрибуции)
hdiutil convert temp.dmg -format ULFO -ov -o final.dmg

# UDRW → UDZO (максимальная совместимость)
hdiutil convert temp.dmg -format UDZO -ov -o final.dmg

# ISO → DMG
hdiutil convert installer.iso -format ULFO -o installer.dmg

# DMG → ISO (для виртуальных машин)
hdiutil convert image.dmg -format UDTO -o image.iso
```

---

## Рабочий процесс создания "красивого" DMG

Стандартный DMG для дистрибуции приложений:
- Содержит приложение и ярлык папки Applications
- Открывается в Finder с кастомным фоном
- Иконки расставлены в удобном положении

### Ручной workflow (базовый)

```bash
#!/bin/bash
set -e

APP_NAME="MyApp"
APP_BUNDLE="MyApp.app"
VERSION="1.0.0"
VOLUME_NAME="${APP_NAME} ${VERSION}"
OUTPUT_DMG="dist/${APP_NAME}-${VERSION}.dmg"
TEMP_DMG="/tmp/${APP_NAME}-temp.dmg"

# 1. Создать writable образ
hdiutil create -size 200m -fs HFS+ -volname "${VOLUME_NAME}" -ov "${TEMP_DMG}"

# 2. Смонтировать
MOUNT_POINT=$(hdiutil attach -noautoopen "${TEMP_DMG}" | grep "/Volumes" | awk '{print $NF}')

# 3. Скопировать приложение
cp -R "${APP_BUNDLE}" "${MOUNT_POINT}/"

# 4. Создать ярлык на Applications
ln -s /Applications "${MOUNT_POINT}/Applications"

# 5. Демонтировать
hdiutil detach "${MOUNT_POINT}"

# 6. Конвертировать в сжатый read-only формат
hdiutil convert "${TEMP_DMG}" -format ULFO -ov -o "${OUTPUT_DMG}"

# 7. Очистить
rm -f "${TEMP_DMG}"
```

### Workflow с кастомизацией через AppleScript

```bash
#!/bin/bash
set -e

APP_NAME="MyApp"
APP_BUNDLE="MyApp.app"
BACKGROUND_IMG="resources/dmg-background.png"
ICON_FILE="resources/app.icns"
VOLUME_NAME="${APP_NAME}"
TEMP_DMG="/tmp/temp.dmg"
OUTPUT_DMG="dist/MyApp.dmg"

# 1. Создать writable образ
hdiutil create -size 200m -fs HFS+ -volname "${VOLUME_NAME}" -ov "${TEMP_DMG}"

# 2. Смонтировать
hdiutil attach -noautoopen "${TEMP_DMG}"
MOUNT_POINT="/Volumes/${VOLUME_NAME}"

# 3. Скопировать содержимое
cp -R "${APP_BUNDLE}" "${MOUNT_POINT}/"
ln -s /Applications "${MOUNT_POINT}/Applications"

# 4. Скопировать фоновое изображение (в скрытую папку)
mkdir -p "${MOUNT_POINT}/.background"
cp "${BACKGROUND_IMG}" "${MOUNT_POINT}/.background/background.png"

# 5. Кастомизация через AppleScript
osascript << EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open

        -- Переключить на icon view
        set current view of container window to icon view

        -- Скрыть тулбар и статус бар
        set toolbar visible of container window to false
        set statusbar visible of container window to false

        -- Размер и позиция окна: {left, top, right, bottom}
        set bounds of container window to {200, 100, 900, 500}

        -- Установить view options
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 12

        -- Фоновое изображение
        set background picture of theViewOptions to file ".background:background.png"

        -- Расположить иконки
        set position of item "${APP_NAME}.app" of container window to {200, 190}
        set position of item "Applications" of container window to {500, 190}

        -- Обновить и закрыть
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# 6. Sync файловой системы
sync

# 7. Демонтировать
hdiutil detach "${MOUNT_POINT}"

# 8. Конвертировать в сжатый формат
hdiutil convert "${TEMP_DMG}" -format ULFO -ov -o "${OUTPUT_DMG}"

# 9. Очистить
rm -f "${TEMP_DMG}"

echo "DMG created: ${OUTPUT_DMG}"
```

---

## Инструменты автоматизации

### create-dmg (bash-скрипт)

Обёртка над hdiutil + AppleScript, самый простой для базовых случаев.

```bash
# Установка
brew install create-dmg

# Минимальный пример
create-dmg \
  --volname "MyApp" \
  --srcfolder "MyApp.app" \
  "MyApp.dmg"

# Полный пример с кастомизацией
create-dmg \
  --volname "MyApp 1.0" \
  --volicon "MyApp.icns" \
  --background "background.png" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --text-size 14 \
  --icon "MyApp.app" 200 200 \
  --hide-extension "MyApp.app" \
  --app-drop-link 600 200 \
  "MyApp.dmg" \
  "./MyApp.app"
```

Параметры create-dmg:

| Параметр | Описание |
|----------|---------|
| `--volname <name>` | Имя тома |
| `--volicon <file>` | .icns файл для иконки тома |
| `--background <file>` | Фоновое изображение |
| `--window-pos X Y` | Позиция окна на экране |
| `--window-size W H` | Размер окна |
| `--icon-size N` | Размер иконок в пикселях |
| `--text-size N` | Размер текста подписей |
| `--icon "NAME" X Y` | Позиция конкретной иконки |
| `--hide-extension "NAME"` | Скрыть расширение файла |
| `--app-drop-link X Y` | Позиция ярлыка Applications |
| `--add-file "NAME" "SRC" X Y` | Добавить произвольный файл |
| `--add-symlink "NAME" "TARGET" X Y` | Добавить symlink |
| `--no-internet-enable` | Отключить автооткрытие |
| `--format FORMAT` | Формат образа (ULFO, UDZO и др.) |
| `--hdiutil-quiet` | Тихий режим hdiutil |
| `--skip-jenkins` | Для CI без Finder |

### dmgbuild (Python)

Более надёжный подход для CI/CD — не требует запущенного Finder.

```bash
# Установка
pip install dmgbuild
```

Конфигурационный файл `settings.py`:
```python
# -*- coding: utf-8 -*-

# Основные параметры
application = defines.get('app', 'MyApp.app')
appname = os.path.basename(application)

# Имя тома
volname = 'MyApp'

# Содержимое
files = [application]
symlinks = {'Applications': '/Applications'}

# Иконка тома
badge_icon = 'MyApp.icns'  # или icon = 'volume.icns'

# Фон
background = 'background.png'

# Размер окна: ((left, top), (width, height))
window_rect = ((200, 120), (800, 400))

# Расположение иконок
icon_locations = {
    appname: (200, 200),
    'Applications': (600, 200),
}

# Параметры view
icon_size = 96
text_size = 12

# Формат сжатия
format = defines.get('format', 'ULFO')
```

Использование:
```bash
# Простое создание
dmgbuild -s settings.py "MyApp" MyApp.dmg

# С переопределением переменных
dmgbuild -s settings.py -D app=dist/MyApp.app -D format=UDZO "MyApp" MyApp.dmg
```

---

## Практические примеры для Crossler

### Пример 1: Простейший DMG для консольной утилиты

Для консольных утилит DMG менее распространён, чем .pkg, но возможен:

```bash
#!/bin/bash
set -e

BINARY="dist/crossler-darwin-arm64"
VERSION="1.0.0"
OUTPUT="dist/crossler-darwin-arm64.dmg"

# Создать временную директорию
STAGING=$(mktemp -d)
cp "${BINARY}" "${STAGING}/crossler"
chmod 755 "${STAGING}/crossler"

# Создать README
cat > "${STAGING}/README.txt" << 'EOF'
# crossler

Copy the `crossler` binary to /usr/local/bin/:
  sudo cp crossler /usr/local/bin/

Or run from any directory:
  ./crossler --help
EOF

# Создать DMG
hdiutil create \
    -volname "Crossler ${VERSION}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format ULFO \
    "${OUTPUT}"

rm -rf "${STAGING}"
echo "Created: ${OUTPUT}"
```

### Пример 2: DMG с приложением и ярлыком (через create-dmg)

```bash
#!/bin/bash
set -e

APP_BUNDLE="dist/MyApp.app"
VERSION=$(cat VERSION)
OUTPUT="dist/MyApp-${VERSION}.dmg"

# Подписать приложение (перед упаковкой)
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Name (TEAM_ID)" \
    --options runtime \
    --timestamp \
    "${APP_BUNDLE}"

# Создать DMG
create-dmg \
    --volname "MyApp ${VERSION}" \
    --volicon "resources/app.icns" \
    --background "resources/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "MyApp.app" 200 200 \
    --hide-extension "MyApp.app" \
    --app-drop-link 600 200 \
    "${OUTPUT}" \
    "${APP_BUNDLE}"

echo "Created: ${OUTPUT}"
```

### Пример 3: DMG через dmgbuild (для CI/CD)

settings.py:
```python
import os

application = defines.get('app', 'MyApp.app')
appname = os.path.basename(application)
volname = defines.get('volname', 'MyApp')

files = [application]
symlinks = {'Applications': '/Applications'}

badge_icon = 'resources/app.icns'
background = 'resources/background.png'

window_rect = ((200, 120), (800, 400))
icon_locations = {
    appname: (200, 200),
    'Applications': (600, 200),
}

icon_size = 96
text_size = 12
format = defines.get('format', 'ULFO')
```

Makefile:
```makefile
dist/MyApp-$(VERSION).dmg: dist/MyApp.app
	dmgbuild \
	  -s resources/dmg-settings.py \
	  -D app=$< \
	  -D volname="MyApp $(VERSION)" \
	  "MyApp $(VERSION)" \
	  $@
```

### Пример 4: Полный pipeline с notarization

```bash
#!/bin/bash
set -e

APP="dist/MyApp.app"
VERSION="1.0.0"
TEAM_ID="XXXXXXXXXX"
APPLE_ID="developer@example.com"
APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password
CERT_NAME="Developer ID Application: Name (TEAM_ID)"
DMG_OUTPUT="dist/MyApp-${VERSION}.dmg"
SIGNED_DMG="dist/MyApp-${VERSION}-signed.dmg"

# 1. Подписать приложение
codesign \
    --deep --force --verify --verbose \
    --sign "${CERT_NAME}" \
    --options runtime \
    --timestamp \
    "${APP}"

# 2. Создать DMG
create-dmg \
    --volname "MyApp ${VERSION}" \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "MyApp.app" 200 200 \
    --app-drop-link 600 200 \
    "${DMG_OUTPUT}" \
    "${APP}"

# 3. Подписать DMG
codesign \
    --sign "${CERT_NAME}" \
    --timestamp \
    "${DMG_OUTPUT}"

# 4. Notarize
xcrun notarytool submit "${DMG_OUTPUT}" \
    --apple-id "${APPLE_ID}" \
    --password "${APP_PASSWORD}" \
    --team-id "${TEAM_ID}" \
    --wait \
    --output-format json | tee /tmp/notarization.json

# 5. Staple
xcrun stapler staple "${DMG_OUTPUT}"

# 6. Проверить
spctl -a -t open --context context:primary-signature -v "${DMG_OUTPUT}"

echo "Ready for distribution: ${DMG_OUTPUT}"
```

### Пример 5: Фрагмент Makefile для Crossler

```makefile
VERSION ?= $(shell git describe --tags --abbrev=0 | sed 's/^v//')

dist/crossler-darwin-arm64.dmg: dist/crossler-darwin-arm64
	@echo "Building macOS DMG (arm64)..."
	@mkdir -p /tmp/crossler-dmg
	@cp $< /tmp/crossler-dmg/crossler
	@chmod 755 /tmp/crossler-dmg/crossler
	@printf '# crossler\n\nCopy to /usr/local/bin/: sudo cp crossler /usr/local/bin/\n' \
	    > /tmp/crossler-dmg/README.txt
	@hdiutil create \
	    -volname "Crossler $(VERSION)" \
	    -srcfolder /tmp/crossler-dmg \
	    -ov \
	    -format ULFO \
	    $@
	@rm -rf /tmp/crossler-dmg

dist/crossler-darwin-amd64.dmg: dist/crossler-darwin-amd64
	@mkdir -p /tmp/crossler-dmg
	@cp $< /tmp/crossler-dmg/crossler
	@chmod 755 /tmp/crossler-dmg/crossler
	@hdiutil create \
	    -volname "Crossler $(VERSION)" \
	    -srcfolder /tmp/crossler-dmg \
	    -ov -format ULFO $@
	@rm -rf /tmp/crossler-dmg
```

---

## Рекомендации по фоновому изображению

- **Разрешение:** 72 DPI (не 96 или 150 DPI — иначе изображение исказится в Finder)
- **Размер:** соответствует размеру окна DMG в пикселях (например, 800×400 для окна 800×400)
- **Формат:** PNG с прозрачностью или JPEG
- **Для Retina-дисплеев:** создать два варианта: `background.png` и `background@2x.png`
- **Типичный дизайн:** тёмный или светлый фон, название приложения, стрелка от иконки к Applications

---

## Best Practices и подводные камни

### Рекомендации

1. **Формат для дистрибуции — ULFO.** Быстрая распаковка + хорошее сжатие + совместимость с macOS 10.11+.

2. **Для максимальной совместимости — UDZO.** Работает на всех версиях macOS, но медленнее распаковывается.

3. **Тихое монтирование в скриптах.** Использовать `-noautoopen -quiet` в CI/CD, чтобы не открывался Finder.

4. **Всегда проверять образ.** `hdiutil verify` перед публикацией.

5. **Подписать и нотаризировать.** С macOS 10.15 Gatekeeper блокирует неподписанные образы.

6. **Для CI/CD использовать dmgbuild.** create-dmg требует запущенный Finder — в headless CI это проблема.

7. **Sync перед демонтированием.** Добавить `sync` или задержку перед `hdiutil detach`.

### Подводные камни

1. **Размер образа.** Если `-size` слишком маленький, образ переполнится при копировании. Решение: задавать с запасом или использовать UDSP.

   ```bash
   # Слишком маленький — ошибка при копировании
   hdiutil create -size 10m ...  # а приложение 50MB

   # Правильно — с запасом 2x
   APP_SIZE=$(du -sm "MyApp.app" | cut -f1)
   IMAGE_SIZE=$((APP_SIZE * 2 + 20))
   hdiutil create -size ${IMAGE_SIZE}m ...
   ```

2. **Потеря DS_Store при конвертации.** Кастомизация Finder (расположение иконок, фон) хранится в `.DS_Store`. Выполнять кастомизацию ДО конвертации.

3. **Finder нужен для AppleScript.** В headless CI нет Finder — AppleScript для кастомизации не работает. Использовать dmgbuild.

4. **Пробелы в именах.** Всегда заключать пути в кавычки:
   ```bash
   hdiutil attach "My App.dmg" -mountpoint "/Volumes/My App"
   ```

5. **Двойное монтирование.** Если образ уже смонтирован, повторный attach вернёт ошибку.
   ```bash
   # Проверить перед монтированием
   hdiutil info | grep "MyApp" || hdiutil attach MyApp.dmg
   ```

6. **APFS vs HFS+.** APFS требует macOS 10.13+. Для широкой совместимости использовать `HFS+`.

### Диагностика

```bash
# Просмотр смонтированных образов
hdiutil info

# Проверить целостность образа
hdiutil verify MyApp.dmg

# Метаданные образа
hdiutil imageinfo MyApp.dmg

# Принудительное демонтирование
hdiutil detach -force /Volumes/MyApp

# Compact sparse образа
hdiutil compact dev.sparseimage
```

---

## Сравнение DMG vs PKG для macOS-дистрибуции

| Аспект | .dmg | .pkg |
|--------|------|------|
| **Установка** | Drag-and-drop пользователем | Запускается инсталлятор |
| **Удаление** | Перетащить в Корзину | Нет встроенного способа |
| **Скрипты** | Нет | preinstall/postinstall |
| **Права root** | Не требуются | Требуются для perSystem установки |
| **Сложные конфиги** | Нет | Можно создать в postinstall |
| **Для GUI приложений** | Стандарт (drag-and-drop) | Используется редко |
| **Для CLI инструментов** | Нестандартно (бинарник в DMG) | Стандартно (установка в /usr/local/bin) |
| **Notarization** | Требуется | Требуется |
| **Пользовательский UX** | Простой и понятный | Wizard-стиль |

**Рекомендация для Crossler:** для CLI-утилиты предпочтительнее `.pkg` (устанавливает в `/usr/local/bin`), DMG — дополнительный вариант для пользователей которые хотят сами контролировать установку.

---

## Ссылки

- [hdiutil Man Page (SS64)](https://ss64.com/mac/hdiutil.html)
- [create-dmg на GitHub](https://github.com/create-dmg/create-dmg)
- [dmgbuild документация](https://dmgbuild.readthedocs.io/)
- [Packaging a Mac OS X Application Using a DMG](https://asmaloney.com/2013/07/howto/packaging-a-mac-os-x-application-using-a-dmg/)
- [Notarizing macOS Software (Apple Developer)](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [macOS distribution: code signing, notarization, quarantine](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

# pkgbuild — создание macOS пакетов (.pkg)

## Что такое pkgbuild

**pkgbuild** — инструмент командной строки Apple для создания компонентных пакетов macOS Installer (`.pkg`). Входит в Xcode Command Line Tools, отдельная установка не требуется.

Инструмент создаёт компонентные `.pkg` файлы, которые затем можно:
- Использовать напрямую (для тихой установки в CI/CD или корпоративном деплое)
- Объединить через `productbuild` в финальный дистрибутивный инсталлятор

### Место pkgbuild в экосистеме macOS-упаковки

```
pkgbuild           → component.pkg  ─┐
pkgbuild           → component2.pkg ─┤
                                      ├→ productbuild → installer.pkg → notarytool → stapler
distribution.xml  ─────────────────── ┘
```

### Установка

```bash
# Входит в Xcode Command Line Tools (macOS)
xcode-select --install

# Проверить наличие
pkgbuild --version
```

---

## Аргументы командной строки

### Три режима работы

**Режим 1: Упаковка дерева файлов (основной)**
```bash
pkgbuild --root <root-path> [options] <output.pkg>
```

**Режим 2: Анализ и генерация component plist**
```bash
pkgbuild --analyze --root <root-path> <output.plist>
```

**Режим 3: Упаковка отдельного бандла**
```bash
pkgbuild --component <bundle-path> [options] <output.pkg>
```

### Полный список флагов

| Флаг | Описание |
|------|---------|
| `--root <path>` | Корневая директория с файлами для установки |
| `--component <path>` | Путь к отдельному бинарному бандлу (.app, .framework, .plugin) |
| `--identifier <id>` | Уникальный идентификатор пакета (reverse DNS: `com.company.app.pkg`) |
| `--version <ver>` | Версия пакета (например, `1.0`, `2.5.3`) |
| `--install-location <path>` | Директория назначения при установке (например, `/Applications`, `/usr/local/bin`) |
| `--scripts <dir>` | Директория со скриптами `preinstall` и `postinstall` |
| `--component-plist <plist>` | Файл конфигурации поведения бандлов |
| `--nopayload` | Создать пакет только со скриптами, без файлов |
| `--filter <regex>` | Исключить файлы по регулярному выражению |
| `--ownership <mode>` | Управление правами: `recommended` (по умолчанию), `preserve`, `preserve-other` |
| `--sign <identity>` | Подписать пакет сертификатом (для дистрибуции: `Developer ID Installer`) |
| `--keychain <path>` | Альтернативный keychain для поиска сертификата |
| `--timestamp` | Добавить временную метку Apple (обязательно для notarization) |
| `--quiet` | Подавить вывод статуса |
| `--analyze` | Режим анализа: вывести plist вместо создания пакета |

### Режим `--ownership`

| Значение | Поведение |
|----------|---------|
| `recommended` | Системные пути → `root:wheel`, пути в `/Users` → текущий пользователь |
| `preserve` | Копировать точные uid/gid с диска (проблема при сборке на разных машинах) |
| `preserve-other` | `recommended` для своих файлов, `preserve` для остальных |

---

## Структура payload (корневая директория)

Payload — физическое дерево файлов, которое будет скопировано на диск. Структура payload **соответствует итоговой структуре на диске**.

Два варианта организации:

**Вариант 1: payload соответствует абсолютным путям**
```
root/
├── usr/
│   └── local/
│       └── bin/
│           └── crossler        ← установится в /usr/local/bin/crossler
└── etc/
    └── crossler/
        └── config.yaml         ← установится в /etc/crossler/config.yaml
```
```bash
pkgbuild --root root/ --install-location / --identifier com.example.crossler.pkg crossler.pkg
```

**Вариант 2: payload для конкретной директории**
```
root/
└── crossler                    ← установится в /usr/local/bin/crossler
```
```bash
pkgbuild --root root/ --install-location /usr/local/bin --identifier com.example.crossler.pkg crossler.pkg
```

Для консольных утилит типичный layout:
```
payload/
├── usr/local/bin/crossler      # исполняемый файл
├── usr/share/man/man1/crossler.1.gz   # man-страница
└── usr/share/doc/crossler/README.md   # документация
```

### Права файлов

```bash
# Права в payload перед упаковкой
chmod 755 payload/usr/local/bin/crossler
chmod 644 payload/etc/crossler/config.yaml

# pkgbuild с --ownership recommended автоматически:
# - файлы в системных путях → root:wheel
# - бинарники → 755
# - конфиги → 644
```

---

## Скрипты preinstall и postinstall

### Расположение и требования

```bash
scripts/
├── preinstall    # запускается ДО установки файлов
└── postinstall   # запускается ПОСЛЕ установки файлов
```

Требования:
- Файлы должны быть исполняемыми: `chmod 755 scripts/preinstall`
- Shebang в первой строке: `#!/bin/bash` или `#!/bin/sh`
- Скрипты могут быть на bash, sh, python, perl — любой интерпретатор системы

### Аргументы скриптов

При вызове скрипту передаются четыре аргумента:

```
$1  — полный путь к .pkg файлу который устанавливается
$2  — полный путь к директории назначения (install-location)
$3  — полный путь к тому (обычно /, иногда /Volumes/...)
$4  — имя скрипта (preinstall или postinstall)
```

```bash
#!/bin/bash
# Пример использования аргументов

PACKAGE_PATH="$1"           # /tmp/crossler.pkg
INSTALL_LOCATION="$2"       # /usr/local/bin (или /)
TARGET_VOLUME="$3"          # /

# Итоговые пути (для --install-location /)
INSTALL_DIR="${TARGET_VOLUME}usr/local/bin"
BINARY="${INSTALL_LOCATION}crossler"
```

### Поведение при ошибках

- `preinstall` завершился с кодом != 0 → **установка прерывается**
- `postinstall` завершился с кодом != 0 → **предупреждение**, установка завершена (файлы уже скопированы)

### Пример preinstall

```bash
#!/bin/bash
set -e

# Остановить приложение если запущено
if pgrep -x "crossler" > /dev/null; then
    echo "Stopping running crossler process..."
    pkill -x "crossler" || true
    sleep 1
fi

# Проверить требования
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but not installed"
    exit 1
fi

exit 0
```

### Пример postinstall

```bash
#!/bin/bash
set -e

BINARY_PATH="$3/usr/local/bin/crossler"

# Проверить установку
if [ ! -f "$BINARY_PATH" ]; then
    echo "Warning: binary not found at $BINARY_PATH"
    exit 0
fi

# Установить права
chmod 755 "$BINARY_PATH"

# Регистрация в launchd (если нужен daemon)
# launchctl load -w /Library/LaunchDaemons/com.example.crossler.plist

echo "crossler installed successfully to $BINARY_PATH"
echo "Run 'crossler --help' to get started"

exit 0
```

---

## Component Property List

Файл `components.plist` описывает поведение бинарных бандлов (.app, .framework, .plugin) при установке. Для консольных утилит (не бандлов) этот файл обычно не нужен.

### Генерация шаблона

```bash
pkgbuild --analyze --root /tmp/MyApp.dst components.plist
```

Результат — XML plist с массивом описаний для каждого найденного бандла:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>RootRelativeBundlePath</key>
    <string>Applications/MyApp.app</string>

    <!-- Разрешить пользователю переместить приложение после установки -->
    <key>BundleIsRelocatable</key>
    <true/>

    <!-- Проверять версию перед установкой -->
    <key>BundleIsVersionChecked</key>
    <true/>

    <!-- Точное совпадение идентификатора -->
    <key>BundleHasStrictIdentifier</key>
    <true/>

    <!-- Поведение при перезаписи: upgrade, downgrade, newer, root -->
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
  </dict>
</array>
</plist>
```

### Ключевые параметры component plist

| Параметр | Тип | Описание |
|----------|-----|---------|
| `RootRelativeBundlePath` | string | Путь к бандлу относительно root (обязателен) |
| `BundleIsRelocatable` | bool | Позволить пользователю переместить приложение после установки |
| `BundleIsVersionChecked` | bool | Не устанавливать если уже установлена более новая версия |
| `BundleHasStrictIdentifier` | bool | Строгое совпадение Bundle ID для версионирования |
| `BundleOverwriteAction` | string | `upgrade` — только если новее; `downgrade` — только если старее; `newer` — новее или одинаково; `root` — всегда |

### Применение component plist

```bash
# Сгенерировать шаблон
pkgbuild --analyze --root /tmp/MyApp.dst components.plist

# Отредактировать через plutil (не relocatable)
plutil -replace '0.BundleIsRelocatable' -bool false components.plist

# Использовать при сборке
pkgbuild \
    --root /tmp/MyApp.dst \
    --component-plist components.plist \
    --identifier com.example.myapp.pkg \
    --version 1.0 \
    MyApp.pkg
```

---

## Связь с productbuild

`pkgbuild` создаёт **компонентные** пакеты. `productbuild` объединяет их в **дистрибутивный** пакет — финальный файл для распространения конечным пользователям.

### Полный рабочий процесс

```bash
# 1. Подготовить payload
mkdir -p payload/usr/local/bin
cp dist/crossler-darwin-arm64 payload/usr/local/bin/crossler
chmod 755 payload/usr/local/bin/crossler

# 2. Создать компонентный пакет
pkgbuild \
    --root payload/ \
    --identifier com.powertech.crossler.pkg \
    --version 1.0.0 \
    --install-location / \
    --scripts scripts/ \
    crossler-component.pkg

# 3. Синтезировать distribution.xml
productbuild \
    --synthesize \
    --package crossler-component.pkg \
    distribution.xml

# 4. (Опционально) Отредактировать distribution.xml

# 5. Создать финальный инсталлятор
productbuild \
    --distribution distribution.xml \
    --resources resources/ \
    --package-path . \
    crossler-installer.pkg

# 6. Подписать (для дистрибуции)
productsign \
    --sign "Developer ID Installer: Name (TEAM_ID)" \
    --timestamp \
    crossler-installer.pkg \
    crossler-signed.pkg

# 7. Notarize
xcrun notarytool submit crossler-signed.pkg \
    --apple-id "apple-id@email.com" \
    --password "app-specific-password" \
    --team-id "XXXXXXXXXX" \
    --wait

# 8. Staple (встроить notarization ticket в пакет)
xcrun stapler staple crossler-signed.pkg
```

### Пример distribution.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <!-- Заголовок инсталлятора -->
    <title>Crossler</title>

    <!-- Минимальная версия macOS -->
    <os-version type="minimum" value="11.0"/>

    <!-- Архитектура -->
    <!-- <allowed-os-versions><os-version min="11.0"/></allowed-os-versions> -->

    <!-- Фоновое изображение -->
    <!-- <background file="background.png" alignment="bottomleft" scaling="none"/> -->

    <!-- Лицензия -->
    <!-- <license file="LICENSE.txt" mime-type="text/plain"/> -->

    <!-- Документация -->
    <!-- <readme file="README.txt"/> -->

    <!-- Ссылки на компонентные пакеты -->
    <pkg-ref id="com.powertech.crossler.pkg">crossler-component.pkg</pkg-ref>

    <!-- Выбор (что устанавливать) -->
    <choices-outline>
        <line choice="default"/>
    </choices-outline>

    <choice id="default" visible="false">
        <pkg-ref id="com.powertech.crossler.pkg"/>
    </choice>
</installer-gui-script>
```

---

## Практические примеры

### Пример 1: Консольная утилита (базовый)

```bash
#!/bin/bash
set -e

APP_NAME="crossler"
VERSION="1.0.0"
ARCH="arm64"
BINARY="dist/crossler-darwin-${ARCH}"
IDENTIFIER="com.powertech.crossler.pkg"

# Подготовить payload
mkdir -p payload/usr/local/bin
cp "${BINARY}" "payload/usr/local/bin/${APP_NAME}"
chmod 755 "payload/usr/local/bin/${APP_NAME}"

# Подготовить скрипты
mkdir -p scripts
cat > scripts/postinstall << 'EOF'
#!/bin/bash
echo "crossler ${VERSION} installed successfully"
exit 0
EOF
chmod 755 scripts/postinstall

# Создать пакет
pkgbuild \
    --root payload/ \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    --install-location / \
    --scripts scripts/ \
    "dist/${APP_NAME}-darwin-${ARCH}.pkg"

# Очистить временные файлы
rm -rf payload scripts
```

### Пример 2: Пакет со скриптами

```bash
#!/bin/bash
set -e

# Структура директорий
mkdir -p payload/usr/local/bin
mkdir -p payload/etc/crossler
mkdir -p scripts

# Бинарник
cp dist/crossler-darwin-arm64 payload/usr/local/bin/crossler
chmod 755 payload/usr/local/bin/crossler

# Конфиг по умолчанию
cat > payload/etc/crossler/config.yaml << 'EOF'
# Default crossler configuration
output_dir: ./dist
verbose: false
EOF

# Preinstall
cat > scripts/preinstall << 'EOF'
#!/bin/bash
set -e
# Остановить процесс если запущен
pkill -x crossler 2>/dev/null || true
exit 0
EOF
chmod 755 scripts/preinstall

# Postinstall
cat > scripts/postinstall << 'EOF'
#!/bin/bash
set -e
echo "crossler installed to /usr/local/bin/crossler"
echo "Configuration: /etc/crossler/config.yaml"
exit 0
EOF
chmod 755 scripts/postinstall

# Собрать
pkgbuild \
    --root payload/ \
    --identifier com.powertech.crossler.pkg \
    --version 1.0.0 \
    --install-location / \
    --scripts scripts/ \
    --filter '\.DS_Store' \
    dist/crossler-darwin-arm64.pkg

rm -rf payload scripts
```

### Пример 3: Payload-free пакет (только скрипты)

Полезно для настройки системы без установки файлов:

```bash
mkdir -p scripts

cat > scripts/postinstall << 'EOF'
#!/bin/bash
set -e

# Создать symlink
ln -sf /Applications/MyApp.app/Contents/MacOS/mytool /usr/local/bin/mytool

# Настроить PATH в zshrc
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc

exit 0
EOF
chmod 755 scripts/postinstall

pkgbuild \
    --nopayload \
    --identifier com.example.setup.pkg \
    --version 1.0 \
    --scripts scripts/ \
    setup.pkg

rm -rf scripts
```

### Пример 4: Исключение файлов с --filter

```bash
pkgbuild \
    --root payload/ \
    --identifier com.example.myapp.pkg \
    --version 1.0 \
    --install-location / \
    --filter '.*\.dSYM$' \
    --filter '.*\.o$' \
    --filter '.*\.a$' \
    --filter '.*__pycache__.*' \
    --filter '.*\.pyc$' \
    myapp.pkg
```

### Пример 5: Makefile-фрагмент для Crossler

```makefile
VERSION ?= $(shell git describe --tags --abbrev=0 | sed 's/^v//')

dist/crossler-darwin-arm64.pkg: dist/crossler-darwin-arm64
	@echo "Building macOS pkg (arm64)..."
	@mkdir -p /tmp/crossler-pkg/payload/usr/local/bin
	@cp dist/crossler-darwin-arm64 /tmp/crossler-pkg/payload/usr/local/bin/crossler
	@chmod 755 /tmp/crossler-pkg/payload/usr/local/bin/crossler
	@pkgbuild \
		--root /tmp/crossler-pkg/payload/ \
		--identifier com.powertech.crossler.pkg \
		--version $(VERSION) \
		--install-location / \
		$@
	@rm -rf /tmp/crossler-pkg

dist/crossler-darwin-amd64.pkg: dist/crossler-darwin-amd64
	@mkdir -p /tmp/crossler-pkg/payload/usr/local/bin
	@cp dist/crossler-darwin-amd64 /tmp/crossler-pkg/payload/usr/local/bin/crossler
	@chmod 755 /tmp/crossler-pkg/payload/usr/local/bin/crossler
	@pkgbuild \
		--root /tmp/crossler-pkg/payload/ \
		--identifier com.powertech.crossler.pkg \
		--version $(VERSION) \
		--install-location / \
		$@
	@rm -rf /tmp/crossler-pkg
```

---

## Best Practices и подводные камни

### Правила

1. **Идентификатор — reverse DNS формат.** Всегда использовать `com.company.app.pkg`. Этот идентификатор используется macOS для проверки установленных пакетов.

2. **Версионирование идентификатора.** Идентификатор должен быть стабильным между версиями — `com.powertech.crossler.pkg` одинаков для 1.0, 2.0 и 3.0.

3. **Права файлов перед упаковкой.** Установить права явно до запуска pkgbuild, или использовать `--ownership recommended`.

4. **Тестировать скрипты на чистой системе.** Скрипты выполняются с правами root без окружения пользователя. Нельзя использовать `$HOME`, `~`, пользовательские `$PATH`.

5. **Всегда использовать `--timestamp` при подписи.** Без временной метки подпись станет невалидной после истечения сертификата.

6. **Удалять debug-артефакты через `--filter`.** Перед упаковкой убедиться, что payload не содержит .dSYM, .o, и т.д.

### Ограничения pkgbuild

- **Нет встроенного удаления.** macOS не имеет встроенного пакетного менеджера для удаления .pkg. Нужно либо создать скрипт удаления, либо использовать LaunchDaemons.
- **Нет зависимостей между пакетами.** pkgbuild не поддерживает объявление зависимостей.
- **Только для macOS.** pkgbuild работает только на macOS.
- **Бандлы только через `--component`.** Режим `--root` упаковывает всё дерево; для отдельного .app лучше использовать `--component`.

### Диагностика

```bash
# Просмотреть содержимое пакета без установки
pkgutil --expand crossler.pkg crossler-expanded/
ls -la crossler-expanded/

# Проверить установленные пакеты
pkgutil --pkgs | grep crossler
pkgutil --info com.powertech.crossler.pkg

# Список файлов установленного пакета
pkgutil --files com.powertech.crossler.pkg

# Забыть пакет (для тестирования переустановки)
sudo pkgutil --forget com.powertech.crossler.pkg

# Проверить подпись
spctl -a -t install crossler.pkg
codesign --verify --verbose crossler.pkg
```

---

## Ссылки

- [pkgbuild Man Page (Apple)](https://www.manpagez.com/man/1/pkgbuild/)
- [productbuild Man Page (Apple)](https://www.manpagez.com/man/1/productbuild/)
- [Distribution XML Reference (Apple Developer)](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/)
- [Notarizing macOS Software (Apple Developer)](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Scripting OS X: Build Simple Packages with Scripts](https://scriptingosx.com/2019/01/build-simple-packages-with-scripts/)
- [Creating payload-free packages with pkgbuild](https://derflounder.wordpress.com/2012/08/15/creating-payload-free-packages-with-pkgbuild/)
- [Making macOS installers with pkgbuild and productbuild](https://moonbase.sh/articles/how-to-make-macos-installers-for-juce-projects-with-pkgbuild-and-productbuild/)

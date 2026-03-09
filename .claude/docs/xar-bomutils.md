# xar + bomutils — создание macOS .pkg на Linux

## Что такое macOS flat package

macOS `.pkg` (flat package) — это XAR-архив с фиксированной внутренней структурой, которую понимает macOS Installer. Формат появился в macOS 10.5 (Leopard) и полностью вытеснил старый bundle-формат пакетов.

Ключевой момент: `.pkg` можно собрать **без macOS** — нужны только `xar` и `mkbom` (из bomutils).

---

## Два типа пакетов

### Component package (компонентный пакет)

Устанавливает один компонент. Структура:

```
MyApp.pkg/           ← XAR-архив
├── Bom              ← Bill of Materials (бинарный)
├── Payload          ← gzip-cpio-архив с файлами для установки
├── Scripts          ← gzip-cpio-архив со скриптами (опционально)
└── PackageInfo      ← XML-метаданные пакета
```

Создаётся напрямую через `xar` + `mkbom`. Именно этот тип собирается на Linux.

### Distribution package (дистрибутивный пакет)

Обёртка над одним или несколькими компонентными пакетами. Добавляет UI-экраны установщика, JavaScript-проверки совместимости, выбор компонентов. Структура:

```
MyApp.pkg/           ← XAR-архив
├── Distribution     ← XML-оркестрация установщика
├── base.pkg/        ← вложенный компонентный пакет
│   ├── Bom
│   ├── Payload
│   ├── Scripts
│   └── PackageInfo
└── Resources/       ← опционально: RTF, PNG, локализации
    └── en.lproj/
        ├── welcome.rtf
        ├── readme.rtf
        └── license.rtf
```

На macOS создаётся через `productbuild`. На Linux собирается вручную — Distribution.xml пишется руками, компонентные пакеты упаковываются в один XAR.

---

## Инструменты

### xar

XAR (eXtensible ARchiver) — формат архива и одноимённая утилита. Используется Apple для упаковки `.pkg`.

**Установка:**
```bash
# Ubuntu/Debian
apt install xar

# Alpine
apk add xar

# Из исходников (mackyle/xar — активно поддерживаемый форк)
apt install libxml2-dev libssl-dev zlib1g-dev libbz2-dev
git clone https://github.com/mackyle/xar && cd xar/xar
sh autogen.sh && make && make install
```

### bomutils / mkbom

Открытая реализация Apple-утилиты `mkbom`. Создаёт Bill of Materials — бинарный файл с описанием всех файлов пакета (пути, права, uid/gid, контрольные суммы).

**Установка:**
```bash
# Ubuntu/Debian (если есть в репозитории)
apt install bomutils

# Из исходников
apt install make g++ libxml2-dev
git clone https://github.com/hogliux/bomutils && cd bomutils
make && make install
```

> **Известный баг bomutils:** в старых версиях переменная с именем `data` конфликтует с системным именем на некоторых дистрибутивах. Фикс:
> ```bash
> sed -i 's/\bdata\b/dataa/g' src/lsbom.cpp src/mkbom.cpp
> ```

---

## xar CLI — полный справочник

### Основные операции (взаимоисключающие)

| Флаг | Описание |
|------|----------|
| `-c` / `--create` | Создать архив |
| `-x` / `--extract` | Извлечь архив |
| `-t` / `--list` | Показать содержимое архива |

### Обязательный параметр

| Флаг | Описание |
|------|----------|
| `-f <file>` | Имя архива (обязателен для всех операций) |

### Сжатие

| Флаг | Описание |
|------|----------|
| `--compression=<type>` | Алгоритм сжатия: `none`, `gzip` (по умолчанию), `bzip2`, `lzma`, `xz` |
| `-z` | Сокращение для `--compression=gzip` |
| `-j` | Сокращение для `--compression=bzip2` |
| `-a` | Сокращение для `--compression=lzma` |
| `--compression-args=<n>` | Уровень сжатия 0–9 для выбранного алгоритма |
| `--no-compress=<regexp>` | POSIX-регулярное выражение: файлы, подходящие под него, не сжимаются |
| `--recompress` | Принудительно перепаковать уже сжатые файлы |

> **Критически важно для `.pkg`:** payload уже сжат (`gzip`). Финальный XAR нужно создавать с `--compression none`, иначе установщик не сможет его распаковать.

### Контрольные суммы

| Флаг | Описание |
|------|----------|
| `--toc-cksum=<alg>` | Алгоритм хэша для TOC (XML-заголовка): `none`, `md5`, `sha1` (по умолч.), `sha224`, `sha256`, `sha384`, `sha512` |
| `--file-cksum=<alg>` | Алгоритм хэша для данных каждого файла (те же варианты) |
| `--dump-toc-cksum` | Вывести контрольную сумму TOC в stdout |

### Извлечение

| Флаг | Описание |
|------|----------|
| `-C <path>` / `--directory=<path>` | Сменить каталог перед извлечением |
| `-p` | Восстановить владельца по символическому имени |
| `-P` | Восстановить владельца по числовому uid/gid |
| `-k` / `--keep-existing` | Не перезаписывать существующие файлы |
| `--keep-setuid` | Сохранять биты setuid/setgid при извлечении |
| `--strip-components=<n>` | Обрезать n уровней пути при извлечении |
| `-O` / `--to-stdout` | Писать содержимое в stdout |

### Фильтрация файлов

| Флаг | Описание |
|------|----------|
| `--exclude=<regexp>` | POSIX-регулярное выражение: исключить файлы (можно указать несколько раз) |
| `-l` / `--one-file-system` | Не переходить на другие файловые системы при создании |

### Управление свойствами файлов

| Флаг | Описание |
|------|----------|
| `--prop-include=<prop>` | Включить только указанное свойство |
| `--prop-exclude=<prop>` | Исключить указанное свойство |
| `--distribution` | Сохранять только свойства, безопасные для дистрибуции: name, type, mode, data |

### Оптимизация

| Флаг | Описание |
|------|----------|
| `--coalesce-heap` | Дедуплицировать одинаковые данные файлов |
| `--link-same` | Создавать хардлинки для файлов с одинаковыми данными |
| `--rsize=<bytes>` | Размер буфера чтения |

### Диагностика

| Флаг | Описание |
|------|----------|
| `-v` / `--verbose` | Подробный вывод |
| `-d <file>` / `--dump-toc=<file>` | Извлечь XML-заголовок в файл (`-` = stdout) |
| `--dump-toc-raw` | Извлечь сжатый XML-заголовок |
| `--dump-header` | Показать бинарный заголовок |
| `--list-subdocs` | Показать вложенные документы |
| `--extract-subdoc=<name>` | Извлечь вложенный документ как `name.xml` |
| `-s <file>` | Управлять subdocument-файлами |

### Подпись XAR-архива

| Флаг | Описание |
|------|----------|
| `--sign` | Зарезервировать место для подписи (требует `--sig-size` и `--cert-loc`) |
| `--replace-sign` | Удалить существующие подписи и добавить новую |
| `--sig-size=<n>` / `--sig-len=<n>` | Байт для подписи (RSA-2048 → 256, RSA-4096 → 512) |
| `--cert-loc=<file>` | DER-файл сертификата (можно указывать несколько раз для цепочки) |
| `--data-to-sign=<file>` | Сохранить сырые байты хэша для внешнего подписания |
| `--digestinfo-to-sign=<file>` | Сохранить хэш с префиксом RFC 3447 (для openssl pkeyutl) |
| `--sig-offset=<file>` | Сохранить байтовое смещение подписи в архиве |
| `--extract-sig=<file>` | Извлечь существующую подпись |
| `--inject-sig=<file>` | Вставить предварительно вычисленную подпись |
| `--extract-certs=<dir>` | Извлечь сертификаты как DER-файлы |
| `--extract-CAfile=<file>` | Извлечь цепочку сертификатов как PEM |

---

## mkbom CLI — полный справочник

```
mkbom [-i] [-u uid] [-g gid] <source> <target-bom-file>
```

| Флаг | Описание |
|------|----------|
| `-u <uid>` | Принудительно установить UID для всех записей (обычно `0` = root) |
| `-g <gid>` | Принудительно установить GID для всех записей (обычно `80` = admin на macOS) |
| `-i` | Источник — текстовый файл со списком (формат `lsbom`/`ls4mkbom`). Несовместим с `-u` и `-g` |

**Аргументы:**
- `source` — каталог с файлами (или текстовый список при `-i`)
- `target-bom-file` — путь к выходному `.bom` файлу

**Типичное использование:**
```bash
mkbom -u 0 -g 80 ./pkgroot ./flat/base.pkg/Bom
```

### Смежные утилиты bomutils

**lsbom** — показывает содержимое `.bom` файла:
```bash
lsbom Bom                    # показать все файлы
lsbom -fls Bom               # только файлы, формат ls
lsbom -f Bom > bom.txt       # только имена файлов
```

**ls4mkbom** — генерирует список файлов в формате для `mkbom -i`.

---

## PackageInfo XML — полный справочник

Файл `PackageInfo` описывает метаданные и поведение компонентного пакета.

### Корневой элемент `<pkg-info>`

```xml
<pkg-info
  format-version="2"
  identifier="com.example.myapp"
  version="1.2.3"
  install-location="/"
  auth="root"
  overwrite-permissions="true"
  relocatable="false"
  postinstall-action="none"
  generator-version="xar-1.6.1"
>
```

**Атрибуты корневого элемента:**

| Атрибут | Обязателен | Значения | Описание |
|---------|-----------|---------|----------|
| `format-version` | да | `"2"` | Версия формата flat package. Всегда `2` |
| `identifier` | да | строка в стиле reverse-DNS | Уникальный ID пакета, напр. `com.example.myapp` |
| `version` | да | строка | Версия пакета, напр. `1.2.3` |
| `install-location` | рекомендован | путь | Корневой путь установки, напр. `/` или `/usr/local` |
| `auth` | рекомендован | `"root"`, `"none"` | Требуемые права. `"root"` — нужен sudo |
| `overwrite-permissions` | нет | `"true"`, `"false"` | Перезаписывать ли права файлов при обновлении |
| `relocatable` | нет | `"true"`, `"false"` | Можно ли переместить пакет в другое место |
| `postinstall-action` | нет | `"none"`, `"logout"`, `"restart"`, `"shutdown"` | Действие после установки |
| `generator-version` | нет | строка | Информация о генераторе (произвольная строка) |

### Дочерние элементы `<pkg-info>`

#### `<payload>`

Описывает содержимое архива Payload.

```xml
<payload numberOfFiles="42" installKBytes="1024"/>
```

| Атрибут | Описание |
|---------|----------|
| `numberOfFiles` | Количество файлов в Payload (включая каталоги) |
| `installKBytes` | Размер установленных файлов в килобайтах |

#### `<scripts>`

Ссылки на скрипты из архива Scripts.

```xml
<scripts>
  <preinstall file="./preinstall"/>
  <postinstall file="./postinstall"/>
</scripts>
```

Файлы `preinstall` и `postinstall` хранятся внутри gzip-cpio-архива `Scripts`. Путь в атрибуте `file` — относительный, `./` обязателен.

Переменные среды, доступные в скриптах:
- `$DSTVOLUME` — путь к тому назначения (напр. `/`)
- `$DSTROOT` — путь к корню установки
- `$INSTALLER_TEMP` — временный каталог установщика
- `$PACKAGE_PATH` — путь к `.pkg` файлу

#### `<bundle-version>`

Список бандлов (`.app`, `.framework`), которые не должны быть понижены в версии при обновлении. Для CLI-утилит — пустой элемент.

```xml
<bundle-version/>
<!-- или с содержимым для GUI-приложений: -->
<bundle-version>
  <bundle
    CFBundleIdentifier="com.example.MyApp"
    CFBundleVersion="123"
    CFBundleShortVersionString="1.2.3"
    path="./MyApp.app"
  />
</bundle-version>
```

#### `<upgrade-bundle>`

Список бандлов, которые пакет обновляет (для механизма обновлений macOS Installer). Для простых пакетов — пустой элемент.

```xml
<upgrade-bundle/>
```

#### `<update-bundle>`

Аналогично `<upgrade-bundle>`, но для патч-обновлений. Для простых пакетов — пустой элемент.

```xml
<update-bundle/>
```

#### `<atomic-update-bundle>`

Указывает бандлы для атомарного обновления. Для простых пакетов — пустой элемент.

```xml
<atomic-update-bundle/>
```

#### `<strict-identifier>`

Обязывает установщик устанавливать только в точно указанный `install-location`, игнорируя ранее зарегистрированные местоположения этого пакета. Для простых пакетов — пустой элемент.

```xml
<strict-identifier/>
```

#### `<relocate>`

Управляет перемещением пакета. При наличии вложенного `<bundle>` — ищет бандл по identifier и устанавливает рядом с найденным. Пустой элемент — отключает перемещение.

```xml
<!-- Отключить перемещение: -->
<relocate/>

<!-- Разрешить перемещение для конкретного бандла: -->
<relocate>
  <bundle id="com.example.MyApp"/>
</relocate>
```

#### Полный пример PackageInfo для CLI-утилиты

```xml
<?xml version="1.0" encoding="utf-8"?>
<pkg-info
  format-version="2"
  identifier="com.example.mytool"
  version="1.2.3"
  install-location="/"
  auth="root"
  overwrite-permissions="true"
  relocatable="false"
  postinstall-action="none"
>
  <payload numberOfFiles="3" installKBytes="2048"/>
  <scripts>
    <preinstall file="./preinstall"/>
    <postinstall file="./postinstall"/>
  </scripts>
  <bundle-version/>
  <upgrade-bundle/>
  <update-bundle/>
  <atomic-update-bundle/>
  <strict-identifier/>
  <relocate/>
</pkg-info>
```

#### Минимальный PackageInfo (только обязательные части)

```xml
<?xml version="1.0" encoding="utf-8"?>
<pkg-info format-version="2" identifier="com.example.mytool" version="1.2.3" install-location="/" auth="root">
  <payload numberOfFiles="3" installKBytes="2048"/>
</pkg-info>
```

---

## Distribution XML — полный справочник

Файл `Distribution` оркестрирует установку нескольких компонентных пакетов и добавляет UI-логику.

### Корневой элемент `<installer-gui-script>`

```xml
<installer-gui-script
  minSpecVersion="2"
  authoringTool="com.apple.PackageMaker"
  authoringToolVersion="3.0.3"
  authoringToolBuild="174"
>
```

| Атрибут | Описание |
|---------|----------|
| `minSpecVersion` | Минимальная версия спецификации установщика. Обычно `1` или `2` |
| `authoringTool` | Идентификатор инструмента-генератора (опционально) |

Альтернативный корневой элемент: `<installer-script>` (без GUI-возможностей).

### `<title>`

Заголовок окна установщика.

```xml
<title>My Application 1.2.3</title>
```

### `<options>`

Параметры поведения установщика.

```xml
<options
  customize="never"
  require-scripts="false"
  allow-external-scripts="no"
  hostArchitectures="x86_64,arm64"
/>
```

| Атрибут | Значения | Описание |
|---------|---------|----------|
| `customize` | `"never"`, `"allow"`, `"always"` | Показывать ли экран выбора компонентов |
| `require-scripts` | `"true"`, `"false"` | Обязательность скриптов |
| `allow-external-scripts` | `"yes"`, `"no"` | Разрешить ли внешние JS-скрипты |
| `hostArchitectures` | `"x86_64"`, `"arm64"`, `"x86_64,arm64"` | Поддерживаемые архитектуры хоста |
| `rootVolumeOnly` | `"true"`, `"false"` | Устанавливать только на системный том |

### `<domains>`

Разрешённые области установки.

```xml
<domains enable_anywhere="true"/>
<!-- или -->
<domains enable_localSystem="true" enable_userHome="false"/>
```

### `<volume-check>`

Проверка совместимости тома назначения. Может содержать JavaScript-функцию или декларативные элементы.

```xml
<volume-check>
  <allowed-os-versions>
    <os-version min="10.15" max="15.99.99"/>
  </allowed-os-versions>
</volume-check>
```

### `<installation-check>`

JavaScript-проверка перед установкой.

```xml
<installation-check script="pm_install_check();"/>
<script>
function pm_install_check() {
  if (!(system.compareVersions(system.version.ProductVersion, '10.15') >= 0)) {
    my.result.title = 'Failure';
    my.result.message = 'macOS 10.15 or later is required.';
    my.result.type = 'Fatal';
    return false;
  }
  return true;
}
</script>
```

### `<choices-outline>`

Иерархия выбора компонентов (дерево `<line>`).

```xml
<choices-outline>
  <line choice="default">
    <line choice="com.example.mytool"/>
  </line>
</choices-outline>
```

### `<choice>`

Определение группы установки.

```xml
<choice id="default"/>
<choice id="com.example.mytool" visible="false" title="My Tool">
  <pkg-ref id="com.example.mytool"/>
</choice>
```

| Атрибут | Описание |
|---------|----------|
| `id` | Уникальный идентификатор группы |
| `visible` | Показывать ли в UI (`true`/`false`) |
| `title` | Отображаемое название |
| `selected` | JS-выражение: выбрана ли группа по умолчанию |
| `enabled` | JS-выражение: доступна ли группа |

### `<pkg-ref>`

Ссылка на компонентный пакет.

```xml
<!-- Декларация: -->
<pkg-ref id="com.example.mytool">
  <bundle-version/>
</pkg-ref>

<!-- Привязка к файлу (с атрибутами): -->
<pkg-ref
  id="com.example.mytool"
  version="1.2.3"
  onConclusion="none"
  installKBytes="2048"
  auth="Root"
>#base.pkg</pkg-ref>
```

| Атрибут | Описание |
|---------|----------|
| `id` | Идентификатор (должен совпадать с `identifier` в PackageInfo) |
| `version` | Версия пакета |
| `installKBytes` | Размер в килобайтах |
| `auth` | Уровень прав (`"Root"` = требует sudo) |
| `onConclusion` | Действие по завершении (`"none"`, `"RequireRestart"`) |

Содержимое элемента — путь к вложенному `.pkg` с префиксом `#`: `#base.pkg`.

### `<product>`

Метаданные верхнего уровня продукта.

```xml
<product id="com.example.mytool.1.2.3"/>
```

### UI-элементы (опциональные файлы)

```xml
<welcome file="welcome.rtf" mime-type="text/rtf"/>
<readme file="readme.rtf" mime-type="text/rtf"/>
<license file="license.rtf" mime-type="text/rtf"/>
<conclusion file="conclusion.rtf" mime-type="text/rtf"/>
```

Файлы размещаются в `Resources/en.lproj/`.

---

## Структура рабочего каталога

```
pkgbuild/
├── root/                        ← файлы для установки
│   └── usr/
│       └── local/
│           └── bin/
│               └── mytool
├── scripts/                     ← скрипты pre/postinstall
│   ├── preinstall
│   └── postinstall
└── flat/                        ← будет упакован в .pkg
    ├── Distribution              ← только для distribution packages
    ├── Resources/                ← опционально
    │   └── en.lproj/
    └── base.pkg/                 ← компонентный пакет
        ├── Bom                   ← генерируется mkbom
        ├── Payload               ← gzip-cpio из root/
        ├── Scripts               ← gzip-cpio из scripts/
        └── PackageInfo           ← XML
```

---

## Полный shell-скрипт сборки .pkg на Linux

```bash
#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
PKG_IDENTIFIER="com.example.mytool"
PKG_VERSION="1.2.3"
PKG_INSTALL_LOCATION="/"
BINARY_NAME="mytool"
BINARY_SRC="./mytool"             # path to the binary to package
OUTPUT_PKG="mytool-1.2.3-macos.pkg"

# ─── Prepare directory structure ─────────────────────────────────────────────
rm -rf pkgbuild
mkdir -p pkgbuild/root/usr/local/bin
mkdir -p pkgbuild/scripts
mkdir -p pkgbuild/flat/base.pkg
mkdir -p pkgbuild/flat/Resources/en.lproj

# ─── Copy files into package root ────────────────────────────────────────────
cp "$BINARY_SRC" pkgbuild/root/usr/local/bin/"$BINARY_NAME"
chmod +x pkgbuild/root/usr/local/bin/"$BINARY_NAME"

# ─── Create pre/postinstall scripts (optional) ───────────────────────────────
cat > pkgbuild/scripts/preinstall << 'EOF'
#!/bin/sh
# Stop service if running
launchctl stop com.example.mytool 2>/dev/null || true
exit 0
EOF

cat > pkgbuild/scripts/postinstall << 'EOF'
#!/bin/sh
# Create symlink in /usr/local/bin (already there via payload)
echo "Installation complete."
exit 0
EOF

chmod +x pkgbuild/scripts/preinstall
chmod +x pkgbuild/scripts/postinstall

# ─── Create Payload (gzip-cpio of install root) ──────────────────────────────
# --format odc: old POSIX format, required by macOS Installer
# --owner 0:80: force uid=0 (root), gid=80 (admin) — macOS convention
( cd pkgbuild/root && find . | cpio -o --format odc --owner 0:80 | gzip -c ) \
  > pkgbuild/flat/base.pkg/Payload

# ─── Create Scripts archive (gzip-cpio of scripts) ───────────────────────────
( cd pkgbuild/scripts && find . | cpio -o --format odc --owner 0:80 | gzip -c ) \
  > pkgbuild/flat/base.pkg/Scripts

# ─── Calculate payload statistics ────────────────────────────────────────────
NUM_FILES=$(cd pkgbuild/root && find . | wc -l)
INSTALL_KBYTES=$(du -sk pkgbuild/root | awk '{print $1}')

# ─── Create Bill of Materials ────────────────────────────────────────────────
# -u 0: force uid=root, -g 80: force gid=admin
mkbom -u 0 -g 80 pkgbuild/root pkgbuild/flat/base.pkg/Bom

# ─── Create PackageInfo ───────────────────────────────────────────────────────
cat > pkgbuild/flat/base.pkg/PackageInfo << EOF
<?xml version="1.0" encoding="utf-8"?>
<pkg-info
  format-version="2"
  identifier="${PKG_IDENTIFIER}"
  version="${PKG_VERSION}"
  install-location="${PKG_INSTALL_LOCATION}"
  auth="root"
  overwrite-permissions="true"
  relocatable="false"
  postinstall-action="none"
>
  <payload numberOfFiles="${NUM_FILES}" installKBytes="${INSTALL_KBYTES}"/>
  <scripts>
    <preinstall file="./preinstall"/>
    <postinstall file="./postinstall"/>
  </scripts>
  <bundle-version/>
  <upgrade-bundle/>
  <update-bundle/>
  <atomic-update-bundle/>
  <strict-identifier/>
  <relocate/>
</pkg-info>
EOF

# ─── Create Distribution XML ──────────────────────────────────────────────────
cat > pkgbuild/flat/Distribution << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>${BINARY_NAME} ${PKG_VERSION}</title>
  <options
    customize="never"
    require-scripts="false"
    allow-external-scripts="no"
    hostArchitectures="x86_64,arm64"
  />
  <volume-check>
    <allowed-os-versions>
      <os-version min="10.15"/>
    </allowed-os-versions>
  </volume-check>
  <pkg-ref id="${PKG_IDENTIFIER}">
    <bundle-version/>
  </pkg-ref>
  <choices-outline>
    <line choice="default">
      <line choice="${PKG_IDENTIFIER}"/>
    </line>
  </choices-outline>
  <choice id="default"/>
  <choice id="${PKG_IDENTIFIER}" visible="false">
    <pkg-ref id="${PKG_IDENTIFIER}"/>
  </choice>
  <pkg-ref
    id="${PKG_IDENTIFIER}"
    version="${PKG_VERSION}"
    onConclusion="none"
    installKBytes="${INSTALL_KBYTES}"
    auth="Root"
  >#base.pkg</pkg-ref>
  <product id="${PKG_IDENTIFIER}.${PKG_VERSION}"/>
</installer-gui-script>
EOF

# ─── Pack everything into .pkg (XAR archive) ─────────────────────────────────
# --compression none: Payload is already gzip-compressed; don't double-compress
( cd pkgbuild/flat && xar --compression none -cf "../../${OUTPUT_PKG}" * )

echo "Created: ${OUTPUT_PKG}"
```

---

## Payload: формат и особенности

Payload — это `gzip(cpio(files))`. Детали:

```bash
# Создание Payload
( cd pkgroot && find . | cpio -o --format odc --owner 0:80 | gzip -c ) > Payload

# Распаковка Payload для инспекции
mkdir payload_out
cd payload_out && zcat ../Payload | cpio -i -d -m
```

**Ключевые параметры `cpio`:**
- `--format odc` — формат old POSIX (odc, portable); macOS Installer требует именно его
- `--owner 0:80` — принудительный uid=0 (root), gid=80 (admin); необходимо, т.к. Linux uid/gid != macOS uid/gid
- `-o` — режим создания (out)
- `-i` — режим извлечения (in)
- `-d` — создавать каталоги при извлечении
- `-m` — сохранять mtime при извлечении

**Альтернатива — pbzx-сжатие** (встречается в пакетах Apple):
```bash
# Создание с pbzx (нестандартный инструмент Apple)
find . -print0 | cpio --null -o --format odc | pbzx -cz > Payload

# Распаковка pbzx
pbzx -n Payload | cpio -i -d -m
```

Для пакетов, собираемых вручную, достаточно обычного `gzip`.

---

## Подпись пакета на Linux

Подпись `.pkg` на Linux выполняется через двухшаговый процесс: xar резервирует место под подпись, внешний инструмент подписывает хэш, результат вставляется обратно.

### Через xar + openssl (Authenticode-like, для xar-подписи)

```bash
# Шаг 1: Зарезервировать место под подпись RSA-2048 (256 байт)
xar --sign -f mytool.pkg \
  --sig-size 256 \
  --cert-loc cert.der \
  --cert-loc intermediate.der \
  --cert-loc root.der \
  --digestinfo-to-sign digestinfo.dat

# Шаг 2: Подписать хэш приватным ключом
openssl pkeyutl -sign -inkey key.pem -in digestinfo.dat -out signature.dat

# Шаг 3: Вставить подпись в архив
xar --inject-sig signature.dat -f mytool.pkg
```

### Через rcodesign (Apple Code Signing, рекомендуется)

```bash
# Подписать .pkg через rcodesign (работает на Linux без macOS)
rcodesign sign \
  --p12-file cert.p12 \
  --p12-password-file pass.txt \
  mytool.pkg

# Нотаризация
rcodesign notary-submit \
  --api-key-path api_key.json \
  --wait \
  mytool.pkg
```

Подробнее о rcodesign: `docs/rcodesign.md`.

---

## Установка и сборка зависимостей

### xar из исходников (рекомендуется mackyle/xar)

```bash
# Ubuntu/Debian
apt install -y libxml2-dev libssl-dev zlib1g-dev libbz2-dev autoconf automake libtool

git clone https://github.com/mackyle/xar
cd xar/xar
sh autogen.sh
./configure
make
make install

# Alpine
apk add libxml2-dev openssl-dev zlib-dev bzip2-dev autoconf automake libtool
```

### bomutils из исходников

```bash
# Ubuntu/Debian
apt install -y make g++ libxml2-dev cpio

git clone https://github.com/hogliux/bomutils
cd bomutils

# Фикс для старых версий (если нужен):
# sed -i 's/\bdata\b/dataa/g' src/lsbom.cpp src/mkbom.cpp

make
make install   # устанавливает в /usr/local/bin
```

### Полная установка одной командой (Ubuntu/Debian)

```bash
apt install -y libxml2-dev libssl-dev zlib1g-dev libbz2-dev autoconf automake libtool make g++ cpio

# xar
git clone https://github.com/mackyle/xar /tmp/xar && cd /tmp/xar/xar
sh autogen.sh && ./configure && make && make install

# bomutils
git clone https://github.com/hogliux/bomutils /tmp/bomutils && cd /tmp/bomutils
make && make install
```

---

## Распаковка существующего .pkg (инспекция)

```bash
# Создать рабочий каталог
mkdir pkg_contents && cd pkg_contents

# Извлечь XAR-архив
xar -xf /path/to/MyApp.pkg

# Посмотреть структуру
ls -la

# Посмотреть TOC (XML-заголовок xar)
xar --dump-toc=- -f /path/to/MyApp.pkg

# Извлечь Payload
mkdir payload && cd payload
zcat ../Payload | cpio -i -d -m

# Прочитать BOM
lsbom -fls ../Bom

# Просмотр PackageInfo
cat ../PackageInfo

# Просмотр Distribution (для distribution packages)
cat ../Distribution
```

---

## Отличия component package vs distribution package

| Аспект | Component package | Distribution package |
|--------|-----------------|---------------------|
| Назначение | Установка одного компонента | Оркестрация одного или нескольких component packages |
| Обязательные файлы | Bom, Payload, PackageInfo | Distribution + вложенные component packages |
| Файл управления | `PackageInfo` (XML) | `Distribution` (XML) |
| UI установщика | Минимальный (без экранов) | Полный UI с welcome/readme/license/conclusion |
| JavaScript | Нет | Да (проверки совместимости, conditions) |
| Выбор компонентов | Нет | Да (choices-outline) |
| Создание на macOS | `pkgbuild` | `productbuild` |
| Создание на Linux | xar + mkbom вручную | xar + mkbom + Distribution.xml вручную |
| Установка | `installer -pkg ... -target /` | `installer -pkg ... -target /` |

---

## Проверка результата

```bash
# Проверить, что .pkg является валидным XAR-архивом
xar -t -f mytool.pkg

# На macOS — validate через pkgutil
pkgutil --check-signature mytool.pkg
pkgutil --expand mytool.pkg pkg_expanded/

# Установить на macOS
sudo installer -pkg mytool.pkg -target /
```

---

## Известные ограничения и подводные камни

1. **gid 80 vs 0**: На macOS группа `admin` имеет gid=80, группа `wheel` — gid=0. Для системных файлов используется uid=0, gid=80. Если указать gid=0, установка пройдёт, но права будут нестандартными.

2. **cpio --format odc**: macOS Installer не принимает другие форматы cpio. Только `odc` (old POSIX).

3. **--compression none для xar**: Payload уже сжат. Если xar дополнительно сожмёт весь архив, установщик не сможет его прочитать.

4. **mkbom path**: mkbom должен запускаться так, чтобы путь `source` указывал непосредственно на корень install root (pkgroot), а не на родительский каталог.

5. **numberOfFiles**: Значение `numberOfFiles` в `<payload>` должно включать каталоги, не только файлы. Используйте `find . | wc -l` внутри install root.

6. **Scripts archive**: Файлы скриптов не должны иметь расширений. Скрипт должен называться `preinstall`, не `preinstall.sh`.

7. **Подпись перед нотаризацией**: Apple требует, чтобы `.pkg` был подписан Developer ID Installer сертификатом перед нотаризацией. Без подписи нотаризация отклонит пакет.

---

## Источники

- [Build an OSX .pkg installer from Linux using mkbom and xar (Gist)](https://gist.github.com/SchizoDuckie/2a1a1cc71284e6463b9a)
- [bomutils — GitHub (hogliux)](https://github.com/hogliux/bomutils)
- [bomutils tutorial](http://hogliux.github.io/bomutils/tutorial.html)
- [Distributing macOS packages from Linux (remedio.io)](https://remedio.io/blog/automating-mac-software-package-process-on-a-linux-based-os)
- [yggdrasil-go create-pkg.sh (реальный production-скрипт)](https://github.com/yggdrasil-network/yggdrasil-go/blob/master/contrib/macos/create-pkg.sh)
- [xar man page (mankier)](https://www.mankier.com/1/xar)
- [xar full documentation (mackyle)](https://mackyle.github.io/xar/xar.html)
- [OSX flat packages (matthew-brett)](https://matthew-brett.github.io/docosx/flat_packages.html)
- [Flat Package Format — The missing documentation (sudre)](http://s.sudre.free.fr/Stuff/Ivanhoe/FLAT.html)
- [Distribution XML Reference (Apple)](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/Chapters/Distribution_XML_Ref.html)
- [Relocatable Package Installers (scriptingosx)](https://scriptingosx.com/2017/05/relocatable-package-installers-and-quickpkg-update/)
- [PackageInfo example (boot2docker)](https://github.com/boot2docker/osx-installer/blob/master/mpkg/boot2dockeriso.pkg/PackageInfo)
- [osx-pkg Node.js module (finnp)](https://github.com/finnp/osx-pkg)
- [Unpack and repack .pkg on Linux (codestudy.net)](https://www.codestudy.net/blog/how-to-unpack-and-pack-pkg-file/)

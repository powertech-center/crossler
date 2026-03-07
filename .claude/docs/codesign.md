# codesign — подпись macOS-бинарников и приложений

## Что такое codesign

`codesign` — нативная утилита macOS для создания и проверки цифровых подписей Apple. Входит в Xcode Command Line Tools. Подпись необходима для:

- Запуска приложений без предупреждения Gatekeeper («неизвестный разработчик»)
- Нотаризации (Apple Notary Service требует, чтобы все компоненты были подписаны)
- Hardened Runtime (ограниченное выполнение, нужно для нотаризации с macOS 10.15+)
- App Store распространения

**Документация:** `man codesign`, [developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide)

---

## Установка

```bash
# Входит в Xcode Command Line Tools
xcode-select --install

# Проверка наличия
codesign --version
```

---

## Типы сертификатов

| Тип | Использование |
|-----|---------------|
| **Developer ID Application** | Подпись приложений для распространения вне App Store |
| **Developer ID Installer** | Подпись `.pkg` пакетов |
| **Apple Development** | Подпись для разработки и тестирования на своих устройствах |
| **Apple Distribution** | Подпись для App Store |

Для Crossler актуальны **Developer ID Application** (бинарники, .dmg) и **Developer ID Installer** (.pkg).

Сертификаты управляются через Keychain (хранилище ключей macOS). Идентификатор сертификата — строка вида `"Developer ID Application: Company Name (TEAMID)"`.

---

## Команды и аргументы

### Подпись файла или приложения

```
codesign [options] --sign <identity> file [file ...]
```

| Аргумент | Описание |
|----------|----------|
| `--sign <identity>` / `-s <identity>` | Идентификатор сертификата (имя субъекта или SHA-1 хэш). `-` означает специальную подпись (ad-hoc) |
| `--force` / `-f` | Перезаписать существующую подпись |
| `--verbose` / `-v` | Подробный вывод (можно `-vvvv`) |
| `--options <flags>` / `-o <flags>` | Флаги подписи: `runtime` (Hardened Runtime), `library-validation` |
| `--entitlements <file>` | Plist-файл с правами (entitlements) |
| `--timestamp` | Добавить защищённый штамп времени Apple TSA |
| `--timestamp=none` | Не добавлять штамп времени |
| `--keychain <keychain>` | Указать конкретный keychain-файл |
| `--identifier <id>` | Явно задать bundle identifier |
| `--deep` | Рекурсивно подписать вложенные компоненты (не рекомендуется для приложений — лучше подписывать вручную изнутри) |
| `--strict` | Строгая проверка при верификации |
| `--preserve-metadata` | Сохранить метаданные существующей подписи |
| `--requirements <reqs>` | Задать designation requirements |

### Верификация подписи

```
codesign --verify [options] file [file ...]
```

| Аргумент | Описание |
|----------|----------|
| `--verify` / `-v` | Верифицировать подпись |
| `--deep` | Рекурсивная верификация |
| `--strict` | Строгие требования |
| `--verbose` | Подробный вывод |

### Просмотр информации о подписи

```
codesign --display [options] file
```

| Аргумент | Описание |
|----------|----------|
| `--display` / `-d` | Показать информацию о подписи |
| `--verbose` | Детальный вывод |
| `--xml` | Вывод в XML |
| `-r-` | Показать embedded requirements |

---

## Hardened Runtime и Entitlements

**Hardened Runtime** — режим выполнения с ограниченными правами, обязательный для нотаризации начиная с macOS 10.15 Catalina. Включается через `--options runtime`.

**Entitlements** — права, которые приложение запрашивает у системы. Файл `.entitlements` — это XML plist.

Пример entitlements для CLI-утилиты:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime по умолчанию строгий; разрешения добавляются по необходимости -->

    <!-- Разрешить JIT-компиляцию (для VM, игровых движков) -->
    <!-- <key>com.apple.security.cs.allow-jit</key><true/> -->

    <!-- Разрешить unsigned memory execution -->
    <!-- <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/> -->

    <!-- Разрешить dyld переменные окружения (DYLD_LIBRARY_PATH и т.д.) -->
    <!-- <key>com.apple.security.cs.allow-dyld-environment-variables</key><true/> -->

    <!-- Разрешить сетевой клиент (обычно не нужен явно) -->
    <!-- <key>com.apple.security.network.client</key><true/> -->
</dict>
</plist>
```

Для большинства CLI-утилит файл entitlements не нужен — достаточно просто включить Hardened Runtime.

---

## Практические примеры

### Подпись CLI-бинарника (минимальная, для нотаризации)

```bash
codesign \
  --sign "Developer ID Application: My Company (TEAMID)" \
  --options runtime \
  --timestamp \
  --verbose \
  ./mybinary
```

### Подпись приложения (.app bundle)

```bash
# Важно: сначала подписываем вложенные компоненты, потом само приложение
# Подписываем фреймворки (если есть)
codesign --sign "Developer ID Application: My Company (TEAMID)" \
  --options runtime --timestamp \
  MyApp.app/Contents/Frameworks/MyFramework.framework

# Подписываем вспомогательные исполняемые файлы
codesign --sign "Developer ID Application: My Company (TEAMID)" \
  --options runtime --timestamp \
  MyApp.app/Contents/MacOS/helper

# Подписываем само приложение
codesign --sign "Developer ID Application: My Company (TEAMID)" \
  --options runtime --timestamp \
  --entitlements MyApp.entitlements \
  MyApp.app
```

### Подпись с кастомным keychain (для CI/CD)

В CI/CD сертификат импортируют во временный keychain:

```bash
# Создать временный keychain
security create-keychain -p "temp_password" build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "temp_password" build.keychain
security set-keychain-settings -t 3600 -u build.keychain

# Импортировать сертификат из PFX
security import codesign.p12 \
  -k build.keychain \
  -P "P12_PASSWORD" \
  -T /usr/bin/codesign

# Разрешить codesign доступ без пользовательского диалога
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "temp_password" \
  build.keychain

# Подписать
codesign \
  --sign "Developer ID Application: My Company (TEAMID)" \
  --keychain build.keychain \
  --options runtime \
  --timestamp \
  ./mybinary

# Удалить keychain после использования
security delete-keychain build.keychain
```

### Подпись бинарника с entitlements

```bash
codesign \
  --sign "Developer ID Application: My Company (TEAMID)" \
  --options runtime \
  --timestamp \
  --entitlements entitlements.plist \
  ./mybinary
```

### Ad-hoc подпись (для локального тестирования, без сертификата)

```bash
codesign --sign - --force ./mybinary
```

Ad-hoc подпись снимает ограничение "неизвестного разработчика" на той же машине, но не работает на других машинах и не подходит для нотаризации.

### Верификация подписи

```bash
# Базовая проверка
codesign --verify ./mybinary

# Строгая проверка с подробным выводом
codesign --verify --deep --strict --verbose=4 ./mybinary
```

### Просмотр информации о подписи

```bash
codesign --display --verbose=4 ./mybinary
```

Пример вывода:
```
Executable=/path/to/mybinary
Identifier=com.example.mybinary
Format=Mach-O thin (arm64)
CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=56+7 location=embedded
Signature size=9022
Timestamp=Mar 7, 2026 at 12:00:00
Info.plist=not bound
TeamIdentifier=ABCD1234EF
Runtime Version=14.0.0
Sealed Resources=none
Internal requirements count=1 size=88
```

### Проверка принятия Gatekeeper

```bash
spctl --assess --type execute --verbose ./mybinary
```

---

## Особенности подписи для разных форматов

### Universal Binary (fat binary: x86_64 + arm64)

Universal Binary подписывается как единый файл — `codesign` автоматически создаёт подпись для каждого среза:

```bash
codesign --sign "Developer ID Application: ..." --options runtime --timestamp ./mybinary-universal
```

### .dylib и .framework

```bash
codesign --sign "Developer ID Application: ..." --options runtime --timestamp ./MyLib.dylib
```

### .pkg пакеты

Для `.pkg` используется отдельный тип сертификата (`Developer ID Installer`) и отдельная утилита `pkgutil`, хотя `productsign` технически использует `codesign` внутри:

```bash
productsign --sign "Developer ID Installer: My Company (TEAMID)" input.pkg output-signed.pkg
```

### .dmg образы

`.dmg` подписывается через `codesign`:

```bash
codesign --sign "Developer ID Application: My Company (TEAMID)" --timestamp MyApp.dmg
```

---

## Подводные камни

**Порядок подписи:** Для .app bundle нужно подписывать изнутри наружу: сначала фреймворки и хелперы, потом само приложение. Если подписать приложение целиком через `--deep`, вложенные компоненты могут получить неправильные подписи.

**`--deep` не рекомендуется для продакшена:** Флаг `--deep` пропускает некоторые компоненты и не гарантирует правильный порядок. Используйте явную последовательность подписи.

**Hardened Runtime и .dylib injection:** Включение Hardened Runtime запрещает DYLD_INSERT_LIBRARIES и аналогичные механизмы. Если приложение их использует, нужен соответствующий entitlement.

**Перекомпиляция инвалидирует подпись:** После подписи файл не должен изменяться — любое изменение байтов делает подпись невалидной.

**Keychain в CI/CD:** codesign должен иметь доступ к private key в keychain без пользовательского диалога. `set-key-partition-list` решает это программно.

**Apple TSA требует сети:** `--timestamp` обращается к серверам Apple. В изолированных сетях это нужно учитывать.

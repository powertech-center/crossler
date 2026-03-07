# rcodesign — кросс-платформенная подпись и нотаризация macOS-артефактов

## Что такое rcodesign

`rcodesign` — CLI-утилита из проекта `apple-codesign` (Rust-крейт), которая реализует протоколы Apple Code Signing и Apple Notary Service без нативного macOS окружения. Позволяет подписывать macOS-бинарники и нотаризировать их прямо с Linux или Windows.

Это **единственный** полноценный open-source инструмент для macOS-подписи вне macOS. Использует Apple Notary API v2 (REST) и воспроизводит те же криптографические операции, что и нативные `codesign` и `notarytool`.

**Репозиторий:** https://github.com/indygreg/apple-platform-rs
**Крейт:** `apple-codesign`
**Лицензия:** MPL-2.0

---

## Установка

```bash
# Скачать готовый бинарник с GitHub Releases
# (рекомендуется для CI/CD — не требует Rust toolchain)
# https://github.com/indygreg/apple-platform-rs/releases
# Архивы: apple-codesign-X.Y.Z-<platform>.tar.gz

# Через cargo (требует Rust)
cargo install apple-codesign

# Проверка
rcodesign --version
```

---

## Ограничения по сравнению с нативным codesign

| Возможность | rcodesign | codesign |
|-------------|:---------:|:--------:|
| Подпись Mach-O бинарников | Да | Да |
| Подпись .app bundle | Да | Да |
| Подпись .dmg | Да | Да |
| Подпись .pkg | Да | Через productsign |
| Hardened Runtime | Да | Да |
| Entitlements | Да | Да |
| Защищённый штамп времени Apple TSA | Да | Да |
| Нотаризация | Да | Через notarytool |
| Stapling | Да | Да |
| Доступ к системному Keychain | Нет | Да |
| Работа без macOS | Да | Нет |

---

## Форматы ключей и сертификатов

rcodesign **не использует** системный Keychain macOS. Вместо этого работает с файлами:

| Формат | Описание |
|--------|----------|
| PFX/PKCS#12 (`.p12`) | Сертификат + приватный ключ в одном файле |
| PEM-сертификат | Открытый сертификат цепочки |
| PEM-ключ | Приватный ключ |
| Смарт-карта / YubiKey | Через встроенную PKCS#11-интеграцию (yubikey feature) |

---

## Команды и аргументы

### sign — подписать файл или директорию

```
rcodesign sign [options] path [path ...]
```

| Аргумент | Описание |
|----------|----------|
| `--p12-file <file>` | PFX/P12-файл с сертификатом и ключом |
| `--p12-password <pass>` | Пароль к P12-файлу |
| `--p12-password-file <file>` | Файл с паролем к P12 |
| `--pem-file <file>` | Сертификат или приватный ключ в PEM (можно указывать несколько раз для цепочки) |
| `--signing-key <key>` | Приватный ключ отдельно (вместе с `--certificate-der-file`) |
| `--certificate-der-file <file>` | DER-сертификат |
| `--entitlements-xml-file <file>` | Plist-файл с entitlements |
| `--code-signature-flags <flags>` | Флаги подписи: `runtime` для Hardened Runtime |
| `--timestamp-url <url>` | URL TSA-сервера (по умолчанию: Apple TSA) |
| `--no-timestamp` | Не добавлять штамп времени |
| `--binary-identifier <id>` | Явно задать bundle identifier |
| `--signing-time <time>` | Фиксированное время подписи (ISO 8601) |
| `--exclude <glob>` | Исключить файлы по glob-паттерну |
| `--verbose` | Подробный вывод |
| `-o <file>` | Выходной файл (по умолчанию подписывает на месте) |

### notarize — отправить на нотаризацию Apple

```
rcodesign notary-submit [options] file
```

| Аргумент | Описание |
|----------|----------|
| `--api-key-file <file>` | JSON-файл с App Store Connect API key |
| `--api-issuer <id>` | Issuer ID (если ключ задан через `--api-key`) |
| `--api-key <id>` | Key ID (вместо JSON-файла) |
| `--wait` | Ждать завершения нотаризации |
| `--max-wait-seconds <n>` | Таймаут ожидания в секундах |
| `--staple` | Автоматически скрепить тикет после нотаризации |
| `--output-path <file>` | Записать результирующий файл (со скреплённым тикетом) в этот путь |

### staple — скрепить нотаризационный тикет

```
rcodesign staple path [path ...]
```

### verify — верифицировать подпись

```
rcodesign verify [options] path
```

| Аргумент | Описание |
|----------|----------|
| `--profile <profile>` | Профиль верификации: `notarization-required`, `notarization-recommended`, `notarization-disabled` |

### extract — извлечь данные подписи

```
rcodesign extract [options] path
```

| Аргумент | Описание |
|----------|----------|
| `--data <type>` | Что извлечь: `blobs`, `cms-info`, `code-directory-v`, `requirements`, `embedded-signature`, `macho-header`, `segment-info` |

### analyze-certificate — анализировать сертификат

```
rcodesign analyze-certificate --p12-file cert.p12 --p12-password pass
```

---

## App Store Connect API Key

rcodesign для нотаризации использует App Store Connect API Key v2 (JSON-формат):

```json
{
  "issuer_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "key_id": "XXXXXXXXXX",
  "private_key": "-----BEGIN EC PRIVATE KEY-----\n...\n-----END EC PRIVATE KEY-----"
}
```

Создать ключ: App Store Connect → Users and Access → Integrations → App Store Connect API → Generate API Key. Скачать `.p8`-файл и вставить его содержимое в поле `private_key`.

---

## Практические примеры

### Подпись бинарника для нотаризации

```bash
rcodesign sign \
  --p12-file codesign.p12 \
  --p12-password "PASSWORD" \
  --code-signature-flags runtime \
  --verbose \
  ./mytool
```

### Подпись бинарника с entitlements

```bash
rcodesign sign \
  --p12-file codesign.p12 \
  --p12-password "PASSWORD" \
  --code-signature-flags runtime \
  --entitlements-xml-file entitlements.plist \
  ./mytool
```

### Подпись .app bundle

```bash
rcodesign sign \
  --p12-file codesign.p12 \
  --p12-password "PASSWORD" \
  --code-signature-flags runtime \
  MyApp.app
```

rcodesign автоматически подписывает вложенные компоненты в правильном порядке (изнутри наружу).

### Подпись .dmg

```bash
rcodesign sign \
  --p12-file codesign.p12 \
  --p12-password "PASSWORD" \
  MyApp.dmg
```

### Нотаризация с ожиданием и автоматическим staple

```bash
rcodesign notary-submit \
  --api-key-file api-key.json \
  --wait \
  --staple \
  MyApp.dmg
```

### Полный рабочий процесс: подпись → нотаризация → staple

```bash
# 1. Подписать
rcodesign sign \
  --p12-file codesign.p12 \
  --p12-password "$P12_PASSWORD" \
  --code-signature-flags runtime \
  MyApp.dmg

# 2. Нотаризировать и скрепить тикет
rcodesign notary-submit \
  --api-key-file api-key.json \
  --wait \
  --staple \
  MyApp.dmg

# 3. Верифицировать
rcodesign verify --profile notarization-required MyApp.dmg
```

### Только staple (после отдельной нотаризации)

```bash
rcodesign staple MyApp.dmg
```

### Использование в CI/CD (GitHub Actions, Linux runner)

```yaml
- name: Sign and notarize macOS binary
  run: |
    # Скачать rcodesign
    curl -L "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.27.0/apple-codesign-0.27.0-x86_64-unknown-linux-musl.tar.gz" | tar xz
    mv rcodesign /usr/local/bin/

    # Декодировать сертификат из секрета
    echo "$P12_BASE64" | base64 --decode > codesign.p12

    # Записать API key
    echo "$NOTARY_API_KEY_JSON" > api-key.json

    # Подписать
    rcodesign sign \
      --p12-file codesign.p12 \
      --p12-password "$P12_PASSWORD" \
      --code-signature-flags runtime \
      ./mytool-darwin-amd64

    # Нотаризировать
    rcodesign notary-submit \
      --api-key-file api-key.json \
      --wait \
      --staple \
      ./mytool-darwin-amd64
  env:
    P12_BASE64: ${{ secrets.MACOS_SIGN_P12 }}
    P12_PASSWORD: ${{ secrets.MACOS_SIGN_PASSWORD }}
    NOTARY_API_KEY_JSON: ${{ secrets.NOTARY_API_KEY_JSON }}
```

---

## Верификация результата

```bash
# Базовая верификация подписи
rcodesign verify ./mytool

# Верификация с требованием нотаризации
rcodesign verify --profile notarization-required ./mytool

# Просмотр информации о подписи
rcodesign extract --data cms-info ./mytool
```

---

## Подводные камни

**P12-файл должен содержать полную цепочку:** Apple требует, чтобы в P12 была встроена вся цепочка сертификатов (Developer ID Application → Apple Worldwide Developer Relations → Apple Root CA). Если промежуточных сертификатов нет, нотаризация завершится ошибкой.

**Экспорт сертификата из Keychain:** При экспорте из macOS Keychain Access выбирайте «Export as P12 with certificate chain» — это гарантирует наличие промежуточных сертификатов.

**Версии Apple Notary API:** rcodesign использует Notary API v2 (REST, введён Apple в 2022). Убедитесь, что используете актуальную версию rcodesign.

**`runtime` flag обязателен для нотаризации:** Без `--code-signature-flags runtime` нотаризация завершится с ошибкой `APPLE_ENABLE_HARDENED_RUNTIME`.

**Universal Binary:** rcodesign поддерживает universal binary (fat binary с несколькими архитектурами) — подписывает каждый срез отдельно.

**Отличие от codesign в обработке .app:** rcodesign v0.22+ правильно обрабатывает .app bundle и подписывает вложенные компоненты в нужном порядке. На более старых версиях могут быть проблемы.

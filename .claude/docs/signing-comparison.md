# Сравнительный анализ инструментов подписи

## Обзор инструментов

| Инструмент | Назначение | Платформа запуска | ОС-цель |
|------------|------------|:-----------------:|---------|
| `signtool.exe` | Authenticode (Windows) | Windows | Windows |
| `osslsigncode` | Authenticode (Windows) | Linux, macOS, Windows | Windows |
| `codesign` | Apple Code Signing | macOS | macOS |
| `notarytool` | Apple Notarization | macOS | macOS |
| `rcodesign` | Apple Code Signing + Notarization | Linux, macOS, Windows | macOS |

---

## 1. Платформа запуска и целевая платформа

Ключевое архитектурное отличие: одни инструменты привязаны к платформе, другие — кросс-платформенны.

### Authenticode (Windows-подпись)

```
Хост:    Linux/macOS  →  osslsigncode  →  .exe/.msi/.dll
Хост:    Windows      →  signtool.exe  →  .exe/.msi/.dll
```

### Apple Code Signing (macOS-подпись)

```
Хост:    macOS        →  codesign + notarytool  →  Mach-O/.app/.dmg/.pkg
Хост:    Linux/Win    →  rcodesign              →  Mach-O/.app/.dmg/.pkg
```

**Вывод:** Для каждого вида подписи есть кросс-платформенная альтернатива. `osslsigncode` — кросс-платформенная альтернатива `signtool`. `rcodesign` — кросс-платформенная альтернатива `codesign` + `notarytool`.

---

## 2. Источник ключей и сертификатов

| Инструмент | PFX/P12 | PEM файлы | Системный Keychain | PKCS#11 / HSM |
|------------|:-------:|:---------:|:-----------------:|:--------------:|
| `signtool` | Да | Нет | Да | Да (через CNG KSP) |
| `osslsigncode` | Да | Да | Нет | Да (через OpenSSL ENGINE) |
| `codesign` | Нет | Нет | Да (только) | Через Keychain |
| `notarytool` | — | — | Apple ID / API Key | — |
| `rcodesign` | Да | Да | Нет | Да (YubiKey) |

**Ключевое отличие:** `codesign` умеет работать исключительно с системным Keychain macOS. `osslsigncode` и `rcodesign` работают с файлами напрямую, что делает их идеальными для CI/CD.

---

## 3. Способ задания алгоритма хэша

| Инструмент | Команда | Значение по умолчанию |
|------------|---------|----------------------|
| `signtool` | `/fd sha256` | sha1 (устаревший), следует явно указывать sha256 |
| `osslsigncode` | `-h sha256` | sha256 |
| `codesign` | Не задаётся | SHA-256 (автоматически) |
| `rcodesign` | Не задаётся | SHA-256 (автоматически) |

---

## 4. Штамп времени (TSA)

| Инструмент | Аргумент | Формат | Примечание |
|------------|----------|--------|------------|
| `signtool` | `/tr <url>` | RFC 3161 | `/td sha256` — алгоритм хэша штампа |
| `signtool` | `/t <url>` | Authenticode (устаревший) | — |
| `osslsigncode` | `-ts <url>` | RFC 3161 | — |
| `osslsigncode` | `-t <url>` | Authenticode (устаревший) | — |
| `codesign` | `--timestamp` | Apple TSA | URL нельзя изменить |
| `notarytool` | — | — | Не применимо |
| `rcodesign` | `--timestamp-url <url>` | Apple TSA | По умолчанию — Apple TSA |

**Важно:** `codesign` и `rcodesign` используют только TSA Apple. `signtool` и `osslsigncode` позволяют задать произвольный TSA-сервер.

---

## 5. Двойная подпись

Двойная подпись (dual-sign, SHA-1 + SHA-256) применяется для совместимости с Windows XP/Vista.

| Инструмент | Поддержка | Аргумент |
|------------|:---------:|---------|
| `signtool` | Да | `/as` (append signature) |
| `osslsigncode` | Да | `-nest` |
| `codesign` | Нет | — |
| `rcodesign` | Нет | — |

Apple Code Signing не имеет понятия двойной подписи — алгоритм выбирается автоматически.

---

## 6. Нотаризация

Нотаризация — исключительно macOS-концепция. Только два инструмента занимаются нотаризацией:

| Возможность | `notarytool` | `rcodesign` |
|-------------|:-----------:|:-----------:|
| Отправка на Apple Notary Service | Да | Да |
| Ожидание результата (`--wait`) | Да | Да |
| Автоматическое stapling | Нет (отдельный `xcrun stapler`) | Да (`--staple`) |
| Просмотр лога ошибок | Да | Да |
| Работает без macOS | Нет | Да |

**Ключевое отличие:** `rcodesign` объединяет подпись и нотаризацию в одном инструменте и работает на любой ОС. `notarytool` — только нотаризация, только на macOS.

---

## 7. Stapling

Stapling — встраивание нотаризационного тикета непосредственно в файл.

| Инструмент | Stapling |
|------------|:-------:|
| `xcrun stapler` | Да (отдельная команда, только macOS) |
| `rcodesign staple` | Да (только macOS, т.к. обращается к Apple CDN) |
| `notarytool` | Нет |

**Примечание:** Даже rcodesign для stapling требует доступа к серверам Apple CDN — тикет скачивается оттуда и встраивается в файл. Технически это можно сделать на любой ОС с интернетом, но в практике stapling обычно выполняется финальным шагом уже после нотаризации.

---

## 8. Поддерживаемые форматы файлов

### Authenticode

| Формат | `signtool` | `osslsigncode` |
|--------|:----------:|:--------------:|
| `.exe` PE32/PE32+ | Да | Да |
| `.dll` | Да | Да |
| `.sys` | Да | Да |
| `.msi` | Да | Да |
| `.cab` | Да | Да |
| `.cat` | Да | Нет |
| `.msix` / `.appx` | Да | Нет |
| PowerShell `.ps1` | Через Set-AuthenticodeSignature | Нет |

### Apple Code Signing

| Формат | `codesign` | `rcodesign` |
|--------|:----------:|:-----------:|
| Mach-O бинарник | Да | Да |
| Universal Binary | Да | Да |
| `.app` bundle | Да | Да |
| `.dmg` | Да | Да |
| `.pkg` | Через productsign | Да |
| `.dylib` | Да | Да |
| `.framework` | Да | Да |

---

## 9. Одна и та же задача разными инструментами

**Задача: Подписать бинарник + добавить штамп времени**

### Windows (Authenticode) через signtool:
```cmd
signtool sign /f cert.pfx /p PASSWORD /fd sha256 /tr http://timestamp.digicert.com /td sha256 myapp.exe
```

### Windows (Authenticode) через osslsigncode (с Linux):
```bash
osslsigncode sign -pkcs12 cert.pfx -pass "PASSWORD" -h sha256 -ts http://timestamp.digicert.com -in myapp.exe -out myapp-signed.exe
```

### macOS (Apple) через codesign:
```bash
codesign --sign "Developer ID Application: ..." --options runtime --timestamp ./mybinary
```

### macOS (Apple) через rcodesign (с Linux):
```bash
rcodesign sign --p12-file cert.p12 --p12-password "PASSWORD" --code-signature-flags runtime ./mybinary
```

---

**Задача: Нотаризировать macOS-бинарник**

### Через notarytool (только macOS):
```bash
ditto -c -k --keepParent ./mybinary mybinary.zip
xcrun notarytool submit mybinary.zip --keychain-profile "profile" --wait
xcrun stapler staple ./mybinary
```

### Через rcodesign (с любой ОС):
```bash
rcodesign notary-submit --api-key-file api-key.json --wait --staple ./mybinary
```

---

## 10. Матрица возможностей

| Возможность | signtool | osslsigncode | codesign | notarytool | rcodesign |
|-------------|:--------:|:------------:|:--------:|:----------:|:---------:|
| Authenticode (Windows) | Да | Да | Нет | Нет | Нет |
| Apple Code Signing (macOS) | Нет | Нет | Да | Нет | Да |
| Нотаризация Apple | Нет | Нет | Нет | Да | Да |
| Stapling | Нет | Нет | Через stapler | Нет | Да |
| Работает на Linux | Нет | Да | Нет | Нет | Да |
| Работает на macOS | Нет | Да | Да | Да | Да |
| Работает на Windows | Да | Да | Нет | Нет | Да |
| Файлы PFX/P12 | Да | Да | Нет | — | Да |
| PEM-файлы | Нет | Да | Нет | — | Да |
| Системный Keychain | Да | Нет | Да | Да | Нет |
| PKCS#11 / HSM | Да (KSP) | Да (ENGINE) | Нет | Нет | Да (YubiKey) |
| Двойная подпись | Да | Да | Нет | Нет | Нет |
| Hardened Runtime | — | — | Да | — | Да |
| Entitlements | — | — | Да | — | Да |
| MSI подпись | Да | Да | — | — | — |
| MSIX / Appx | Да | Нет | — | — | — |
| Open source | Нет | Да | Нет | Нет | Да |

---

## 11. Ключевые архитектурные наблюдения

### Симметрия кросс-платформенных альтернатив

Для каждого вида подписи существует кросс-платформенная альтернатива:
- `signtool` ↔ `osslsigncode` (оба — Authenticode; `osslsigncode` работает везде)
- `codesign` + `notarytool` ↔ `rcodesign` (оба — Apple подпись; `rcodesign` работает везде)

### Разделение ответственности в нативном macOS стеке

Apple разделила подпись и нотаризацию на два отдельных инструмента: `codesign` (подпись) и `notarytool` (нотаризация). `rcodesign` объединяет оба в одном бинарнике.

### Работа с ключами

Нативные инструменты (signtool, codesign) тесно интегрированы с системными хранилищами ключей (Windows certstore, macOS Keychain). Кросс-платформенные инструменты (osslsigncode, rcodesign) работают с файлами напрямую — это делает их более простыми для CI/CD, но требует аккуратного обращения с секретами.

### MSI подпись — нюанс

MSI-файлы требуют флага `-add-msi-dse` в osslsigncode для добавления расширения `MsiDigitalSignatureEx`. Без этого подпись технически работает, но некоторые инструменты (например, WiX toolset) могут выдавать предупреждения.

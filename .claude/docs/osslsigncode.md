# osslsigncode — Authenticode-подпись на Linux и macOS

## Что такое osslsigncode

`osslsigncode` — утилита с открытым исходным кодом для создания и проверки Authenticode-подписей (цифровая подпись Microsoft) на файлах PE (`.exe`, `.dll`), MSI-пакетах и CAB-архивах. Работает на Linux и macOS без установки Windows SDK или .NET. Использует OpenSSL как криптографический бэкенд.

Аналог штатного `signtool.exe` из Windows SDK, но кросс-платформенный. Позволяет CI/CD-пайплайнам, работающим на Linux, подписывать Windows-артефакты без виртуальной машины с Windows.

**Репозиторий:** https://github.com/mtrojnar/osslsigncode
**Лицензия:** GPLv3

---

## Установка

```bash
# Alpine Linux
apk add osslsigncode

# Ubuntu/Debian
apt install osslsigncode

# macOS
brew install osslsigncode

# Из исходников (если версия в репозитории устарела)
cmake -B build -S . && cmake --build build && cmake --install build
```

---

## Форматы сертификатов

osslsigncode работает с несколькими форматами ключей и сертификатов:

| Формат | Расширение | Описание |
|--------|------------|----------|
| PFX/PKCS#12 | `.pfx`, `.p12` | Сертификат + приватный ключ в одном файле (парольная защита) |
| PEM | `.pem`, `.crt` | Открытый сертификат в Base64 |
| PEM (ключ) | `.key` | Приватный ключ в Base64 |
| DER | `.der`, `.cer` | Бинарный формат сертификата |
| ENGINE | — | HSM или PKCS#11-устройство через OpenSSL ENGINE |

---

## Команды и аргументы

### sign — подписать файл

```
osslsigncode sign [options] -in input -out output
```

| Аргумент | Описание |
|----------|----------|
| `-in <file>` | Входной файл (PE, MSI, CAB) |
| `-out <file>` | Выходной подписанный файл |
| `-pkcs12 <file>` | PFX/P12-файл с сертификатом и ключом |
| `-pass <password>` | Пароль к PFX-файлу |
| `-certs <file>` | Сертификат в PEM/DER |
| `-key <file>` | Приватный ключ в PEM |
| `-h <algo>` | Алгоритм хэша: `sha1`, `sha256` (по умолчанию `sha256`) |
| `-n <name>` | Описание программы (отображается в диалоге UAC) |
| `-i <url>` | URL с информацией об издателе |
| `-t <url>` | URL штампа времени (RFC 3161), устаревший формат |
| `-ts <url>` | URL штампа времени (RFC 3161), современный формат |
| `-p <proxy>` | HTTP-прокси для обращения к TSA |
| `-ac <file>` | Дополнительный промежуточный сертификат |
| `-comm` | Пометить как Commercial (не Individually) |
| `-jp <level>` | Java CAB signing (low/medium/high) |
| `-ph` | Добавить Page Hash (требуется для некоторых EV-сертификатов) |
| `-add-msi-dse` | Добавить MsiDigitalSignatureEx в MSI |
| `-nest` | Добавить подпись поверх существующей (без замены) |
| `-verbose` | Подробный вывод |

### verify — проверить подпись

```
osslsigncode verify [options] -in file
```

| Аргумент | Описание |
|----------|----------|
| `-in <file>` | Файл для проверки |
| `-CAfile <file>` | Корневой CA-сертификат для верификации |
| `-CRLfile <file>` | CRL-файл для проверки отзыва |
| `-require-leaf-hash <algo>:<hash>` | Проверить хэш конечного сертификата |
| `-timestamp` | Проверить штамп времени |
| `-verbose` | Подробный вывод |

### extract — извлечь данные подписи

```
osslsigncode extract -in file -out signature.pkcs7
```

### remove — удалить подпись

```
osslsigncode remove -in file -out unsigned_file
```

---

## Штамп времени (Timestamp)

Штамп времени (TSA — Timestamp Authority) критически важен: он позволяет подписи оставаться валидной даже после истечения срока сертификата. Без штампа подпись становится невалидной, как только истечёт сертификат.

Публичные TSA-серверы (бесплатные):

```
http://timestamp.digicert.com
http://timestamp.sectigo.com
http://timestamp.comodoca.com
http://timestamp.globalsign.com
http://tsa.starfieldtech.com
```

Рекомендуется всегда добавлять `-ts` (RFC 3161):
```bash
osslsigncode sign \
  -pkcs12 cert.pfx -pass "password" \
  -ts http://timestamp.digicert.com \
  -in myapp.exe -out myapp-signed.exe
```

---

## Практические примеры

### Минимальная подпись PE-файла (PFX)

```bash
osslsigncode sign \
  -pkcs12 codesign.pfx \
  -pass "PFX_PASSWORD" \
  -in myapp.exe \
  -out myapp-signed.exe
```

### Подпись с SHA-256, штампом времени и описанием

```bash
osslsigncode sign \
  -pkcs12 codesign.pfx \
  -pass "PFX_PASSWORD" \
  -h sha256 \
  -ts http://timestamp.digicert.com \
  -n "My Application" \
  -i "https://example.com" \
  -in myapp.exe \
  -out myapp-signed.exe
```

### Подпись с отдельным ключом и сертификатом (PEM)

```bash
osslsigncode sign \
  -certs codesign.crt \
  -key codesign.key \
  -ac intermediate.crt \
  -h sha256 \
  -ts http://timestamp.digicert.com \
  -in myapp.exe \
  -out myapp-signed.exe
```

### Подпись MSI-пакета

```bash
osslsigncode sign \
  -pkcs12 codesign.pfx \
  -pass "PFX_PASSWORD" \
  -h sha256 \
  -ts http://timestamp.digicert.com \
  -add-msi-dse \
  -in installer.msi \
  -out installer-signed.msi
```

Флаг `-add-msi-dse` добавляет расширение `MsiDigitalSignatureEx`, которое требуется для корректного отображения подписи в Windows Installer.

### Двойная подпись (SHA-1 + SHA-256)

Некоторые организации требуют подпись обоими алгоритмами для совместимости с Windows XP/Vista:

```bash
# Первая подпись: SHA-1
osslsigncode sign \
  -pkcs12 codesign.pfx -pass "PASSWORD" \
  -h sha1 \
  -ts http://timestamp.digicert.com \
  -in myapp.exe -out myapp-sha1.exe

# Добавить SHA-256 поверх SHA-1
osslsigncode sign \
  -pkcs12 codesign.pfx -pass "PASSWORD" \
  -h sha256 \
  -ts http://timestamp.digicert.com \
  -nest \
  -in myapp-sha1.exe -out myapp-dual-signed.exe
```

### Верификация подписи

```bash
osslsigncode verify -in myapp-signed.exe
```

Пример вывода:
```
Current PE checksum   : 00000000
Calculated PE checksum: 00000000

Message digest algorithm  : SHA256
Current message digest    : <hash>
Calculated message digest : <hash>

Signature verification: ok
```

### Подпись через PKCS#11 HSM (через OpenSSL ENGINE)

```bash
osslsigncode sign \
  -e pkcs11 \
  -pkcs11module /usr/lib/opensc-pkcs11.so \
  -key "pkcs11:token=MyToken;object=MyKey;pin-value=1234" \
  -certs codesign.crt \
  -h sha256 \
  -ts http://timestamp.digicert.com \
  -in myapp.exe -out myapp-signed.exe
```

---

## Поддерживаемые форматы файлов

| Формат | Поддержка |
|--------|-----------|
| PE32 `.exe` (32-бит) | Полная |
| PE32+ `.exe` (64-бит) | Полная |
| `.dll` | Полная |
| `.sys` (драйвер) | Полная |
| `.msi` | Полная (с `-add-msi-dse`) |
| `.cab` | Полная |
| `.cat` | Нет |
| Appx/MSIX | Нет |

---

## Ограничения и подводные камни

**Не поддерживает MSIX/Appx:** Современные пакеты Microsoft Store требуют специфического механизма подписи (`signtool` с ключом `/fd SHA256`). osslsigncode с ними не работает.

**PFX с пустым паролем:** Некоторые PFX-файлы без пароля могут не работать с `-pass ""`. В таком случае попробуйте не указывать `-pass` вообще.

**Промежуточные сертификаты:** Если цепочка не встроена в PFX, добавляйте промежуточные сертификаты через `-ac intermediate.crt`. Без полной цепочки Windows может не доверять подписи.

**SHA-1 deprecated:** Windows 10 v1703+ блокирует исполняемые файлы, подписанные только SHA-1. Всегда используйте `-h sha256` или добавляйте двойную подпись.

**Сетевые ошибки при штампе времени:** TSA-серверы могут быть недоступны или медленны. Рекомендуется retry-логика или использование нескольких TSA-URL.

**Права на запись:** osslsigncode пишет во временный файл и заменяет выходной файл атомарно. Убедитесь, что у процесса есть права на директорию назначения.

---

## Сравнение с signtool.exe

| Возможность | osslsigncode | signtool.exe |
|-------------|:------------:|:------------:|
| Linux | Да | Нет |
| macOS | Да | Нет |
| Windows | Да | Да |
| PFX/P12 | Да | Да |
| PEM/KEY (раздельно) | Да | Нет |
| PKCS#11 / HSM | Да | Да (через KSP) |
| SHA-256 | Да | Да |
| Двойная подпись (`-nest`) | Да | Да (`/as`) |
| MSI подпись | Да | Да |
| MSIX/Appx | Нет | Да |
| EV сертификаты | Да | Да |
| Kernel Mode Code Signing | Нет | Да (через WHQL) |

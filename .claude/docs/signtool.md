# signtool — Authenticode-подпись на Windows

## Что такое signtool

`signtool.exe` — официальная утилита Microsoft для Authenticode-подписи файлов на Windows. Входит в состав Windows SDK и доступна в Windows SDK, Visual Studio, а также в GitHub Actions на Windows-раннерах.

Authenticode — стандарт цифровой подписи Microsoft, позволяющий Windows и браузерам верифицировать издателя исполняемых файлов. Без Authenticode-подписи Windows Defender SmartScreen показывает предупреждение при запуске приложения.

**Расположение:** `C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\signtool.exe`

---

## Установка

```
# Через Visual Studio Installer (автоматически)
# или отдельный Windows SDK:
# winget install Microsoft.WindowsSDK.10.0.26100

# В GitHub Actions (windows-latest) signtool уже доступен
# Обычно в PATH или по пути:
# C:\Program Files (x86)\Windows Kits\10\bin\10.0.*/x64\signtool.exe
```

---

## Форматы сертификатов

| Формат | Описание |
|--------|----------|
| PFX/PKCS#12 | Сертификат + приватный ключ в одном файле (парольная защита) |
| Хранилище Windows | Сертификат установлен в системное хранилище (certstore) |
| SHA-1 thumbprint | Ссылка на сертификат в хранилище по отпечатку |
| Subject name | Ссылка на сертификат по имени субъекта |
| PKCS#11 / CNG KSP | HSM и hardware-токены через Key Storage Provider |
| Azure Key Vault | Через AzureSignTool (надстройка над signtool) |

---

## Команды и аргументы

### sign — подписать файл

```
signtool sign [options] file [file ...]
```

**Выбор сертификата:**

| Аргумент | Описание |
|----------|----------|
| `/f <pfx>` | PFX-файл с сертификатом и ключом |
| `/p <password>` | Пароль к PFX-файлу |
| `/sha1 <hash>` | SHA-1 thumbprint сертификата в хранилище |
| `/n <name>` | Имя субъекта сертификата в хранилище |
| `/s <store>` | Хранилище: `My` (Personal), `Root`, `CA` (по умолчанию `My`) |
| `/sm` | Использовать хранилище машины вместо текущего пользователя |
| `/a` | Автоматически выбрать лучший сертификат |
| `/u <oid>` | Ограничить по Extended Key Usage OID |

**Алгоритм и хэш:**

| Аргумент | Описание |
|----------|----------|
| `/fd <algo>` | Алгоритм хэша файла: `sha1`, `sha256`, `sha384`, `sha512` (рекомендуется `sha256`) |
| `/td <algo>` | Алгоритм хэша штампа времени (RFC 3161, рекомендуется `sha256`) |

**Штамп времени:**

| Аргумент | Описание |
|----------|----------|
| `/t <url>` | URL штампа времени (устаревший формат Authenticode) |
| `/tr <url>` | URL штампа времени (RFC 3161, рекомендуется) |

**Описание:**

| Аргумент | Описание |
|----------|----------|
| `/d <desc>` | Описание программы (отображается в диалоге UAC) |
| `/du <url>` | URL с информацией об издателе |

**Дополнительные параметры:**

| Аргумент | Описание |
|----------|----------|
| `/as` | Добавить подпись поверх существующей (dual-sign) |
| `/ph` | Добавить Page Hash (для некоторых EV-сертификатов) |
| `/ac <file>` | Дополнительный промежуточный сертификат |
| `/v` | Подробный вывод |
| `/q` | Тихий режим (только ошибки) |
| `/debug` | Отладочная информация |
| `/dlib <dll>` | Пользовательская DLL для создания подписи |
| `/dmdf <file>` | Аргументы для пользовательской DLL |

### verify — проверить подпись

```
signtool verify [options] file [file ...]
```

| Аргумент | Описание |
|----------|----------|
| `/pa` | Использовать политику Authenticode (по умолчанию) |
| `/ph` | Проверить Page Hash |
| `/r <rootname>` | Имя корневого CA-сертификата |
| `/tw` | Предупреждать, если нет штампа времени |
| `/all` | Проверить все подписи (для dual-signed файлов) |
| `/v` | Подробный вывод |

### timestamp — добавить штамп времени к уже подписанному файлу

```
signtool timestamp /t <url> file
signtool timestamp /tr <url> file
```

### catdb — управление базой каталогов

```
signtool catdb [options] catalog [catalog ...]
```

---

## Штамп времени (Timestamp)

Публичные TSA-серверы (бесплатные):

```
http://timestamp.digicert.com          # RFC 3161
http://timestamp.sectigo.com           # RFC 3161
http://timestamp.comodoca.com          # RFC 3161
http://timestamp.globalsign.com/tsa/r6 # RFC 3161
http://tsa.starfieldtech.com           # RFC 3161
```

Рекомендуется всегда использовать `/tr` (RFC 3161) вместо `/t` (Authenticode), и указывать `/td sha256`.

---

## Практические примеры

### Минимальная подпись (PFX)

```cmd
signtool sign /f codesign.pfx /p "PASSWORD" myapp.exe
```

### Подпись с SHA-256 и штампом времени

```cmd
signtool sign ^
  /f codesign.pfx ^
  /p "PASSWORD" ^
  /fd sha256 ^
  /tr http://timestamp.digicert.com ^
  /td sha256 ^
  /d "My Application" ^
  /du "https://example.com" ^
  myapp.exe
```

### Подпись по thumbprint (сертификат в хранилище)

```cmd
signtool sign ^
  /sha1 "ABCDEF1234567890ABCDEF1234567890ABCDEF12" ^
  /fd sha256 ^
  /tr http://timestamp.digicert.com ^
  /td sha256 ^
  myapp.exe
```

### Подпись нескольких файлов одной командой

```cmd
signtool sign /f codesign.pfx /p "PASSWORD" /fd sha256 /tr http://timestamp.digicert.com /td sha256 ^
  myapp.exe helper.dll installer.msi
```

### Двойная подпись (SHA-1 + SHA-256)

```cmd
REM Первая подпись: SHA-1 (для Windows XP/Vista)
signtool sign /f codesign.pfx /p "PASSWORD" /fd sha1 /t http://timestamp.digicert.com myapp.exe

REM Добавить SHA-256 поверх SHA-1
signtool sign /f codesign.pfx /p "PASSWORD" /fd sha256 /tr http://timestamp.digicert.com /td sha256 /as myapp.exe
```

### Подпись MSI-пакета

```cmd
signtool sign ^
  /f codesign.pfx ^
  /p "PASSWORD" ^
  /fd sha256 ^
  /tr http://timestamp.digicert.com ^
  /td sha256 ^
  installer.msi
```

### Верификация подписи

```cmd
signtool verify /pa myapp.exe
```

### Верификация с подробным выводом

```cmd
signtool verify /pa /v myapp.exe
```

---

## EV-сертификаты и HSM

EV (Extended Validation) сертификаты хранятся на аппаратных токенах (HSM, USB-токены) и не могут быть экспортированы в PFX. Для работы с ними signtool использует CNG Key Storage Provider (KSP).

```cmd
REM Токен должен быть подключён, driver установлен
REM Сертификат появится в хранилище My
signtool sign ^
  /sha1 "<EV_CERT_THUMBPRINT>" ^
  /fd sha256 ^
  /tr http://timestamp.digicert.com ^
  /td sha256 ^
  myapp.exe
```

### Azure Key Vault через AzureSignTool

Для CI/CD без физического токена используют Azure Key Vault + [AzureSignTool](https://github.com/vcsjones/AzureSignTool):

```cmd
AzureSignTool sign ^
  -kvu "https://my-vault.vault.azure.net" ^
  -kvc "my-cert-name" ^
  -kvi "<CLIENT_ID>" ^
  -kvs "<CLIENT_SECRET>" ^
  -kvt "<TENANT_ID>" ^
  -fd sha256 ^
  -tr http://timestamp.digicert.com ^
  -td sha256 ^
  myapp.exe
```

---

## Использование в GitHub Actions

```yaml
- name: Sign executable
  shell: cmd
  run: |
    # Декодировать PFX из секрета
    echo %CERT_PFX_BASE64% > cert_b64.txt
    certutil -decode cert_b64.txt codesign.pfx

    # Найти signtool
    for /f "delims=" %%i in ('where /r "C:\Program Files (x86)\Windows Kits" signtool.exe') do set SIGNTOOL=%%i

    # Подписать
    "%SIGNTOOL%" sign /f codesign.pfx /p "%CERT_PASSWORD%" /fd sha256 /tr http://timestamp.digicert.com /td sha256 myapp.exe
  env:
    CERT_PFX_BASE64: ${{ secrets.CODE_SIGN_PFX }}
    CERT_PASSWORD: ${{ secrets.CODE_SIGN_PASSWORD }}
```

---

## Поддерживаемые форматы файлов

| Формат | Поддержка |
|--------|-----------|
| PE32 `.exe` (32-бит) | Полная |
| PE32+ `.exe` (64-бит) | Полная |
| `.dll` | Полная |
| `.sys` (драйвер) | Полная |
| `.msi` | Полная |
| `.cab` | Полная |
| `.cat` (каталог) | Полная |
| `.msix` / `.appx` | Полная (через `/fd sha256`) |
| `.appxbundle` | Полная |
| PowerShell `.ps1` | Нет (используется `Set-AuthenticodeSignature`) |

---

## Ограничения

**Только Windows:** signtool.exe работает исключительно на Windows. Для Linux/macOS аналог — `osslsigncode`.

**Требует Windows SDK:** Не входит в стандартную поставку Windows, нужна отдельная установка SDK или Visual Studio.

**EV-сертификаты требуют физического токена:** В CI/CD нужен либо Cloud HSM (Azure Key Vault + AzureSignTool), либо аппаратный токен, подключённый к машине.

**Нет нативной поддержки PKCS#11:** В отличие от osslsigncode, signtool не работает с PKCS#11 напрямую — только через CNG KSP.

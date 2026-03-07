# notarytool — нотаризация macOS-пакетов

## Что такое нотаризация и notarytool

**Нотаризация** — процесс, при котором Apple проверяет бинарник или пакет на наличие вредоносного кода и выдаёт «тикет» (notarization ticket), подтверждающий проверку. Начиная с macOS 10.15 Catalina нотаризация обязательна для всех приложений, распространяемых вне App Store — без неё Gatekeeper блокирует запуск.

`notarytool` — CLI-утилита для отправки артефактов в Apple Notary Service и получения результата. Появилась в Xcode 13 (2021) как замена устаревшему `altool`. Входит в Xcode Command Line Tools.

**Официальная документация:** [developer.apple.com/documentation/notaryapi](https://developer.apple.com/documentation/notaryapi)

---

## Установка

```bash
# Входит в Xcode Command Line Tools
xcode-select --install

# Проверка версии
xcrun notarytool --version
```

Обычно вызывается через `xcrun`:
```bash
xcrun notarytool submit ...
```

---

## Требования перед нотаризацией

1. **Подпись через codesign** с Hardened Runtime (`--options runtime`) и защищённым штампом времени (`--timestamp`)
2. **Developer ID Application** (или Developer ID Installer для .pkg) сертификат
3. **Apple ID** с платной подпиской Apple Developer Program (99$/год)
4. **App Store Connect API key** (рекомендуется для CI/CD) или Apple ID + пароль приложения

---

## Аутентификация

notarytool поддерживает три способа аутентификации:

### 1. App Store Connect API Key (рекомендуется для CI/CD)

```bash
xcrun notarytool submit myapp.zip \
  --key AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --wait
```

Ключ генерируется в App Store Connect → Users and Access → Integrations → App Store Connect API.

### 2. Apple ID + пароль приложения

```bash
xcrun notarytool submit myapp.zip \
  --apple-id "developer@example.com" \
  --password "xxxx-xxxx-xxxx-xxxx" \
  --team-id "ABCD1234EF" \
  --wait
```

Пароль приложения генерируется на appleid.apple.com → App-Specific Passwords.

### 3. Keychain profile (рекомендуется для сохранения учётных данных)

```bash
# Сохранить credentials в keychain один раз
xcrun notarytool store-credentials "my-notarytool-profile" \
  --key AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Использовать сохранённый профиль
xcrun notarytool submit myapp.zip \
  --keychain-profile "my-notarytool-profile" \
  --wait
```

---

## Команды и аргументы

### submit — отправить на нотаризацию

```
xcrun notarytool submit <file> [auth options] [options]
```

| Аргумент | Описание |
|----------|----------|
| `<file>` | Файл для нотаризации: `.zip`, `.dmg`, `.pkg`, `.app` |
| `--wait` | Ждать завершения нотаризации (блокирует терминал) |
| `--timeout <duration>` | Таймаут ожидания (формат: `1h`, `30m`, `120s`; по умолчанию 1h) |
| `--output-format <format>` | Формат вывода: `text` (по умолчанию), `json`, `plist` |
| `--verbose` | Подробный вывод (не работает с `--output-format`) |

### log — получить лог нотаризации

```
xcrun notarytool log <submission-id> [auth options]
```

Логи содержат детальную информацию об ошибках нотаризации (JSON).

### info — получить статус нотаризации

```
xcrun notarytool info <submission-id> [auth options]
```

### history — список всех отправок

```
xcrun notarytool history [auth options] [--page <n>]
```

### store-credentials — сохранить учётные данные в keychain

```
xcrun notarytool store-credentials <profile-name> [auth options]
```

---

## Поддерживаемые форматы входных файлов

| Формат | Описание |
|--------|----------|
| `.zip` | ZIP-архив с подписанным бинарником |
| `.dmg` | Подписанный образ диска |
| `.pkg` | Подписанный установщик |
| `.app` (прямо) | Приложение (нужно заархивировать в zip для CLI) |

**Важно:** Нотаризируется контейнер, а не само приложение напрямую. Для бинарника без приложения — упаковать в `.zip` или `.dmg`.

---

## Полный рабочий процесс нотаризации

### Нотаризация CLI-утилиты

```bash
# 1. Подписать бинарник
codesign \
  --sign "Developer ID Application: My Company (TEAMID)" \
  --options runtime \
  --timestamp \
  ./mytool

# 2. Упаковать в ZIP для нотаризации
ditto -c -k --keepParent ./mytool mytool.zip

# 3. Отправить на нотаризацию и дождаться результата
xcrun notarytool submit mytool.zip \
  --keychain-profile "my-notarytool-profile" \
  --wait

# 4. Проверить статус (если --wait не использовался)
# xcrun notarytool info <submission-id> --keychain-profile "my-notarytool-profile"

# 5. Скрепить тикет с файлом (staple)
xcrun stapler staple ./mytool

# 6. Верификация
xcrun stapler validate ./mytool
spctl --assess --type execute --verbose ./mytool
```

### Нотаризация .dmg

```bash
# 1. Подписать приложение внутри DMG
codesign --sign "Developer ID Application: ..." --options runtime --timestamp MyApp.app

# 2. Создать DMG
hdiutil create -volname "MyApp" -srcfolder MyApp.app -ov -format ULFO MyApp.dmg

# 3. Подписать DMG
codesign --sign "Developer ID Application: ..." --timestamp MyApp.dmg

# 4. Нотаризировать
xcrun notarytool submit MyApp.dmg \
  --keychain-profile "my-notarytool-profile" \
  --wait

# 5. Скрепить тикет
xcrun stapler staple MyApp.dmg
```

### Нотаризация .pkg

```bash
# 1. Создать .pkg через pkgbuild
pkgbuild --root ./payload \
  --identifier "com.example.mytool" \
  --version "1.0.0" \
  --install-location /usr/local/bin \
  mytool-component.pkg

# 2. Подписать .pkg
productsign \
  --sign "Developer ID Installer: My Company (TEAMID)" \
  mytool-component.pkg \
  mytool-signed.pkg

# 3. Нотаризировать
xcrun notarytool submit mytool-signed.pkg \
  --keychain-profile "my-notarytool-profile" \
  --wait

# 4. Скрепить тикет
xcrun stapler staple mytool-signed.pkg
```

---

## Stapling — скрепление тикета

После успешной нотаризации Apple возвращает тикет. **Stapling** — встраивание тикета непосредственно в файл, чтобы Gatekeeper мог верифицировать его без доступа к интернету.

```bash
# Скрепить тикет
xcrun stapler staple MyApp.dmg

# Верификация
xcrun stapler validate MyApp.dmg
```

Stapling поддерживается для: `.app`, `.dmg`, `.pkg`. Для standalone-бинарников (`.zip`) stapling невозможен — тикет получается онлайн.

---

## Обработка ошибок нотаризации

При ошибке нотаризации нужно смотреть детальный лог:

```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "my-notarytool-profile" | python3 -m json.tool
```

Типичные ошибки:

| Код | Описание | Решение |
|-----|----------|---------|
| `APPLE_ENABLE_HARDENED_RUNTIME` | Hardened Runtime не включён | Добавить `--options runtime` в codesign |
| `UNSIGNED_BINARY` | Вложенные бинарники не подписаны | Подписать все `.dylib`, `.framework`, хелперы |
| `TIMESTAMP_REQUIRED` | Нет защищённого штампа времени | Добавить `--timestamp` в codesign |
| `MISSING_ENTITLEMENT_DEPRECATED` | Устаревший entitlement | Убрать или заменить на актуальный |
| `MAIN_EXECUTABLE_NOT_SIGNED` | Главный исполняемый файл не подписан | Проверить подпись |

---

## Использование в GitHub Actions

```yaml
- name: Notarize macOS binary
  run: |
    # Сохранить API key
    echo "$NOTARY_KEY" | base64 --decode > AuthKey.p8

    # Упаковать для нотаризации
    ditto -c -k --keepParent ./mytool mytool.zip

    # Нотаризировать
    xcrun notarytool submit mytool.zip \
      --key AuthKey.p8 \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER" \
      --wait \
      --output-format json | tee notary-result.json

    # Проверить результат
    STATUS=$(cat notary-result.json | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
    if [ "$STATUS" != "Accepted" ]; then
      SUBMISSION_ID=$(cat notary-result.json | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
      xcrun notarytool log "$SUBMISSION_ID" --key AuthKey.p8 --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
      exit 1
    fi

    # Скрепить тикет (если stapling возможен)
    xcrun stapler staple ./mytool || true
  env:
    NOTARY_KEY: ${{ secrets.NOTARY_API_KEY }}
    NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
    NOTARY_ISSUER: ${{ secrets.NOTARY_ISSUER }}
```

---

## Ограничения

**Только macOS:** notarytool требует macOS и Xcode. Для нотаризации с Linux/Windows используется `rcodesign`.

**Требует Apple Developer Program:** Бесплатный аккаунт Apple ID не даёт доступа к нотаризации.

**Медленно:** Нотаризация занимает от 30 секунд до нескольких минут. Рекомендуется `--wait` с разумным `--timeout`.

**Интернет обязателен:** Apple Notary Service — облачный сервис. Без интернета нотаризировать невозможно.

**App Bundles vs бинарники:** Standalone-бинарники нужно упаковывать в zip перед отправкой. Stapling к ним невозможен — браузер или Gatekeeper проверяет тикет онлайн.

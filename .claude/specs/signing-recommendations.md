# Рекомендации по реализации подписи в Crossler

## Контекст

Crossler собирается для 6 таргетов: Linux/macOS/Windows × x64/arm64. Каждый бинарник должен уметь подписывать артефакты для своей платформы. Цель исследования — определить, как именно реализовать поддержку подписи: какие инструменты использовать, как описать их в конфиге, что вынести в общий слой.

---

## 1. Архитектурная модель: два вида подписи

Все задачи подписи делятся на два полностью независимых вида:

### Authenticode — подпись Windows-артефактов

Authenticode — цифровая подпись Microsoft для `.exe`, `.dll`, `.msi`. Без неё Windows SmartScreen предупреждает пользователей при запуске.

**Бэкенды:**
- `osslsigncode` — на Linux и macOS (кросс-платформенный, open source)
- `signtool.exe` — на Windows (нативный, из Windows SDK)

**Что подписываем:**
- Бинарники `.exe` перед упаковкой
- MSI-файлы после сборки

### Apple Code Signing — подпись macOS-артефактов

Apple Code Signing + нотаризация — обязательны для распространения macOS-приложений. Без нотаризации Gatekeeper блокирует запуск на macOS 10.15+.

**Бэкенды:**
- `rcodesign` — на Linux и Windows (кросс-платформенный, open source)
- `codesign` + `notarytool` — на macOS (нативные Apple-инструменты)

**Что подписываем:**
- Mach-O бинарники перед упаковкой
- `.dmg`, `.pkg` после сборки

---

## 2. Рекомендуемое отображение хостов на инструменты

| Хост | Windows Authenticode | macOS Apple Signing |
|------|---------------------|---------------------|
| Linux | `osslsigncode` | `rcodesign` |
| macOS | `osslsigncode` | `codesign` + `notarytool` |
| Windows | `signtool.exe` | `rcodesign` |

Это отображение полностью совпадает с тем, что уже задокументировано в CLAUDE.md. Важно: **не нужно давать пользователю выбор бэкенда** — Crossler сам определяет нужный инструмент по хосту.

---

## 3. Конфигурация подписи в Crossler

### Какие параметры нужны обязательно

**Для Authenticode (Windows):**
```
windows_sign:
  certificate: codesign.pfx       # PFX-файл или переменная окружения
  password: ...                   # пароль к PFX или переменная окружения
  timestamp_url: ...              # URL TSA-сервера (RFC 3161)
  description: "My Application"  # описание для диалога UAC (опционально)
  url: "https://example.com"     # URL издателя (опционально)
```

**Для Apple Code Signing:**
```
macos_sign:
  certificate: codesign.p12       # P12-файл или переменная окружения
  password: ...                   # пароль к P12 или переменная окружения
  identity: "Developer ID Application: ..."  # для нативного codesign (macOS-хост)
  notarize: true                  # отправлять ли на нотаризацию
  notary_api_key: api-key.json    # JSON с App Store Connect API Key
  entitlements: entitlements.plist  # (опционально, для GUI)
```

### Секреты и переменные окружения

Пароли и ключи **никогда не должны быть захардкожены в конфиг-файле** — только через переменные окружения или файлы, путь к которым задаётся в конфиге. Рекомендуемый подход:

```yaml
windows_sign:
  certificate: "${CROSSLER_WIN_CERT}"   # путь к PFX или содержимое в base64
  password: "${CROSSLER_WIN_CERT_PASS}"
  timestamp_url: "http://timestamp.digicert.com"

macos_sign:
  certificate: "${CROSSLER_MAC_CERT}"   # путь к P12
  password: "${CROSSLER_MAC_CERT_PASS}"
  notarize: true
  notary_api_key: "${CROSSLER_NOTARY_KEY}"  # путь к JSON
```

### Когда подписывать: до или после упаковки?

Это критически важный вопрос, и ответ разный для разных форматов:

| Артефакт | Когда подписывать |
|----------|-----------------|
| `.exe` бинарник | **До** упаковки в MSI или tar.gz |
| `.msi` | **После** создания MSI (osslsigncode/signtool) |
| Mach-O бинарник | **До** упаковки в .pkg, .dmg или tar.gz |
| `.pkg` | **После** создания .pkg (productsign / rcodesign) |
| `.dmg` | **После** создания .dmg, **до** нотаризации |
| `tar.gz` с macOS-бинарником | Бинарник внутри подписывается **до** упаковки |

Crossler должен реализовать правильную последовательность шагов автоматически.

---

## 4. Обработка секретов: рекомендации

### PFX/P12 из переменной окружения

В CI/CD сертификаты часто хранятся как base64 в секретах. Crossler должен уметь принимать либо путь к файлу, либо base64-закодированное содержимое:

```yaml
# Вариант 1: путь к файлу
certificate: "/run/secrets/codesign.pfx"

# Вариант 2: base64-содержимое (Crossler декодирует во временный файл)
certificate: "base64:${CODE_SIGN_PFX_BASE64}"
```

### App Store Connect API Key для rcodesign

rcodesign принимает JSON-файл с API ключом. Crossler должен поддерживать:
- Путь к JSON-файлу
- Либо отдельные поля (key_id, issuer_id, private_key) в конфиге с подстановкой из env

---

## 5. Функционал, который нужен в Crossler обязательно

**Authenticode:**
- Подпись бинарников PE (`.exe`) перед упаковкой
- Подпись MSI после сборки
- SHA-256 хэш (без устаревшего SHA-1)
- Штамп времени RFC 3161 с настраиваемым URL TSA
- Описание приложения (`description`, `url`)

**Apple Code Signing:**
- Подпись Mach-O-бинарников перед упаковкой
- Hardened Runtime (обязателен для нотаризации)
- Защищённый штамп времени Apple TSA
- Нотаризация через App Store Connect API Key
- Stapling для `.dmg` и `.pkg`

---

## 6. Функционал, который полезен, но не срочен

**Authenticode:**
- Двойная подпись (SHA-1 + SHA-256) — нужна только для поддержки Windows XP/Vista, которая практически не актуальна
- Подпись через PKCS#11 / HSM — нужна для EV-сертификатов в строгих окружениях

**Apple Code Signing:**
- Entitlements — нужны для GUI-приложений, для CLI-утилит как правило не требуются
- Подпись `.app` bundle (для GUI-приложений, не CLI)

---

## 7. Функционал, который НЕ нужен в Crossler

**Authenticode:**
- Поддержка MSIX / Appx — это формат Microsoft Store, не наша целевая аудитория
- Подпись CAT-файлов — не нужно для обычных приложений
- Подпись PowerShell-скриптов — не наш кейс
- Поддержка устаревшего SHA-1 Authenticode (только SHA-256)
- Устаревший TSA формат Authenticode (только RFC 3161)

**Apple Code Signing:**
- Управление Keychain macOS — слишком платформенно-специфично, работаем с файлами
- Подпись XCFramework и специфических Apple-форматов — вне нашего scope
- Произвольные requirements (`--requirements`) — для продвинутых сценариев, не наш случай
- Provisioning profiles — только для iOS/embedded, не macOS

---

## 8. Архитектурные решения

### Решение 1: Crossler сам управляет порядком подписи

Пользователь не должен думать о том, когда именно подписывать — до или после упаковки. Crossler знает правильную последовательность и выполняет её автоматически:

```
1. Собрать бинарник
2. Подписать бинарник (Authenticode или Apple)
3. Упаковать (tar.gz, .msi, .pkg, .dmg)
4. Подписать пакет (если применимо)
5. Нотаризировать (для macOS)
6. Staple (для .dmg, .pkg)
```

### Решение 2: Единый блок конфига для подписи

Подпись описывается один раз в конфиге с возможностью переопределения. Не нужно отдельно описывать «подпись бинарника» и «подпись MSI» — Crossler применяет правильный инструмент к правильному файлу автоматически.

### Решение 3: Нативные инструменты на macOS, cross-platform на Linux/Windows

На macOS — всегда `codesign` + `notarytool` (более надёжные, лучше интегрированы с системой).
На Linux/Windows — всегда `rcodesign` (нет альтернатив).
На macOS для Authenticode — `osslsigncode` (удобнее, чем тащить Windows SDK).

### Решение 4: Подпись опциональна

Подпись не должна быть обязательным шагом. Если параметры подписи не заданы — Crossler просто собирает пакет без подписи. Это удобно для тестовых сборок и сред без сертификатов.

### Решение 5: Явная ошибка при отсутствии сертификата в production

Если подпись явно включена в конфиге (например, `sign: true` или секция `windows_sign`/`macos_sign` присутствует), но сертификат не найден — Crossler должен завершаться с понятной ошибкой, а не собирать неподписанный пакет молча.

---

## 9. Итоговая схема

```
Конфиг Crossler
├── windows_sign         # Параметры Authenticode
│   ├── certificate      # PFX путь или base64
│   ├── password         # пароль к PFX
│   ├── timestamp_url    # TSA сервер
│   ├── description      # (опционально)
│   └── url              # (опционально)
│
└── macos_sign           # Параметры Apple Code Signing
    ├── certificate      # P12 путь или base64
    ├── password         # пароль к P12
    ├── identity         # "Developer ID Application: ..." (для нативного codesign)
    ├── notarize         # bool: нотаризировать ли
    ├── notary_api_key   # путь к JSON или поля inline
    └── entitlements     # (опционально, для GUI-приложений)

Crossler автоматически выбирает инструмент по хосту:
├── Linux  → osslsigncode (Windows) + rcodesign (macOS)
├── macOS  → osslsigncode (Windows) + codesign + notarytool (macOS)
└── Windows→ signtool.exe (Windows) + rcodesign (macOS)
```

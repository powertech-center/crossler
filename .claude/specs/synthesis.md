# Crossler — синтез ключевых решений

> **Философия этого документа**: KISS + Бритва Оккама + YAGNI.
> Только утверждённые решения. Никакой спекуляции. Все детали идут от пользователя.

---

## Структура конфига

- **Плоская модель**: параметры первого уровня — скалярные значения без вложенности.
- **Параметры-словари** (файловые группы `bin`, `share`, `etc` и др.) записываются через многострочный inline (TOML 1.1):
  ```toml
  bin = {
    "myapp" = "bin/myapp",
  }
  share = {
    "icons/hicolor/48x48/apps/myapp.png" = "share/icons/hicolor/48x48/apps/myapp.png",
  }
  ```
- **Секции `[...]`** зарезервированы исключительно для таргетирования (переопределения под конкретный таргет). Способ парсинга (стандартный TOML или кастомный с предварительной обработкой секций) и точный формат таргетирования — открытые вопросы.
- Часть параметров обязательна, часть необязательна (отсутствие = значение по умолчанию).

## Правила пополнения таблиц параметров

Каждый новый параметр добавляется только после явного согласования с пользователем. При добавлении обязательно заполнить все колонки:

- **Параметр** — имя в TOML-конфиге, в `code`-форматировании.
- **Тип** — `string`, `string/array`, `map` и т.д.
- **Дефолт** — точное значение или описание логики вывода. Если параметр обязателен — писать **required**.
- **Комментарий** — одна фраза: что это и зачем.
- **Маппинг в бэкенды** — краткие пометки вида `tool: field`. Если параметр влияет только на логику Crossler (не передаётся в бэкенд) — писать `crossler only`.

## Проект

Параметры, описывающие проект: название, версия, идентификатор.

| Параметр | Тип | Дефолт | Комментарий | Маппинг в бэкенды |
|----------|-----|--------|-------------|-------------------|
| `name` | string | имя текущей директории (Title Case), иначе `"Unknown"` | Коммерческое название продукта | nfpm: `name`, wixl: `Product/@Name`, pkgbuild: `--identifier` (частично) |
| `slug` | string | `name` → lowercase + спецсимволы → `-` | Базовое имя для файлов пакетов; валидируется при ручном вводе | nfpm: имя пакета в метаданных, имя выходного файла |
| `version` | string | `"0.0.0"` | SemVer-строка; маппится на нужный формат при генерации | nfpm: `version`, wixl: `Product/@Version`, pkgbuild: `--version` |
| `description` | string | `"{name} installation package v{version}"` | Краткое описание пакета (одна строка) | nfpm: `description`, wixl: `Package/@Description` → `ARPCOMMENTS`, nfpm RPM: `Summary` + `%description` |
| `company` | string | `""` | Название компании-разработчика; обязательно для `.msi` (ошибка если пусто) | nfpm RPM: `Vendor`, wixl: `Product/@Manufacturer` |
| `maintainer` | string | `""` | Контакт для обратной связи, формат `"Name <email>"`; обязательно для `.deb`, `.apk` (ошибка если пусто) | nfpm: `maintainer` |
| `license` | string | `"Proprietary"` | Лицензия ПО. Значение интерпретируется так: (1) если это путь к существующему файлу относительно `input` — используется как файл лицензии напрямую; (2) если в `input` есть файл `LICENSE`, `LICENSE.txt` или `LICENSE.md` — используется он; (3) иначе — Crossler генерирует файл лицензии по строковому значению (логика генерации TBD). Итоговый файл лицензии кладётся в нужное место каждым бэкендом | nfpm: `license`, nfpm deb: `/usr/share/doc/{slug}/copyright`, nfpm rpm: `%license` |
| `homepage` | string | `""` | URL сайта проекта | nfpm: `homepage` |

## Сборка

Параметры, управляющие процессом сборки: откуда брать файлы, куда класть пакеты, для каких платформ и в каких форматах.

| Параметр | Тип | Дефолт | Комментарий | Маппинг в бэкенды |
|----------|-----|--------|-------------|-------------------|
| `os` | string/array | хостовая ОС | Значения: `linux`, `macos`, `windows` | crossler only: определяет набор запускаемых бэкендов |
| `arch` | string/array | хостовая архитектура | Значения: `x64`, `arm64` | nfpm: маппинг архитектуры по формату, wixl/wix: Platform |
| `formats` | string/array | `"tar.gz"` | Форматы выходных пакетов | crossler only: определяет набор запускаемых бэкендов |
| `input` | string | `{current-dir}` | Базовая директория для поиска файлов | все бэкенды: base path для разрешения относительных путей в файловых группах |
| `output` | string | `"{current-dir}/{config-name}/{slug}-{version}-{os}-{arch}.{format}"` | Полный путь выходного файла пакета, включая имя | все бэкенды: выходной файл |
| `temp` | string | `"{config-dir}/{config-name}.temp"` | Рабочая директория для временных файлов (конфиги бэкендов, сгенерированные файлы). Поддерживает `{tmp}` для системной temp-директории. Пересоздаётся при каждом запуске (старое содержимое удаляется). Удаляется после успешного завершения; при ошибке сохраняется для диагностики. | crossler only |

## Файлы

Файлы описываются через **файловые группы** — именованные параметры-словари, соответствующие FHS-категориям. Crossler транслирует их в целевые пути в зависимости от формата пакета.

### Формат записи

Каждая группа — словарь вида `"результат" = "исходник"`, где:
- **результат** — относительный путь внутри группы (файл или директория)
- **исходник** — путь относительно `input` (файл или директория)

```toml
bin = {
  "myapp" = "bin/myapp",
}
etc = {
  "config.yaml" = "etc/config.yaml",
}
share = {
  "templates/template.xls" = "share/templates/template.xls",
  "icons/hicolor/48x48/apps/myapp.png" = "share/icons/hicolor/48x48/apps/myapp.png",
}
```

**Короткая форма**: если результат и исходник совпадают (с учётом имени группы как префикса), можно писать `"path/to/file" = true`:
```toml
share = {
  "icons/hicolor/48x48/apps/myapp.png" = true,
}
```

**Сверхкороткая форма**: если внутри `input` уже есть директория с именем группы и нужно включить её целиком, можно писать `bin = true`:
```toml
bin = true
lib = true
share = true
```

### Файловые группы и маппинг по форматам

| Группа | `.deb` / `.rpm` / `.apk` / `.pkg` (macOS) | `.msi` | `tar.gz` / `.dmg` |
|--------|------------------------------------------|--------|-------------------|
| `bin` | `/usr/bin/` | `INSTALLDIR\bin\` | `bin/` |
| `sbin` | `/usr/sbin/` | `INSTALLDIR\sbin\` | `sbin/` |
| `lib` | `/usr/lib/` | `INSTALLDIR\lib\` | `lib/` |
| `libexec` | `/usr/libexec/{slug}/` | `INSTALLDIR\libexec\` | `libexec/` |
| `include` | `/usr/include/{slug}/` | `INSTALLDIR\include\` | `include/` |
| `share` | см. правило ниже | `INSTALLDIR\share\` | `share/` |
| `etc` | `/etc/{slug}/` | `INSTALLDIR\etc\` | `etc/` |
| `var` | `/var/lib/{slug}/` | `INSTALLDIR\var\` | `var/` |

### Поддерживаемые группы

`bin`, `sbin`, `lib`, `libexec`, `include`, `share`, `etc`, `var`.

### Правило маппинга для группы `share` (Linux/macOS пакеты)

Путь внутри группы `share` анализируется по префиксу:

- Если префикс совпадает с одним из стандартизированных подпутей → файл кладётся в `/usr/share/{подпуть}` напрямую.
- Иначе (fallback) → файл кладётся в `/usr/share/{slug}/{подпуть}`.

**Стандартизированные префиксы:**

| Префикс | Целевой путь | Назначение |
|---------|-------------|------------|
| `applications/` | `/usr/share/applications/` | `.desktop` файлы (ярлык в меню DE) |
| `icons/` | `/usr/share/icons/` | иконки приложения (hicolor и др.) |
| `pixmaps/` | `/usr/share/pixmaps/` | legacy иконки |
| `man/` | `/usr/share/man/` | man-страницы |
| `locale/` | `/usr/share/locale/` | переводы (gettext) |
| `bash-completion/` | `/usr/share/bash-completion/` | bash autocompletion |
| `zsh/` | `/usr/share/zsh/` | zsh autocompletion |
| `dbus-1/` | `/usr/share/dbus-1/` | D-Bus сервисы |

**Примеры:**

```
share/"applications/myapp.desktop"         → /usr/share/applications/myapp.desktop
share/"icons/hicolor/48x48/apps/myapp.png" → /usr/share/icons/hicolor/48x48/apps/myapp.png
share/"man/man1/myapp.1"                   → /usr/share/man/man1/myapp.1
share/"templates/template.xls"             → /usr/share/myapp/templates/template.xls  (fallback)
share/"sounds/notify.wav"                  → /usr/share/myapp/sounds/notify.wav        (fallback)
```

## Подписывание

Параметры подписи — обычные параметры конфига, задаются в таргет-секциях (`[windows]`, `[macos]`). Crossler автоматически выбирает инструмент по хосту: на Linux/macOS для Authenticode — `osslsigncode`, на Windows — `signtool`; для Apple — `rcodesign` на Linux/Windows, `codesign`+`notarytool` на macOS. Порядок подписи управляется Crossler автоматически: бинарники подписываются до упаковки, пакеты (`.msi`, `.pkg`, `.dmg`) — после.

Подпись опциональна: если параметры не заданы — пакет собирается без подписи.

### Общие параметры (Windows и macOS)

| Параметр | Тип | Дефолт | Комментарий | Маппинг в бэкенды |
|----------|-----|--------|-------------|-------------------|
| `certificate` | string | — | Путь к файлу сертификата (PFX для Windows, P12 для macOS) | osslsigncode: `-pkcs12`, signtool: `/f`, rcodesign/codesign: `--p12-file` |
| `password` | string | `""` | Пароль к файлу сертификата | osslsigncode: `-pass`, signtool: `/p`, rcodesign: `--p12-password`, codesign: через keychain |

### Параметры Windows (Authenticode)

| Параметр | Тип | Дефолт | Комментарий | Маппинг в бэкенды |
|----------|-----|--------|-------------|-------------------|
| `timeserver` | string | `"http://timestamp.digicert.com"` | TSA-сервер RFC 3161 для штампа времени; без штампа подпись теряет силу после истечения сертификата | osslsigncode: `-ts`, signtool: `/tr` |

`description` и `url` берутся автоматически из параметров проекта: `description` — из `name` и `company`, `url` — из `homepage`.

### Параметры macOS (Apple Code Signing)

| Параметр | Тип | Дефолт | Комментарий | Маппинг в бэкенды |
|----------|-----|--------|-------------|-------------------|
| `notary` | string или object | — | Нотаризация Apple. Строка — путь к JSON-файлу с App Store Connect API Key. Объект — поля `id` (key ID), `issuer` (issuer UUID), `key` (путь к `.p8`). Наличие параметра = нотаризировать. | rcodesign: `--api-key-file` / отдельные флаги, notarytool: `--key-id`, `--issuer`, `--key` |
| `entitlements` | string | — | Путь к `.plist` файлу с entitlements (опционально, для GUI-приложений) | codesign: `--entitlements`, rcodesign: `--entitlements-xml-path` |

Hardened Runtime включается автоматически при подписи macOS (обязателен для нотаризации).

### CLI-примеры для подписи

```
crossler packages.toml windows.certificate=codesign.pfx windows.password=$WIN_PASS
crossler packages.toml macos.notary=api-key.json
crossler packages.toml macos.notary.id=$KEY_ID macos.notary.issuer=$ISSUER macos.notary.key=private.p8
```

## Интеграция

### PATH

Бинарники из файловой группы `bin` должны быть глобально доступны из командной строки на всех платформах. Crossler обеспечивает это автоматически, без явного параметра в конфиге:

- **Linux-пакеты** (deb, rpm, apk, pkg.tar.zst): `bin` маппится в `/usr/bin/` — уже в PATH.
- **Homebrew** (.rb): Homebrew сам управляет симлинками в `/opt/homebrew/bin/` или `/usr/local/bin/` — уже в PATH.
- **macOS .pkg**: бинарники ставятся в `/usr/local/bin/` — уже в PATH.
- **Windows .msi**: директория `INSTALLDIR\bin\` автоматически добавляется в системный PATH (`<Environment Part="last" Permanent="no">`). При деинсталляции запись удаляется.
- **DMG**: не актуально (формат доставки GUI-приложений, PATH не затрагивается).
- **tar.gz**: архив для ручной установки, PATH не управляется.

Произвольные переменные окружения (`env`) в спецификацию не включаются — для целевой аудитории (CLI-утилиты и демоны) не востребованы. Демонам переменные задаются в unit-файле (systemd, launchd), а не глобально.

### Деинсталляция macOS .pkg

macOS .pkg не имеет встроенного механизма деинсталляции (нет preremove/postremove). Crossler должен генерировать uninstall-скрипт и включать его в пакет. *(Детали реализации — отдельный вопрос.)*

## Переменные шаблонизатора

Используются в строковых параметрах (`output` и др.) в виде `{name}`.

| Переменная | Значение |
|------------|----------|
| `{tmp}` | системная временная директория (`/tmp` на Linux/macOS, `%TEMP%` на Windows); доступна только в параметре `temp` |
| `{current-dir}` | текущая рабочая директория (откуда запущен crossler) |
| `{config-dir}` | директория, в которой находится файл конфигурации |
| `{config-name}` | базовое имя файла конфигурации без расширения (например, `packages`) |
| `{slug}` | вычисленный slug проекта |
| `{version}` | версия проекта |
| `{os}` | целевая ОС текущего прогона (`linux`, `macos`, `windows`) |
| `{arch}` | целевая архитектура текущего прогона (`x64`, `arm64`) |
| `{format}` | целевой формат текущего прогона (`tar.gz`, `deb`, `msi` и т.д.) |

## CLI

Вызов:

```
crossler <путь-к-конфигу> [параметр=значение ...]
```

Примеры:

```
crossler ./packages.toml
crossler packages.toml version=1.2.3
```

- Первый аргумент — путь к TOML-файлу конфигурации.
- Последующие аргументы вида `ключ=значение` переопределяют параметры конфига.
- Аргументы, начинающиеся с `--` (например, `--version`, `--help`) — служебные флаги утилиты, не параметры конфига.

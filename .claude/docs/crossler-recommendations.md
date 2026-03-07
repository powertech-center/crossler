# Рекомендации по функционалу Crossler

Анализ на основе изучения wixl, nfpm, pkgbuild и hdiutil. Цель — определить оптимальный объём функционала для первой версии и далее.

---

## Категория 1: Гарантированный базовый функционал

Без этого Crossler бесполезен. Должно быть в v1.0.

### 1.1 Метаданные пакета

Минимальный общий знаменатель всех форматов:

```yaml
# Предполагаемый конфиг Crossler
name: crossler
version: 1.0.0
description: Cross-platform package creation tool
homepage: https://github.com/powertech-center/crossler
license: MIT
maintainer: "PowerTech Center <dev@powertech.center>"
vendor: PowerTech Center
```

**Обоснование:**
- `name`, `version` — обязательны во всех форматах без исключения
- `description` — обязательно для deb/rpm; важно для ARP в MSI; нет в .pkg/.dmg, но стоит хранить
- `homepage`, `license`, `maintainer`, `vendor` — нужны для deb/rpm; в MSI частично (Manufacturer); стоит иметь единое место

**Маппинг на бэкенды:**

| Поле Crossler | MSI | deb/rpm/apk | pkg | dmg |
|---------------|-----|-------------|-----|-----|
| `name` | `Product/@Name` | `name` | `--identifier` суффикс | `-volname` |
| `version` | `Product/@Version` | `version` | `--version` | имя тома |
| `description` | `Package/@Description` | `description` | distribution.xml | — |
| `maintainer` | — | `maintainer` | — | — |
| `homepage` | — | `homepage` | — | — |
| `license` | — | `license` | distribution.xml | — |
| `vendor` | `Product/@Manufacturer` | `vendor` | — | — |

### 1.2 Установка файлов

Основная функция любого упаковщика:

```yaml
files:
  - src: dist/crossler           # источник (относительный путь)
    dst: /usr/bin/crossler       # назначение на целевой системе
    mode: 0755                   # права доступа

  - src: config/default.yaml
    dst: /etc/crossler/config.yaml
    mode: 0644
    type: config                 # не перезаписывать при обновлении

  - src: /usr/bin/crossler
    dst: /usr/local/bin/crossler
    type: symlink                # символическая ссылка

  - dst: /var/lib/crossler
    type: dir                    # создать пустую директорию
    mode: 0750
    owner: crossler
    group: crossler
```

**Почему важны типы файлов:**
- `config` / `config|noreplace` — нативная концепция deb/rpm/apk, пользователи ожидают что их правки в `/etc/` сохраняются
- `symlink` — нужен для создания альтернативных путей
- `dir` — для директорий с нестандартными правами

**Маппинг на бэкенды:**

| Тип Crossler | wixl | nfpm | pkgbuild | hdiutil |
|--------------|------|------|----------|---------|
| `file` | `<File>` в Component | `type: file` | файл в payload | файл в staging |
| `config` | `<File>` (нет атомарной защиты) | `type: config\|noreplace` | файл в payload | — |
| `symlink` | — (не нужно в MSI) | `type: symlink` | symlink в payload | symlink в staging |
| `dir` | `<CreateFolder>` | `type: dir` | mkdir в payload | mkdir в staging |

### 1.3 Скрипты жизненного цикла

Четыре хука для всех платформ где это применимо:

```yaml
scripts:
  preinstall: scripts/preinstall.sh
  postinstall: scripts/postinstall.sh
  preremove: scripts/preremove.sh
  postremove: scripts/postremove.sh
```

**Где применяется:**
- `preinstall` / `postinstall` — wixl (через CustomAction), nfpm, pkgbuild
- `preremove` / `postremove` — nfpm только (deb/rpm/apk)
- hdiutil — не поддерживает никакие скрипты

**Важное ограничение wixl:** CustomAction в wixl ограничена, поддерживаются EXE-based действия. Скрипты установки в MSI — нестандартная практика для консольных утилит. Для Crossler v1 можно сделать preinstall/postinstall только для Linux/macOS форматов.

### 1.4 Многоуровневое наслоение (override)

Ключевая архитектурная фича — единый конфиг с переопределениями:

```yaml
# Общие настройки
name: crossler
version: 1.0.0
depends:
  - bash

# Переопределения для платформ
platforms:
  linux:
    overrides:
      deb:
        depends:
          - bash (>= 4.0)
      rpm:
        release: 1
        depends:
          - bash >= 4.0
      apk:
        depends:
          - bash>=4.0
  windows:
    # MSI-специфичные переопределения
  macos:
    identifier: com.powertech.crossler
    # pkg/dmg-специфичные переопределения
```

**Уровни наслоения (от общего к частному):**
1. Базовые настройки (общие для всех платформ)
2. Переопределения по платформе (linux/windows/macos)
3. Переопределения по формату (deb/rpm/apk/msi/pkg/dmg)
4. Переопределения по архитектуре (amd64/arm64) — при необходимости

### 1.5 Поддержка всех 6 таргетов

Crossler должен генерировать пакеты для всех заявленных форматов:

| Формат | Кто делает | Откуда запускается |
|--------|------------|-------------------|
| `.msi` | wixl | Linux-бинарник Crossler |
| `.deb` | nfpm | Linux-бинарник Crossler |
| `.rpm` | nfpm | Linux-бинарник Crossler |
| `.apk` | nfpm | Linux-бинарник Crossler |
| `.tar.gz` | tar (встроено) | Все бинарники Crossler |
| `.pkg` | pkgbuild | macOS-бинарник Crossler |
| `.dmg` | hdiutil | macOS-бинарник Crossler |
| `.rb` (Homebrew) | генерация формулы | Linux/macOS бинарники |

### 1.6 Homebrew formula (.rb)

Homebrew — стандарт установки CLI-инструментов на macOS (и Linux). Formula — Ruby-файл, описывающий как установить приложение:

```ruby
# crossler.rb (генерируется Crossler)
class Crossler < Formula
  desc "Cross-platform package creation tool"
  homepage "https://github.com/powertech-center/crossler"
  url "https://github.com/powertech-center/crossler/releases/download/v1.0.0/crossler-darwin-arm64.tar.gz"
  sha256 "HASH_HERE"
  license "MIT"
  version "1.0.0"

  def install
    bin.install "crossler"
  end

  test do
    system "#{bin}/crossler", "--version"
  end
end
```

**Важно:** formula — это не формат пакета, а скрипт для Homebrew. Crossler должен генерировать этот файл на основе своего конфига и SHA256 хешей собранных архивов.

---

## Категория 2: Полезный, но не срочный функционал

Имеет смысл добавить в v1.x или v2.0. Полезно для части пользователей.

### 2.1 Зависимости пакетов (Linux)

Зависимости критичны для полноценного Linux-пакета. Без них пакет не установит свои prerequisites автоматически.

```yaml
depends:
  - bash
  - curl

recommends:
  - jq

suggests:
  - docker

conflicts:
  - old-crossler

replaces:
  - old-crossler-legacy

provides:
  - crossler-ng
```

**Почему не в базовом:** нет зависимостей в Windows MSI и macOS pkg/dmg. Для первой версии можно принять что консольные Go-утилиты не имеют runtime-зависимостей.

**Почему полезно:** стандарт для Linux-пакетов, пользователи ожидают. `recommends` и `suggests` нужны для зависимостей по умолчанию.

### 2.2 Записи в реестр Windows (MSI)

Для регистрации приложения в системе Windows:

```yaml
platforms:
  windows:
    registry:
      - root: HKLM
        key: Software\PowerTech\Crossler
        values:
          - name: InstallPath
            type: string
            value: "[INSTALLFOLDER]"
          - name: Version
            type: string
            value: "1.0.0"
```

**Почему полезно:** позволяет другим программам находить Crossler, добавить в PATH через реестр, интеграция с Windows-инструментами.

**Почему не срочно:** консольным утилитам реестр нужен редко. PATH можно добавить в MSI по-другому.

### 2.3 Ярлыки Windows (MSI Shortcuts)

```yaml
platforms:
  windows:
    shortcuts:
      - location: StartMenu
        name: Crossler
        target: "[INSTALLFOLDER]crossler.exe"
        description: "Cross-platform package tool"
      - location: Desktop
        name: Crossler
        target: "[INSTALLFOLDER]crossler.exe"
```

**Почему полезно:** для GUI-приложений обязательно; для CLI — иногда полезно иметь ярлык в меню Пуск.

**Почему не срочно:** 80% аудитории — CLI. Ярлыки для CLI нестандартны.

### 2.4 Systemd юниты (Linux)

```yaml
platforms:
  linux:
    systemd:
      - src: systemd/crossler.service
        enabled: true    # автоматически включить при установке
```

Это специальный тип файла, требующий `postinstall` с `systemctl daemon-reload`.

**Почему полезно:** для серверных утилит и демонов — стандарт.

**Почему не срочно:** Crossler пока ориентирован на CLI-инструменты сборки, не на серверные демоны.

### 2.5 Условия установки (MSI)

```yaml
platforms:
  windows:
    conditions:
      - check: os_version
        minimum: "6.1"   # Windows 7+
        message: "This application requires Windows 7 or later."
      - check: architecture
        value: x64
        message: "This installer requires a 64-bit Windows."
```

**Почему полезно:** предотвращает установку на несовместимых системах.

**Почему не срочно:** современные Windows всегда достаточно новые; Go-бинарники работают везде.

### 2.6 Payload-free пакеты (macOS)

Пакет только со скриптами, без файлов — для настройки системы:

```yaml
platforms:
  macos:
    payload_free: true  # только скрипты, без файлов
```

**Почему полезно:** создание symlinks, настройка PATH, регистрация launchd-демонов.

**Почему не срочно:** нестандартный сценарий.

### 2.7 Файловые ассоциации (MSI)

```yaml
platforms:
  windows:
    file_associations:
      - extension: .crossler
        prog_id: Crossler.Project
        description: Crossler Project File
        target: "[INSTALLFOLDER]crossler.exe"
        argument: '"%1"'
```

**Почему полезно:** если у утилиты есть файл конфига со своим расширением.

**Почему не срочно:** редкий сценарий для консольных утилит.

---

## Категория 3: Функционал, который не нужен в Crossler

Добавлять не стоит ни в каком горизонте.

### 3.1 MSI UI диалоги

**Почему не нужно:**
- wixl (основной инструмент для MSI) не поддерживает WixUI
- 80% целевых приложений — консольные утилиты; им не нужны wizard-диалоги
- Silent install (`msiexec /quiet`) — стандарт для CI/CD деплоя
- Создание UI сложно и увеличивает .wxs в разы
- Пользователи консольных утилит не ожидают UI инсталлятора

### 3.2 Burn Bootstrapper (MSI Bundle)

**Почему не нужно:**
- Burn — для сложных инсталляторов с prerequisites (.NET, VC++ Runtime)
- wixl не поддерживает Burn
- Go-бинарники не имеют runtime-зависимостей — prerequisites не нужны
- Добавляет огромную сложность без пользы

### 3.3 Merge Modules (.msm)

**Почему не нужно:**
- .msm — механизм переиспользования компонентов между несколькими MSI-пакетами
- wixl не поддерживает .msm
- Crossler — инструмент для упаковки конкретных приложений, не для разработки переиспользуемых компонентов

### 3.4 WiX Extensions (IIS, SQL Server, .NET)

**Почему не нужно:**
- Расширения WiX для специфичных серверных сценариев
- wixl их не поддерживает
- Целевая аудитория Crossler — обычные приложения, не корпоративные серверные продукты

### 3.5 DMG-кастомизация (фон, позиции иконок)

**Почему не нужно:**
- Требует запущенный Finder (невозможно в headless CI/CD)
- Для реализации нужен AppleScript или dmgbuild — сложная интеграция
- Это скорее дизайнерская работа, не задача упаковщика
- Пользователи могут самостоятельно использовать create-dmg или dmgbuild для кастомизации

**Что Crossler должен делать:** создать функциональный DMG (бинарник + symlink на /Applications). Кастомизацию оставить на откуп пользователю.

### 3.6 Component Property List (pkgbuild)

**Почему не нужно:**
- BundleIsRelocatable, BundleOverwriteAction и т.д. — детали реализации pkgbuild
- Crossler работает на уровне выше — он описывает что установить, pkgbuild решает как
- Для консольных утилит (бинарники, не .app бандлы) component plist не применим
- Пользователи Crossler не должны знать об этой концепции

### 3.7 Локализация установщиков (WiX .wxl)

**Почему не нужно:**
- .wxl — файлы локализации для WiX UI (строки диалогов)
- Раз UI диалоги не нужны, локализация тоже не нужна
- Crossler упаковывает приложения, строки локализации — задача самого приложения

### 3.8 Шифрование DMG-образов

**Почему не нужно:**
- Шифрованные DMG нужны для безопасного хранения чувствительных данных
- Дистрибутивные пакеты не шифруются — скачивает любой
- Это специфический сценарий (корпоративные архивы, backup)
- Усложняет workflow (требует пароль, не автоматизируется просто)

### 3.9 Ghost-файлы RPM

**Почему не нужно:**
- Ghost — RPM-специфичная концепция для логов и состояния
- Редко нужна в упакованных приложениях
- Усложняет конфиг ради edge-case

### 3.10 archlinux и ipk форматы (в v1)

**Почему не нужно в v1:**
- Arch Linux пользователи предпочитают AUR (git-репозиторий), не бинарные пакеты
- ipk — для встроенных систем OpenWrt, очень нишевой рынок
- Достаточно deb + rpm + apk для покрытия 95%+ Linux-дистрибутивов

---

## Рекомендуемая архитектура конфига Crossler

На основе анализа всех инструментов предлагается следующая структура:

```yaml
# crossler.yaml — предлагаемая схема

# === МЕТАДАННЫЕ ===
name: crossler
version: 1.0.0
description: Cross-platform package creation tool
maintainer: "PowerTech Center <dev@powertech.center>"
homepage: https://github.com/powertech-center/crossler
license: MIT
vendor: PowerTech Center

# === ФАЙЛЫ (общие для всех платформ) ===
files:
  - src: dist/${PLATFORM}_${ARCH}/crossler${EXE}
    dst: /usr/bin/crossler           # Linux/macOS путь
    win_dst: crossler.exe            # Windows путь относительно INSTALLFOLDER
    mode: 0755
    type: file

  - src: docs/README.md
    dst: /usr/share/doc/crossler/README.md
    win_dst: README.md
    type: doc

# === СКРИПТЫ (общие) ===
scripts:
  postinstall: scripts/postinstall.sh

# === ПЛАТФОРМЕННЫЕ ПЕРЕОПРЕДЕЛЕНИЯ ===
platforms:
  linux:
    # Linux-специфичные метаданные
    depends:
      - bash

    # Форматные переопределения
    formats:
      deb:
        depends:
          - bash (>= 4.0)
      rpm:
        release: 1
        depends:
          - bash >= 4.0
      apk:
        depends:
          - bash>=4.0

  windows:
    # MSI identifier
    upgrade_code: "FIXED-GUID-HERE"
    install_scope: perMachine

  macos:
    # pkg identifier
    identifier: com.powertech.crossler

# === АРХИТЕКТУРНЫЕ ПЕРЕОПРЕДЕЛЕНИЯ ===
# (если нужно переопределить что-то для конкретной arch)
architectures:
  arm64:
    # переопределения для arm64
```

---

## Проектные решения для обсуждения

### Решение 1: Как описывать пути для разных платформ?

Windows и Unix используют разные пути (`C:\Program Files\` vs `/usr/bin`). Crossler должен либо:
- **Вариант A:** Иметь отдельные поля `dst` (Unix) и `win_dst` (Windows)
- **Вариант B:** Использовать только `dst` = Unix-путь, а для Windows автоматически маппить на INSTALLFOLDER
- **Вариант C:** Инструментальный путь — пользователь описывает в `platforms.windows.files` отдельно

Рекомендация: **Вариант B** для простых случаев + **Вариант C** как эскейп для сложных.

### Решение 2: Один конфиг или несколько?

nfpm подход — один yaml → несколько форматов. Это удобно, но некоторые вещи (реестр Windows, component plist macOS) принципиально платформо-специфичны.

Рекомендация: **один главный crossler.yaml** с секцией `platforms:` для платформо-специфичного. Единый конфиг — ключевое преимущество Crossler перед использованием nfpm + wixl + pkgbuild по отдельности.

### Решение 3: Как обрабатывать Windows-специфику (реестр, ярлыки)?

Реестр и ярлыки существуют только в MSI. Два подхода:
- **Вариант A:** Поддержать в конфиге, генерировать в .wxs
- **Вариант B:** Не поддерживать в v1, добавить позже

Рекомендация: **Вариант B** для v1, реализовать в v1.x как опциональную секцию `platforms.windows.registry`.

### Решение 4: Homebrew formula

Formula требует SHA256 хешей уже собранных tar.gz архивов. Это означает:
- Crossler сначала собирает tar.gz для macOS
- Вычисляет SHA256
- Генерирует formula с правильными хешами

Это pipeline, а не просто упаковка. Рекомендация: реализовать как отдельную команду `crossler generate-formula`.

---

## Итоговые приоритеты

### v1.0 — Must Have

1. Метаданные: name, version, description, maintainer, homepage, license, vendor
2. Установка файлов: src/dst/mode/type (file, config, symlink, dir)
3. Скрипты: postinstall (все платформы кроме DMG), preinstall (Linux+macOS)
4. Многоуровневые переопределения: глобальное → платформа → формат
5. Форматы: deb, rpm, apk (Linux), msi (Windows через wixl), pkg (macOS через pkgbuild), dmg (macOS через hdiutil), tar.gz (все)
6. Homebrew formula: генерация .rb файла

### v1.x — Should Have

1. Зависимости: depends/recommends/suggests/conflicts/replaces/provides для Linux
2. Preremove/postremove скрипты для Linux
3. Ярлыки Windows (Shortcuts) для GUI приложений
4. Условия установки MSI (проверка ОС, архитектуры)

### v2.0 — Nice to Have

1. Записи в реестр Windows
2. Файловые ассоциации Windows
3. Systemd юниты
4. Payload-free macOS пакеты
5. archlinux (PKGBUILD) формат

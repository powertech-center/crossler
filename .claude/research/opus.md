# Кроссплатформенная сборка установочных пакетов из Linux

> Дата составления: 2026-03-02
> Язык: русский
> Область применения: DevOps, CI/CD, разработка ПО под Linux/Windows/macOS

---

## 1. Типовые задачи при создании установочных пакетов

Создание установочного пакета — это не просто упаковка бинарного файла в архив. Каждый формат пакета несёт в себе декларацию о том, как программа должна быть интегрирована в операционную систему. Ниже перечислены основные аспекты, которые необходимо учитывать.

### 1.1 Метаданные пакета

Каждый пакет обязан содержать метаданные, которые система управления пакетами использует для идентификации, отображения и управления программой:

- **Имя пакета** (name) — машиночитаемый идентификатор, как правило строчными буквами, без пробелов.
- **Версия** (version) — семантическая версия в формате `MAJOR.MINOR.PATCH` или с доп. суффиксами (`1.2.3-1`, `1.2.3+build4`).
- **Архитектура** (arch) — целевая платформа: `amd64`, `arm64`, `i386`, `all`/`noarch` и т.д.
- **Описание** (description) — краткое (одна строка) и подробное (многострочное).
- **Мейнтейнер** (maintainer) — контактное лицо в формате `Имя <email@example.com>`.
- **Лицензия** (license) — SPDX-идентификатор (`MIT`, `Apache-2.0`, `GPL-2.0-only`).
- **Домашняя страница** (homepage/url).
- **Вендор** (vendor) — организация-производитель (актуально для RPM).
- **Epoch** — целочисленный префикс версии для принудительного обновления при смене схемы версионирования (RPM/DEB).

### 1.2 Файлы и пути установки

Стандартные пути установки для Linux определены стандартом FHS (Filesystem Hierarchy Standard):

| Тип файла | Путь |
|-----------|------|
| Исполняемые файлы | `/usr/bin/`, `/usr/sbin/` |
| Библиотеки | `/usr/lib/`, `/usr/lib64/` |
| Конфиги | `/etc/` |
| Данные (read-only) | `/usr/share/<name>/` |
| Переменные данные | `/var/lib/<name>/`, `/var/log/<name>/` |
| Документация | `/usr/share/doc/<name>/` |
| Man-страницы | `/usr/share/man/man1/` |
| Systemd units | `/lib/systemd/system/` или `/usr/lib/systemd/system/` |

Для Windows и macOS пути принципиально отличаются. Windows использует `%ProgramFiles%\Vendor\App\`, macOS — `/Applications/App.app/` или `/usr/local/` через Homebrew.

### 1.3 Сервисы и демоны

Большинство серверных приложений требуют интеграции с системой инициализации:

- **Linux (systemd)**: файл `.service`, установленный в `/lib/systemd/system/`. После установки пакет должен выполнить `systemctl daemon-reload` и, при необходимости, `systemctl enable <service>`.
- **Windows**: регистрация как Windows Service через `sc create` или NSIS/WiX/MSI-интеграцию.
- **macOS**: LaunchDaemon (plist-файл в `/Library/LaunchDaemons/`) или LaunchAgent (`/Library/LaunchAgents/`).

### 1.4 Конфигурационные файлы

Конфигурационные файлы требуют особого обращения — при обновлении пакета файл, изменённый пользователем, не должен быть перезаписан без предупреждения:

- **DEB**: файлы, перечисленные в `/DEBIAN/conffiles`, сохраняются при обновлении. `dpkg` спрашивает пользователя о конфликте.
- **RPM**: файлы, помеченные `%config(noreplace)` в spec-файле, не перезаписываются.
- **nFPM**: тип `config|noreplace` в секции `contents`.

### 1.5 Переменная PATH и глобальная доступность

Исполняемые файлы должны попасть в директорию, включённую в `$PATH`. Стандартный путь — `/usr/bin/`. На macOS Homebrew использует `/usr/local/bin/` (Intel) или `/opt/homebrew/bin/` (Apple Silicon). Для Windows MSI-пакеты добавляют путь к `PATH` через ключ реестра `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment`.

### 1.6 Скрипты pre/post install/remove

Скрипты позволяют выполнять действия на разных стадиях жизненного цикла пакета:

| Хук | Когда выполняется |
|-----|-------------------|
| `preinst` / `pre-install` | До распаковки файлов |
| `postinst` / `post-install` | После распаковки файлов |
| `prerm` / `pre-remove` | До удаления файлов |
| `postrm` / `post-remove` | После удаления файлов |

Типичные задачи: создание системного пользователя (`useradd`), установка прав на файлы, `systemctl enable/disable/start/stop`, создание директорий.

### 1.7 Зависимости

Пакетные менеджеры могут автоматически устанавливать зависимости:

- **depends** / **requires**: обязательные зависимости.
- **recommends** (DEB): рекомендуемые, устанавливаются по умолчанию, но не обязательны.
- **suggests** (DEB): необязательные дополнения.
- **provides**: пакет декларирует, что предоставляет некий виртуальный пакет.
- **conflicts**: несовместимые пакеты.
- **replaces** (DEB) / **obsoletes** (RPM): пакеты, которые данный пакет заменяет.

### 1.8 Конфликты файлов

При установке нескольких пакетов, содержащих одинаковые файлы, возникает конфликт. Решения:

- Явно объявить `conflicts` с конкурирующим пакетом.
- Использовать `replaces` (DEB) или `obsoletes` (RPM) для замены.
- Использовать механизм `alternatives` (Debian alternatives, RPM alternatives) для управления несколькими версиями одного исполняемого файла.

### 1.9 Подпись пакетов

Подпись гарантирует целостность и подлинность пакета:

- **DEB**: подпись репозитория через GPG (`apt-key`, `signed-by`). Отдельные `.deb`-файлы могут подписываться `dpkg-sig`.
- **RPM**: встроенная поддержка GPG-подписи через `rpm --addsign` или `rpmsign`.
- **APK (Alpine)**: подпись ключом разработчика через `abuild-keygen`.
- **AppImage**: подпись через `gpg` и встроенный файл `.sig`.
- **macOS**: подпись кода через `codesign` (обязательно для notarization).
- **Windows**: Authenticode-подпись через `signtool.exe` (для MSI и EXE).

### 1.10 Специфика Windows (MSI vs NSIS vs другие)

Windows предлагает несколько конкурирующих форматов установщиков:

| Формат | Инструмент | Особенности |
|--------|------------|-------------|
| MSI | WiX, msitools | Поддерживается Windows Installer, тихая установка, групповые политики |
| MSIX | WiX v5, MSIX Packaging Tool | Современный формат, песочница, Microsoft Store |
| NSIS EXE | NSIS | Гибкий скриптовый язык, малый размер накладных расходов |
| Inno Setup EXE | Inno Setup | Простота, богатые диалоги, Pascal-скриптинг |
| WinGet | winget-pkgs | Декларативный JSON/YAML-манифест, репозиторий Microsoft |
| Chocolatey | choco | PowerShell-скрипты, корпоративное использование |
| Scoop | scoop | JSON-манифест, portable-подход |

MSI является наиболее корпоративно-приемлемым форматом: поддерживает тихую установку (`/quiet`), логирование (`/l*v`), трансформации (`.mst`), развёртывание через Group Policy.

### 1.11 Специфика macOS (universal binary, notarization)

**Universal Binary (arm64 + x86_64)**:
Начиная с Apple Silicon (M1), macOS-приложения должны поддерживать обе архитектуры. Инструмент `lipo` позволяет объединить два бинарника в один:
```bash
lipo -create -output myapp-universal myapp-amd64 myapp-arm64
```

**Notarization**:
Apple требует нотаризации для приложений, распространяемых вне Mac App Store. Процесс:
1. Подписать код: `codesign --deep --force --options runtime --sign "Developer ID Application: ..." MyApp.app`
2. Создать архив: `ditto -c -k --keepParent MyApp.app MyApp.zip`
3. Отправить на нотаризацию: `xcrun notarytool submit MyApp.zip --apple-id ... --team-id ... --password ... --wait`
4. Прикрепить статус: `xcrun stapler staple MyApp.app`

Нотаризация возможна только с настоящего macOS-агента (не из Linux), что делает macOS-сборку в Linux CI-пайплайнах нетривиальной задачей.

---

## 2. Форматы пакетов

### 2.1 Linux

| Формат | Расширение | Дистрибутивы | Менеджер |
|--------|-----------|--------------|----------|
| Debian package | `.deb` | Debian, Ubuntu, Mint, Pop!_OS | apt, dpkg |
| RPM Package Manager | `.rpm` | RHEL, Fedora, openSUSE, AlmaLinux | dnf, zypper, rpm |
| Alpine Package | `.apk` | Alpine Linux | apk |
| Arch Linux package | `.pkg.tar.zst` | Arch, Manjaro | pacman |
| OpenWrt package | `.ipk` | OpenWrt, LEDE | opkg |
| AppImage | `.AppImage` | Любой Linux | Без установки |
| Flatpak | `.flatpakref` / репозиторий | Любой Linux (с flatpak) | flatpak |
| Snap | `.snap` | Ubuntu, другие (со snapd) | snap |

### 2.2 Windows

| Формат | Расширение | Особенности |
|--------|-----------|-------------|
| Windows Installer | `.msi` | Стандарт корпоративного развёртывания |
| MSIX | `.msix`, `.msixbundle` | Современный формат, Microsoft Store |
| Self-extracting installer | `.exe` | NSIS, Inno Setup — нестандартный формат |
| Portable | `.zip`, `.exe` | Без установки, scoop-совместимый |
| WinGet manifest | `.yaml` | Публикация в winget-pkgs |

### 2.3 macOS

| Формат | Расширение | Особенности |
|--------|-----------|-------------|
| macOS Installer Package | `.pkg` | pkgbuild + productbuild |
| Disk Image | `.dmg` | Drag & Drop установка |
| App Bundle | `.app` | Само-содержащееся приложение |
| Homebrew Formula | `.rb` | Менеджер пакетов Homebrew |
| Homebrew Cask | `.rb` (cask) | GUI-приложения через Homebrew |

---

## 3. Инструменты

### 3.1 nFPM

**Документация**: https://nfpm.goreleaser.com/
**GitHub**: https://github.com/goreleaser/nfpm

#### Философия и описание

nFPM расшифровывается как "nFPM is Not FPM" — это альтернатива `fpm`, написанная на Go без внешних зависимостей. Единственный бинарник без Ruby, без tar, без дополнительных системных утилит. Конфигурируется через YAML-файл, поддерживает создание пакетов на любой платформе, где работает Go.

nFPM часто используется совместно с GoReleaser, но может работать и как самостоятельный инструмент.

#### Поддерживаемые форматы

- `.deb` (Debian/Ubuntu)
- `.rpm` (RHEL/Fedora/openSUSE)
- `.apk` (Alpine Linux)
- `.ipk` (OpenWrt)
- Arch Linux (`.pkg.tar.zst`)
- `termux.deb` (Android Termux)

#### Плюсы

- Нет внешних зависимостей — единственный бинарник
- Один YAML для всех форматов пакетов
- Поддержка GPG-подписи для deb и rpm
- Поддержка systemd units через `scripts`
- Активная разработка, интеграция с GoReleaser
- Поддержка переменных окружения в конфигурации (`${VERSION}`)
- Кроссплатформенная сборка: собирает пакеты для Linux с любого хоста

#### Минусы

- Только Linux-пакеты (нет Windows MSI, macOS .pkg)
- Нет шаблонизации (намеренное ограничение дизайна)
- Для сложных сценариев нужны внешние скрипты

#### Полный пример конфигурации (nfpm.yaml)

```yaml
# nfpm.yaml — полный пример конфигурации
name: "myapp"
arch: "${GOARCH}"
platform: "linux"
version: "${VERSION}"
version_schema: semver
epoch: 0
release: 1
prerelease: ""
version_metadata: ""

section: default
priority: optional
maintainer: "Иван Иванов <ivan@example.com>"
description: |
  Краткое описание.
  Подробное описание приложения на несколько строк.
vendor: "MyCompany Ltd"
homepage: "https://example.com"
license: "MIT"

# Зависимости
depends:
  - libc6
  - libssl3
recommends:
  - curl
suggests:
  - jq
conflicts:
  - myapp-legacy
replaces:
  - myapp-legacy

# Файлы пакета
contents:
  # Основной бинарник
  - src: ./dist/myapp
    dst: /usr/bin/myapp
    file_info:
      mode: 0755
      owner: root
      group: root

  # Конфигурационный файл (не перезаписывать при обновлении)
  - src: ./packaging/myapp.conf
    dst: /etc/myapp/myapp.conf
    type: config|noreplace

  # Systemd unit
  - src: ./packaging/myapp.service
    dst: /lib/systemd/system/myapp.service
    file_info:
      mode: 0644

  # Директория для данных (ghost — создать пустую)
  - dst: /var/lib/myapp
    type: ghost
    file_info:
      mode: 0750
      owner: myapp
      group: myapp

  # Симлинк
  - src: /usr/bin/myapp
    dst: /usr/local/bin/myapp
    type: symlink

  # Man-страница
  - src: ./docs/myapp.1
    dst: /usr/share/man/man1/myapp.1
    file_info:
      mode: 0644

# Скрипты установки/удаления
scripts:
  preinstall: ./packaging/scripts/preinstall.sh
  postinstall: ./packaging/scripts/postinstall.sh
  preremove: ./packaging/scripts/preremove.sh
  postremove: ./packaging/scripts/postremove.sh

# Специфика для DEB
deb:
  lintian_overrides:
    - "statically-linked-binary"
  fields:
    Bugs: "https://github.com/example/myapp/issues"
  signature:
    key_file: "${GPG_KEY_FILE}"
    key_id: "${GPG_KEY_ID}"

# Специфика для RPM
rpm:
  compression: lzma
  group: Applications/System
  summary: "Короткое описание для RPM"
  signature:
    key_file: "${GPG_KEY_FILE}"
  scripts:
    verify: ./packaging/scripts/rpm-verify.sh

# Специфика для APK
apk:
  signature:
    key_file: "${APK_KEY_FILE}"
    key_name: "myapp@example.com"
```

**Сборка пакетов:**
```bash
# Собрать DEB
nfpm package --config nfpm.yaml --packager deb --target ./dist/

# Собрать RPM
nfpm package --config nfpm.yaml --packager rpm --target ./dist/

# Собрать APK
nfpm package --config nfpm.yaml --packager apk --target ./dist/

# Собрать все форматы одной командой (через скрипт)
for fmt in deb rpm apk; do
  nfpm package --config nfpm.yaml --packager $fmt --target ./dist/
done
```

---

### 3.2 fpm (Effing Package Management)

**Документация**: https://fpm.readthedocs.io/
**GitHub**: https://github.com/jordansissel/fpm

#### Философия и описание

fpm — это "универсальный конвертер пакетов", написанный на Ruby. Его девиз: "Создавать пакеты должно быть просто и не требовать глубоких знаний специфики каждого формата". fpm работает по принципу `источник → цель`: вы указываете, откуда брать файлы и в какой формат упаковывать.

В отличие от nFPM, fpm поддерживает широкий спектр источников: директории, Python-пакеты, Ruby gems, npm-пакеты, tar-архивы и даже уже готовые deb/rpm-пакеты для конвертации.

#### Поддерживаемые форматы

**Источники (input):** `dir`, `gem`, `rpm`, `deb`, `python`, `npm`, `tar`, `zip`, `osxpkg`, `snap`, `solaris`, `freebsd`, `p5p`, `pear`, `pleaserun`, `puppet`, `virtualenv`

**Цели (output):** `deb`, `rpm`, `osxpkg`, `pacman`, `solaris`, `freebsd`, `p5p`, `snap`, `tar`, `dir`, `zip`, `sh`

#### Плюсы

- Огромная гибкость форматов источников и целей
- Работа из командной строки без конфигурационного файла
- Поддержка macOS `.pkg` (osxpkg)
- Конвертация существующих пакетов между форматами
- Поддержка скриптов pre/post install

#### Минусы

- Требует Ruby и RubyGems
- Медленнее, чем nFPM
- Менее активная разработка по сравнению с nFPM
- Нет поддержки Windows MSI

#### Примеры использования

```bash
# Установка
gem install fpm

# Базовый пример: директория → DEB
fpm -s dir -t deb \
  -n myapp \
  -v 1.0.0 \
  -a amd64 \
  --description "My Application" \
  --maintainer "Ivan <ivan@example.com>" \
  --license MIT \
  --url "https://example.com" \
  --depends libc6 \
  --depends libssl3 \
  --deb-no-default-config-files \
  ./dist/myapp=/usr/bin/myapp \
  ./packaging/myapp.conf=/etc/myapp/myapp.conf \
  ./packaging/myapp.service=/lib/systemd/system/myapp.service

# Директория → RPM
fpm -s dir -t rpm \
  -n myapp \
  -v 1.0.0 \
  --iteration 1 \
  -a x86_64 \
  --description "My Application" \
  --rpm-group "Applications/System" \
  --depends glibc \
  ./dist/myapp=/usr/bin/myapp

# Python-пакет → DEB
fpm -s python -t deb requests

# npm-пакет → RPM
fpm -s npm -t rpm express

# Конвертация DEB → RPM
fpm -s deb -t rpm myapp_1.0.0_amd64.deb

# Скрипты установки
fpm -s dir -t deb -n myapp -v 1.0.0 \
  --before-install ./scripts/preinstall.sh \
  --after-install ./scripts/postinstall.sh \
  --before-remove ./scripts/preremove.sh \
  --after-remove ./scripts/postremove.sh \
  ./dist/myapp=/usr/bin/myapp

# Использование файла конфигурации .fpm (помещается в текущую директорию)
cat > .fpm <<'EOF'
-s dir
-t deb
--name myapp
--version 1.0.0
--architecture amd64
--depends libc6
--description My Application
--maintainer Ivan <ivan@example.com>
./dist/myapp=/usr/bin/myapp
EOF
fpm  # Запуск без аргументов, читает .fpm
```

---

### 3.3 GoReleaser

**Документация**: https://goreleaser.com/
**GitHub**: https://github.com/goreleaser/goreleaser

#### Философия и описание

GoReleaser — это комплексный инструмент автоматизации релизов для Go-проектов (и не только). Он охватывает весь цикл: сборка бинарников для всех платформ → создание архивов → генерация пакетов (через nFPM) → вычисление контрольных сумм → GPG-подпись → публикация в GitHub/GitLab Releases → публикация Docker-образов → Homebrew formula → Scoop bucket → AUR → Winget.

GoReleaser является оберткой над nFPM для Linux-пакетов, но добавляет оркестрацию всего пайплайна релиза.

#### Поддерживаемые форматы

Через встроенные инструменты и интеграции:
- `.deb`, `.rpm`, `.apk`, `.ipk`, Arch Linux (через nFPM)
- `.tar.gz`, `.zip`, `.tar.xz` (архивы)
- Docker images (multi-platform)
- Homebrew formula (macOS/Linux)
- Scoop bucket (Windows)
- Winget manifests
- AUR (Arch User Repository)
- GitHub/GitLab/Gitea Releases
- NPM пакеты

#### Плюсы

- Полный пайплайн релиза в одном файле
- Матрица сборок: OS × ARCH в одном `.goreleaser.yaml`
- Встроенная поддержка множества платформ без дополнительных скриптов
- Параллельная сборка для ускорения
- Управление переменными и шаблонами (Go templating)
- Поддержка Cosign для подписи артефактов
- Генерация SBOM (Software Bill of Materials)

#### Минусы

- Ориентирован преимущественно на Go-проекты (хотя поддерживает и другие)
- Требует понимания конфигурационного формата
- Pro-версия для части функций

#### Пример .goreleaser.yaml

```yaml
# .goreleaser.yaml
version: 2

project_name: myapp

before:
  hooks:
    - go mod tidy
    - go generate ./...

builds:
  - id: myapp
    main: ./cmd/myapp
    binary: myapp
    env:
      - CGO_ENABLED=0
    goos:
      - linux
      - windows
      - darwin
    goarch:
      - amd64
      - arm64
      - arm
    goarm:
      - "7"
    ignore:
      - goos: windows
        goarch: arm
    ldflags:
      - -s -w
      - -X main.version={{.Version}}
      - -X main.commit={{.Commit}}
      - -X main.date={{.Date}}

archives:
  - id: default
    name_template: "{{ .ProjectName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}"
    format_overrides:
      - goos: windows
        formats: [zip]
    files:
      - README.md
      - LICENSE
      - completions/*

checksum:
  name_template: "checksums.txt"
  algorithm: sha256

signs:
  - artifacts: checksum
    args:
      - "--batch"
      - "-u"
      - "{{ .Env.GPG_FINGERPRINT }}"
      - "--output"
      - "${signature}"
      - "--detach-sign"
      - "${artifact}"

# Linux пакеты через nFPM
nfpms:
  - id: linux-packages
    package_name: myapp
    file_name_template: "{{ .PackageName }}_{{ .Version }}_{{ .Arch }}"
    vendor: "MyCompany Ltd"
    homepage: "https://example.com"
    maintainer: "Ivan Ivanov <ivan@example.com>"
    description: |-
      My Application — краткое описание.
      Подробное описание на несколько строк.
    license: "MIT"
    formats:
      - deb
      - rpm
      - apk
      - archlinux
    dependencies:
      - libc6
    recommends:
      - curl
    contents:
      - src: ./packaging/myapp.service
        dst: /lib/systemd/system/myapp.service
        file_info:
          mode: 0644
      - src: ./packaging/myapp.conf
        dst: /etc/myapp/myapp.conf
        type: config|noreplace
      - dst: /var/lib/myapp
        type: ghost
        file_info:
          mode: 0750
    scripts:
      preinstall: ./packaging/scripts/preinstall.sh
      postinstall: ./packaging/scripts/postinstall.sh
      preremove: ./packaging/scripts/preremove.sh
      postremove: ./packaging/scripts/postremove.sh
    deb:
      signature:
        key_file: "{{ .Env.GPG_KEY_FILE }}"
    rpm:
      signature:
        key_file: "{{ .Env.GPG_KEY_FILE }}"

# Docker образы
dockers:
  - image_templates:
      - "mycompany/myapp:{{ .Tag }}-amd64"
    use: buildx
    build_flag_templates:
      - "--platform=linux/amd64"
    dockerfile: Dockerfile
  - image_templates:
      - "mycompany/myapp:{{ .Tag }}-arm64"
    use: buildx
    build_flag_templates:
      - "--platform=linux/arm64"
    dockerfile: Dockerfile
    goarch: arm64

docker_manifests:
  - name_template: "mycompany/myapp:{{ .Tag }}"
    image_templates:
      - "mycompany/myapp:{{ .Tag }}-amd64"
      - "mycompany/myapp:{{ .Tag }}-arm64"

# Homebrew formula
brews:
  - name: myapp
    repository:
      owner: mycompany
      name: homebrew-tap
    directory: Formula
    description: "My Application"
    license: "MIT"
    test: |
      system "#{bin}/myapp --version"

# Scoop для Windows
scoops:
  - name: myapp
    repository:
      owner: mycompany
      name: scoop-bucket
    description: "My Application"
    license: MIT

changelog:
  sort: asc
  filters:
    exclude:
      - "^docs:"
      - "^test:"
      - "^ci:"

release:
  github:
    owner: mycompany
    name: myapp
  draft: false
  prerelease: auto
  name_template: "{{.ProjectName}} v{{.Version}}"
```

---

### 3.4 CPack (CMake)

**Документация**: https://cmake.org/cmake/help/latest/module/CPack.html
**Входит в**: CMake (начиная с версии 2.4)

#### Философия и описание

CPack — это подсистема CMake, предназначенная для создания установочных пакетов из CMake-проектов. Интегрирован непосредственно в систему сборки, что упрощает создание пакетов для проектов C/C++. CPack использует концепцию "генераторов" — каждый генератор отвечает за свой формат пакета.

#### Поддерживаемые форматы (генераторы)

- `DEB` — Debian пакеты
- `RPM` — RPM пакеты
- `NSIS` / `NSIS64` — Windows NSIS-установщик
- `WIX` — Windows MSI через WiX
- `DMG` — macOS Disk Image
- `PKG` — macOS Package
- `TGZ`, `TBZ2`, `TZST` — tar-архивы
- `ZIP` — ZIP-архив
- `STGZ` — самораспаковывающийся tar.gz
- `IFW` — Qt Installer Framework
- `FreeBSD` — FreeBSD пакеты

#### Плюсы

- Встроен в CMake — не нужны дополнительные инструменты
- Поддержка компонентной установки (пользователь выбирает компоненты)
- Хорошо работает для C/C++-проектов
- Поддержка NSIS и WiX для Windows из Linux (при наличии инструментов)

#### Минусы

- Сложность конфигурации для нестандартных случаев
- Менее гибкий, чем nFPM или fpm
- Требует знания CMake-синтаксиса
- Слабая поддержка systemd units из коробки

#### Примеры CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.20)
project(MyApp VERSION 1.2.3)

# Основной исполняемый файл
add_executable(myapp src/main.cpp)

# Установка файлов
install(TARGETS myapp
    RUNTIME DESTINATION bin
    COMPONENT Runtime
)
install(FILES packaging/myapp.conf
    DESTINATION /etc/myapp
    COMPONENT Config
)
install(FILES packaging/myapp.service
    DESTINATION /lib/systemd/system
    COMPONENT SystemdService
)

# ===== CPack конфигурация =====
include(CPack)

set(CPACK_PACKAGE_NAME "myapp")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_VENDOR "MyCompany Ltd")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "My Application — краткое описание")
set(CPACK_PACKAGE_DESCRIPTION "Подробное описание приложения.")
set(CPACK_PACKAGE_CONTACT "Ivan Ivanov <ivan@example.com>")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://example.com")

# Лицензия
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/LICENSE")

# Генераторы — выбор форматов для сборки
set(CPACK_GENERATOR "DEB;RPM")

# ---- DEB специфика ----
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Ivan Ivanov <ivan@example.com>")
set(CPACK_DEBIAN_PACKAGE_SECTION "misc")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libc6 (>= 2.17), libstdc++6 (>= 5.2)")
set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA
    "${CMAKE_SOURCE_DIR}/packaging/debian/postinst;${CMAKE_SOURCE_DIR}/packaging/debian/prerm"
)
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)  # Автоимя из метаданных

# ---- RPM специфика ----
set(CPACK_RPM_PACKAGE_LICENSE "MIT")
set(CPACK_RPM_PACKAGE_GROUP "Applications/System")
set(CPACK_RPM_PACKAGE_REQUIRES "glibc >= 2.17, libstdc++ >= 5.2")
set(CPACK_RPM_POST_INSTALL_SCRIPT_FILE "${CMAKE_SOURCE_DIR}/packaging/rpm/postinstall.sh")
set(CPACK_RPM_PRE_UNINSTALL_SCRIPT_FILE "${CMAKE_SOURCE_DIR}/packaging/rpm/preuninstall.sh")
set(CPACK_RPM_FILE_NAME RPM-DEFAULT)

# ---- NSIS специфика (Windows) ----
set(CPACK_NSIS_DISPLAY_NAME "My Application")
set(CPACK_NSIS_PACKAGE_NAME "MyApp")
set(CPACK_NSIS_INSTALL_ROOT "$PROGRAMFILES64")
set(CPACK_NSIS_MODIFY_PATH ON)
```

```bash
# Сборка пакетов
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --parallel
cpack -G DEB   # Только DEB
cpack -G RPM   # Только RPM
cpack          # Все генераторы из CPACK_GENERATOR
```

---

### 3.5 cargo-deb и cargo-rpm (Rust)

**cargo-deb GitHub**: https://github.com/kornelski/cargo-deb
**cargo-generate-rpm (замена cargo-rpm)**: https://crates.io/crates/cargo-generate-rpm

#### Философия

Инструменты для создания системных пакетов непосредственно из Rust/Cargo-проектов. Метаданные берутся из `Cargo.toml`, что исключает дублирование. `cargo-deb` создаёт `.deb`-пакеты, `cargo-generate-rpm` создаёт `.rpm` (исходный `cargo-rpm` устарел и не поддерживается с 2022 года).

#### Примеры Cargo.toml конфигурации

```toml
[package]
name = "myapp"
version = "1.2.3"
authors = ["Ivan Ivanov <ivan@example.com>"]
description = "My Application — описание пакета"
license = "MIT"
homepage = "https://example.com"
repository = "https://github.com/mycompany/myapp"
readme = "README.md"
edition = "2021"

[[bin]]
name = "myapp"
path = "src/main.rs"

# ===== cargo-deb конфигурация =====
[package.metadata.deb]
maintainer = "Ivan Ivanov <ivan@example.com>"
copyright = "2024, MyCompany Ltd"
license-file = ["LICENSE", "2"]
extended-description = """\
Подробное описание приложения для DEB-пакета.
Может быть многострочным."""
depends = "$auto, libssl3"
section = "utils"
priority = "optional"
revision = "1"
assets = [
    # [source, destination, mode]
    ["target/release/myapp", "usr/bin/", "755"],
    ["README.md", "usr/share/doc/myapp/README.md", "644"],
    ["packaging/myapp.conf", "etc/myapp/myapp.conf", "644"],
    ["packaging/myapp.1.gz", "usr/share/man/man1/", "644"],
]
conf-files = ["/etc/myapp/myapp.conf"]
maintainer-scripts = "packaging/debian/"
systemd-units = [
    { name = "myapp", enable = true, start = true }
]

# ===== cargo-generate-rpm конфигурация =====
[package.metadata.generate-rpm]
name = "myapp"
version = "1.2.3"
release = "1"
license = "MIT"
summary = "My Application"
description = "Подробное описание для RPM-пакета."
group = "Applications/System"
url = "https://example.com"

[package.metadata.generate-rpm.requires]
glibc = ">= 2.17"
openssl-libs = "*"

assets = [
    { source = "target/release/myapp", dest = "/usr/bin/myapp", mode = "755" },
    { source = "packaging/myapp.conf", dest = "/etc/myapp/myapp.conf", mode = "644", config = true },
    { source = "packaging/myapp.service", dest = "/usr/lib/systemd/system/myapp.service", mode = "644" },
    { source = "README.md", dest = "/usr/share/doc/myapp/README.md", mode = "644", doc = true },
]

[package.metadata.generate-rpm.pre_install_script]
file = "packaging/rpm/preinstall.sh"

[package.metadata.generate-rpm.post_install_script]
file = "packaging/rpm/postinstall.sh"
```

```bash
# Сборка
cargo build --release

# Создать DEB
cargo deb

# Создать DEB для другой архитектуры (кросс-компиляция)
cargo deb --target aarch64-unknown-linux-gnu

# Создать RPM
cargo generate-rpm

# Создать RPM с указанием пути к бинарнику
cargo generate-rpm --payload-compress zstd
```

---

### 3.6 msitools

**Документация**: https://wiki.gnome.org/msitools
**GitLab (GNOME)**: https://gitlab.gnome.org/GNOME/msitools

#### Описание

msitools — это набор утилит GNOME-проекта для инспекции и создания Windows Installer (`.msi`) файлов из Linux. Основан на `libmsi` — портированной реализации Windows Installer из проекта Wine.

Ключевая утилита — `wixl`, компилятор WiX-совместимых `.wxs`-файлов в `.msi`. По синтаксису `.wxs` wixl совместим с WiX Toolset, что позволяет переиспользовать наработки.

#### Создание MSI из Linux

```bash
# Установка на Debian/Ubuntu
sudo apt install msitools

# Установка на Fedora/RHEL
sudo dnf install msitools

# Создание MSI из WXS-файла
wixl -o myapp-1.0.0-x64.msi myapp.wxs

# С указанием архитектуры
wixl -a x64 -o myapp-1.0.0-x64.msi myapp.wxs

# wixl-heat — генерация WXS-фрагмента из директории с файлами
wixl-heat -p /path/to/files/ \
  --component-group MyFiles \
  --directory-ref INSTALLDIR \
  --var var.SourceDir \
  /path/to/files/ > files.wxs
```

#### Плюсы

- Позволяет создавать MSI из Linux без Windows
- WiX-совместимый синтаксис WXS
- Бесплатно, открытый код, часть GNOME
- Подходит для CI/CD-пайплайнов на Linux

#### Минусы

- Поддерживает значительно меньше функций, чем WiX Toolset
- Не работает под Windows
- Ограниченная поддержка сложных WiX-расширений
- Менее активная разработка
- Нет поддержки MSIX

---

### 3.7 WiX Toolset

**Документация**: https://wixtoolset.org/ / https://docs.firegiant.com/wix/
**GitHub**: https://github.com/wixtoolset/wix

#### Философия и описание

WiX (Windows Installer XML) Toolset — это наиболее мощный и гибкий инструмент создания Windows Installer (`.msi`) пакетов. Описывает структуру установщика в XML-формате (`.wxs`). В 2024 году вышла версия WiX v5, которая переработала синтаксис и добавила поддержку MSIX.

WiX работает под Windows и (частично) Linux (через mono или .NET 6+). Для запуска в Linux CI рекомендуется использовать .NET global tool.

#### Создание MSI/MSIX

**Установка (как .NET global tool):**
```bash
dotnet tool install --global wix
wix --version
```

#### Пример Package.wxs (WiX v5)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package
    Name="My Application"
    Manufacturer="MyCompany Ltd"
    Version="1.2.3.0"
    UpgradeCode="PUT-GUID-HERE-1111-2222-333333333333"
    Language="1033"
    Scope="perMachine">

    <!-- Автоматическое обнаружение и удаление предыдущих версий -->
    <MajorUpgrade DowngradeErrorMessage="Новая версия уже установлена." />

    <!-- Папка установки -->
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="MANUFACTURERFOLDER" Name="MyCompany">
        <Directory Id="INSTALLFOLDER" Name="MyApp" />
      </Directory>
    </StandardDirectory>

    <!-- Директория меню Пуск -->
    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="ApplicationProgramsFolder" Name="My Application" />
    </StandardDirectory>

    <!-- Компоненты -->
    <ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER">
      <!-- Основной исполняемый файл -->
      <Component Id="MainExecutable" Guid="GUID-COMP-1111-2222-333333333333">
        <File Id="MyAppEXE"
              Source=".\dist\myapp.exe"
              Name="myapp.exe"
              KeyPath="yes" />

        <!-- Добавить PATH к переменной окружения -->
        <Environment Id="PATH"
                     Name="PATH"
                     Value="[INSTALLFOLDER]"
                     Permanent="no"
                     Part="last"
                     Action="set"
                     System="yes" />
      </Component>

      <!-- Конфигурационный файл -->
      <Component Id="ConfigFile" Guid="GUID-COMP-2222-3333-444444444444">
        <File Id="MyAppConf"
              Source=".\packaging\myapp.conf"
              Name="myapp.conf" />
      </Component>
    </ComponentGroup>

    <!-- Ярлык в меню Пуск -->
    <ComponentGroup Id="ShortcutComponents" Directory="ApplicationProgramsFolder">
      <Component Id="StartMenuShortcut" Guid="GUID-COMP-3333-4444-555555555555">
        <Shortcut Id="AppStartMenuShortcut"
                  Name="My Application"
                  Description="My Application"
                  Target="[INSTALLFOLDER]myapp.exe"
                  WorkingDirectory="INSTALLFOLDER" />
        <RemoveFolder Id="CleanUpShortCut" Directory="ApplicationProgramsFolder" On="uninstall" />
        <RegistryValue Root="HKCU"
                       Key="Software\MyCompany\MyApp"
                       Name="installed"
                       Type="integer"
                       Value="1"
                       KeyPath="yes" />
      </Component>
    </ComponentGroup>

    <!-- Функции установки -->
    <Feature Id="ProductFeature" Title="My Application" Level="1">
      <ComponentGroupRef Id="ProductComponents" />
      <ComponentGroupRef Id="ShortcutComponents" />
    </Feature>
  </Package>
</Wix>
```

```bash
# Сборка MSI (WiX v5 из Linux)
wix build -o myapp-1.2.3-x64.msi Package.wxs

# С архитектурой
wix build -arch x64 -o myapp-1.2.3-x64.msi Package.wxs
```

#### Плюсы

- Наиболее полная поддержка функций Windows Installer
- Поддержка MSIX (v5+)
- Работает как .NET global tool (кроссплатформенно)
- Большое сообщество и обширная документация

#### Минусы

- Сложный XML-синтаксис
- Крутая кривая обучения
- Требует .NET Runtime

---

### 3.8 NSIS (Nullsoft Scriptable Install System)

**Документация**: https://nsis.sourceforge.io/
**Последняя версия**: 3.10 (март 2025)

#### Философия и описание

NSIS — это профессиональная система создания Windows-установщиков с открытым исходным кодом. Изначально разработана Nullsoft (авторы Winamp) для распространения своих продуктов. Создаёт компактные `.exe`-установщики. Настраивается скриптовым языком `.nsi`.

Компилятор `makensis` может быть собран под Linux, что позволяет создавать Windows-установщики в Linux CI без Wine.

#### Установка на Linux

```bash
# Debian/Ubuntu
sudo apt install nsis

# Fedora/RHEL
sudo dnf install mingw32-nsis  # или nsis

# Arch Linux
sudo pacman -S nsis
```

#### Пример .nsi скрипта

```nsi
; myapp-installer.nsi — Полный пример NSIS-скрипта

;----------- Метаданные -----------
!define APP_NAME "My Application"
!define APP_VERSION "1.2.3"
!define APP_PUBLISHER "MyCompany Ltd"
!define APP_URL "https://example.com"
!define APP_EXE "myapp.exe"
!define APP_GUID "{PUT-GUID-HERE-1111-2222-333333333333}"
!define INSTALL_DIR "$PROGRAMFILES64\MyCompany\MyApp"

;----------- Настройки компилятора -----------
Name "${APP_NAME} ${APP_VERSION}"
OutFile "myapp-${APP_VERSION}-installer.exe"
InstallDir "${INSTALL_DIR}"
InstallDirRegKey HKLM "Software\MyCompany\MyApp" "InstallPath"
RequestExecutionLevel admin
Unicode True
SetCompressor /SOLID lzma

;----------- Современный интерфейс (MUI2) -----------
!include "MUI2.nsh"
!include "WinMessages.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "packaging\myapp.ico"
!define MUI_UNICON "packaging\myapp.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "packaging\installer-banner.bmp"

; Страницы установщика
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; Страницы деинсталлятора
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

;----------- Секции установки -----------
Section "Основные файлы (обязательно)" SecCore
    SectionIn RO  ; Нельзя отключить

    SetOutPath "$INSTDIR"
    File "dist\myapp.exe"
    File "dist\*.dll"
    File "README.txt"

    SetOutPath "$INSTDIR\config"
    File "packaging\myapp.conf"

    ; Записать путь установки в реестр
    WriteRegStr HKLM "Software\MyCompany\MyApp" "InstallPath" "$INSTDIR"
    WriteRegStr HKLM "Software\MyCompany\MyApp" "Version" "${APP_VERSION}"

    ; Добавить в PATH
    EnVar::SetHKLM
    EnVar::AddValue "PATH" "$INSTDIR"

    ; Создать деинсталлятор
    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; Запись в "Программы и компоненты"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "Publisher" "${APP_PUBLISHER}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "URLInfoAbout" "${APP_URL}"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}" \
        "NoRepair" 1
SectionEnd

Section "Ярлыки в меню Пуск" SecShortcuts
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" \
        "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
    CreateShortcut "$SMPROGRAMS\${APP_NAME}\Удалить ${APP_NAME}.lnk" \
        "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Ярлык на рабочем столе" SecDesktop
    CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

;----------- Деинсталляция -----------
Section "Uninstall"
    ; Удалить файлы
    Delete "$INSTDIR\${APP_EXE}"
    Delete "$INSTDIR\*.dll"
    Delete "$INSTDIR\README.txt"
    Delete "$INSTDIR\config\myapp.conf"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR\config"
    RMDir "$INSTDIR"

    ; Удалить ярлыки
    Delete "$SMPROGRAMS\${APP_NAME}\*.lnk"
    RMDir "$SMPROGRAMS\${APP_NAME}"
    Delete "$DESKTOP\${APP_NAME}.lnk"

    ; Удалить из реестра
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_GUID}"
    DeleteRegKey HKLM "Software\MyCompany\MyApp"

    ; Удалить из PATH
    EnVar::SetHKLM
    EnVar::DeleteValue "PATH" "$INSTDIR"
SectionEnd
```

```bash
# Сборка установщика из Linux
makensis myapp-installer.nsi

# Тихая сборка (нет вывода кроме ошибок)
makensis /V1 myapp-installer.nsi
```

#### Плюсы

- Компактный размер установщика
- Мощный скриптовый язык
- Многоязычность из коробки
- Компилируется на Linux (нет Wine)
- Огромное количество плагинов (EnVar, NSServiceV2, и т.д.)

#### Минусы

- Нестандартный установщик (не MSI)
- Нет поддержки тихой установки через MSI-интерфейс
- Нет нативной поддержки групповых политик
- Синтаксис скриптов не самый читаемый

---

### 3.9 Inno Setup

**Документация**: https://jrsoftware.org/isinfo.php
**Последняя версия**: 6.x

#### Философия и описание

Inno Setup — бесплатный инструмент создания Windows-установщиков, известный своей простотой и красивыми диалогами. Конфигурируется через `.iss`-файлы (Inno Setup Script). Поддерживает Pascal Script для сложной логики.

Для запуска из Linux используется Wine + Inno Setup, или Docker-образ с Wine.

#### Пример .iss скрипта

```pascal
; myapp.iss — Пример скрипта Inno Setup

[Setup]
AppId={{PUT-GUID-HERE-1111-2222-333333333333}}
AppName=My Application
AppVersion=1.2.3
AppPublisher=MyCompany Ltd
AppPublisherURL=https://example.com
AppSupportURL=https://example.com/support
AppUpdatesURL=https://example.com/releases
DefaultDirName={autopf}\MyCompany\MyApp
DefaultGroupName=My Application
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=myapp-1.2.3-setup
SetupIconFile=packaging\myapp.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "addtopath"; Description: "Добавить в PATH"; GroupDescription: "Системная интеграция:"; Flags: checkedonce

[Files]
Source: "dist\myapp.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "packaging\myapp.conf"; DestDir: "{app}\config"; Flags: onlyifdoesntexist
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\My Application"; Filename: "{app}\myapp.exe"
Name: "{group}\Удалить My Application"; Filename: "{uninstallexe}"
Name: "{autodesktop}\My Application"; Filename: "{app}\myapp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\myapp.exe"; Description: "{cm:LaunchProgram,My Application}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKLM; Subkey: "Software\MyCompany\MyApp"; ValueType: string; ValueName: "Version"; ValueData: "1.2.3"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "PATH"; ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath(ExpandConstant('{app}'))

[Code]
function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'PATH', OrigPath)
  then begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Param + ';', ';' + OrigPath + ';') = 0;
end;
```

```bash
# Сборка через Docker с Wine (из Linux)
docker run --rm \
  -v "$PWD:/work" \
  --workdir /work \
  amake/innosetup:6 \
  myapp.iss

# Через Wine напрямую
wine "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" myapp.iss
```

#### Плюсы

- Очень простой и читаемый синтаксис
- Богатые диалоги установщика
- Pascal Script для сложной логики
- Поддержка Unicode, локализации
- Бесплатно, активная разработка

#### Минусы

- Нет нативной Linux-поддержки (нужен Wine или Docker)
- Нет поддержки MSI-формата (только EXE)
- Нет подписи кода из Wine-среды

---

### 3.10 AppImage

**Документация**: https://appimage.org/ / https://docs.appimage.org/
**GitHub**: https://github.com/AppImage/AppImageKit

#### Философия "portable app"

AppImage реализует концепцию "один файл — одно приложение". Пользователь скачивает единственный файл, делает его исполняемым (`chmod +x`) и запускает — без установки, без root, без менеджера пакетов. AppImage монтирует встроенную SquashFS-файловую систему при запуске. Формат похож на macOS `.app`-bundle по философии.

#### Структура AppDir

```
MyApp.AppDir/
├── AppRun                   # Точка входа (скрипт или симлинк на бинарник)
├── myapp.desktop            # Desktop-файл (обязателен)
├── myapp.png                # Иконка (обязательна)
├── usr/
│   ├── bin/
│   │   └── myapp            # Основной бинарник
│   └── lib/
│       └── *.so             # Зависимые библиотеки
└── .DirIcon -> myapp.png    # Симлинк на иконку
```

#### Пример создания AppImage

```bash
# Установка appimagetool
wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage

# Создать структуру AppDir
mkdir -p MyApp.AppDir/usr/bin
mkdir -p MyApp.AppDir/usr/lib

# Скопировать бинарник
cp dist/myapp MyApp.AppDir/usr/bin/myapp

# Скопировать зависимые библиотеки (используя linuxdeploy)
linuxdeploy-x86_64.AppImage \
  --appdir MyApp.AppDir \
  --executable dist/myapp \
  --output appimage

# Создать myapp.desktop
cat > MyApp.AppDir/myapp.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=My Application
Exec=myapp
Icon=myapp
Categories=Utility;
Comment=My Application Description
EOF

# Скопировать иконку
cp packaging/myapp.png MyApp.AppDir/myapp.png
ln -sf myapp.png MyApp.AppDir/.DirIcon

# Создать AppRun
cat > MyApp.AppDir/AppRun <<'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin/:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib/:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/myapp" "$@"
EOF
chmod +x MyApp.AppDir/AppRun

# Собрать AppImage
ARCH=x86_64 ./appimagetool-x86_64.AppImage MyApp.AppDir MyApp-1.2.3-x86_64.AppImage

# Подписать
gpg --detach-sign --armor MyApp-1.2.3-x86_64.AppImage
```

#### Плюсы

- Не требует установки и root-прав
- Работает на любом Linux-дистрибутиве
- Один файл для распространения
- Портабельность: можно носить на флешке

#### Минусы

- Нет автообновлений из коробки (есть AppImageUpdate)
- Большой размер (содержит все зависимости)
- Нет интеграции с системным менеджером пакетов
- Нет автоматических обновлений безопасности зависимостей

---

### 3.11 Flatpak и Snap

#### Flatpak

**Документация**: https://docs.flatpak.org/
**Репозиторий**: https://flathub.org/

Flatpak использует общие рантаймы (freedesktop, GNOME, KDE) для уменьшения дублирования зависимостей. Приложение работает в песочнице с явными разрешениями (порты D-Bus, доступ к файлам, сети и т.д.).

**Пример манифеста (com.example.MyApp.yaml):**

```yaml
id: com.example.MyApp
runtime: org.freedesktop.Platform
runtime-version: '24.08'
sdk: org.freedesktop.Sdk
command: myapp

finish-args:
  # Доступ к домашней директории
  - --filesystem=home
  # Сеть
  - --share=network
  # Доступ к X11
  - --socket=x11
  # Доступ к Wayland
  - --socket=wayland
  # D-Bus
  - --talk-name=org.freedesktop.Notifications

modules:
  - name: myapp
    buildsystem: simple
    build-commands:
      - install -Dm755 myapp /app/bin/myapp
      - install -Dm644 packaging/myapp.desktop /app/share/applications/com.example.MyApp.desktop
      - install -Dm644 packaging/myapp.png /app/share/icons/hicolor/256x256/apps/com.example.MyApp.png
    sources:
      - type: file
        path: dist/myapp
      - type: file
        path: packaging/myapp.desktop
      - type: file
        path: packaging/myapp.png
```

```bash
# Сборка Flatpak
flatpak-builder --force-clean build-dir com.example.MyApp.yaml

# Тест
flatpak-builder --run build-dir com.example.MyApp.yaml myapp

# Создать и экспортировать .flatpak-файл
flatpak-builder --repo=repo --force-clean build-dir com.example.MyApp.yaml
flatpak build-bundle repo myapp.flatpak com.example.MyApp
```

#### Snap

**Документация**: https://snapcraft.io/docs/
**Репозиторий**: https://snapcraft.io/store

Snap включает все зависимости в пакет, работает под snapd. Поддерживает три уровня ограничений: `strict` (рекомендуется), `devmode`, `classic`.

**Пример snapcraft.yaml:**

```yaml
name: myapp
summary: My Application
description: |
  Подробное описание приложения.
  Несколько строк.
version: "1.2.3"
base: core24
grade: stable
confinement: strict

apps:
  myapp:
    command: bin/myapp
    plugs:
      - home
      - network
      - network-bind
      - removable-media
    environment:
      HOME: $SNAP_USER_DATA
      XDG_CONFIG_HOME: $SNAP_USER_DATA/.config

parts:
  myapp:
    plugin: dump
    source: dist/
    organize:
      myapp: bin/myapp
    stage-packages:
      - libssl3
      - libc6
```

```bash
# Установка snapcraft
sudo snap install snapcraft --classic

# Сборка snap-пакета
snapcraft

# Тестирование
snap install myapp_1.2.3_amd64.snap --dangerous

# Публикация
snapcraft upload myapp_1.2.3_amd64.snap --release=stable
```

#### Сравнение Flatpak vs Snap

| Критерий | Flatpak | Snap |
|----------|---------|------|
| Зависимости | Общие рантаймы | Всё в пакете |
| Размер пакета | Меньше | Больше |
| Производительность | Сопоставимо | Медленнее старт (squashfs) |
| Магазин | Flathub | Snap Store (Canonical) |
| Поддержка GUI | Отличная | Хорошая |
| CLI-приложения | Хуже | Лучше |
| Контроль | Сообщество | Canonical |

---

### 3.12 pkgbuild и productbuild (macOS)

**Документация Apple**: https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution

#### Описание

`pkgbuild` и `productbuild` — стандартные macOS-инструменты создания `.pkg`-установщиков. Доступны только в macOS (Xcode Command Line Tools). Из Linux их использовать невозможно напрямую; для CI нужен macOS-агент.

#### Создание .pkg и .dmg

```bash
# ---- Создание компонентного .pkg ----

# Структура для установки
mkdir -p payload/usr/local/bin
cp dist/myapp payload/usr/local/bin/myapp
chmod 755 payload/usr/local/bin/myapp

# Создать component package
pkgbuild \
  --root payload/ \
  --identifier com.example.myapp \
  --version 1.2.3 \
  --install-location / \
  --scripts packaging/macos/scripts/ \
  myapp-component.pkg

# ---- Создание product archive из нескольких компонентов ----

# distribution.xml описывает UI-установщика
cat > distribution.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>My Application</title>
    <license file="LICENSE.txt" mime-type="text/plain" />
    <readme file="README.txt" mime-type="text/plain" />
    <options customize="never" require-scripts="false" />
    <pkg-ref id="com.example.myapp"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.example.myapp"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.example.myapp" visible="false">
        <pkg-ref id="com.example.myapp"/>
    </choice>
    <pkg-ref id="com.example.myapp" version="1.2.3" onConclusion="none">myapp-component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild \
  --distribution distribution.xml \
  --resources packaging/macos/resources/ \
  --package-path . \
  MyApp-1.2.3.pkg

# ---- Universal Binary с lipo ----
lipo -create \
  -arch x86_64 dist/myapp-amd64 \
  -arch arm64 dist/myapp-arm64 \
  -output dist/myapp-universal

# Проверить архитектуры
lipo -info dist/myapp-universal
file dist/myapp-universal

# ---- Подпись кода ----
codesign \
  --deep \
  --force \
  --options runtime \
  --sign "Developer ID Application: MyCompany Ltd (TEAM_ID)" \
  dist/myapp-universal

# ---- Нотаризация ----
# Упаковать для нотаризации
ditto -c -k --keepParent dist/myapp-universal myapp.zip

# Отправить на нотаризацию Apple
xcrun notarytool submit myapp.zip \
  --apple-id "dev@example.com" \
  --team-id "ABCD123456" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Прикрепить статус нотаризации к pkg
xcrun stapler staple MyApp-1.2.3.pkg

# ---- Создание DMG ----
# Простой способ через hdiutil
mkdir dmg-staging
cp -r "My Application.app" dmg-staging/
ln -s /Applications dmg-staging/Applications

hdiutil create \
  -volname "My Application" \
  -srcfolder dmg-staging \
  -ov \
  -format UDZO \
  MyApp-1.2.3.dmg

# Подписать DMG
codesign \
  --sign "Developer ID Application: MyCompany Ltd (TEAM_ID)" \
  MyApp-1.2.3.dmg
```

#### Плюсы

- Нативные macOS-инструменты без внешних зависимостей
- Поддержка всех функций macOS-установщика
- Нотаризация через Apple Developer Program

#### Минусы

- Работают только на macOS — нельзя использовать из Linux
- Требуется платный Apple Developer аккаунт для нотаризации
- Нотаризация требует интернет-подключения к Apple серверам

---

## 4. Кросс-компиляция и сборка для других платформ

### 4.1 Сборка Windows-пакетов из Linux

#### Подход 1: nFPM — только для Linux-пакетов (не Windows)

nFPM не поддерживает Windows MSI/NSIS. Для Windows нужны другие инструменты.

#### Подход 2: NSIS (makensis) — нативная сборка под Linux

```bash
# Установить NSIS
sudo apt install nsis nsis-pluginapi

# Кросс-компиляция Windows-бинарника
GOOS=windows GOARCH=amd64 go build -o dist/myapp.exe ./cmd/myapp

# Или с MinGW для C/C++
sudo apt install gcc-mingw-w64-x86-64
x86_64-w64-mingw32-gcc -o dist/myapp.exe src/main.c

# Создать Windows-установщик из Linux
makensis myapp-installer.nsi
```

#### Подход 3: WiX Toolset как .NET global tool

```bash
# Установить .NET Runtime и WiX
sudo apt install dotnet-sdk-8.0
dotnet tool install --global wix --version 5.0.0

# Кросс-компиляция бинарника
GOOS=windows GOARCH=amd64 go build -o dist/myapp.exe ./cmd/myapp

# Собрать MSI
~/.dotnet/tools/wix build -arch x64 -o dist/myapp-1.2.3-x64.msi Package.wxs
```

#### Подход 4: msitools (wixl)

```bash
# Установить msitools
sudo apt install msitools

# Собрать MSI из WXS
wixl -a x64 -o dist/myapp-1.2.3-x64.msi Package.wxs
```

#### Подход 5: Inno Setup через Docker с Wine

```bash
docker run --rm \
  -v "$PWD:/work" \
  --workdir /work \
  amake/innosetup:6 \
  myapp.iss
```

#### Подпись Windows-исполняемых файлов из Linux

```bash
# osslsigncode — кросс-платформенная подпись Authenticode
sudo apt install osslsigncode

osslsigncode sign \
  -certs myapp.crt \
  -key myapp.key \
  -n "My Application" \
  -i "https://example.com" \
  -t "http://timestamp.digicert.com" \
  -in dist/myapp.exe \
  -out dist/myapp-signed.exe

# Подписать MSI
osslsigncode sign \
  -certs myapp.crt \
  -key myapp.key \
  -in dist/myapp.msi \
  -out dist/myapp-signed.msi
```

### 4.2 Сборка macOS-пакетов из Linux (ограничения)

Создание полноценных macOS-пакетов из Linux крайне ограничено:

- **Бинарники**: Возможно кросс-компилировать через `osxcross` (toolchain для macOS из Linux) или `zig cc --target aarch64-macos`.
- **`.app`-bundle**: Можно создать вручную (структура директорий + Info.plist).
- **`.pkg`/`.dmg`**: Невозможно без macOS — инструменты `pkgbuild` и `productbuild` не доступны на Linux.
- **Нотаризация**: Требует macOS и Apple Developer аккаунт.

**Рекомендуемый подход**: использовать macOS-агент в CI (GitHub Actions: `runs-on: macos-latest`) для финальной упаковки и нотаризации.

```bash
# osxcross — кросс-компиляция для macOS из Linux
# Сборка osxcross (требует MacOSX SDK)
git clone https://github.com/tpoechtrager/osxcross
# ... (требуется SDK из Xcode)

# Компиляция с Zig (проще, не требует SDK)
zig build-exe src/main.zig \
  -target aarch64-macos \
  -O ReleaseSafe \
  -femit-bin=dist/myapp-arm64

zig build-exe src/main.zig \
  -target x86_64-macos \
  -O ReleaseSafe \
  -femit-bin=dist/myapp-amd64

# Go кросс-компиляция
GOOS=darwin GOARCH=arm64 go build -o dist/myapp-arm64 ./cmd/myapp
GOOS=darwin GOARCH=amd64 go build -o dist/myapp-amd64 ./cmd/myapp
```

### 4.3 Сборка для arm64 из amd64 (QEMU, cross-compilation)

#### Метод 1: Прямая кросс-компиляция (Go, Rust, Zig)

```bash
# Go — встроенная поддержка кросс-компиляции
GOOS=linux GOARCH=arm64 go build -o dist/myapp-arm64 ./cmd/myapp

# Rust
rustup target add aarch64-unknown-linux-gnu
sudo apt install gcc-aarch64-linux-gnu
cargo build --target aarch64-unknown-linux-gnu --release

# Zig
zig build-exe src/main.zig \
  -target aarch64-linux-gnu \
  -O ReleaseSafe
```

#### Метод 2: QEMU User Mode + chroot

```bash
# Установить QEMU и binfmt
sudo apt install qemu-user-static binfmt-support

# Зарегистрировать binfmt-обработчики
sudo update-binfmts --enable qemu-aarch64

# Создать ARM64 chroot (например, через debootstrap)
sudo debootstrap \
  --arch=arm64 \
  --foreign \
  bookworm /chroot/arm64 \
  http://deb.debian.org/debian

sudo cp /usr/bin/qemu-aarch64-static /chroot/arm64/usr/bin/
sudo chroot /chroot/arm64 /debootstrap/debootstrap --second-stage

# Собрать пакет внутри chroot
sudo chroot /chroot/arm64 bash -c "
  apt install -y build-essential
  cd /build
  make
  dpkg-buildpackage -b
"
```

#### Метод 3: Docker multi-platform (buildx)

```bash
# Установить Docker buildx с QEMU
docker run --privileged --rm tonistiigi/binfmt --install all

# Многоплатформенная сборка Docker-образа
docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  -t mycompany/myapp:latest \
  --push \
  .

# Извлечь артефакты из образа
docker buildx build \
  --platform linux/arm64 \
  --output type=local,dest=./dist/arm64 \
  .
```

---

## 5. Сравнительная таблица инструментов

| Инструмент | DEB | RPM | APK | Windows MSI | Windows EXE | macOS PKG | macOS DMG | AppImage | Flatpak | Snap |
|------------|:---:|:---:|:---:|:-----------:|:-----------:|:---------:|:---------:|:--------:|:-------:|:----:|
| **nFPM** | + | + | + | - | - | - | - | - | - | - |
| **fpm** | + | + | - | - | - | + | - | - | - | + |
| **GoReleaser** | + | + | + | - | - | - | - | - | - | - |
| **CPack** | + | + | - | + | - | + | + | - | - | - |
| **cargo-deb** | + | - | - | - | - | - | - | - | - | - |
| **cargo-generate-rpm** | - | + | - | - | - | - | - | - | - | - |
| **msitools** | - | - | - | + | - | - | - | - | - | - |
| **WiX Toolset** | - | - | - | + | - | - | - | - | - | - |
| **NSIS** | - | - | - | - | + | - | - | - | - | - |
| **Inno Setup** | - | - | - | - | + | - | - | - | - | - |
| **appimagetool** | - | - | - | - | - | - | - | + | - | - |
| **flatpak-builder** | - | - | - | - | - | - | - | - | + | - |
| **snapcraft** | - | - | - | - | - | - | - | - | - | + |
| **pkgbuild/productbuild** | - | - | - | - | - | + | + | - | - | - |

| Инструмент | Язык реализации | Зависимости | Linux CI | Кросс-платформа | Сложность |
|------------|-----------------|-------------|----------|-----------------|-----------|
| **nFPM** | Go | Нет (1 бинарник) | Отлично | Да | Низкая |
| **fpm** | Ruby | Ruby + RubyGems | Хорошо | Частично | Низкая |
| **GoReleaser** | Go | Нет | Отлично | Да | Средняя |
| **CPack** | CMake | CMake | Хорошо | Да | Высокая |
| **cargo-deb/rpm** | Rust | Cargo | Хорошо | Частично | Низкая |
| **WiX (v5)** | .NET | .NET Runtime | Хорошо | Да (.NET) | Высокая |
| **msitools** | C (GNOME) | GLib | Хорошо | Linux→Win | Средняя |
| **NSIS** | C++ | Нет | Хорошо | Linux→Win | Средняя |
| **Inno Setup** | Delphi/Pascal | Wine/Docker | Возможно | Через Wine | Средняя |
| **appimagetool** | C++ | Нет | Хорошо | Нет | Низкая |
| **flatpak-builder** | C | flatpak | Хорошо | Нет | Средняя |
| **snapcraft** | Python | snapd | Хорошо | Нет | Средняя |

---

## 6. Рекомендации по выбору инструмента

### Для Go-проектов

Используйте **GoReleaser** как оркестратор всего пайплайна. Он интегрирует nFPM для Linux-пакетов, управляет сборкой бинарников для всех платформ, создаёт Homebrew-формулы и Scoop-бакеты:

```yaml
# В CI (GitHub Actions)
- uses: goreleaser/goreleaser-action@v6
  with:
    version: latest
    args: release --clean
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    GPG_KEY_FILE: ${{ secrets.GPG_KEY_FILE }}
```

### Для Rust-проектов

- **cargo-deb** для `.deb` — минимальная конфигурация, всё в `Cargo.toml`
- **cargo-generate-rpm** для `.rpm`
- Для Windows и macOS — дополнительные инструменты (NSIS, WiX, productbuild)

### Для C/C++-проектов с CMake

Используйте **CPack** — уже встроен в систему сборки. Добавьте `include(CPack)` и настройте нужные генераторы.

### Для создания только Linux-пакетов (без Go)

**nFPM** — лучший выбор. Один бинарник, один YAML-файл, все форматы.

### Для создания Windows-установщиков из Linux

1. Если нужен `.msi`: **WiX Toolset** как .NET global tool или **msitools** (wixl) для простых случаев.
2. Если нужен `.exe`: **NSIS** (makensis работает нативно на Linux) или **Inno Setup** через Docker+Wine.
3. Для подписи: **osslsigncode**.

### Для создания macOS-пакетов

Полноценная сборка возможна только на macOS. Используйте GitHub Actions с `runs-on: macos-latest`:

```yaml
jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: make build-macos
      - name: Sign
        run: |
          codesign --deep --force --sign "${{ secrets.APPLE_SIGN_ID }}" dist/myapp
      - name: Package
        run: pkgbuild --root payload/ --identifier com.example.myapp myapp.pkg
      - name: Notarize
        run: |
          xcrun notarytool submit myapp.pkg \
            --apple-id "${{ secrets.APPLE_ID }}" \
            --team-id "${{ secrets.APPLE_TEAM_ID }}" \
            --password "${{ secrets.APPLE_PASSWORD }}" \
            --wait
```

### Для "portable" Linux-дистрибуции (без root)

Используйте **AppImage** для графических приложений. Для CLI-инструментов — просто статически слинкованный бинарник (особенно удобно с Go: `CGO_ENABLED=0`).

### Для магазинов и universal Linux

- **Flatpak + Flathub**: предпочтительно для GUI-приложений в 2025 году
- **Snap Store**: если целевая аудитория — Ubuntu-пользователи

### Общая стратегия для CI/CD пайплайна

Типичный многоплатформенный CI-пайплайн выглядит так:

```
Linux CI-агент (amd64):
├── go build / cargo build / cmake
├── nFPM → .deb, .rpm, .apk
├── makensis → Windows .exe (NSIS)
├── wix build → Windows .msi
├── appimagetool → .AppImage
└── snapcraft → .snap

macOS CI-агент:
├── go build (darwin/amd64, darwin/arm64)
├── lipo → universal binary
├── codesign → подпись
├── pkgbuild + productbuild → .pkg
├── hdiutil → .dmg
└── xcrun notarytool → нотаризация
```

Такой подход позволяет максимально использовать Linux как основную платформу сборки, прибегая к macOS-агенту только для операций, требующих Apple-специфичных инструментов.

---

*Документ подготовлен на основе официальной документации инструментов и актуального состояния экосистемы по состоянию на начало 2026 года.*

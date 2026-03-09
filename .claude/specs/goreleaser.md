# GoReleaser — Полное руководство

> Исследование проведено для понимания возможностей GoReleaser как референсного инструмента при разработке Crossler.

---

## 1. Общее назначение и концепция

**GoReleaser** — инструмент автоматизации выпуска программного обеспечения с девизом «Release engineering, simplified». Основная идея: разработчик описывает параметры релиза в единый конфиг-файл `.goreleaser.yaml`, а GoReleaser сам выполняет весь процесс — от компиляции до публикации в реестры пакетов и объявления в мессенджерах.

### Ключевые принципы

- **Единый конфиг** — весь процесс релиза описывается в одном `.goreleaser.yaml`, который коммитится в репозиторий.
- **Полиязычность** — изначально создавался для Go, но поддерживает Rust, Zig, Bun, Deno, Python (UV, Poetry).
- **Кроссплатформенность** — одной командой собирается для Linux, macOS, Windows × amd64/arm64 и других архитектур.
- **Расширяемость** — любой шаг можно заменить кастомным хуком или внешней командой.
- **Безопасность** — встроенная генерация SBOM, подпись артефактов (GPG, cosign, Authenticode, Apple Code Signing).
- **CI-first** — спроектирован для запуска внутри GitHub Actions, GitLab CI и других CI-систем.

### Две версии: OSS и Pro

GoReleaser существует в двух вариантах. **OSS** — бесплатная версия с открытым исходным кодом, покрывает большинство задач. **Pro** — платная версия с расширенными возможностями:

- Создание `.pkg` (macOS), `.msi` (Windows через WiX), `.exe` (NSIS), `.dmg`, App Bundles
- Нативная подпись и нотаризация macOS-пакетов
- AI-powered changelog (Anthropic, OpenAI, Ollama)
- Nightly builds, Split & Merge для параллельной сборки
- Template files, кастомные переменные шаблонов
- Podman, NPM publishing, CloudSmith, GemFury

---

## 2. Установка

```bash
# Homebrew (macOS/Linux)
brew install goreleaser

# Go
go install github.com/goreleaser/goreleaser/v2@latest

# npm
npm i -g @goreleaser/goreleaser

# Docker
docker run --rm goreleaser/goreleaser release

# Snap
sudo snap install --classic goreleaser

# AUR (Arch Linux)
yay -S goreleaser-bin

# Apt/Yum (Linux) — через репозиторий GoReleaser
```

---

## 3. Команды CLI

### Основные команды

| Команда | Описание |
|---------|----------|
| `goreleaser init` | Генерирует `.goreleaser.yaml` с начальной конфигурацией |
| `goreleaser check` | Валидирует конфиг-файл |
| `goreleaser healthcheck` | Проверяет наличие всех необходимых внешних инструментов |
| `goreleaser build` | Собирает бинарники (без упаковки и публикации) |
| `goreleaser release` | Полный цикл: сборка → упаковка → публикация |
| `goreleaser changelog` | Предпросмотр changelog |
| `goreleaser continue` | Продолжает прерванный релиз (Pro) |
| `goreleaser publish` | Публикует подготовленный релиз (Pro) |
| `goreleaser announce` | Объявляет о подготовленном релизе (Pro) |
| `goreleaser completion` | Генерирует автодополнение для shell |
| `goreleaser jsonschema` | Выводит JSON Schema конфига |

### Флаги `goreleaser release`

| Флаг | Описание |
|------|----------|
| `--snapshot` | Сборка без публикации, без проверки тега |
| `--auto-snapshot` | Автоматически включает `--snapshot` при грязном репозитории |
| `--clean` | Удаляет директорию `dist` перед сборкой |
| `--draft` | Создаёт релиз как черновик |
| `--skip strings` | Пропускает указанные этапы (validate, before, build, archive, package, publish, announce, ...) |
| `--fail-fast` | Прерывает при первой ошибке |
| `-f, --config string` | Путь к конфиг-файлу |
| `-p, --parallelism int` | Число параллельных задач (по умолчанию: число CPU) |
| `--timeout duration` | Тайм-аут всего процесса (по умолчанию: 1h) |
| `--release-notes string` | Кастомный текст заметок релиза |
| `--release-notes-tmpl string` | Заметки из шаблона |
| `--release-header string` | Заголовок заметок |
| `--release-footer string` | Подвал заметок |
| `--prepare` | Подготовить релиз без публикации (Pro) |
| `--split` | Разделённая сборка для последующего merge (Pro) |
| `--id stringArray` | Собирать только указанные build IDs (Pro) |
| `--single-target` | Сборка только для текущей платформы (Pro) |
| `-k, --key string` | Лицензионный ключ GoReleaser Pro |
| `--verbose` | Подробный вывод |

### Флаги `goreleaser build`

| Флаг | Описание |
|------|----------|
| `--single-target` | Только для текущих GOOS/GOARCH |
| `--id stringArray` | Только указанные build IDs |
| `-o, --output string` | Скопировать бинарник по пути (только с --single-target) |
| `--snapshot` | Снапшот без проверки тегов |
| `--auto-snapshot` | Автоматический снапшот при грязном репо |
| `--clean` | Удалить dist перед сборкой |
| `--skip strings` | Пропустить: after, before, pre-hooks, post-hooks, validate, report-sizes |
| `--timeout duration` | Тайм-аут (по умолчанию: 1h) |
| `-p, --parallelism int` | Параллелизм |

---

## 4. Архитектура и порядок шагов релиза

При выполнении `goreleaser release` шаги выполняются в следующем порядке:

1. **Validate** — проверка конфига, тега, чистоты репозитория
2. **Before hooks** — глобальные хуки `before.hooks` (go mod tidy, go generate и т.д.)
3. **Build** — компиляция бинарников для всех таргетов
4. **Universal binaries** — объединение macOS amd64+arm64 в fat binary (опционально)
5. **UPX** — сжатие бинарников (опционально)
6. **Archives** — упаковка в tar.gz / zip / binary
7. **Linux packages** (nfpm) — создание .deb, .rpm, .apk, .ipk, .pkg.tar.zst
8. **Snapcraft** — создание Snap-пакетов
9. **macOS pkg** — создание .pkg через pkgbuild
10. **MSI** — создание .msi через WiX
11. **NSIS** — создание .exe-инсталлятора
12. **DMG** — создание .dmg образа
13. **App Bundles** — создание .app
14. **Source archive** — архив исходных кодов
15. **SBOM** — генерация Software Bill of Materials
16. **Checksums** — вычисление контрольных сумм
17. **Signing** — подпись архивов/пакетов/бинарников (GPG, cosign)
18. **Binary signing** — подпись отдельных бинарников
19. **Docker** — сборка и push Docker-образов
20. **Ko** — сборка контейнеров через ko
21. **Publish** — публикация Release на GitHub/GitLab/Gitea + загрузка артефактов
22. **Blobs** — загрузка в S3 / Azure / GCS
23. **Upload** — кастомная загрузка через HTTP
24. **Homebrew formulas** — обновление tap-репозитория
25. **Scoop manifests** — обновление Scoop bucket
26. **AUR packages** — обновление AUR PKGBUILD
27. **Winget manifests** — обновление winget-pkgs
28. **Nix derivations** — обновление Nix User Repository
29. **Announce** — объявление в Discord, Slack, Mastodon и т.д.

Каждый шаг можно пропустить через `--skip` или отдельные поля `skip:` в конфиге.

---

## 5. Конфигурационный файл `.goreleaser.yaml`

### Полная структура верхнего уровня

```yaml
version: 2                    # Версия схемы конфига (обязательно для v2)
project_name: myapp           # Имя проекта (используется в именах архивов, формул и т.д.)
dist: dist                    # Директория для артефактов (по умолчанию: dist)

# Метаданные проекта
metadata:
  mod_timestamp: "{{ .CommitTimestamp }}"
  maintainers:               # Pro
    - "Name <email>"
  license: "MIT"             # Pro, SPDX идентификатор
  homepage: "https://..."    # Pro
  description: "..."         # Pro

# Глобальные переменные окружения
env:
  - FOO=bar
  - ENV={{ .Env.SOME_VAR }}

# Глобальные хуки до/после релиза
before:
  hooks:
    - go mod tidy
    - go generate ./...
after:                       # Pro
  hooks:
    - make clean

# Git-настройки
git:
  tag_sort: semver
  prerelease_suffix: "-"
  ignore_tags: []

# Сборка
builds: [...]

# macOS Universal Binaries
universal_binaries: [...]

# UPX сжатие
upx: [...]

# Архивы
archives: [...]

# Linux-пакеты (nfpm)
nfpms: [...]

# macOS .pkg
pkgs: [...]

# macOS .dmg
dmgs: [...]                  # Pro

# Windows .msi
msi: [...]                   # Pro

# Windows .exe (NSIS)
nsis: [...]                  # Pro

# macOS App Bundles
app_bundles: [...]           # Pro

# Snap-пакеты
snapcrafts: [...]

# Snap-пакеты v2
dockers_v2: [...]

# Source archive
source:
  enabled: false

# SBOM
sboms: [...]

# Checksums
checksum:
  name_template: "{{ .ProjectName }}_{{ .Version }}_checksums.txt"
  algorithm: sha256

# Подпись архивов
signs: [...]

# Подпись бинарников
binary_signs: [...]

# Подпись Docker-образов
docker_signs: [...]

# macOS нотаризация
notarize:
  macos: [...]

# Docker-образы
dockers: [...]
docker_manifests: [...]

# Ko (контейнеры)
kos: [...]

# Changelog
changelog:
  use: git

# Snapshot-настройки
snapshot:
  version_template: "{{ incpatch .Version }}-devel"

# Release (GitHub/GitLab/Gitea)
release:
  github:
    owner: user
    name: repo

# Blobs (S3/Azure/GCS)
blobs: [...]

# Custom upload
uploads: [...]

# Custom publishers
publishers: [...]

# Homebrew формулы
brews: [...]

# Homebrew casks
homebrew_casks: [...]        # Pro

# Scoop manifests
scoops: [...]

# AUR packages
aurs: [...]

# AUR source packages
aursources: [...]

# Winget manifests
winget: [...]

# Nix derivations
nix: [...]

# Krew plugin manifests
krews: [...]

# NPM packages
npm: [...]                   # Pro

# Artifactory
artifactories: [...]

# GemFury
gemfuries: [...]             # Pro

# CloudSmith
cloudsmithes: [...]          # Pro

# Announce
announce:
  slack: ...
  discord: ...
  mastodon: ...
  twitter: ...
  telegram: ...

# Includes (переиспользование конфигов)
includes: [...]              # Pro

# Частичная сборка (Split & Merge)
partial:
  by: target                 # Pro

# Nightly сборки
nightlies: [...]             # Pro

# Report sizes
report_sizes: true
```

---

## 6. Секция `builds` — сборка

GoReleaser поддерживает несколько строителей (builders). Каждый элемент в `builds` — отдельная конфигурация сборки.

### Go builder (основной)

```yaml
builds:
  - id: myapp                     # Уникальный ID (по умолчанию: имя директории)
    builder: go                   # Тип строителя (по умолчанию: go)

    # Исходники
    main: .                       # Путь к main.go или пакету (по умолчанию: .)
    dir: .                        # Рабочая директория с кодом

    # Выходной файл
    binary: myapp                 # Имя бинарника (поддерживает шаблоны)

    # Целевые платформы
    goos:
      - linux
      - darwin
      - windows
    goarch:
      - amd64
      - arm64
      - "386"
    goarm:
      - "6"
      - "7"
    goamd64:
      - v1
      - v2
      - v3
    goarm64:
      - v8.0
    gomips:
      - hardfloat
      - softfloat
    go386:
      - sse2
      - softfloat
    goppc64:
      - power8
    goriscv64:
      - rva20u64

    # Переопределение матрицы
    targets:                      # Явный список таргетов вместо матрицы
      - linux_amd64_v1
      - darwin_arm64
      - go_first_class            # Первоклассные таргеты Go

    # Исключения из матрицы
    ignore:
      - goos: windows
        goarch: arm64
      - goos: darwin
        goarch: "386"

    # Флаги компиляции
    flags:
      - -trimpath
      - -v
    ldflags:
      - -s -w
      - -X main.version={{.Version}}
      - -X main.commit={{.Commit}}
      - -X main.date={{.Date}}
    gcflags:
      - all=-trimpath={{.Env.GOPATH}}
    asmflags:
      - all=-trimpath={{.Env.GOPATH}}
    tags:
      - netgo
      - osusergo

    # Режим сборки
    buildmode: pie                # c-shared, c-archive, pie и т.д.
    command: build                # Команда (по умолчанию: build)
    tool: go1.22                  # Конкретная версия Go

    # Переменные окружения
    env:
      - CGO_ENABLED=0
      - CC=musl-gcc

    # Временная метка для воспроизводимости
    mod_timestamp: "{{ .CommitTimestamp }}"

    # Опции
    no_unique_dist_dir: false     # Не создавать уникальную директорию на таргет
    no_main_check: false          # Не проверять наличие функции main

    # Хуки до/после сборки
    hooks:
      pre:
        - cmd: rice embed-go
      post:
        - cmd: ./sign.sh {{ .Path }}
          env:
            - SIGNING_KEY={{ .Env.SIGNING_KEY }}

    # Условный пропуск
    skip: false

    # Переопределения для конкретных таргетов (CGO и т.д.)
    overrides:
      - goos: windows
        goarch: amd64
        env:
          - CGO_ENABLED=1
          - CC=x86_64-w64-mingw32-gcc
        ldflags:
          - -s -w
```

### Другие строители

```yaml
builds:
  # Rust
  - builder: rust
    binary: myapp
    targets:
      - x86_64-unknown-linux-gnu
      - aarch64-apple-darwin

  # Zig
  - builder: zig
    binary: myapp
    targets:
      - target: x86_64-linux-gnu
      - target: aarch64-macos

  # Bun
  - builder: bun
    binary: myapp

  # Deno
  - builder: deno
    binary: myapp
    main: main.ts

  # Pre-built (импорт готовых бинарников)
  - builder: prebuilt               # Pro
    goos: [linux, darwin, windows]
    goarch: [amd64, arm64]
    prebuilt:
      path: ./bin/{{ .Os }}_{{ .Arch }}/{{ .ProjectName }}
```

---

## 7. Секция `archives` — упаковка в архивы

```yaml
archives:
  - id: default                     # Уникальный ID

    # Фильтр по builds
    ids:
      - myapp

    # Форматы (можно несколько)
    formats:
      - tar.gz
      - zip
    # Устаревшее: format: tar.gz

    # Переопределение формата по ОС
    format_overrides:
      - goos: windows
        formats: [zip]

    # Имя архива (шаблон)
    name_template: >-
      {{ .ProjectName }}_
      {{- title .Os }}_
      {{- if eq .Arch "amd64" }}x86_64
      {{- else if eq .Arch "386" }}i386
      {{- else }}{{ .Arch }}{{ end }}

    # Обернуть все файлы в одну директорию
    wrap_in_directory: true         # true/false/"{{ .ProjectName }}"

    # Убрать родительские директории из бинарников
    strip_binary_directory: true

    # Дополнительные файлы в архив
    files:
      - LICENSE
      - README.md
      - CHANGELOG.md
      - completions/*
      - docs/**/*.md
      - src: "*.cfg"
        dst: config/
        strip_parent: true
        info:
          owner: root
          group: root
          mode: 0644
          mtime: "{{ .CommitDate }}"

    # Шаблонизированные файлы (Pro)
    templated_files:
      - src: .goreleaser.yaml
        dst: goreleaser.yaml

    # Метаданные файлов по умолчанию
    builds_info:
      group: root
      owner: root
      mode: 0755
      mtime: "{{ .CommitDate }}"

    # Хуки (Pro)
    hooks:
      before:
        - cmd: make completions
      after:
        - cmd: ./post-archive.sh {{ .Path }}

    # Не включать стандартные файлы
    # (установить files: [none*])

    # Формат binary — просто бинарник без архива
    # formats: [binary]
```

### Поддерживаемые форматы архивов

| Формат | Описание |
|--------|----------|
| `tar.gz`, `tgz` | Gzip-сжатый tar (по умолчанию на Linux/macOS) |
| `tar.xz`, `txz` | XZ-сжатый tar |
| `tar.zst`, `tzst` | Zstandard-сжатый tar |
| `tar` | Несжатый tar |
| `gz` | Gzip (один файл) |
| `zip` | ZIP-архив (по умолчанию на Windows) |
| `binary` | Без архивирования, просто бинарник |

---

## 8. Секция `nfpms` — Linux-пакеты

```yaml
nfpms:
  - id: myapp

    # Фильтр по builds
    ids:
      - myapp

    # Имя пакета
    package_name: myapp

    # Шаблон имени файла
    file_name_template: "{{ .ConventionalFileName }}"

    # Форматы для сборки
    formats:
      - deb
      - rpm
      - apk
      - archlinux
      - ipk

    # Метаданные
    vendor: "My Company"
    homepage: "https://example.com"
    maintainer: "Name <email@example.com>"
    description: "My application"
    license: "MIT"

    # Путь установки бинарника
    bindir: /usr/bin

    # Версионирование
    epoch: 0
    prerelease: ""
    version_metadata: ""
    release: "1"
    mtime: "{{ .CommitDate }}"

    # Зависимости
    dependencies:
      - git
    provides:
      - myapp
    recommends:
      - curl
    suggests:
      - jq
    conflicts:
      - myapp-legacy
    replaces:
      - myapp-old

    # Файлы пакета
    contents:
      # Бинарник (добавляется автоматически)

      # Конфигурационный файл
      - src: config.yaml
        dst: /etc/myapp/config.yaml
        type: config|noreplace

      # Документация
      - src: README.md
        dst: /usr/share/doc/myapp/README.md

      # Symlink
      - src: /usr/bin/myapp
        dst: /usr/local/bin/myapp
        type: symlink

      # Директория
      - dst: /var/lib/myapp
        type: dir
        file_info:
          mode: 0750

      # Ghost-файл (только RPM — объявление, но не установка)
      - dst: /var/log/myapp.log
        type: ghost

    # Скрипты установки/удаления
    scripts:
      preinstall: scripts/preinstall.sh
      postinstall: scripts/postinstall.sh
      preremove: scripts/preremove.sh
      postremove: scripts/postremove.sh

    # Changelog
    changelog: .goreleaser-changelog.yaml

    # Секция, приоритет, umask
    section: utils
    priority: optional
    umask: 0o002

    # Специфика форматов:

    overrides:
      deb:
        dependencies: [libc6]
        contents:
          - src: deb-specific.conf
            dst: /etc/myapp/deb.conf
        deb:
          lintian_overrides:
            - "statically-linked-binary"
          compression: xz       # gzip, xz, zstd, none
          triggers:
            interest_await:
              - /usr/share/myapp
          predepends:
            - dpkg (>= 1.16.1)

      rpm:
        dependencies: [glibc]
        rpm:
          summary: "My App Summary"
          group: "Applications/System"
          compression: lzma     # gzip, lzma, xz
          prefixes:
            - /usr
          scripts:
            pretrans: scripts/pretrans.sh
            posttrans: scripts/posttrans.sh

      apk:
        apk:
          scripts:
            preupgrade: scripts/preupgrade.sh
            postupgrade: scripts/postupgrade.sh

      archlinux:
        archlinux:
          pkgbase: myapp
          packager: "Name <email>"
          scripts:
            preupgrade: scripts/preupgrade.sh
            postupgrade: scripts/postupgrade.sh
```

### Поддерживаемые форматы nfpm

| Формат | Дистрибутив |
|--------|-------------|
| `deb` | Debian, Ubuntu и производные |
| `rpm` | RHEL, Fedora, CentOS, SUSE |
| `apk` | Alpine Linux |
| `archlinux` | Arch Linux |
| `ipk` | OpenWrt и embedded Linux |
| `termux.deb` | Android Termux |

---

## 9. Секция `checksum` — контрольные суммы

```yaml
checksum:
  name_template: "{{ .ProjectName }}_{{ .Version }}_checksums.txt"
  algorithm: sha256             # sha256, sha512, sha1, sha224, sha384, sha3, blake2, crc32, md5
  split: false                  # Создать отдельный файл на каждый артефакт
  ids: []                       # Пустой = все опубликованные артефакты
  disable: false
  extra_files:
    - glob: ./path/to/file.txt
```

---

## 10. Секция `signs` — подпись артефактов

```yaml
signs:
  - id: default
    # Тип артефактов для подписи
    # all, archive, binary, checksum, source, package, installer, diskimage, sbom
    artifacts: checksum

    # Фильтр по IDs
    ids:
      - foo

    # Команда подписи
    cmd: gpg
    args:
      - "--batch"
      - "--local-user"
      - "{{ .Env.GPG_FINGERPRINT }}"
      - "--output"
      - "${signature}"
      - "--detach-sign"
      - "${artifact}"

    # Переменные в args:
    # ${artifact}    — путь к подписываемому файлу
    # ${signature}   — имя файла подписи
    # ${certificate} — имя файла сертификата
    # ${artifactID}  — ID артефакта

    # Шаблон имени подписи
    signature: "${artifact}.sig"
    certificate: "${artifact}.pem"

    # stdin для пароля
    stdin: "{{ .Env.GPG_PASSWORD }}"
    stdin_file: ./.gpg-password

    # Переменные окружения
    env:
      - FOO=bar

    # Показывать вывод команды
    output: true

    # Условное выполнение (Pro)
    if: '{{ eq .Os "linux" }}'
```

### Подпись через cosign

```yaml
signs:
  - cmd: cosign
    certificate: "${artifact}.pem"
    args:
      - sign-blob
      - "--key=cosign.key"
      - "--output-certificate=${certificate}"
      - "--output-signature=${signature}"
      - "${artifact}"
      - "--yes"
    artifacts: checksum
    output: true
```

---

## 11. Секция `binary_signs` — подпись бинарников

```yaml
binary_signs:
  - id: foo
    artifacts: binary             # none или binary
    cmd: gpg
    args:
      - "--output"
      - "${signature}"
      - "--detach-sign"
      - "${artifact}"
    signature: "${artifact}_sig"
    ids:
      - build1
    env:
      - GPG_TTY=/dev/pts/0
    if: '{{ eq .Os "linux" }}'   # Pro
    stdin: "{{ .Env.GPG_PASSWORD }}"
```

---

## 12. Секция `notarize` — нотаризация macOS

### Метод 1: кроссплатформенный (Anchore Quill)

Работает на любой ОС, только для бинарников и universal binaries.

```yaml
notarize:
  macos:
    - enabled: true
      ids:
        - myapp
      sign:
        certificate: "{{ .Env.MACOS_SIGN_P12 }}"     # путь или base64 .p12
        password: "{{ .Env.MACOS_SIGN_PASSWORD }}"
        entitlements: entitlements.plist               # опционально
      notarize:
        issuer_id: "{{ .Env.MACOS_NOTARY_ISSUER_ID }}"
        key_id: "{{ .Env.MACOS_NOTARY_KEY_ID }}"
        key: "{{ .Env.MACOS_NOTARY_KEY }}"           # путь или base64 .p8
        wait: true
        timeout: 20m
```

### Метод 2: нативный macOS

Только на macOS, поддерживает DMG и PKG.

```yaml
notarize:
  macos:
    - enabled: true
      use: dmg                    # dmg или pkg
      ids:
        - myapp
      sign:
        keychain: ~/Library/Keychains/login.keychain-db
        identity: "Developer ID Application: ..."
        options: ["runtime"]
        entitlements: entitlements.plist
      notarize:
        profile_name: "MyNotaryProfile"
        wait: true
```

---

## 13. Секция `release` — публикация GitHub/GitLab/Gitea

```yaml
release:
  # GitHub
  github:
    owner: myorg
    name: myrepo

  # GitLab
  # gitlab:
  #   owner: myorg
  #   name: myrepo

  # Gitea
  # gitea:
  #   owner: myorg
  #   name: myrepo
  #   url: https://gitea.example.com

  # Режим работы при существующем релизе
  mode: keep-existing             # keep-existing, append, prepend, replace

  # Черновик (только GitHub и Gitea)
  draft: false

  # Пре-релиз
  prerelease: auto                # auto, true, false

  # Помечать как latest (только GitHub)
  make_latest: true

  # Категория Discussion
  discussion_category_name: ""

  # Кастомное имя релиза
  name_template: "{{.ProjectName}}-v{{.Version}}"

  # Заголовок/подвал в описании
  header: |
    ## What's new
  footer: |
    ## Thanks to all contributors!

  # Дополнительные файлы
  extra_files:
    - glob: ./path/to/extra/files/*

  # Фильтр по IDs
  ids:
    - default

  # Пропустить загрузку (только создать релиз)
  skip_upload: false

  # Режим замены файлов при append/prepend
  replace_existing_draft: false
  replace_existing_artifacts: false
  target_commitish: "{{ .FullCommit }}"

  disable_generator: false        # Не использовать автоматический changelog
```

---

## 14. Секция `changelog` — история изменений

```yaml
changelog:
  # Источник данных
  # git: из git log
  # github: из GitHub PR
  # gitlab: из GitLab MR
  # gitea: из Gitea
  # github-native: GitHub release notes API
  use: github

  # Отключить changelog
  disable: false

  # Сортировка: asc, desc, ""
  sort: asc
  abbrev: 0                       # Длина сокращённого хеша (0 = не сокращать)

  # Формат строки (шаблон)
  format: "{{.SHA}}: {{.Message}} (@{{.AuthorUsername}})"

  # Фильтры
  filters:
    include:
      - "^feat:"
      - "^fix:"
    exclude:
      - "^chore:"
      - "^docs:"
      - typo

  # Группировка по типу коммита
  groups:
    - title: "New Features"
      regexp: "^feat"
      order: 0
    - title: "Bug Fixes"
      regexp: "^fix"
      order: 1
    - title: "Other Changes"
      order: 999                  # Последняя группа — все остальные

  # AI-суммаризация (Pro)
  # ai:
  #   provider: openai
  #   model: gpt-4o-mini
  #   api_key: "{{ .Env.OPENAI_API_KEY }}"

  # Фильтрация по путям (Pro)
  # paths:
  #   - src/myapp/
```

---

## 15. Секция `snapshot` — нерелизные сборки

```yaml
snapshot:
  # Шаблон версии для --snapshot
  version_template: "{{ incpatch .Version }}-devel"
  # По умолчанию: {{ .Version }}-SNAPSHOT-{{.ShortCommit}}
```

---

## 16. Секция `brews` — Homebrew формулы

```yaml
brews:
  - name: myapp                   # По умолчанию: project_name

    # Откуда брать артефакты
    ids:
      - default
    goamd64: v1
    goarm: "6"

    # Tap-репозиторий
    repository:
      owner: myorg
      name: homebrew-tap
      branch: main
      token: "{{ .Env.HOMEBREW_TAP_GITHUB_TOKEN }}"

    directory: Formula            # Поддиректория в репозитории

    # Метаданные
    homepage: "https://example.com"
    description: "My awesome app"
    license: "MIT"
    caveats: "Run `myapp --help` to get started"

    # Зависимости
    dependencies:
      - name: git
      - name: openssl
        type: optional
        os: mac
        version: "3"
    conflicts:
      - myapp-legacy

    # Пользовательские URL
    url_template: "https://github.com/{{ .Env.GITHUB_REPOSITORY }}/releases/download/{{ .Tag }}/{{ .ArtifactName }}"
    download_strategy: ""

    # Сервис (launchd)
    service: |
      run [opt_bin/"myapp", "serve"]
      keep_alive true
      log_path var/"log/myapp.log"

    # Тесты
    test: |
      system "#{bin}/myapp --version"

    # Установка (обычно автоматическая)
    install: |
      bin.install "myapp"

    # Дополнительная установка
    extra_install: |
      bash_completion.install "completions/bash/myapp"

    post_install: ""
    custom_block: ""

    commit_msg_template: "chore: update {{ .ProjectName }} formula to {{ .Tag }}"
    skip_upload: auto             # auto — пропустить для pre-release
```

---

## 17. Секция `scoops` — Scoop (Windows)

```yaml
scoops:
  - name: myapp

    # Репозиторий
    repository:
      owner: myorg
      name: scoop-bucket

    # Формат: archive, msi, nsis
    use: archive

    # Метаданные
    homepage: "https://example.com"
    description: "My awesome app"
    license: "MIT"

    depends: []
    shortcuts: [["myapp.exe", "My App"]]
    persist: ["data"]
    pre_install: []
    post_install: []

    commit_msg_template: "chore: update myapp to {{ .Tag }}"
    skip_upload: auto
```

---

## 18. Секция `aurs` — AUR (Arch Linux)

```yaml
aurs:
  - name: myapp-bin              # Суффикс -bin обязателен по правилам AUR

    # SSH-ключ для коммита в AUR
    private_key: "{{ .Env.AUR_KEY }}"
    git_url: "ssh://aur@aur.archlinux.org/myapp-bin.git"

    # Метаданные
    homepage: "https://example.com"
    description: "My app"
    license: ["MIT"]

    maintainers:
      - "Name <email at example dot org>"

    depends:
      - glibc
    optdepends:
      - "docker: for container support"
    provides:
      - myapp
    conflicts:
      - myapp

    # Файлы для резервного копирования при обновлении
    backup:
      - etc/myapp/config.yaml

    # Кастомная установка (опционально)
    package: |-
      install -Dm755 "./myapp" "${pkgdir}/usr/bin/myapp"
      install -Dm644 "./LICENSE" "${pkgdir}/usr/share/licenses/myapp/LICENSE"

    commit_msg_template: "Update to {{ .Tag }}"
    skip_upload: auto
```

---

## 19. Секция `winget` — Windows Package Manager

```yaml
winget:
  - name: MyApp
    package_identifier: MyOrg.MyApp
    package_name: My Application

    publisher: My Organization
    publisher_url: "https://example.com"
    publisher_support_url: "https://github.com/myorg/myapp/issues"

    homepage: "https://example.com"
    description: "My awesome application"
    short_description: "My app"
    license: "MIT"
    license_url: "https://github.com/myorg/myapp/blob/main/LICENSE"
    copyright: "Copyright (c) My Org"

    tags:
      - cli
      - tool

    # Формат: msi, nsis, archive, binary
    use: msi

    release_notes: "{{ .Changelog }}"
    release_notes_url: "https://github.com/myorg/myapp/releases/tag/{{ .Tag }}"

    repository:
      owner: myorg
      name: winget-pkgs
      branch: main
      pull_request:
        enabled: true
        base:
          owner: microsoft
          name: winget-pkgs
          branch: master

    skip_upload: auto
    commit_msg_template: "New version: {{ .ProjectName }} version {{ .Version }}"
```

---

## 20. Секция `nix` — Nix User Repository

```yaml
nix:
  - name: myapp

    repository:
      owner: myorg
      name: nur

    path: pkgs/myapp/default.nix  # По умолчанию: pkgs/<name>/default.nix

    homepage: "https://example.com"
    description: "My app"
    license: "mit"

    dependencies:
      - name: git
      - name: curl
        os: linux

    install: |-
      mkdir -p $out/bin
      cp myapp $out/bin/myapp

    formatter: nixfmt             # nixfmt или alejandra
    skip_upload: auto
```

---

## 21. Секция `blobs` — публикация в облачное хранилище

```yaml
blobs:
  # Amazon S3
  - provider: s3
    bucket: my-releases-bucket
    region: us-east-1
    directory: "{{ .ProjectName }}/{{ .Tag }}"
    ids:
      - default
    acl: "public-read"
    cache_control: "max-age=3600"
    include_meta: false
    disable_ssl: false
    s3_force_path_style: true
    extra_files:
      - glob: ./CHANGELOG.md

  # Azure Blob Storage
  - provider: azblob
    bucket: my-releases
    directory: "{{ .ProjectName }}/{{ .Tag }}"

  # Google Cloud Storage
  - provider: gs
    bucket: my-releases-gcs
    directory: "{{ .ProjectName }}/{{ .Tag }}"

  # S3-совместимые (MinIO и т.д.)
  - provider: s3
    bucket: my-bucket
    endpoint: https://minio.example.com
    region: us-east-1
```

---

## 22. Секция `publishers` — кастомная публикация

```yaml
publishers:
  - name: my-publisher
    ids:
      - default
    checksum: true
    signature: true
    cmd: >-
      my-tool
      --version={{ .Version }}
      --file={{ .ArtifactPath }}
    env:
      - API_KEY={{ .Env.PUBLISHER_API_KEY }}
    dir: ./tools
    output: false
    disable: "{{ if .IsNightly }}true{{ end }}"
    extra_files:
      - glob: ./extras/*
    if: '{{ eq .Os "linux" }}'   # Pro
```

---

## 23. Секция `before` — глобальные хуки

```yaml
before:
  hooks:
    # Простая команда
    - go mod tidy

    # Развёрнутый формат
    - cmd: go generate ./...
      output: true
      dir: ./submodule

    # С переменными
    - cmd: "make completions TARGET={{ .Env.TARGET }}"
      env:
        - TARGET=linux

    # Условное выполнение
    - cmd: dotnet tool install --global wix
      if: '{{ eq .Runtime.Goos "windows" }}'
```

---

## 24. Секция `sboms` — Software Bill of Materials

```yaml
sboms:
  - id: archive
    artifacts: archive            # archive, binary, package, source, any
    cmd: syft
    args:
      - "$artifact"
      - "--output"
      - "spdx-json=$document"
    documents:
      - "${artifact}.sbom.json"
    ids:
      - default
    env:
      - SYFT_QUIET=true
```

---

## 25. Секция `upx` — сжатие бинарников

```yaml
upx:
  - enabled: true
    ids:
      - myapp
    goos:
      - linux
      - windows
    goarch:
      - amd64
    compress: "9"               # 1-9 или best
    lzma: false                 # LZMA-сжатие (медленнее, меньше)
    brute: false                # Перебор всех методов (очень медленно)
```

**Важно**: UPX не поддерживает macOS Ventura и новее.

---

## 26. Секция `universal_binaries` — fat binary для macOS

```yaml
universal_binaries:
  - id: myapp-universal
    ids:
      - myapp-amd64
      - myapp-arm64
    name_template: "{{.ProjectName}}"
    replace: true               # Убрать одиночные бинарники из артефактов
    mod_timestamp: "{{ .CommitTimestamp }}"
    hooks:
      pre: rice embed-go
      post: ./sign.sh {{ .Path }}
```

---

## 27. Секция `source` — архив исходного кода

```yaml
source:
  enabled: true
  name_template: "{{ .ProjectName }}-{{ .Version }}"
  format: tar.gz                # tar, tgz, tar.gz, zip
  prefix_template: "{{ .ProjectName }}-{{ .Version }}/"
  files:
    - src: extra-file.txt
      dst: extra-file.txt
```

---

## 28. Секция `msi` — Windows MSI (Pro)

```yaml
msi:
  - id: myapp
    wxs: ./msi/myapp.wxs        # Обязательный путь к WXS-файлу
    name: "{{ .ProjectName }}_{{ .MsiArch }}"
    ids:
      - default
    goamd64: v1
    extensions: []
    extra_files:
      - ./msi/banner.bmp
      - ./msi/dialog.bmp
    replace: false
    mod_timestamp: "{{ .CommitTimestamp }}"
    version: v4                 # v3 или v4 (автоопределение)
    disable: false
    hooks:
      before:
        - cmd: wix extension add ...
      after:
        - cmd: echo "done"
```

### Пример WXS для Schema v4

```xml
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="{{ .ProjectName }}"
           Manufacturer="My Company"
           Version="{{ .Version }}"
           UpgradeCode="PUT-GUID-HERE">
    <MajorUpgrade DowngradeErrorMessage="Downgrade not supported." />
    <Feature Id="Main">
      <ComponentGroupRef Id="Binaries" />
    </Feature>
  </Package>
  <Fragment>
    <ComponentGroup Id="Binaries" Directory="INSTALLFOLDER">
      <Component>
        <File Source="{{ .Binary }}" />
      </Component>
    </ComponentGroup>
  </Fragment>
</Wix>
```

---

## 29. Секция `dmgs` — macOS DMG (Pro)

```yaml
dmgs:
  - id: myapp-dmg
    name: "{{ .ProjectName }}_{{ .Arch }}"
    ids:
      - default
    use: binary                 # binary или appbundle
    replace: false
    mod_timestamp: "{{ .CommitTimestamp }}"
    extra_files:
      - glob: ./icons/*.icns
    if: '{{ eq .Os "darwin" }}'  # Pro
```

---

## 30. Секция `pkgs` — macOS PKG

```yaml
pkgs:
  - id: myapp-pkg
    name: "{{ .ProjectName }}_{{ .Arch }}"
    identifier: "com.example.myapp"   # Обязательно
    ids:
      - default
    use: binary                       # binary или appbundle
    install_location: /usr/local/bin
    scripts:
      preinstall: scripts/preinstall.sh
      postinstall: scripts/postinstall.sh
    replace: false
    mod_timestamp: "{{ .CommitTimestamp }}"
```

---

## 31. Секция `docker_signs` — подпись Docker-образов

```yaml
docker_signs:
  - cmd: cosign
    args:
      - sign
      - "--key=cosign.key"
      - "${artifact}"
      - "--yes"
    artifacts: manifests         # all, images, manifests
    stdin: "{{ .Env.COSIGN_PASSWORD }}"
```

---

## 32. Переменные шаблонов

GoReleaser использует Go-шаблоны (`text/template`) во всех полях с суффиксом `_template` и в большинстве строковых полей.

### Основные переменные

| Переменная | Описание |
|------------|----------|
| `.ProjectName` | Имя проекта |
| `.Version` | Версия (без ведущего `v`) |
| `.Tag` | Git-тег (с `v`) |
| `.PreviousTag` | Предыдущий тег |
| `.Major` | Мажорная версия |
| `.Minor` | Минорная версия |
| `.Patch` | Патч-версия |
| `.RawVersion` | Версия `{Major}.{Minor}.{Patch}` |
| `.ShortCommit` | Короткий хеш коммита |
| `.FullCommit` | Полный хеш коммита |
| `.CommitDate` | Дата коммита (RFC 3339) |
| `.CommitTimestamp` | Unix-timestamp коммита |
| `.Date` | Дата релиза (RFC 3339) |
| `.Timestamp` | Unix-timestamp релиза |
| `.Now` | Текущее время (`time.Time`) |
| `.Branch` | Текущая ветка |
| `.GitURL` | URL удалённого репозитория |
| `.GitTreeState` | `clean` или `dirty` |
| `.ModulePath` | Go module path |
| `.Env.NAME` | Переменная окружения |
| `.IsSnapshot` | Является ли сборка snapshot |
| `.IsDraft` | Является ли черновиком |
| `.IsNightly` | Является ли nightly |
| `.Changelog` | Сгенерированный changelog |
| `.ReleaseURL` | URL релиза |
| `.Var.NAME` | Кастомная переменная (Pro) |

### Артефакт-специфичные переменные

| Переменная | Описание |
|------------|----------|
| `.Os` | Целевая ОС (linux, darwin, windows) |
| `.Arch` | Архитектура (amd64, arm64, ...) |
| `.Arm` | ARM вариант |
| `.Amd64` | AMD64 уровень |
| `.Ext` | Расширение файла (`.exe` на Windows) |
| `.Target` | Идентификатор таргета (linux_amd64_v1) |
| `.ArtifactName` | Имя артефакта |
| `.ArtifactPath` | Полный путь к артефакту |
| `.MsiArch` | Архитектура для MSI |

### Функции шаблонов

```
# Строки
tolower .ProjectName
toupper .ProjectName
title "hello world"
replace "foo_bar" "_" "-"
trim " hello "
trimprefix "v1.0.0" "v"
trimsuffix "file.tar.gz" ".tar.gz"
split "a:b:c" ":"
join "," (split "a:b" ":")

# Пути
dir "/usr/bin/myapp"     → /usr/bin
base "/usr/bin/myapp"    → myapp
abs "relative/path"      → /absolute/path

# Фильтрация
filter "feat: foo\nfix: bar" "^feat"   → feat: foo
reverseFilter "..." "regex"

# Версии
incmajor .Version
incminor .Version
incpatch .Version

# Хеши (v2.9+)
md5 $content
sha256 $content
sha512 $content

# Прочее
envOrDefault "VAR_NAME" "default"
readFile "./file.txt"
mustReadFile "./file.txt"
time "2006-01-02"        → текущая дата в этом формате
```

---

## 33. Переменные окружения

### Обязательные переменные окружения

| Переменная | Назначение |
|------------|------------|
| `GITHUB_TOKEN` | Токен для GitHub (scope: repo, write:packages) |
| `GITLAB_TOKEN` | Токен для GitLab |
| `GITEA_TOKEN` | Токен для Gitea |

### Переменные для отдельных провайдеров

| Переменная | Назначение |
|------------|------------|
| `HOMEBREW_TAP_GITHUB_TOKEN` | Токен для обновления Homebrew tap |
| `AUR_KEY` | SSH-ключ для AUR |
| `NFPM_*_PASSPHRASE` | Пароль для подписи пакетов nfpm |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Учётные данные AWS S3 |
| `AZURE_STORAGE_ACCOUNT` / `AZURE_STORAGE_KEY` | Azure Blob Storage |
| `GOOGLE_APPLICATION_CREDENTIALS` | Google Cloud Storage |
| `COSIGN_PASSWORD` | Пароль для cosign |
| `GPG_FINGERPRINT` / `GPG_PASSWORD` | GPG подпись |

---

## 34. Интеграция с CI/CD

### GitHub Actions

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write
  packages: write
  id-token: write  # для cosign

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod

      - uses: goreleaser/goreleaser-action@v6
        with:
          distribution: goreleaser  # или goreleaser-pro
          version: latest
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Для Pro:
          GORELEASER_KEY: ${{ secrets.GORELEASER_KEY }}
```

### Пример полного workflow с Matrix Build (Pro)

```yaml
jobs:
  goreleaser:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            targets: linux_amd64_v1,linux_arm64
          - os: macos-latest
            targets: darwin_amd64_v1,darwin_arm64
          - os: windows-latest
            targets: windows_amd64_v1
    runs-on: ${{ matrix.os }}
    steps:
      - uses: goreleaser/goreleaser-action@v6
        with:
          args: release --split --clean
        env:
          GORELEASER_CURRENT_TAG: ${{ needs.tag.outputs.tag }}
```

---

## 35. Жизненный цикл: что происходит при `goreleaser release`

```
1. Validate
   ├── Проверка конфига (.goreleaser.yaml)
   ├── Проверка git-тега (должен существовать, если не --snapshot)
   ├── Проверка чистоты рабочей директории (нет незакоммиченных изменений)
   └── Запуск goreleaser healthcheck (опционально)

2. Before hooks
   └── Выполнение команд из before.hooks

3. Build
   └── Компиляция для каждой комбинации goos × goarch × ...

4. Post-build transformations
   ├── Universal Binaries (macOS fat binary)
   └── UPX compression

5. Packaging
   ├── Archives (tar.gz, zip, binary)
   ├── Source archive
   ├── nfpm (deb, rpm, apk, ...)
   ├── Snapcraft
   ├── macOS PKG
   ├── MSI (Pro)
   ├── NSIS (Pro)
   ├── DMG (Pro)
   └── App Bundles (Pro)

6. Security
   ├── SBOM generation
   ├── Checksums
   ├── Signing (signs, binary_signs, docker_signs)
   └── Notarization (macOS)

7. Containers
   ├── Docker build + push
   ├── Docker manifests
   └── Ko

8. Publish
   ├── GitHub/GitLab/Gitea Release
   ├── Blobs (S3/Azure/GCS)
   ├── Custom Upload
   └── Custom Publishers

9. Package registries
   ├── Homebrew tap
   ├── Scoop bucket
   ├── AUR
   ├── Winget
   ├── Nix NUR
   ├── Krew
   └── NPM (Pro)

10. Announce
    └── Discord, Slack, Mastodon, Twitter, Telegram, ...

11. After hooks (Pro)
    └── Выполнение команд из after.hooks
```

---

## 36. Полный пример минимального конфига

```yaml
version: 2

project_name: myapp

before:
  hooks:
    - go mod tidy

builds:
  - id: myapp
    main: ./cmd/myapp
    binary: myapp
    goos: [linux, darwin, windows]
    goarch: [amd64, arm64]
    ldflags:
      - -s -w
      - -X main.version={{.Version}}
    env:
      - CGO_ENABLED=0

archives:
  - id: default
    formats: [tar.gz]
    format_overrides:
      - goos: windows
        formats: [zip]
    name_template: "{{ .ProjectName }}_{{ .Os }}_{{ .Arch }}"
    files:
      - LICENSE
      - README.md

checksum:
  name_template: "checksums.txt"
  algorithm: sha256

signs:
  - artifacts: checksum
    args: ["--batch", "-u", "{{ .Env.GPG_FINGERPRINT }}", "--output", "${signature}", "--detach-sign", "${artifact}"]

changelog:
  use: github
  sort: asc
  filters:
    exclude:
      - "^chore:"
      - "^docs:"
  groups:
    - title: "New Features"
      regexp: "^feat"
      order: 0
    - title: "Bug Fixes"
      regexp: "^fix"
      order: 1

release:
  github:
    owner: myorg
    name: myrepo
  draft: false
  prerelease: auto
```

---

## 37. Полный пример расширенного конфига

```yaml
version: 2

project_name: myapp

env:
  - GO111MODULE=on
  - CGO_ENABLED=0

before:
  hooks:
    - go mod tidy
    - go generate ./...
    - make completions

builds:
  - id: myapp
    main: ./cmd/myapp
    binary: myapp
    goos: [linux, darwin, windows]
    goarch: [amd64, arm64, "386"]
    ignore:
      - goos: darwin
        goarch: "386"
      - goos: windows
        goarch: arm64
    ldflags:
      - -s -w
      - -X github.com/myorg/myapp/internal/version.Version={{.Version}}
      - -X github.com/myorg/myapp/internal/version.Commit={{.ShortCommit}}
      - -X github.com/myorg/myapp/internal/version.Date={{.Date}}
    flags:
      - -trimpath
    mod_timestamp: "{{ .CommitTimestamp }}"

universal_binaries:
  - replace: true

archives:
  - id: default
    ids: [myapp]
    formats: [tar.gz]
    format_overrides:
      - goos: windows
        formats: [zip]
    name_template: >-
      {{ .ProjectName }}_
      {{- title .Os }}_
      {{- if eq .Arch "amd64" }}x86_64
      {{- else if eq .Arch "386" }}i386
      {{- else }}{{ .Arch }}{{ end }}
    files:
      - LICENSE
      - README.md
      - CHANGELOG.md
      - completions/*
      - man/man1/*.1

nfpms:
  - id: myapp-pkg
    package_name: myapp
    formats: [deb, rpm, apk, archlinux]
    homepage: "https://example.com"
    maintainer: "My Name <me@example.com>"
    description: "My awesome app"
    license: MIT
    bindir: /usr/bin
    contents:
      - src: completions/bash/myapp
        dst: /usr/share/bash-completion/completions/myapp
      - src: man/man1/myapp.1
        dst: /usr/share/man/man1/myapp.1
      - src: config.yaml.example
        dst: /etc/myapp/config.yaml
        type: config|noreplace
    scripts:
      postinstall: scripts/postinstall.sh

source:
  enabled: true
  format: tar.gz

sboms:
  - artifacts: archive

checksum:
  name_template: "{{ .ProjectName }}_{{ .Version }}_checksums.txt"
  algorithm: sha256

signs:
  - artifacts: checksum
    args: ["--batch", "-u", "{{ .Env.GPG_FINGERPRINT }}", "--output", "${signature}", "--detach-sign", "${artifact}"]

changelog:
  use: github
  sort: asc
  filters:
    exclude: ["^chore:", "^docs:", "typo"]
  groups:
    - title: "New Features"
      regexp: "^feat"
      order: 0
    - title: "Bug Fixes"
      regexp: "^fix"
      order: 1
    - title: "Dependencies"
      regexp: "^(chore\\(deps\\)|bump)"
      order: 2

release:
  github:
    owner: myorg
    name: myrepo
  draft: false
  prerelease: auto
  mode: append
  name_template: "{{ .ProjectName }} v{{ .Version }}"

brews:
  - name: myapp
    repository:
      owner: myorg
      name: homebrew-tap
    homepage: "https://example.com"
    description: "My awesome app"
    license: MIT
    test: |
      system "#{bin}/myapp --version"
    skip_upload: auto

scoops:
  - repository:
      owner: myorg
      name: scoop-bucket
    homepage: "https://example.com"
    description: "My awesome app"
    license: MIT
    skip_upload: auto

aurs:
  - name: myapp-bin
    private_key: "{{ .Env.AUR_KEY }}"
    git_url: "ssh://aur@aur.archlinux.org/myapp-bin.git"
    homepage: "https://example.com"
    description: "My awesome app"
    license: ["MIT"]
    skip_upload: auto

dockers:
  - image_templates:
      - "ghcr.io/myorg/myapp:{{ .Tag }}"
      - "ghcr.io/myorg/myapp:latest"
    dockerfile: Dockerfile
    build_flag_templates:
      - "--label=org.opencontainers.image.version={{.Version}}"
      - "--label=org.opencontainers.image.created={{.Date}}"
      - "--label=org.opencontainers.image.revision={{.FullCommit}}"
    skip_push: auto

snapshot:
  version_template: "{{ incpatch .Version }}-devel"

blobs:
  - provider: s3
    bucket: my-releases
    region: us-east-1
    directory: "{{ .ProjectName }}/{{ .Tag }}"
```

---

## 38. Сравнение GoReleaser с Crossler

| Аспект | GoReleaser | Crossler (наш инструмент) |
|--------|------------|---------------------------|
| **Язык** | Go | Go |
| **Конфиг** | `.goreleaser.yaml` | `.crossler.toml` (TOML) |
| **Фокус** | Релиз Go/Rust/Zig проектов | Кроссплатформенная упаковка любых бинарников |
| **Сборка** | Встроенная (go build, cargo, zig) | Нет (принимает готовые бинарники) |
| **Git/Release** | Встроенная публикация в GitHub/GitLab | Нет |
| **Linux пакеты** | Через nfpm | Через nfpm |
| **Windows MSI** | Через WiX (Pro) | Через wixl / WiX |
| **macOS PKG** | pkgbuild (Pro) | pkgbuild / xar+bomutils |
| **macOS DMG** | hdiutil (Pro) | hdiutil |
| **Подпись** | GPG, cosign, встроенная Apple (через quill) | osslsigncode, signtool, rcodesign, codesign |
| **Homebrew** | Встроенная | Опционально (генерация .rb) |
| **Многоуровневый конфиг** | Нет | Да (общие → платформа → архитектура) |

### Ключевые отличия

GoReleaser — это **полный pipeline от кода до релиза**, включая сборку, создание GitHub Release, объявление. Crossler фокусируется на **упаковке и подписи** уже собранных бинарников с единым многоуровневым конфигом и поддержкой всех форматов без Pro-подписки.

GoReleaser хорошо решает задачу в экосистеме Go/GitHub. Crossler решает более широкую задачу: стандартизировать упаковку для команды с поддержкой всех форматов и платформ в одном инструменте.

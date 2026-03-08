# Crossler

## Суть проекта

Crossler — инструмент для кроссплатформенной упаковки. Читает единый конфиг и делегирует сборку пакетов внешним бэкендам. Название "cross" отражает кроссплатформенность упаковки, а не мультиплатформенность самой утилиты.

### Зависимости

Crossler собирается для **3 ОС × 2 архитектуры = 6 таргетов**: Linux, macOS, Windows × x64, arm64. Каждый бинарник поддерживает разный набор форматов и требует соответствующих внешних инструментов:

| Формат / возможность | Linux | macOS | Windows |
|----------------------|:-----:|:-----:|:-------:|
| `.msi` | ✓ `wixl` | ✓ `wixl` | ✓ `wix` |
| `.deb`, `.rpm`, `.apk`, `.pkg.tar.zst`, `.ipk` | ✓ `nfpm` | ✓ `nfpm` | ✓ `nfpm` |
| `.tar.gz` (любой таргет) | ✓ | ✓ | ✓ |
| `.rb` (Homebrew formula) | ✓ | ✓ | ✓ |
| `.pkg` (macOS installer) | ✓ `xar`+`bomutils` | ✓ `pkgbuild` | ✓ `xar`+`bomutils` |
| `.dmg` (macOS disk image) | — | ✓ `hdiutil` | — |
| Подпись Windows-бинарников (Authenticode) | ✓ `osslsigncode` | ✓ `osslsigncode` | ✓ `signtool` |
| Подпись `.msi` (Authenticode) | ✓ `osslsigncode` | ✓ `osslsigncode` | ✓ `signtool` |
| Подпись macOS-бинарников | ✓ `rcodesign` | ✓ `codesign` | ✓ `rcodesign` |
| Нотаризация macOS-пакетов | ✓ `rcodesign` | ✓ `notarytool` | ✓ `rcodesign` |

**Linux-бинарник — основной**: умеет собирать и подписывать для всех платформ, включая macOS-подпись через `rcodesign`.
**macOS-бинарник — вторичный**: всё, что требует нативного macOS окружения, включая подпись перед упаковкой в `tar.gz`, `.pkg`, `.dmg`; также поддерживает подпись Windows-артефактов через `osslsigncode`.
**Windows-бинарник — минимальный**: сборка и подпись `.msi` и бинарников через штатный `signtool`.

Установка внешних зависимостей:

| Инструмент | Платформа | Пакет / источник |
|------------|-----------|------------------|
| `wixl` | Linux | `msitools` — пакетный менеджер дистрибутива (`apk add msitools`, `apt install msitools`) |
| `wixl` | macOS | `brew install msitools` |
| `nfpm` | Linux, macOS, Windows | скачать бинарник с [github.com/goreleaser/nfpm](https://github.com/goreleaser/nfpm/releases) или `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest`; на macOS также `brew install nfpm` |
| `osslsigncode` | Linux | пакетный менеджер дистрибутива (`apk add osslsigncode`, `apt install osslsigncode`) |
| `osslsigncode` | macOS | `brew install osslsigncode` |
| `wix` | Windows | .NET tool: `dotnet tool install --global wix` |
| `signtool` | Windows | входит в Windows SDK (устанавливается вместе с Visual Studio или отдельно) |
| `pkgbuild`, `hdiutil` | macOS | входят в macOS, дополнительная установка не требуется |
| `codesign`, `notarytool` | macOS | входят в Xcode Command Line Tools: `xcode-select --install` |
| `rcodesign` | Linux, Windows | скачать бинарник с [github.com/indygreg/apple-platform-rs](https://github.com/indygreg/apple-platform-rs/releases) или `cargo install apple-codesign`; open-source альтернатива `codesign`+`notarytool`, работает без macOS |
| `xar` | Linux | пакетный менеджер дистрибутива (`apt install xar`, `apk add xar`) или собрать из исходников |
| `bomutils` | Linux | [github.com/hogliux/bomutils](https://github.com/hogliux/bomutils) — предоставляет `mkbom`; альтернатива macOS-утилите для создания `.pkg` |
| `xar`, `bomutils` | Windows | собрать из исходников или использовать WSL |

### Конфиг-файл

Формат файла конфигурации **ещё не определён** (рассматриваются TOML, YAML и другие). Конфиг должен поддерживать **многоуровневое наслоение настроек**: общие параметры → переопределения для платформы → переопределения для архитектуры. Бинарники и сопроводительные файлы (иконки, документация) описываются раздельно, т.к. физически лежат в разных местах.

### Инсталляция

В репозитории есть скрипты `scripts/install.sh` (Linux/macOS) и `scripts/install.ps1` (Windows). Это **публичные bootstrap-скрипты для конечных пользователей Crossler** — не внутренние инструменты разработки.

Их цель: одной командой установить Crossler со всеми внешними зависимостями в любом окружении (CI/CD Docker, GitHub Actions runner, машина разработчика).

Скрипты устанавливают сам бинарник `crossler` и все внешние инструменты (wixl, nfpm, osslsigncode, rcodesign, xar, bomutils на Linux/macOS; nfpm, rcodesign, signtool, wix на Windows).

### Целевая аудитория

80% — консольные утилиты. GUI-приложения поддерживаются, но вторичны. Цель — стандартизировать упаковку наших проектов, не покрывать все возможные кейсы.

## Исследовательские статьи (.claude/docs/)

Перед разработкой были написаны подробные технические статьи по каждому бэкенд-инструменту. Они служат справочником при реализации соответствующих модулей Crossler.

### Упаковщики

| Файл | Инструмент | Формат | Что внутри |
|------|------------|--------|------------|
| `docs/wixl.md` | wixl (msitools) | `.msi` | CLI, формат .wxs, элементы WiX, GUID, препроцессор, ограничения |
| `docs/nfpm.md` | nfpm | `.deb`, `.rpm`, `.apk`, `.pkg.tar.zst`, `.ipk` | CLI, структура nfpm.yaml, contents, скрипты, overrides, маппинг архитектур |
| `docs/pkgbuild.md` | pkgbuild | `.pkg` (macOS) | CLI, payload, скрипты, component plist, связь с productbuild |
| `docs/hdiutil.md` | hdiutil | `.dmg` | CLI, форматы образов, рабочий процесс "красивого" DMG, сторонние инструменты |

### Инструменты подписи

| Файл | Инструмент | Назначение | Что внутри |
|------|------------|------------|------------|
| `docs/osslsigncode.md` | osslsigncode | Authenticode на Linux/macOS | CLI, форматы сертификатов, TSA, MSI, PKCS#11, сравнение с signtool |
| `docs/signtool.md` | signtool.exe | Authenticode на Windows | CLI, Windows certstore, EV-сертификаты, Azure Key Vault, GitHub Actions |
| `docs/codesign.md` | codesign | Apple Code Signing на macOS | CLI, Hardened Runtime, entitlements, порядок подписи bundle, CI/CD с keychain |
| `docs/notarytool.md` | notarytool | Нотаризация Apple на macOS | Три способа аутентификации, полный рабочий процесс, stapling, типичные ошибки |
| `docs/rcodesign.md` | rcodesign | Apple Code Signing + нотаризация на Linux/Windows | CLI, P12-файлы, notary-submit со staple, CI/CD на Linux |

### Сравнительный анализ и рекомендации

| Файл | Что внутри |
|------|------------|
| `docs/comparison.md` | Сравнение упаковщиков: подход к описанию содержимого, метаданные, скрипты, зависимости, сниппеты одной задачи в разных форматах, матрица возможностей |
| `docs/crossler-recommendations.md` | Рекомендации по конфигу Crossler для упаковки: что реализовать обязательно / желательно / не нужно |
| `docs/signing-comparison.md` | Сравнение инструментов подписи: платформы, форматы ключей, TSA, двойная подпись, нотаризация, матрица возможностей |
| `docs/signing-recommendations.md` | Рекомендации по реализации подписи в Crossler: архитектурная модель, структура конфига, порядок шагов, что включить/исключить |

## Языковая политика

- **Общение агента с пользователем** — на русском языке
- **Файлы в директории `.claude/`** (CLAUDE.md, memory и т.д.) — на русском языке
- **Весь остальной проект** (комментарии в коде, строковые константы, документация, README.md и т.д.) — на английском языке

## Структура проекта

- Репозиторий: git, основная ветка `master`, разработка в `develop`
- Язык реализации: **Go** — выбран как простой популярный компилируемый язык, даёт один бинарник без зависимостей, встроенная кросс-компиляция, удобная работа с YAML/TOML и другими форматами через вендорируемые библиотеки
- Go-модуль: `github.com/powertech-center/crossler`
- Точка входа: `cmd/crossler/main.go`
- Артефакты сборки: `dist/` (в `.gitignore`)

## Dev-окружение

Локальная разработка ведётся внутри Dev Container на базе Alpine Linux:

- **Образ**: `ghcr.io/powertech-center/alpine-go:latest` — содержит Go, все необходимые инструменты разработки и crossler с зависимостями
- **VSCode**: `.vscode/settings.json` + `.vscode/tasks.json` (задачи build / run / test)

## CI: сборка и релиз

Автоматическая сборка через GitHub Actions с использованием образа `ghcr.io/powertech-center/alpine-cross-go:latest` (Go + кросс-компилятор для всех таргетов):

- **Makefile** — кросс-компиляция для 6 таргетов (Linux/macOS/Windows × x64/arm64); `CGO_ENABLED=0`, чистый Go, никаких внешних компиляторов не требуется
- **Тесты** — запускаются на каждый push/PR
- **Релиз** — сборка всех 6 бинарников + создание GitHub Release только при теге `v*`

## CI: тестирование install-скриптов

Отдельный workflow тестирует `scripts/install.sh` и `scripts/install.ps1` на реальных раннерах и контейнерах — без образа alpine-cross-go, с чистыми дистрибутивными образами:

- **Раннеры**: ubuntu-latest (x64), ubuntu-24.04-arm (arm64 нативный), macos-latest (Apple Silicon), windows-latest, windows-11-arm
- **Контейнеры**: alpine:latest, debian:stable-slim, fedora:latest, archlinux:latest
- **Порядок шагов в каждой задаче**: установка базовых инструментов → `install.sh`/`install.ps1` → проверка инструментов → проверка идемпотентности
- **Подробная матрица** с конфигурацией каждой задачи и известными особенностями: `docs/install-testing.md`

## Рабочий процесс

- Новые фичи — в ветке от `develop`, PR в `develop`
- В `master` попадает только стабильный код через PR из `develop`
- Коммиты на английском, в повелительном наклонении (Add, Fix, Update, Remove...)

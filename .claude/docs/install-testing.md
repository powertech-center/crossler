# Тестирование install-скриптов в CI

`scripts/install.sh` и `scripts/install.ps1` — публичные bootstrap-скрипты для конечных
пользователей Crossler. Они должны корректно работать в самых разных окружениях: CI/CD
Docker-контейнеры, GitHub Actions, машины разработчиков — с разными дистрибутивами и
архитектурами.

Чтобы гарантировать это, в репозитории есть отдельный GitHub Actions workflow, который
запускает install-скрипты на реальных раннерах и контейнерах и проверяет результат.
Этот документ описывает устройство тестового окружения: какие платформы покрываются,
как настроена каждая задача и какие есть особенности.

---

## Принципы организации

- **Одна задача на комбинацию ОС/дистрибутив/архитектура** — сбои изолированы и легко диагностируются.
- **Порядок шагов**: Установка → Проверка инструментов → Проверка идемпотентности. Проверка идёт до прогона идемпотентности, чтобы сломанная установка сразу выявлялась.
- **Базовые инструменты устанавливаются самой CI-задачей**, а не install-скриптом. Скрипт устанавливает только зависимости Crossler; он предполагает, что `gcc`, `g++`, `make`, `cmake`, `autoconf`, `git`, `curl` уже есть (нужны для сборки xar, osslsigncode, bomutils из исходников).
- **Чистые дистрибутивные образы** — никаких project-специфичных образов (вроде `alpine-cross-go`). Цель — максимально приблизиться к реальным условиям установки.

---

## Задачи x86_64

### Alpine

```yaml
runs-on: ubuntu-latest
container:
  image: alpine:latest
```

Базовые инструменты:
```sh
apk add --no-cache curl git ca-certificates gcc g++ make cmake autoconf \
  libxml2-dev openssl-dev zlib-dev bzip2-dev
```

Примечания:
- `msitools` (wixl) находится в community-репозитории Alpine — install-скрипт включает его автоматически.
- `osslsigncode` отсутствует в репозиториях Alpine; собирается из исходников через cmake.
- `bomutils` (mkbom) отсутствует в репозиториях Alpine; собирается из исходников через make.
- `xar` есть в репозиториях Alpine.

---

### Ubuntu

```yaml
runs-on: ubuntu-latest
# без контейнера — запускается напрямую на GitHub-hosted раннере
```

Базовые инструменты:
```sh
sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends \
  curl git ca-certificates cmake gcc g++ libssl-dev make autoconf \
  libxml2-dev zlib1g-dev libbz2-dev
```

Запуск install-скрипта от root с сохранением окружения:
```sh
sudo -E sh scripts/install.sh
```

Примечания:
- `xar` отсутствует в репозиториях Ubuntu (удалён после 20.04); собирается из исходников.
  Требует патча для OpenSSL 3.x (`EVP_EncryptInit` вместо `OpenSSL_add_all_ciphers`)
  и обновлённых `config.guess`/`config.sub`.
- Пакет `wixl` на apt-системах называется `wixl` (не `msitools`).

---

### Debian

```yaml
runs-on: ubuntu-latest
container:
  image: debian:stable-slim
```

Базовые инструменты:
```sh
apt-get update -qq && apt-get install -y --no-install-recommends \
  curl git ca-certificates cmake gcc g++ libssl-dev make autoconf \
  libxml2-dev zlib1g-dev libbz2-dev
```

Примечания:
- Все 6 инструментов доступны; `xar` есть в репозиториях Debian (в отличие от Ubuntu).
- `bomutils` собирается из исходников (в репозиториях Debian отсутствует).

---

### Fedora

```yaml
runs-on: ubuntu-latest
container:
  image: fedora:latest
```

Базовые инструменты:
```sh
dnf install -y curl git ca-certificates cmake gcc gcc-c++ openssl-devel \
  make tar gzip findutils autoconf libxml2-devel zlib-devel bzip2-devel
```

Примечания:
- `osslsigncode` есть в репозиториях Fedora.
- `xar` есть в репозиториях Fedora.
- `bomutils` собирается из исходников; требует `CXXFLAGS="-O2 -fPIE -fPIC"` из-за
  принудительного PIE в hardened GCC Fedora.

---

### Arch Linux

```yaml
runs-on: ubuntu-latest
container:
  image: archlinux:latest
```

Базовые инструменты:
```sh
pacman -Syu --noconfirm curl git ca-certificates cmake gcc make tar gzip \
  findutils autoconf libxml2 pkgconf zlib bzip2 openssl
```

Примечания:
- `pkgconf` обязателен — на Arch `xml2-config` делегирует вызовы `pkg-config`.
- `msitools` (wixl) есть в репозитории `extra` и устанавливается нормально.
- `osslsigncode` отсутствует в официальных репозиториях; собирается из исходников через cmake.
- `xar` отсутствует в официальных репозиториях (только AUR); собирается из исходников.
  Требует патча `lib/ext2.c`: добавить `<stdlib.h>`, обернуть обращения к `EXT2_ECOMPR_FL`
  в `#ifdef` (константа удалена из современных заголовков e2fsprogs).
- `bomutils` собирается из исходников; требует `CXXFLAGS="-O2 -fPIE -fPIC"`.
- Пакет `gcc` на Arch уже включает C++ (отдельного пакета `g++` нет).

---

## Задачи arm64

### Alpine arm64

```yaml
runs-on: ubuntu-24.04-arm
# без контейнера на уровне задачи
```

`actions/checkout@v4` — это JavaScript-экшен, и он **не работает внутри Alpine-контейнеров
на arm64-раннерах** (бинарник Node.js недоступен для этой комбинации). Обходной путь:
checkout на хосте, затем всё запускается внутри `docker run` в одном шаге:

```yaml
- name: Checkout code
  uses: actions/checkout@v4

- name: Install, verify, idempotency check
  run: |
    docker run --rm -v "$PWD:/ws" -w /ws alpine:latest sh -c "
      apk add --no-cache curl git ca-certificates gcc g++ make cmake \
        autoconf libxml2-dev openssl-dev zlib-dev bzip2-dev &&
      sh scripts/install.sh &&
      echo '--- Verify ---' &&
      for t in wixl nfpm osslsigncode rcodesign xar mkbom; do
        command -v \"\$t\" && echo \"OK: \$t\" || { echo \"MISSING: \$t\"; exit 1; }
      done &&
      echo '--- Idempotency ---' &&
      sh scripts/install.sh
    "
```

Примечания:
- Поскольку контейнер эфемерный (один `docker run`), все три фазы
  (установка, проверка, идемпотентность) должны быть в одном вызове shell.
- Docker предустановлен на раннерах `ubuntu-24.04-arm`.

---

### Ubuntu arm64

```yaml
runs-on: ubuntu-24.04-arm
# без контейнера — нативный arm64-раннер
```

Базовые инструменты и вызов скрипта идентичны Ubuntu x64. Никакой специальной обработки
не требуется — `ubuntu-24.04-arm` является нативным arm64-раннером (Cobalt 100),
а не QEMU-эмуляцией.

Примечания:
- `config.guess`/`config.sub` в исходниках xar датированы 2005 годом и не знают
  об `aarch64`. Install-скрипт копирует обновлённые версии из системного пакета automake
  перед запуском `./configure`.

---

## macOS

```yaml
runs-on: macos-latest
# без контейнера
```

`macos-latest` — это Apple Silicon (arm64) начиная с августа 2025 года.
Установка базовых инструментов не нужна — Homebrew предустановлен.

Примечания:
- Все инструменты устанавливаются через `brew install`.
- `rcodesign` устанавливается через скачивание бинарника (формулы Homebrew нет).
- `mkbom` входит в Xcode Command Line Tools, отдельно не устанавливается.
- `xar` устанавливается через `brew install xar-mackyle`.

---

## Windows

### Windows x64

```yaml
runs-on: windows-latest
```

### Windows arm64

```yaml
runs-on: windows-11-arm
```

Примечания:
- `rcodesign` не имеет бинарника для Windows arm64; на обеих архитектурах используется
  сборка x86_64 (Windows arm64 запускает x64-бинарники через эмуляцию).
- `wix` устанавливается как .NET global tool: `dotnet tool install --global wix`.
- `signtool` устанавливается через winget (Windows SDK).
- `nfpm` скачивается как zip-архив из GitHub Releases.

---

## Сводная таблица раннеров

| Метка раннера       | Арх.  | ОС / примечания                       | Бесплатно для публичных репо |
|---------------------|-------|---------------------------------------|------------------------------|
| `ubuntu-latest`     | x64   | Ubuntu 24.04                          | ✅                           |
| `ubuntu-24.04-arm`  | arm64 | Ubuntu 24.04, нативный Cobalt 100 CPU | ✅ (GA с авг. 2025)          |
| `macos-latest`      | arm64 | macOS 15, Apple Silicon (с авг. 2025) | ✅                           |
| `windows-latest`    | x64   | Windows Server 2025                   | ✅                           |
| `windows-11-arm`    | arm64 | Windows 11 arm64                      | ✅ (Preview апр. 2025)       |

Образы контейнеров, используемые поверх этих раннеров:

| Образ                | Поддержка арх. | JS-экшены на arm64       |
|----------------------|----------------|--------------------------|
| `alpine:latest`      | multi-arch     | ❌ (нужен обходной путь) |
| `debian:stable-slim` | multi-arch     | ✅                       |
| `fedora:latest`      | только x64     | н/д                      |
| `archlinux:latest`   | только x64     | н/д                      |

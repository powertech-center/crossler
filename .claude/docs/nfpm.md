# nfpm — создание Linux-пакетов (.deb, .rpm, .apk)

## Что такое nfpm

**nfpm** (nFPM is Not FPM) — лёгкая утилита для создания Linux-пакетов, написанная на Go. Это упрощённая и полностью самодостаточная альтернатива классическому FPM (Effing Package Management), который требует Ruby и множество зависимостей.

### Ключевые характеристики

- **Нулевые зависимости** — один бинарник без Ruby, dpkg, rpm и прочего
- **Единый конфиг → несколько форматов** — один nfpm.yaml порождает deb, rpm, apk и другие
- **Кросс-платформенность** — собирает Linux-пакеты на любой ОС (Linux, macOS, Windows)
- **GOARCH нотация** — использует Go-стиль для архитектур, автоматически конвертирует
- **Часть экосистемы GoReleaser** — но работает полностью самостоятельно

### Поддерживаемые форматы

| Формат | Целевая система | Описание |
|--------|-----------------|---------|
| `.deb` | Debian, Ubuntu и производные | Стандарт для половины Linux-мира |
| `.rpm` | Red Hat, CentOS, Fedora, SUSE | Стандарт для другой половины |
| `.apk` | Alpine Linux | Лёгкий формат для контейнеров |
| `.archlinux` | Arch Linux | Пакеты для Arch и Manjaro |
| `.ipk` | OpenWrt | Встроенные системы |

### Установка

```bash
# Alpine Linux (dev-контейнер Crossler)
# nfpm не в стандартных репозиториях Alpine, скачать бинарник:
curl -fsSL https://github.com/goreleaser/nfpm/releases/latest/download/nfpm_linux_amd64.tar.gz | tar xz
mv nfpm /usr/local/bin/

# или через Go
go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest

# macOS
brew install goreleaser/tap/nfpm

# Linux (deb)
echo 'deb [trusted=yes] https://repo.goreleaser.com/apt/ /' | sudo tee /etc/apt/sources.list.d/goreleaser.list
sudo apt update && sudo apt install nfpm
```

---

## Аргументы командной строки

### Основные команды

```
nfpm package   # создать пакет
nfpm init      # инициализировать nfpm.yaml с примерами
nfpm jsonschema # вывести JSON Schema конфигурации
nfpm completion # shell completion (bash/zsh/fish/powershell)
```

### nfpm package

```bash
nfpm package [FLAGS]
```

| Флаг | Полный | Описание |
|------|--------|---------|
| `-c FILE` | `--config FILE` | Путь к конфигурационному файлу (по умолчанию `nfpm.yaml`) |
| `-t PATH` | `--target PATH` | Путь выходного пакета или директории. Формат определяется по расширению |
| `-p FMT` | `--packager FMT` | Явно указать формат: `deb`, `rpm`, `apk`, `archlinux`, `ipk` |
| `-v` | `--verbose` | Подробный вывод |

```bash
# Создать deb в текущей директории
nfpm package -c nfpm.yaml -p deb -t ./

# Создать rpm с автоопределением формата по расширению
nfpm package --config nfpm.yaml --target dist/myapp-1.0.rpm

# Все поддерживаемые форматы из одного конфига (через цикл)
for fmt in deb rpm apk; do
  nfpm package -c nfpm.yaml -p $fmt -t dist/
done
```

### nfpm init

```bash
nfpm init [FLAGS]
```

| Флаг | Описание |
|------|---------|
| `--config FILE` | Куда сохранить новый конфиг (по умолчанию `nfpm.yaml`) |

Создаёт файл с подробными комментариями по всем полям.

---

## Конфигурационный файл nfpm.yaml

### Минимальный конфиг

```yaml
name: myapp
version: 1.0.0
arch: amd64

contents:
  - src: dist/myapp
    dst: /usr/bin/myapp
```

### Полная структура с описанием всех полей

```yaml
# === ОБЯЗАТЕЛЬНЫЕ ПОЛЯ ===
name: myapp                          # имя пакета (обязательно)
version: 1.0.0                       # версия (обязательно)
arch: amd64                          # архитектура в GOARCH формате (обязательно)

# === МЕТАДАННЫЕ ===
maintainer: "Team <team@example.com>"
description: |
  Multi-line description.
  Second line.
homepage: https://github.com/org/myapp
license: MIT
vendor: My Company

# === РАСШИРЕННОЕ ВЕРСИОНИРОВАНИЕ ===
epoch: 1          # RPM epoch — повышает приоритет при сравнении версий
release: 1        # Номер ревизии пакета (не приложения)
prerelease: beta1 # Метка пре-релиза (влияет на сортировку)
version_metadata: build1  # Метаданные (после +)

# === ПЛАТФОРМА ===
platform: linux

# === ЗАВИСИМОСТИ ===
depends:
  - bash
  - curl >= 7.0          # rpm-стиль ограничения версии
  - curl (>= 7.0)        # deb-стиль (nfpm принимает оба в зависимости от формата)

recommends:    # устанавливаются автоматически, но не обязательны
  - jq

suggests:      # только рекомендации, не устанавливаются автоматически
  - docker

conflicts:     # конфликтующие пакеты
  - old-myapp

replaces:      # замещает эти пакеты при обновлении
  - old-myapp-legacy

provides:      # виртуальные пакеты, которые предоставляет этот пакет
  - myapp-ng

# === ФАЙЛЫ ===
contents:
  - src: dist/myapp
    dst: /usr/bin/myapp
    type: file
    file_info:
      mode: 0755
      owner: root
      group: root

  - src: config/default.yaml
    dst: /etc/myapp/config.yaml
    type: config
    file_info:
      mode: 0644

  - src: README.md
    dst: /usr/share/doc/myapp/README.md
    type: doc

  - src: /usr/bin/myapp
    dst: /usr/local/bin/myapp
    type: symlink

  - dst: /var/lib/myapp
    type: dir
    file_info:
      mode: 0750
      owner: myapp
      group: myapp

# === СКРИПТЫ ===
scripts:
  preinstall: scripts/preinstall.sh
  postinstall: scripts/postinstall.sh
  preremove: scripts/preremove.sh
  postremove: scripts/postremove.sh

# === ПЕРЕОПРЕДЕЛЕНИЯ ПО ФОРМАТАМ ===
overrides:
  deb:
    depends:
      - curl (>= 7.0)
    scripts:
      postinstall: scripts/deb-postinstall.sh
    deb:
      predepends:
        - libc6
  rpm:
    release: 1.el8
    depends:
      - curl >= 7.0
  apk:
    depends:
      - curl>=7.0
```

---

## Метаданные пакета

| Поле | Обязательно | Описание | Пример |
|------|:-----------:|---------|--------|
| `name` | Да | Имя пакета | `crossler` |
| `version` | Да | Версия (`v` в начале удаляется автоматически) | `1.2.3` или `v1.2.3` |
| `arch` | Да | Архитектура в GOARCH-стиле | `amd64`, `arm64`, `386` |
| `maintainer` | Нет | Имя и email сопровождающего | `"Name <name@example.com>"` |
| `description` | Нет | Описание (поддерживает многострочное) | строка или `|` блок |
| `homepage` | Нет | URL проекта | `https://github.com/...` |
| `license` | Нет | SPDX-идентификатор лицензии | `MIT`, `Apache-2.0`, `GPL-3.0` |
| `vendor` | Нет | Организация-производитель | `PowerTech Center` |
| `platform` | Нет | Целевая платформа | `linux` |
| `epoch` | Нет | RPM epoch, повышает приоритет | `1` |
| `release` | Нет | Ревизия пакета (не приложения) | `1`, `1.el8` |

---

## Секция contents — установка файлов

### Синтаксис элемента

```yaml
contents:
  - src: <источник на машине сборки>
    dst: <путь назначения на целевой системе>
    type: <тип>
    file_info:
      mode: 0644
      owner: root
      group: root
    expand: true   # развернуть переменные окружения в src/dst
```

### Типы файлов

| Тип | Описание | Применение |
|-----|---------|-----------|
| `file` | Обычный файл | бинарники, скрипты, данные |
| `config` | Конфигурационный файл | перезаписывается при обновлении |
| `config\|noreplace` | Config, не перезаписывается | сохраняет пользовательские правки |
| `dir` | Явная директория | для директорий с особыми правами/владельцем |
| `symlink` | Символическая ссылка | `src` = цель ссылки, `dst` = путь ссылки |
| `ghost` | Ghost-файл (только RPM) | файлы, отслеживаемые RPM, но не устанавливаемые (логи) |
| `doc` | Документация | README, LICENSE |
| `licence` | Лицензия (alias для doc) | LICENSE файлы |
| `tree` | Рекурсивно скопировать директорию | все файлы дерева |

### Примеры

```yaml
contents:
  # Исполняемый бинарник
  - src: dist/crossler
    dst: /usr/bin/crossler
    type: file
    file_info:
      mode: 0755
      owner: root
      group: root

  # Конфиг, не перезаписывается при обновлении
  - src: config/default.yaml
    dst: /etc/crossler/config.yaml
    type: config|noreplace
    file_info:
      mode: 0644

  # Symlink
  - src: /usr/bin/crossler
    dst: /usr/local/bin/crossler
    type: symlink

  # Пустая директория с особыми правами
  - dst: /var/lib/crossler
    type: dir
    file_info:
      mode: 0750
      owner: crossler
      group: crossler

  # Ghost-файл для логов (RPM)
  - dst: /var/log/crossler.log
    type: ghost
    file_info:
      mode: 0644
      owner: crossler

  # Glob pattern
  - src: docs/*.md
    dst: /usr/share/doc/crossler/
    type: doc

  # Systemd юнит
  - src: systemd/crossler.service
    dst: /lib/systemd/system/crossler.service
    type: file
    file_info:
      mode: 0644

  # С расширением переменных окружения
  - src: dist/${GOOS}_${GOARCH}/crossler
    dst: /usr/bin/crossler
    type: file
    expand: true
```

---

## Скрипты жизненного цикла

### Декларация в конфиге

```yaml
scripts:
  preinstall: scripts/preinstall.sh
  postinstall: scripts/postinstall.sh
  preremove: scripts/preremove.sh
  postremove: scripts/postremove.sh
```

### Маппинг на форматы пакетов

| nfpm | deb | rpm | apk |
|------|-----|-----|-----|
| `preinstall` | `preinst` | `%pre` | pre-install |
| `postinstall` | `postinst` | `%post` | post-install |
| `preremove` | `prerm` | `%preun` | pre-deinstall |
| `postremove` | `postrm` | `%postun` | post-deinstall |

RPM также поддерживает `pretrans` и `posttrans` — через `overrides.rpm`.

### Порядок при обновлении пакета

```
1. preinstall (новой версии)
2. Установка файлов новой версии
3. postinstall (новой версии)
4. preremove (старой версии)  ← только если upgrade, не fresh install
5. Удаление файлов старой версии
6. postremove (старой версии) ← только если upgrade
```

Для определения, это первая установка или обновление, в скриптах можно проверить аргументы:

```bash
#!/bin/bash
# В deb-скриптах $1 содержит action:
# preinst: install, upgrade
# postinst: configure
# prerm: remove, upgrade, deconfigure
# postrm: remove, purge, upgrade, failed-upgrade

case "$1" in
  install)
    echo "Fresh install"
    ;;
  upgrade)
    echo "Upgrade from old version"
    ;;
esac
```

### Пример postinstall скрипта

```bash
#!/bin/bash
set -e

# Создать системного пользователя
if ! id -u crossler >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /bin/false crossler
fi

# Установить права на директорию данных
if [ -d /var/lib/crossler ]; then
  chown crossler:crossler /var/lib/crossler
fi

# Перезагрузить systemd
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable crossler.service 2>/dev/null || true
fi
```

---

## Зависимости, конфликты, замещения

```yaml
depends:
  - bash               # без ограничения версии
  - curl               # (конкретный синтаксис зависит от формата)

recommends:            # рекомендуемые (устанавливаются автоматически в apt)
  - jq

suggests:              # предлагаемые (не устанавливаются автоматически)
  - docker

conflicts:             # конфликтующие пакеты (не могут быть установлены вместе)
  - legacy-crossler

replaces:              # этот пакет заменяет (для корректного обновления)
  - old-crossler

provides:              # виртуальные пакеты которые предоставляет
  - package-builder
```

### Синтаксис ограничений версии по форматам

```yaml
overrides:
  deb:
    depends:
      - curl (>= 7.0)           # deb-стиль
      - libssl1.1 | libssl3     # OR-зависимость
      - python3 (>= 3.6)
  rpm:
    depends:
      - curl >= 7.0             # rpm-стиль
      - openssl >= 1.1
  apk:
    depends:
      - curl>=7.0               # apk-стиль (без пробелов)
      - libssl3
```

---

## Переопределения (overrides) по форматам

Секция `overrides` позволяет переопределить любые поля верхнего уровня для конкретного формата:

```yaml
# Общие зависимости
depends:
  - bash
  - curl

overrides:
  deb:
    # Переопределить зависимости для deb
    depends:
      - bash
      - curl (>= 7.0)
    # Переопределить скрипт
    scripts:
      postinstall: scripts/deb-post.sh
    # deb-специфичные поля
    deb:
      predepends:
        - libc6 (>= 2.17)
      triggers:
        interest:
          - /usr/lib/python3/dist-packages

  rpm:
    release: 1.el8
    depends:
      - bash
      - curl >= 7.0
    rpm:
      compression: zstd

  apk:
    depends:
      - bash
      - curl>=7.0
    apk:
      arch_overrides:
        amd64: x86_64
        arm64: aarch64
```

---

## Маппинг архитектур

nfpm принимает GOARCH нотацию и автоматически преобразует в формат-специфичные значения:

| GOARCH | deb | rpm | apk | archlinux |
|--------|-----|-----|-----|-----------|
| `amd64` | amd64 | x86_64 | x86_64 | x86_64 |
| `386` | i386 | i686 | x86 | i686 |
| `arm64` | arm64 | aarch64 | aarch64 | aarch64 |
| `arm7` (GOARM=7) | armhf | armv7hl | armv7 | armv7h |
| `arm6` | armel | armv6 | armv6 | armv6h |
| `ppc64le` | ppc64el | ppc64le | ppc64le | ppc64le |
| `s390x` | s390x | s390x | — | — |
| `mips` | mips | mips | — | — |
| `mipsle` | mipsel | mipsel | — | — |
| `all` | all | noarch | — | any |

---

## Специфика форматов

### .deb (Debian / Ubuntu)

Структура пакета:
```
package.deb
├── control.tar.gz      # метаданные: control, md5sums, conffiles, скрипты
└── data.tar.xz         # полезная нагрузка (файлы)
```

Дополнительные поля в `deb:`:
```yaml
deb:
  # Предварительные зависимости (должны быть установлены до основного пакета)
  predepends:
    - libc6 (>= 2.17)

  # Триггеры (уведомляют другие пакеты при установке)
  triggers:
    interest:              # этот пакет интересуется триггером
      - /usr/lib/python3/dist-packages
    activate:              # этот пакет активирует триггер
      - libc-bin

  # Поля для Breaks/Enhances (специфичные deb отношения)
  breaks:
    - old-myapp (< 2.0)

  # Метод подписи (gpg)
  signature:
    key_id: 1234567890ABCDEF
    signer: "Signer Name <signer@example.com>"
```

### .rpm (Red Hat / CentOS / Fedora)

Дополнительные поля в `rpm:`:
```yaml
rpm:
  release: 1            # обязательный для rpm: номер ревизии сборки
  # Для dist-специфичных ревизий:
  # release: 1.el8      # RHEL/CentOS 8
  # release: 1.fc38     # Fedora 38

  compression: gzip     # алгоритм сжатия: gzip, zstd, lzma, xz

  # Ghost файлы (только rpm) — файлы известные rpm, но не физически устанавливаемые
  # Объявляются в секции contents с type: ghost

  # Скрипты специфичные для rpm (дополнительно к preinstall/postinstall)
  scripts:
    pretrans: scripts/pretrans.sh    # перед транзакцией
    posttrans: scripts/posttrans.sh  # после транзакции
    verify: scripts/verify.sh        # при проверке пакета
```

### .apk (Alpine Linux)

Дополнительные поля в `apk:`:
```yaml
apk:
  # Переопределение имён архитектур
  arch_overrides:
    amd64: x86_64
    arm64: aarch64
    386: x86

  # Подпись (RSA, не PGP как в deb/rpm)
  signature:
    key_file: /etc/apk/keys/signing.rsa.key
    key_id: keyname      # имя ключа (используется как суффикс файла подписи)
```

Особенности APK:
- Самый лёгкий формат, идеален для Docker-образов
- Использует RSA-подпись вместо PGP
- Поддерживает только `preinstall` и `postinstall` скрипты (нет preremove/postremove в базовом APK)
- Нет triggers, predepends и других сложных deb/rpm механизмов

---

## Переменные и шаблонизация

### Переменные окружения в конфиге

nfpm поддерживает `expand: true` для отдельных полей contents:

```yaml
contents:
  - src: dist/${GOOS}_${GOARCH}/crossler
    dst: /usr/bin/crossler
    expand: true     # развернёт ${GOOS} и ${GOARCH} из окружения
```

Для поля `version` и других строковых полей — только напрямую при использовании через CI:

```bash
VERSION=1.2.3 nfpm package -c nfpm.yaml -p deb -t dist/
```

### Шаблонизация через envsubst (рекомендуемый подход)

nfpm сам не поддерживает шаблонизацию в YAML. Рекомендуется генерировать конфиг перед запуском:

```bash
# Шаблон nfpm.yaml.tmpl
name: ${APP_NAME}
version: ${VERSION}
arch: ${ARCH}
maintainer: ${MAINTAINER}

# Генерация и сборка
export APP_NAME=crossler VERSION=1.2.3 ARCH=amd64 MAINTAINER="Team <t@t.com>"
envsubst < nfpm.yaml.tmpl > nfpm.yaml
nfpm package -c nfpm.yaml -p deb -t dist/
```

### Шаблон имени файла

```yaml
# В конфиге не поддерживается напрямую, но при использовании через GoReleaser:
file_name_template: >-
  {{ .PackageName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}
```

---

## Практические примеры

### Пример 1: Консольная утилита Crossler

```yaml
name: crossler
version: ${VERSION}
arch: ${ARCH}
maintainer: "PowerTech Center <dev@powertech.center>"
description: |
  Cross-platform package creation tool.
  Delegates package building to external backends.
homepage: https://github.com/powertech-center/crossler
license: MIT
vendor: PowerTech Center

contents:
  - src: dist/crossler_linux_${ARCH}/crossler
    dst: /usr/bin/crossler
    type: file
    file_info:
      mode: 0755
    expand: true

  - src: README.md
    dst: /usr/share/doc/crossler/README.md
    type: doc

scripts:
  postinstall: scripts/postinstall.sh

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
```

Скрипт postinstall.sh:
```bash
#!/bin/bash
echo "crossler installed successfully"
echo "Run 'crossler --help' to get started"
```

Сборка:
```bash
for arch in amd64 arm64; do
  export ARCH=$arch VERSION=1.0.0
  envsubst < nfpm.yaml.tmpl > /tmp/nfpm-${arch}.yaml
  for fmt in deb rpm apk; do
    nfpm package -c /tmp/nfpm-${arch}.yaml -p $fmt -t dist/
  done
done
```

### Пример 2: Приложение с systemd-юнитом и пользователем

```yaml
name: myapp
version: 2.0.0
arch: amd64
maintainer: "Team <team@example.com>"
description: My web application
homepage: https://myapp.example.com
license: Apache-2.0

depends:
  - bash
  - ca-certificates

contents:
  - src: bin/myapp
    dst: /usr/bin/myapp
    type: file
    file_info:
      mode: 0755

  - src: config/defaults.yaml
    dst: /etc/myapp/config.yaml
    type: config|noreplace
    file_info:
      mode: 0640
      owner: myapp
      group: myapp

  - src: systemd/myapp.service
    dst: /lib/systemd/system/myapp.service
    type: file
    file_info:
      mode: 0644

  - dst: /var/lib/myapp
    type: dir
    file_info:
      mode: 0750
      owner: myapp
      group: myapp

  - dst: /var/log/myapp
    type: dir
    file_info:
      mode: 0750
      owner: myapp
      group: myapp

scripts:
  preinstall: scripts/preinstall.sh
  postinstall: scripts/postinstall.sh
  preremove: scripts/preremove.sh
  postremove: scripts/postremove.sh
```

scripts/preinstall.sh:
```bash
#!/bin/bash
set -e
getent group myapp >/dev/null || groupadd --system myapp
getent passwd myapp >/dev/null || useradd --system --gid myapp \
  --no-create-home --shell /bin/false myapp
```

scripts/postinstall.sh:
```bash
#!/bin/bash
set -e
systemctl daemon-reload
systemctl enable myapp.service
systemctl start myapp.service
```

scripts/preremove.sh:
```bash
#!/bin/bash
systemctl stop myapp.service || true
systemctl disable myapp.service || true
```

scripts/postremove.sh:
```bash
#!/bin/bash
systemctl daemon-reload
```

### Пример 3: Makefile-фрагмент для Crossler

```makefile
NFPM_VERSION ?= $(shell git describe --tags --abbrev=0)

.PHONY: packages-linux

packages-linux: dist/crossler_linux_amd64 dist/crossler_linux_arm64
	@for arch in amd64 arm64; do \
	  export VERSION=$(NFPM_VERSION) ARCH=$$arch; \
	  envsubst < packaging/nfpm.yaml.tmpl > /tmp/nfpm-$$arch.yaml; \
	  for fmt in deb rpm apk; do \
	    nfpm package -c /tmp/nfpm-$$arch.yaml -p $$fmt -t dist/; \
	  done; \
	done
```

---

## Best Practices и подводные камни

### Рекомендации

1. **Используйте `config|noreplace` для конфигов** — пользователи не теряют настройки при обновлении

2. **Явно указывайте права файлов** — особенно для бинарников (0755) и конфигов (0640/0644)

3. **Разделяйте зависимости по форматам** через `overrides` — синтаксис deb и rpm различается

4. **Всегда добавляйте `release: 1` для rpm** — без него сборка rpm может работать некорректно

5. **Используйте envsubst для шаблонизации** — nfpm не поддерживает шаблоны внутри YAML

6. **Тестируйте скрипты на целевой ОС** — то, что работает в bash, может не работать в /bin/sh Alpine

7. **Используйте set -e в скриптах** — это предотвратит молчаливое игнорирование ошибок

### Частые ошибки

- **Неправильный синтаксис зависимостей** — `curl (>= 7.0)` для deb, `curl >= 7.0` для rpm, `curl>=7.0` для apk
- **Отсутствие `/` в конце dst для директорий** — `dst: /usr/share/doc/myapp/` (с /) правильно для glob
- **Symlink в обратную сторону** — `src` = цель (куда указывает), `dst` = путь самой ссылки
- **Забыть `release` для rpm** — rpm-пакеты без поля release могут не устанавливаться
- **Ghost файлы только в rpm** — тип `ghost` просто игнорируется в deb/apk

---

## Ссылки

- [Официальный сайт nfpm](https://nfpm.goreleaser.com/)
- [Документация по конфигурации](https://nfpm.goreleaser.com/configuration/)
- [Tips & Hints](https://nfpm.goreleaser.com/tips/)
- [Маппинг архитектур](https://nfpm.goreleaser.com/goarch-to-pkg/)
- [GitHub репозиторий](https://github.com/goreleaser/nfpm)
- [Интеграция с GoReleaser](https://goreleaser.com/customization/nfpm/)

# Кроссплатформенная сборка установочных пакетов из Linux

Цель: из Linux (обычно в CI) собирать и публиковать установочные артефакты для:

- Windows `amd64`, Windows `arm64`
- Linux `amd64`, Linux `arm64`
- macOS `amd64`, macOS `arm64` (и опционально **universal2**)

Проектные языки: Go (главный), а также Rust и C/C++ — это влияет на *сборку бинарников*, но **философия упаковки** в пакеты на уровне ОС во многом одинаковая.

Важно: ниже — исследование по инструментам и практикам упаковки. Оно **не использует** файлы текущего проекта.

---

## 1) Типовые задачи при создании установочных пакетов

Ниже — задачи, которые почти всегда возникают независимо от платформы.

### 1.1 Метаданные и идентичность пакета

- **Имя пакета**
  - Linux: имя пакета в `deb/rpm/apk` часто имеет правила (строчные, без пробелов и т.п.).
  - Windows: `ProductName`, `ProductCode`, `UpgradeCode` (MSI).
  - macOS: bundle id / identifier (`com.company.app`), product identifier.
- **Версия**
  - Linux: `deb` требует, чтобы версия начиналась с цифры (часто `v` нужно убирать).
  - Windows MSI и macOS pkg также чувствительны к схемам версии.
- **Vendor/maintainer/homepage/license/description**

### 1.2 Состав содержимого и размещение файлов

Типовые назначения:

- **Бинарники CLI**
  - Linux: `/usr/bin`, `/usr/local/bin` (зависит от политики)
  - macOS: часто `/Applications/MyApp.app` для GUI; для CLI — `/usr/local/bin` или отдельный pkg
  - Windows: `Program Files` (и регистрация PATH по желанию)
- **Конфиги**
  - Linux: `/etc/<name>/...` и важное поведение при апгрейде (`noreplace` / conffiles).
  - Windows: `%ProgramData%`, `%AppData%` — часто не стоит перетирать.
- **Данные/кеш/логи**
  - Linux: `/var/lib`, `/var/cache`, `/var/log`.
  - RPM: часто нужно “владение” директориями, иначе удаление/апгрейд ведут себя неожиданно.
- **Документация / manpages**
  - Linux: `/usr/share/doc`, `/usr/share/man/...`.

### 1.3 Права, владельцы, SELinux/AppArmor

- Права на файлы (`0644`, `0755`) и владельцы (`root:root` и т.п.).
- На Linux иногда нужны политики (SELinux) — чаще решается через distro packaging (rpmbuild/debhelper) либо пост-инстал скриптами.

### 1.4 Скрипты жизненного цикла и “хуки”

- Linux: `preinstall/postinstall/preremove/postremove` (и аналоги у apk/rpm/deb).
- Windows MSI: Custom Actions, ServiceInstall/ServiceControl, реестр.
- macOS pkg: `preinstall/postinstall` скрипты.

Важно: хуки усложняют поддержку и тестирование, но без них часто нельзя:

- создание системных пользователей/групп
- миграции конфигов и данных
- регистрация сервисов
- перезапуск демонов при апгрейде

### 1.5 Сервисы/демоны

- Linux: systemd units (`/lib/systemd/system/...`), enable/start/daemon-reload.
- Windows: сервисы (SCM), MSI таблицы для установки/управления сервисом или внешние инструменты.
- macOS: LaunchDaemon / LaunchAgent (`/Library/LaunchDaemons/...`).

### 1.6 PATH / “доступность команды без полного пути”

- Linux: кладёте бинарник в `/usr/bin` — обычно достаточно.
- Windows: либо добавляете каталог установки в PATH, либо кладёте shim/launcher, либо используете `winget`/MSIX механизмы, либо просите пользователя.
- macOS: для CLI аналогично Linux (через pkg), но для GUI-приложений PATH не решается автоматически.

### 1.7 Конфликты, “replaces/provides/obsoletes” и collisions

- Linux: `conflicts`, `replaces`, `provides`, `breaks` и т.д.
- Windows MSI: важны `UpgradeCode` и правила апгрейда/major upgrade; конфликты файлов обычно решаются через правила MSI и план миграции.
- macOS: конфликты чаще решаются корректным identifier и дисциплиной путей.

### 1.8 Апгрейды и сохранение пользовательских данных

- Нужно гарантировать:
  - **не перетирать пользовательские конфиги** при обновлении
  - корректно мигрировать формат конфигов/данных
  - минимизировать downtime сервисов

### 1.9 Подпись, trust chain, “проверяемость”

- Linux: подпись пакета и/или репозитория (APT repo metadata, RPM repo metadata). Инструменты часто требуют GPG.
- Windows: подпись `.exe/.msi/.msix` через Authenticode (обычно выполняется на Windows или с использованием специальных тулчей/SDK).
- macOS: `codesign` + **notarization** (Apple Notary Service) + `stapler`.
  - Apple отдельно подчёркивает: если у вас вложенные контейнеры, **нотарифицируйте только внешний** (например, DMG с pkg внутри).

### 1.10 Тестирование установки/удаления

Типовой минимальный набор тестов на каждый таргет:

- install
- run
- upgrade (N-1 → N)
- uninstall
- re-install
- проверка сохранности конфигов/данных

---

## 2) Две стратегии сборки пакетов (практический выбор)

### 2.1 “Нативные пакеты” на каждую ОС

- Linux: `deb/rpm/apk` (часто несколько вариантов)
- Windows: MSI / EXE installer / MSIX
- macOS: `.pkg` и/или `.dmg`

Плюс: лучший UX для пользователей и админов, интеграция с ОС.
Минус: больше инструментов/пайплайнов, сложнее поддерживать.

### 2.2 “Универсальные” форматы как доп. канал

- Linux: AppImage / Snap / Flatpak

Плюс: меньше distro-specific боли.
Минус: ограничения sandbox/политик, иной UX, иногда не подходит для серверных демонов.

На практике часто делают **оба**:

- “официальные” `deb/rpm` для серверов и админов
- Snap/Flatpak для desktop
- AppImage как portable-артефакт

### 2.3 Универсальные решения “одним инструментом на 3 ОС” — что реально есть

Если под “универсальным решением” понимать *один конфиг/один тул*, который умеет выпускать инсталляторы под Windows+Linux+macOS, то **такие решения есть**, но почти всегда с ограничениями:

- они лучше подходят для **desktop GUI** приложений, чем для серверных демонов
- они либо генерируют **не самые нативные** пакеты, либо внутри всё равно используют нативные backend’ы
- для **подписей/нотаризации** часто нужна целевая ОС (особенно macOS)

Ниже — наиболее “достойные” варианты, которые в 2025–2026 широко используются.

#### CMake + CPack

- **Документация**
  - CPack module: https://cmake.org/cmake/help/latest/module/CPack.html
  - CPack productbuild generator (macOS pkg): https://cmake.org/cmake/help/latest/cpack_gen/productbuild.html
  - CPack DragNDrop generator (macOS dmg): https://cmake.org/cmake/help/latest/cpack_gen/dmg.html
- **Философия**
  - CPack — слой упаковки поверх `install()` в CMake: вы описываете установку артефактов через `install(...)`, а затем `cpack` генерирует пакеты разного типа.
  - `cpack` может итеративно собрать **несколько форматов** за один прогон (через `CPACK_GENERATOR`).
- **Что умеет (важное из доков)**
  - Входными файлами для бинарных пакетов являются файлы, установленные через CMake `install()`.
  - В `CPACK_GENERATOR` можно перечислить генераторы, и `cpack` соберёт по одному пакету на каждый.
  - Для macOS есть генераторы, завязанные на нативные утилиты:
    - `productbuild`/`pkgbuild` (для `.pkg`)
    - DragNDrop (для `.dmg`, опции UDZO/DS_Store/background/и т.д.)
- **Плюсы**
  - особенно хорош для C/C++/Rust проектов, где CMake и так “источник правды” по установке файлов
  - один слой метаданных/версий для нескольких пакетных форматов
  - есть генераторы для Windows (WiX/NSIS), Linux (deb/rpm и др.), macOS (pkg/dmg)
- **Минусы / практические ограничения**
  - качество “нативности” зависит от выбранного generator’а: иногда требуется тонкая настройка, а где-то проще сделать WiX/deb/rpm отдельно
  - если вы хотите **подписывать** и особенно **нотаризировать** macOS артефакты, всё равно нужна инфраструктура с macOS toolchain

#### Qt Installer Framework (Qt IFW)

- **Документация**
  - Overview: https://doc.qt.io/qtinstallerframework/ifw-overview.html
  - Tools: https://doc.qt.io/qtinstallerframework/ifw-tools.html
- **Философия**
  - один фреймворк для GUI-инсталлятора с “native look & feel” на Windows/macOS/Linux
  - поддерживает offline installers (всё внутри) и online installers (репозиторий + maintenance tool)
- **Ключевые инструменты**
  - `binarycreator` — сборка offline/online installer’ов
  - `repogen` — генерация online repository
- **Плюсы**
  - хороший UX для desktop, компоненты, обновления через maintenance tool
  - подходит, если вы хотите единый “брендированный” инсталлятор, а не строго deb/rpm/msi
- **Минусы**
  - это **не** замена системных пакетных менеджеров Linux (скорее отдельный инсталлятор)
  - подпись/нотаризация и platform-specific требования остаются (в overview отдельно подчёркивается важность signing, включая macOS notarizing)

#### BitRock InstallBuilder

- **Документация**
  - User Guide: https://releases.installbuilder.com/installbuilder/docs/installbuilder-userguide/_installation_and_getting_started.html
- **Философия**
  - коммерческий инструмент для сборки кроссплатформенных инсталляторов; один проект может билдиться на разных ОС.
- **Плюсы**
  - ориентирован на сценарий “один проект — много платформ”, много встроенных действий инсталлятора
- **Минусы**
  - коммерческая лицензия
  - как и Qt IFW, это часто “свой инсталлятор”, а не строго distro-native пакеты

#### electron-builder (экосистема Electron)

- **Документация**
  - Multi platform build: https://www.electron.build/multi-platform-build.html
  - Linux targets: https://www.electron.build/linux.html
- **Философия**
  - сделать релиз Electron-приложения во множество форматов: Windows installer, macOS dmg, Linux deb/rpm/appimage/snap/flatpak и др.
- **Что важно про сборку из Linux (из доков)**
  - electron-builder описывает сборку Windows-таргетов на Linux через Wine и рекомендует Docker-образ `electronuserland/builder:wine`.
- **Плюсы**
  - практически стандарт для Electron desktop
  - действительно покрывает “три ОС” одним конфигом
- **Минусы**
  - применимо в основном к Electron
  - для некоторых таргетов нужны специфические зависимости (Wine/Mono/подпись)

#### Tauri (tauri-bundler)

- **Документация**
  - Distribute: https://v2.tauri.app/distribute/
- **Философия**
  - кроссплатформенный toolkit; “bundling” для Windows/macOS/Linux интегрирован в toolchain.
- **Покрытие по форматам (из доков)**
  - Linux: Debian package, Snap, AppImage, Flatpak, RPM, AUR
  - macOS: App Store или DMG (с требованием code signing + notarization)
  - Windows: Microsoft Store или Windows installer
- **Плюсы**
  - хорошо подходит для desktop, если у вас Rust + webview архитектура
- **Минусы**
  - это не универсальный “упаковщик любых Go/Rust/C++ бинарников”; это packaging в рамках экосистемы Tauri

#### Вывод по “универсальности”

Универсальные решения существуют, но они делятся на два класса:

- **Desktop-ориентированные фреймворки** (electron-builder, Tauri, Qt IFW, InstallBuilder):
  - реально дают один конфиг/проект на 3 ОС
  - чаще всего генерируют DMG/EXE/MSI-подобные инсталляторы и/или Linux форматы
  - отлично подходят для GUI-продуктов
- **Генераторы/оркестраторы поверх нативной установки** (CPack):
  - могут закрыть много форматов одним слоем, но качество зависит от generator’ов

Для **CLI/daemon/server** продуктов по-прежнему обычно выигрывает подход “best-of-breed”:

- Linux: `nfpm`/`debhelper`/`rpmbuild`
- Windows: WiX/MSI или MSIX
- macOS: `productbuild`/`pkgbuild` + `codesign` + `notarytool`/`stapler`

---

## 3) Инструменты для Linux (deb/rpm/apk/arch/ipk) из Linux

### 3.1 nFPM (goreleaser/nfpm)

- **Документация**
  - https://nfpm.goreleaser.com/docs/quick-start/
  - https://nfpm.goreleaser.com/docs/configuration/
- **Философия**
  - “Not FPM”: простой, минималистичный, без Ruby и лишних зависимостей, ориентирован на сборку пакетов из уже готовых артефактов.
  - Конфигурация описывает метаданные + список файлов + lifecycle скрипты.
- **Плюсы**
  - 0/минимум внешних зависимостей (Go-бинарник)
  - поддерживает несколько форматов: `deb`, `rpm`, `apk`, `ipk`, `archlinux`
  - есть понятная модель “contents + scripts + overrides”
- **Минусы**
  - это не полный “distro packaging” фреймворк: нет глубокого соответствия политикам конкретных дистрибутивов как у `debhelper/rpmbuild`.
  - шаблонизация намеренно ограничена (в конфиге прямо сказано, что templating “не будет поддерживаться”)
- **Типовые задачи — как делать**

1) Инициализация:

```bash
nfpm init
```

(создаёт `nfpm.yaml` с примерами)

2) Сборка:

```bash
nfpm package
# или явно
nfpm pkg --packager deb --target /tmp/
nfpm pkg --packager rpm --target /tmp/
nfpm pkg --packager apk --target /tmp/
```

3) Размещение файлов и конфигов

`nfpm` позволяет задавать `contents` со схемами `config`, `config|noreplace`, `symlink`, `dir`, `ghost` и т.п.

Пример идеи (упрощённо):

```yaml
contents:
  - src: ./dist/mytool
    dst: /usr/bin/mytool
  - src: ./packaging/mytool.conf
    dst: /etc/mytool/mytool.conf
    type: config|noreplace
scripts:
  postinstall: ./scripts/postinstall.sh
  preremove: ./scripts/preremove.sh
```

4) Конфликты/depends/replaces/provides

В `nfpm.yaml` есть поля `depends`, `conflicts`, `replaces`, `provides`.

5) Подпись

В `nfpm` есть секции signature для `rpm`/`deb`/`apk`.

### 3.2 GoReleaser + nFPM

- **Документация**
  - https://goreleaser.com/customization/nfpm/
- **Философия**
  - GoReleaser оркестрирует сборку бинарников/архивов/чек-сумм/релизов и может дергать `nfpm` как “пакетный этап”.
- **Полезные детали**
  - passphrase для ключей берётся из env var по приоритету:
    - `$NFPM_[ID]_[FORMAT]_PASSPHRASE`
    - `$NFPM_[ID]_PASSPHRASE`
    - `$NFPM_PASSPHRASE`

### 3.3 FPM (jordansissel/fpm)

- **Документация**
  - https://github.com/jordansissel/fpm
  - (upstream docs) http://fpm.readthedocs.io/en/latest/
- **Философия**
  - сделать “быстро и просто”: “вот каталог/архив/пакет — сделай мне deb/rpm/pkg”.
- **Плюсы**
  - очень гибкий: умеет конвертировать и “тюнить” пакеты
  - много источников/таргетов
- **Минусы**
  - Ruby-зависимость и окружение
  - часто используется как “быстрый молоток”, но при росте требований начинает требовать дисциплины

### 3.4 Нативные toolchains: dpkg-deb/debhelper, rpmbuild

- **Документация**
  - Debian packaging: https://www.debian.org/doc/manuals/maint-guide/
  - RPM packaging: https://rpm-packaging-guide.github.io/
- **Философия**
  - “делай как дистрибутив”: spec/control/rules, строгие политики, интеграция.
- **Плюсы**
  - максимально “правильно” по правилам конкретных экосистем
- **Минусы**
  - выше порог входа
  - труднее поддерживать много distro/arch комбинаций без инфраструктуры (OBS, COPR)

### 3.5 Универсальные Linux-форматы

#### AppImage

- **Документация**
  - https://docs.appimage.org/packaging-guide/manual.html
- **Философия**
  - portable “один файл”, который содержит приложение и (часто) его зависимости.
- **Ключевые моменты из доков**
  - нужно собрать структуру `AppDir` и избегать “hard-coded paths”, т.к. AppImage предполагает relocatable упаковку.
  - сборка финального файла через `appimagetool`.

Типовой каркас:

```
MyApp.AppDir/
  AppRun
  myapp.desktop
  myapp.png
  usr/bin/myapp
  usr/lib/...
```

#### Snap (snapcraft)

- **Документация**
  - https://documentation.ubuntu.com/snapcraft/stable/tutorials/craft-a-snap/
- **Философия**
  - sandboxed пакет, обычно через Snap Store; хорош для desktop и некоторых server use-cases.
- **Типовые вещи**
  - метаданные в `snapcraft.yaml` (name/base/version/summary/description)
  - таргет платформы задаётся `platforms: amd64:` и т.п.
  - сборка: `snapcraft pack`

#### Flatpak

- **Документация**
  - manifests: https://docs.flatpak.org/en/latest/manifests.html
  - builder: https://docs.flatpak.org/en/latest/flatpak-builder.html
- **Философия**
  - sandboxed desktop-ориентированная доставка + runtimes.
- **Типовые вещи**
  - manifest задаёт `id`, `runtime`, `runtime-version`, `sdk`, `command`
  - экспортируемые файлы (`.desktop`, icons) должны быть prefixed app id
  - разрешения sandbox задаются через `finish-args`
  - публикация репо должна быть GPG-signed (`flatpak-builder --gpg-sign=<key> --repo=... <manifest>`)

---

## 4) Инструменты для Windows (из Linux/CI)

Windows-упаковка — самая “неудобная” часть именно **из Linux**, потому что:

- MSI/Authenticode-цепочка и многие официальные инструменты живут в Windows SDK
- часть тулов можно запускать через Wine, но это повышает риск нестабильности

На практике часто делают так:

- сборка windows-бинарников (Go/Rust) происходит из Linux через cross-compile
- упаковка MSI/MSIX и подпись — либо отдельный job на Windows runner, либо использование кросс-платформенных инструментов (msitools), либо Wine.

### 4.1 WiX Toolset (WiX v4/v5/v6, современный dotnet tool)

- **Документация**
  - Using WiX: https://docs.firegiant.com/wix/using-wix/
  - wix.exe: https://docs.firegiant.com/wix/tools/wixexe/
  - Quick start: https://docs.firegiant.com/quick-start/
- **Философия**
  - декларативное описание установки (XML `.wxs`) + сборка в MSI/Bundle.
  - современный путь — WiX как MSBuild SDK и/или `wix` как `.NET tool`.
- **Плюсы**
  - де-факто стандарт для серьёзных MSI
  - мощная модель апгрейдов, компонентов, фич
- **Минусы**
  - крутая кривая обучения
  - реально “удобно” собирать на Windows, хотя часть сценариев можно автоматизировать иначе

**Минимальный пример из Quick Start (WiX v4)**

WiX проект:

```xml
<Project Sdk="WixToolset.Sdk/6.0.0"></Project>
```

WiX source (`Package.wxs`) с одним файлом:

```xml
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Id="AcmeCorp.QuickStartExample" Name="QuickStart Example"
           Manufacturer="ACME Corp" Version="0.0.1">
    <File Source="example.txt" />
  </Package>
</Wix>
```

Сборка:

```bash
# требует .NET SDK
# (в примере docs это Windows cmd, но смысл тот же)
dotnet build
```

Итог: `bin\Debug\QuickStart.msi`.

**CLI-инструмент**

WiX можно поставить как global tool:

```bash
dotnet tool install --global wix
wix --version
```

Команды `wix.exe` включают `wix build`, `wix msi ...`, `wix burn ...`.

### 4.2 msitools (GNOME) + wixl

- **Документация**
  - https://github.com/GNOME/msitools
- **Философия**
  - собрать/инспектировать MSI из Linux, как решение для “packaging and deployment of cross-compiled Windows applications”.
- **Плюсы**
  - работает на Linux
  - есть `wixl` (WiX-like) и `wixl-heat` для генерации XML фрагментов из директорий
- **Минусы**
  - сам проект отмечает раннюю стадию и что `wixl` “lacks many features compared to WiX”
  - msitools не работает под Windows (планируется self-host)

Инструменты:

- `msiinfo`, `msibuild`, `msidiff`, `msidump`, `msiextract`
- `wixl` (WiX-like builder)
- `wixl-heat` (генерация XML фрагментов)

### 4.3 MSIX + MakeAppx.exe (обычно Windows SDK)

- **Документация**
  - MakeAppx.exe: https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool
- **Философия**
  - современный контейнер приложения с более предсказуемой установкой/удалением, чем MSI.
- **Плюсы**
  - чистая установка/удаление, хороший UX
- **Минусы**
  - часто требует Windows SDK и практик вокруг подписи

Из доков: `MakeAppx pack` может собирать из директории или mapping file:

```text
MakeAppx pack /d <content directory> /p <output package name>
MakeAppx pack /f <mapping file> /p <output package name>
```

### 4.4 WinGet (как канал доставки, а не “инсталлятор”)

- **Документация**
  - manifests: https://learn.microsoft.com/en-us/windows/package-manager/package/manifest
- **Философия**
  - WinGet — пакетный менеджер Windows. Вы публикуете manifest, а `InstallerUrl` указывает на ваш MSI/EXE/MSIX.
- **Плюсы**
  - хороший канал распространения, автоматизация обновлений
- **Минусы**
  - WinGet не заменяет необходимость иметь нормальный installer

Минимальные поля manifest включают (схема v1.6.0):

- `PackageIdentifier`, `PackageVersion`, `PackageLocale`, `Publisher`, `PackageName`, `License`, `ShortDescription`
- `Installers` (архитектура, тип установщика, URL, sha256)

### 4.5 NSIS / Inno Setup (часто через Wine)

- **Документация**
  - NSIS: https://nsis.sourceforge.io/Docs/
  - Inno Setup (ISCC CLI): https://jrsoftware.org/ishelp/topic_compilercmdline.htm
- **Философия**
  - генерация `.exe` установщиков через скрипт.
- **Плюсы**
  - проще MSI для базовых сценариев
  - часто удобнее делать “просто поставь файлы”
- **Минусы**
  - интеграция с enterprise-экосистемой хуже, чем у MSI
  - из Linux обычно требует Wine

---

## 5) Инструменты для macOS (.pkg / .dmg) и notarization

### 5.1 Apple: productbuild/pkgbuild/pkgutil + security/codesign/hdiutil

- **Документация**
  - Packaging Mac software for distribution (Apple):
    https://developer.apple.com/tutorials/data/documentation/xcode/packaging-mac-software-for-distribution.md
  - Notarizing macOS software before distribution:
    https://developer.apple.com/tutorials/data/documentation/security/notarizing-macos-software-before-distribution.md
- **Философия**
  - Apple-канонический pipeline: codesign → pkg/dmg → notarize → staple.

Из Apple doc:

- Проверить installer-signing identity:

```bash
security find-identity -v
```

- Простейший `productbuild` для app:

```bash
productbuild --sign <Identity> --component <PathToApp> /Applications <PathToPackage>
```

- Для DMG:

```bash
hdiutil create -srcFolder <ProductDirectory> -o <DiskImageFile>
codesign -s <CodeSigningIdentity> --timestamp -i <Identifier> <DiskImageFile>
```

- Apple рекомендует при “nested containers” notarize **только внешний контейнер**.
- Staple для dmg пример:

```bash
xcrun stapler staple FlyingAnimals.dmg
```

### 5.2 create-dmg (обёртка вокруг hdiutil + “косметика”)

- **Документация**
  - https://github.com/create-dmg/create-dmg
- **Философия**
  - скрипт, который делает “красивые DMG”: фон, иконки, symlink на Applications.
- **Плюсы**
  - удобно автоматизировать внешний вид
  - поддерживает codesign/notarize параметры (в рамках возможностей окружения)
- **Минусы**
  - всё равно нужен Apple toolchain (обычно macOS runner) для подписей/нотарификации

Пример использования:

```bash
create-dmg [options] <output_name.dmg> <source_folder>
```

---

## 6) Архитектуры: amd64/arm64 и 6 таргетов

### 6.1 Windows

- два отдельных артефакта:
  - `windows/amd64`
  - `windows/arm64`

В MSI/MSIX можно делать либо отдельные пакеты, либо bundle.

### 6.2 Linux

- `deb/rpm/apk` обычно отдельные файлы на arch.
- универсальные форматы (snap/flatpak/appimage) тоже чаще делаются per-arch.

### 6.3 macOS

- `darwin/amd64`
- `darwin/arm64`
- опционально **universal2**

Universal2 обычно означает один `.app`, в котором есть два “слайса” (arm64+x86_64) в бинарнике.

Практически:

- для Go: универсальный бинарник можно собрать через `lipo` из двух сборок (это требует macOS toolchain и обычно делается на macOS runner).
- для Rust/C++ аналогично: нужно собрать отдельно и затем “склеить”.

---

## 7) Рекомендованный “реалистичный” пайплайн из Linux CI

Ниже — подход, который обычно минимизирует боль.

### 7.1 Сборка бинарников (из Linux)

- Go: `GOOS/GOARCH` кросс-компиляция
- Rust: `cross` / `cargo zigbuild` / dockerized toolchains
- C/C++: clang/zig/оснастка под target (часто контейнеры)

### 7.2 Упаковка

- Linux пакеты (`deb/rpm/apk`):
  - **nFPM** как базовый инструмент, особенно если вам важны простота и единый конфиг
  - если нужны строгие distro-политики — `debhelper/rpmbuild` + инфраструктура (OBS)

- Windows:
  - если MSI критичен: WiX (часто на Windows runner)
  - если хотите из Linux: попробовать msitools/wixl, но учитывать ограничения
  - дополнительно: публиковать WinGet manifest для удобства доставки

- macOS:
  - сборка `.pkg/.dmg` и подпись/нотаризация практически всегда требуют macOS runner
  - из Linux имеет смысл только готовить “payload”

### 7.3 Подпись и trust

- Linux: подпись пакетов/репо (GPG)
- Windows: подпись Authenticode (обычно Windows)
- macOS: codesign + notarization + staple (macOS)

---

## 8) Быстрый выбор инструмента (шпаргалка)

### Если у вас Go-проект и нужна простая упаковка Linux

- **nFPM** (или GoReleaser+nFPM)

### Если нужны “правильные” distro пакеты и публикация в репозитории

- `debhelper` / `rpmbuild` + OBS/COPR + репозитории

### Если нужен “enterprise-style” MSI

- **WiX Toolset** (скорее всего на Windows runner)

### Если нужна упаковка MSI прямо на Linux

- **msitools/wixl** (принимать ограничения)

### Если нужен “portable single-file” для Linux

- **AppImage**

### Если нужен sandboxed desktop distribution

- **Snap** / **Flatpak**

---

## 9) Ссылки (основные)

- nFPM
  - https://nfpm.goreleaser.com/docs/quick-start/
  - https://nfpm.goreleaser.com/docs/configuration/
- GoReleaser + nFPM
  - https://goreleaser.com/customization/nfpm/
- fpm
  - https://github.com/jordansissel/fpm
- WiX Toolset
  - https://docs.firegiant.com/wix/using-wix/
  - https://docs.firegiant.com/wix/tools/wixexe/
  - https://docs.firegiant.com/quick-start/
- msitools
  - https://github.com/GNOME/msitools
- MSIX / MakeAppx
  - https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool
- WinGet manifests
  - https://learn.microsoft.com/en-us/windows/package-manager/package/manifest
- Apple packaging & notarization
  - https://developer.apple.com/tutorials/data/documentation/xcode/packaging-mac-software-for-distribution.md
  - https://developer.apple.com/tutorials/data/documentation/security/notarizing-macos-software-before-distribution.md
- create-dmg
  - https://github.com/create-dmg/create-dmg
- AppImage
  - https://docs.appimage.org/packaging-guide/manual.html
- Snapcraft
  - https://documentation.ubuntu.com/snapcraft/stable/tutorials/craft-a-snap/
- Flatpak
  - https://docs.flatpak.org/en/latest/manifests.html
  - https://docs.flatpak.org/en/latest/flatpak-builder.html

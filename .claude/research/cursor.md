# Кроссплатформенная сборка установочных пакетов из Linux

Документ описывает типовые задачи при создании установочных пакетов для приложений (CLI и сервисы/демоны) и даёт обзор популярных утилит, подходящих для сборки из Linux под 6 таргетов:

- Linux: `linux/amd64`, `linux/arm64`
- Windows: `windows/amd64`, `windows/arm64`
- macOS: `darwin/amd64`, `darwin/arm64` (и «универсальные» сборки)

Фокус: кроссплатформенные проекты на Go, Rust, C/C++, собираемые и упаковываемые на Linux.

---

## 1. Типовые задачи и проблемы при создании установочных пакетов

### 1.1. Цели упаковки

Типичные цели:

- Унифицированный способ доставки бинарников и сопутствующих файлов пользователю.
- Интеграция с инфраструктурой ОС:
  - Linux: пакетные менеджеры (`apt`, `dnf`, `yum`, `apk`, `pacman` и т.п.).
  - Windows: Windows Installer (MSI), EXE‑инсталляторы.
  - macOS: `.pkg`, `.dmg`, Homebrew, архивы.
- Управление жизненным циклом:
  - установка/обновление/удаление;
  - миграции данных и конфигураций;
  - запуск/рестарт демонов и сервисов.

### 1.2. Базовые метаданные пакета

Во всех системах нужны:

- **Имя пакета**: уникальное в рамках экосистемы (Linux — часто с префиксом/неймингом под дистрибутив, Windows — `ProductName`, macOS — идентификатор bundle).
- **Версия**: обычно SemVer (`MAJOR.MINOR.PATCH`), иногда с суффиксами (`-rc1`, `-beta`).
- **Архитектура**: `amd64`/`x86_64`, `arm64`/`aarch64`; иногда `all` (архитектурно‑независимые пакеты).
- **Описание, homepage, лицензия, vendor/maintainer**.
- **Категории / теги** (в Linux — `Section`, `Priority`, в macOS — `CFBundleCategoryType` и т.п.).

### 1.3. Размещение файлов

Ключевые решения:

- **Где лежит бинарник**:
  - Linux: обычно `/usr/bin` или `/usr/local/bin`.
  - Windows: `%ProgramFiles%\Vendor\App\bin` (64‑бит) и иногда `%ProgramFiles(x86)%` для 32‑бит.
  - macOS: CLI — `/usr/local/bin` или через Homebrew (`/usr/local/Cellar` / `/opt/homebrew`); GUI — `.app` bundle в `/Applications`.
- **Конфигурация**:
  - Linux: обычно `/etc/<app>/config.yml`.
  - Windows: `C:\ProgramData\<App>\config.yml` либо `%ProgramFiles%\...`, либо реестр.
  - macOS: `/Library/Application Support/<App>` или `~/Library/Application Support/<App>`.
- **Данные, логи, кэш**:
  - Linux: `/var/lib/<app>`, `/var/log/<app>`, `/var/cache/<app>`.
  - Windows: `%ProgramData%\<App>`, `%LOCALAPPDATA%\<App>`.
  - macOS: `~/Library/Logs`, `~/Library/Caches`.

### 1.4. Конфигурационные файлы

Основные задачи:

- Установить **дефолтный конфиг**.
- Не затирать **пользовательские изменения** при обновлениях.
- Опционально — мигрировать формат конфига между версиями.

Подходы:

- Linux (deb/rpm):
  - помечать файлы как `config` / `conffile` (Debian) или `%config(noreplace)` (RPM);
  - миграции — в `preinst`/`postinst`/`preun`/`postun` скриптах.
- Windows:
  - инсталлятор кладёт дефолтный конфиг, при обновлении:
    - либо не трогает существующий файл;
    - либо пишет рядом `.example` и документирует ручное обновление;
    - сложные случаи — собственный мигратор, запускаемый из installer custom action.
- macOS:
  - похожий подход: дефолтный конфиг + аккуратное обновление/слияние.

### 1.5. Демоны и сервисы

- **Linux**:
  - systemd unit (`/lib/systemd/system/<app>.service` или `/etc/systemd/system/...`);
  - enable/disable + start/stop через `systemctl` в post‑/pre‑install скриптах;
  - учёт разных init‑систем (systemd, OpenRC и т.п.) при необходимости.
- **Windows**:
  - Windows Service (Service Control Manager);
  - регистрация сервиса в инсталляторе (MSI custom actions или сценарий NSIS);
  - выбор типа запуска: auto/manual/delayed, «run as» учётной записи.
- **macOS**:
  - `launchd` plist в `/Library/LaunchDaemons` или `~/Library/LaunchAgents`;
  - загрузка/перезапуск через `launchctl`.

### 1.6. Доступ к утилитам через PATH

Задача: сделать так, чтобы бинарь был доступен как простая команда без полного пути.

Способы:

- Кладём бинарь в директорию, которая уже в PATH:
  - Linux: `/usr/bin`, `/usr/local/bin`.
  - macOS: `/usr/local/bin` или директория, в которую пишет Homebrew.
- Создаём **symlink** или маленький wrapper‑скрипт в такой директории.
- Модифицируем PATH:
  - Windows: через MSI таблицу `Environment` или скрипт (NSIS, PowerShell);
  - Linux/macOS: лучше избегать прямого изменения глобального PATH инсталлятором — предпочтительнее использовать стандартные директории.

### 1.7. Зависимости и конфликты

Типовые задачи:

- Объявить зависимости:
  - Linux: `Depends`, `Recommends`, `Suggests` (deb), `Requires` (rpm).
  - Windows: зависимость часто выражается через bundled DLLs или отдельные инсталляторы (VC++ runtime и т.п.).
  - macOS: обычно статика/бандлинг, либо зависимость через Homebrew.
- Объявить конфликты:
  - Linux: `Conflicts`, `Replaces`, `Obsoletes`.
  - Используется для:
    - миграции с `old-app` на `new-app`;
    - разделения пакетов на edition’ы, которые не должны сосуществовать.

### 1.8. Скрипты жизенного цикла

Во всех системах есть аналоги:

- **Linux**: `preinst`, `postinst`, `prerm`, `postrm`, `triggers`.
- **RPM**: `%pre`, `%post`, `%preun`, `%postun`, `%trigger`.
- **Windows MSI**: custom actions (DLL, EXE, скрипты).
- **NSIS**: секции `Section`, `SectionEnd`, callbacks `Function .onInit`, `Function un.onUninstSuccess` и т.п.
- **macOS pkg**: `preinstall`, `postinstall` скрипты.

Через них:

- создаём пользователей/группы, директории с правами;
- мигрируем БД, конфиги;
- регистрируем/перезапускаем сервисы;
- выполняем очистку на удаление.

### 1.9. Подпись и доверие

Критично для production:

- **Linux**:
  - пакеты обычно подписываются GPG‑ключом репозитория;
  - пользователь доверяет целому репозиторию, а не отдельным `.deb`/`.rpm`.
- **Windows**:
  - Authenticode подпись бинарей/инсталляторов (сертификат Code Signing);
  - улучшает UX (меньше страшных warning’ов SmartScreen).
- **macOS**:
  - `codesign` + notarization через Apple;
  - в Gatekeeper неподписанные/ненотаризованные приложения запускаются с осложнениями.

Существенное ограничение: **подпись macOS‑пакетов и notarization требуют macOS**. Из Linux вы можете собрать содержимое пакета, но финальную подпись и notarization почти всегда будут делать на macOS‑runner’е.

### 1.10. Мульти‑архитектура и универсальные сборки

Подход:

- **Отдельные пакеты на архитектуру**:
  - разные имена файлов артефактов: `myapp_1.2.3_linux_amd64.deb`, `myapp_1.2.3_linux_arm64.deb` и т.п.;
  - в метаданных правильно выставленная `Architecture`.
- **Универсальные сборки (macOS Universal)**:
  - объединение нескольких Mach‑O бинарников (x86_64 + arm64) в один через `lipo` или `clang` с нужными флагами;
  - такое объединение (и дальнейший `codesign`) практически всегда выполняют на macOS.

---

## 2. Общая стратегия для сборки из Linux

Реалистичная стратегия (учитывая ограничения по подписи macOS):

1. **Кросс‑компиляция бинарников**:
   - Go: через `GOOS`/`GOARCH` (`linux`, `windows`, `darwin` + `amd64`/`arm64`).
   - Rust: через таргеты (`x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `x86_64-pc-windows-gnu/msvc`, `aarch64-pc-windows-msvc`, `x86_64-apple-darwin`, `aarch64-apple-darwin`).
   - C/C++: через cross‑toolchains, CMake toolchains и т.п.
2. **Linux‑пакеты (deb/rpm/apk/archlinux)**:
   - использовать `nfpm`, `fpm`, `cpack`, `goreleaser (через nfpm)` для генерации пакетов;
   - таргеты: `linux/amd64`, `linux/arm64`.
3. **Windows‑инсталляторы**:
   - для enterprise (AD/GPO, SCCM и т.п.) — собирать `.msi` через `msitools`/`wixl`;
   - для более простого UX — NSIS EXE‑инсталлятор (`makensis`);
   - можно параллельно выкладывать `.zip` как самый простой вариант.
4. **macOS**:
   - из Linux:
     - собирать `.tar.gz`/`.zip` с бинарями и `.app`‑bundle (если GUI);
     - генерировать Homebrew‑formula (через `goreleaser` или вручную).
   - на macOS‑runner’е:
     - собирать `.pkg`/`.dmg` (через `pkgbuild`/`productbuild`, `appdmg`, `dmgbuild`, `fpm osxpkg`);
     - выполнять `codesign` + notarization.

---

## 3. Обзор популярных инструментов

### 3.1. nFPM

- **Сайт/документация**: [nfpm.goreleaser.com](https://nfpm.goreleaser.com/docs/)
- **Репозиторий**: [github.com/goreleaser/nfpm](https://github.com/goreleaser/nfpm)

#### 3.1.1. Общая информация и философия

nFPM — это утилита на Go для сборки Linux‑пакетов из простой YAML‑конфигурации.

Поддерживаемые форматы (по состоянию на 2026 г.):

- `deb` (Debian/Ubuntu и производные);
- `rpm` (RHEL/CentOS/Alma/Rocky/Fedora и т.п.);
- `apk` (Alpine);
- `archlinux` (pacman);
- `ipk` (opkg);
- `srpm` (source RPM).

**Философия**:

- минимум внешних зависимостей (zero‑dependency, написан на Go);
- единый YAML для нескольких форматов;
- фокус на Linux, без попытки покрыть Windows/macOS;
- легко встраивается в CI/CD и инструменты уровня `goreleaser`.

#### 3.1.2. Плюсы и минусы nFPM

**Плюсы**:

- простой формат YAML, низкий порог входа;
- единая конфигурация для разных дистрибутивов;
- встроенная поддержка:
  - системных сервисов (systemd, OpenRC);
  - конфигурационных файлов (`config_files`);
  - скриптов жизненного цикла (`scripts`);
  - зависимостей, конфликтов;
- легко запускать из Linux для `amd64` и `arm64` пакетов.

**Минусы**:

- только Linux‑пакеты (нет MSI, NSIS, macOS pkg);
- не покрывает тонкости сложных Debian/RPM пакетов (сильная интеграция с debhelper/rpm macros и т.п.);
- не умеет сам публиковать в репозитории (это задача внешних инструментов).

#### 3.1.3. Типовые задачи и примеры

##### Простой CLI‑пакет для deb/rpm

`nfpm.yaml`:

```yaml
name: myapp
arch: amd64
platform: linux
version: 1.2.3
section: utilities
maintainer: "ACME Corp <dev@acme.test>"
description: "MyApp — кроссплатформенная CLI‑утилита"
license: "MIT"
homepage: "https://example.com/myapp"

contents:
  - src: ./dist/linux_amd64/myapp
    dst: /usr/bin/myapp
    file_info:
      mode: 0755

overrides:
  deb:
    depends:
      - "ca-certificates"
  rpm:
    depends:
      - "ca-certificates"
```

Сборка:

```bash
nfpm pkg --config nfpm.yaml --packager deb --target dist/
nfpm pkg --config nfpm.yaml --packager rpm --target dist/
```

##### Добавление systemd‑сервиса и конфига

```yaml
name: myservice
arch: arm64
platform: linux
version: 0.4.0

contents:
  - src: ./dist/linux_arm64/myservice
    dst: /usr/bin/myservice
    file_info:
      mode: 0755

  - src: packaging/systemd/myservice.service
    dst: /lib/systemd/system/myservice.service
    type: config
    file_info:
      mode: 0644

  - src: packaging/config/config.yml
    dst: /etc/myservice/config.yml
    type: config
    file_info:
      mode: 0644

scripts:
  postinstall: packaging/scripts/postinstall.sh
  postremove: packaging/scripts/postremove.sh
```

`postinstall.sh` может:

- выполнить `systemctl daemon-reload`;
- включить сервис (`systemctl enable myservice`);
- запустить или перезапустить сервис.

##### Мульти‑архитектура

Обычно используют один шаблон `nfpm.yaml`, а в CI подставляют арх:

```yaml
name: myapp
arch: ${ARCH}
platform: linux
version: ${VERSION}
```

И запускают:

```bash
ARCH=amd64 VERSION=1.2.3 nfpm pkg --config nfpm.yaml --packager deb --target dist/
ARCH=arm64 VERSION=1.2.3 nfpm pkg --config nfpm.yaml --packager deb --target dist/
```

---

### 3.2. FPM (Effing Package Management)

- **Документация**: [fpm.readthedocs.io](https://fpm.readthedocs.io/en/latest/)
- **Репозиторий**: [github.com/jordansissel/fpm](https://github.com/jordansissel/fpm)

#### 3.2.1. Общая информация и философия

FPM — исторически один из самых популярных универсальных CLI‑инструментов для упаковки.

Идея:

- «упаковка должна быть простой» («packaging made simple»);
- главный интерфейс: `fpm -s <source> -t <target> ...`.

**Поддерживаемые входные типы**:

- `dir`, `tar`, `gem`, `python`, `npm`, `deb`, `rpm`, `pacman`, `empty` и др.

**Выходные типы**:

- `deb`, `rpm`, `osxpkg`, `pacman`, `solaris`, `freebsd`, `tar`, `zip`, `sh` (self‑extracting), `dir` и др.

#### 3.2.2. Плюсы и минусы FPM

**Плюсы**:

- огромный список поддерживаемых форматов;
- можно «конвертировать» пакеты между форматами;
- гибкие CLI‑флаги: зависимости, конфиги, скрипты, users/groups и т.п.;
- подходит для многочисленных сценариев миграции/релизов.

**Минусы**:

- написан на Ruby: нужна среда Ruby (что не всегда удобно в CI);
- проект зрелый, но развивается не так активно, как когда‑то;
- высокий уровень абстракции: многие тонкости конкретных дистрибутивов остаются на совести инженера.

#### 3.2.3. Типовые задачи и примеры

##### Упаковка дерева директорий в `.deb`

```bash
fpm -s dir -t deb \
  -n myapp \
  -v 1.2.3 \
  --architecture amd64 \
  --description "MyApp — утилита для ..." \
  --license MIT \
  --maintainer "ACME <dev@acme.test>" \
  --deb-systemd systemd/myapp.service \
  --config-files /etc/myapp/config.yml \
  --after-install packaging/scripts/postinst.sh \
  ./dist/root/=/   # содержимое root/ будет положено в корень ФС
```

Здесь:

- `./dist/root/` содержит структуру а‑ля:
  - `usr/bin/myapp`
  - `etc/myapp/config.yml`
  - `lib/systemd/system/myapp.service`
- `--deb-systemd` автоматически регистрирует systemd unit от имени пакета.

##### Создание RPM

```bash
fpm -s dir -t rpm \
  -n myapp \
  -v 1.2.3 \
  --architecture arm64 \
  --depends "ca-certificates" \
  ./dist/root/=/ 
```

##### macOS osxpkg (с замечаниями)

```bash
fpm -s dir -t osxpkg \
  -n myapp \
  -v 1.2.3 \
  --osxpkg-identifier "com.example.myapp" \
  ./dist/macos_root/=/ 
```

Важно:

- из Linux можно сформировать структуру pkg, но для реальной подписи и notarization потребуется шаг на macOS;
- FPM сам по себе не решает вопрос кросс‑подписи.

---

### 3.3. msitools / wixl (MSI для Windows)

- **Wiki / гайд**: [Beginner's guide to MSI creation](https://wiki.gnome.org/msitools/HowTo/CreateMSI)
- **Репозиторий**: [GNOME/msitools](https://github.com/GNOME/msitools) и GitLab `gnome/msitools`

`msitools` — набор утилит для работы с Windows Installer (MSI) под Linux.

Ключевой компонент — **`wixl`**, компилятор WiX‑подобного XML в `.msi`.

#### 3.3.1. Философия и возможности

- совместимость с форматом **WiX** (`.wxs`) по максимуму;
- работа полностью на Linux (без Windows/Visual Studio);
- утилиты для инспекции, сравнения и извлечения MSI:
  - `msidump`, `msiextract`, `msidiff`, `msiinfo` и др.

Подход:

- вы описываете продукт в `.wxs` (директории, компоненты, файлы, фичи, ярлыки, реестр, переменные среды и т.д.);
- запускаете:

```bash
wixl -o myapp-1.2.3-x64.msi myapp.wxs
```

#### 3.3.2. Плюсы и минусы msitools

**Плюсы**:

- родной Linux‑инструмент для MSI;
- формат WiX широко документирован (можно использовать WiX‑гайды/примеры);
- удобно интегрировать в CI;
- можно делать enterprise‑дружественные MSI (Group Policy, SCCM).

**Минусы**:

- реализует **подмножество** WiX: не всё, что возможно в WiX, поддерживается `wixl`;
- документация по самим `msitools` скромная — приходится активно опираться на WiX‑документацию;
- подписание MSI (Authenticode) всё равно нужно делать отдельно (Windows `signtool` или `osslsigncode` из Linux).

#### 3.3.3. Типовые задачи и примеры

##### Простой MSI, устанавливающий CLI в `Program Files`

`myapp.wxs` (упрощённый пример):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product
    Id="*"
    Name="MyApp"
    Language="1033"
    Version="1.2.3"
    Manufacturer="ACME Corp"
    UpgradeCode="PUT-GUID-HERE">

    <Package
      InstallerVersion="500"
      Compressed="yes"
      Description="MyApp CLI" />

    <Media Id="1" Cabinet="product.cab" EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="MyApp" />
      </Directory>
    </Directory>

    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="cmpMyAppExe" Guid="PUT-GUID-HERE-2">
        <File Id="filMyAppExe" Source="dist/windows_amd64/myapp.exe" KeyPath="yes" />
      </Component>
    </DirectoryRef>

    <Feature Id="MainFeature" Title="MyApp" Level="1">
      <ComponentRef Id="cmpMyAppExe" />
    </Feature>
  </Product>
</Wix>
```

Сборка:

```bash
wixl -o myapp-1.2.3-x64.msi myapp.wxs
```

Для ARM64 архитектуры будет отдельный `.wxs`/артефакт (с другим `Source` на `dist/windows_arm64/myapp.exe` и, при необходимости, с указанием архитектуры в метаданных MSI).

##### Добавление переменной среды (PATH)

В WiX‑формате можно использовать таблицу `Environment` для добавления пути в PATH. Примерно так (псевдокод, поддержка в `wixl` зависит от версии):

```xml
<Component Id="cmpEnvPath" Guid="PUT-GUID-HERE-3">
  <Environment
    Id="AddToPath"
    Name="PATH"
    Action="set"
    Part="last"
    System="yes"
    Permanent="no"
    Value="[INSTALLFOLDER]" />
</Component>
```

##### Windows‑сервис

В WiX есть элементы `ServiceInstall` и `ServiceControl`. Общий паттерн:

```xml
<Component Id="cmpMyService" Guid="PUT-GUID-HERE-4">
  <File Id="filMyServiceExe" Source="dist/windows_amd64/myservice.exe" KeyPath="yes" />
  <ServiceInstall
    Id="MyService"
    Name="MyService"
    DisplayName="My Service"
    Type="ownProcess"
    Start="auto"
    ErrorControl="normal"
    Description="My background service" />
  <ServiceControl
    Id="MyServiceControl"
    Name="MyService"
    Start="install"
    Stop="both"
    Remove="uninstall"
    Wait="yes" />
</Component>
```

Перед использованием таких конструкций стоит проверить текущую поддержку соответствующих элементов в той версии `msitools`, которая используется в вашей системе.

---

### 3.4. NSIS (makensis) — EXE‑инсталляторы для Windows

- **Сайт**: [nsis.sourceforge.io](https://nsis.sourceforge.io/Main_Page)
- **Документация**: `Docs/` в дистрибутиве (есть онлайн‑версии)

NSIS — классический скриптовый инсталлятор для Windows. Сама утилита `makensis` доступна и под Linux (через пакеты дистрибутивов).

#### 3.4.1. Плюсы и минусы NSIS

**Плюсы**:

- лёгкие, компактные EXE‑инсталляторы;
- мощный скриптовый язык, позволяющий:
  - создавать UI‑мастеры;
  - выполнять произвольные действия в системе;
  - интегрироваться с сервисами, реестром, PATH и т.п.;
- доступен на Linux.

**Минусы**:

- не MSI, то есть не интегрируется с некоторыми enterprise‑механизмами Windows Installer;
- скрипт NSIS — отдельный DSL, который нужно осваивать;
- поддержка ARM64 зависит от среды и используемых плагинов.

#### 3.4.2. Пример базового NSIS‑скрипта

```nsis
!define APP_NAME "MyApp"
!define APP_VERSION "1.2.3"
!define APP_PUBLISHER "ACME Corp"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "MyApp-${APP_VERSION}-setup.exe"
InstallDir "$PROGRAMFILES64\\MyApp"
RequestExecutionLevel admin

Page directory
Page instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File "dist\\windows_amd64\\myapp.exe"

  # Добавляем в PATH (упрощённый пример)
  WriteRegStr HKLM "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment" "PATH" "$\"$INSTDIR;$%PATH%$\""
  SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd
```

Сборка:

```bash
makensis myapp.nsi
```

---

### 3.5. mkisofs / genisoimage / xorriso (ISO‑образы)

Хотя `mkisofs` фигурирует в обсуждениях упаковки, по сути это **инструмент для создания ISO‑файловых систем**, а не пакетных форматов:

- исторический инструмент: `mkisofs` (cdrtools);
- в большинстве современных дистрибутивов его заменяют:
  - `genisoimage`;
  - `xorriso -as mkisofs` / `xorrisofs`.

Документация:

- [Debian Wiki: genisoimage](https://wiki.debian.org/genisoimage)
- [GNU xorriso](https://www.gnu.org/software/xorriso/)

#### 3.5.1. Назначение и типичные сценарии

- создание **установочных ISO** (например, для дистрибутивов Linux);
- создание **офлайн‑образов**, содержащих ваши пакеты + mini‑репозиторий;
- распространение большого набора материалов (документация, бинарники и т.п.) в виде ISO.

Пример:

```bash
xorrisofs -v -J -r \
  -V "MYAPP_OFFLINE_1_2_3" \
  -o dist/myapp-offline-1.2.3.iso \
  ./offline-root/
```

Здесь:

- `./offline-root/` — директория с деревом файлов (пакеты, скрипты, README и т.п.).

Важно: для обычной доставки приложений сейчас гораздо чаще используют пакеты (`deb`, `rpm`, MSI, `.dmg`) или архивы (`.tar.gz`, `.zip`), а не ISO. ISO имеет смысл, когда нужен именно образ диска/флешки.

---

### 3.6. CPack (часть CMake)

- **Документация**: [CPack — CMake](https://cmake.org/cmake/help/latest/module/CPack.html)

CPack — встроенный в CMake инструмент упаковки. Если ваш C/C++ (и не только) проект уже использует CMake, CPack может стать единым интерфейсом к пакетам.

Поддерживаемые генераторы включают:

- архивы: `TGZ`, `ZIP` и т.п.;
- Linux пакеты: `DEB`, `RPM`;
- Windows: NSIS, WIX (на Windows);
- macOS: DragNDrop `.dmg`, bundle и др. (обычно на macOS).

#### 3.6.1. Пример CMake + CPack

`CMakeLists.txt` (упрощённо):

```cmake
cmake_minimum_required(VERSION 3.20)
project(MyApp VERSION 1.2.3)

add_executable(myapp src/main.cpp)

install(TARGETS myapp DESTINATION bin)

set(CPACK_PACKAGE_NAME "myapp")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "ACME <dev@acme.test>")
set(CPACK_GENERATOR "DEB;RPM")

include(CPack)
```

Сборка и упаковка:

```bash
cmake -B build
cmake --build build --config Release
cd build
cpack -G DEB
cpack -G RPM
```

Плюсы:

- естественно для C/C++‑проектов;
- единый источник метаданных в CMake.

Минусы:

- меньше гибкости, чем в специализированных пакетных инструментах (nfpm/fpm);
- тонкая настройка требует хорошего знания CPack.

---

### 3.7. GoReleaser (поверх nFPM)

- **Сайт/доки**: `https://goreleaser.com/`

GoReleaser — инструмент, ориентированный на проекты на Go, но его можно использовать и как обёртку для кросс‑компиляции + упаковки.

Ключевые фичи:

- кросс‑сборка бинарников для многих OS/архитектур;
- упаковка:
  - архивы (`tar.gz`, `zip`);
  - Linux‑пакеты (через `nfpm`);
  - Homebrew formulae, Scoop (Windows);
- генерация чек‑сумм, подписи (GPG/`cosign`);
- публикация релизов в GitHub/GitLab.

#### 3.7.1. Пример конфигурации (фрагмент)

`.goreleaser.yaml`:

```yaml
builds:
  - id: myapp
    main: ./cmd/myapp
    env:
      - CGO_ENABLED=0
    goos:
      - linux
      - windows
      - darwin
    goarch:
      - amd64
      - arm64

archives:
  - id: archive
    format: tar.gz
    replacements:
      linux: Linux
      windows: Windows
      darwin: macOS
    files:
      - LICENSE
      - README.md

nfpms:
  - id: linux-packages
    package_name: myapp
    formats:
      - deb
      - rpm
    maintainer: "ACME <dev@acme.test>"
    description: "MyApp — кроссплатформенная утилита"
    license: MIT
    contents:
      - src: ./dist/myapp_{{ .Os }}_{{ .Arch }}/myapp
        dst: /usr/bin/myapp
```

В таком сценарии GoReleaser:

- соберёт бинарники для всех нужных OS/arch;
- сделает архивы;
- через `nfpm` создаст `deb`/`rpm` для нужных Linux‑архитектур.

---

### 3.8. Языко‑специфичные инструменты (Rust, др.)

Для Rust есть полезные утилиты:

- `cargo-deb` — генерация `.deb` из `Cargo.toml`;
- `cargo-rpm` — генерация `.rpm`;
- `cargo-dist` — более общий инструмент для кросс‑релизов (архивы, инсталляторы, некоторые интеграции с платформами).

Они хорошо интегрируются с экосистемой Rust, но для единой кросс‑языковой стратегии (Go + Rust + C/C++) чаще удобнее использовать общий набор (`nfpm`, `fpm`, `goreleaser`, `cpack`).

---

## 4. Сводные рекомендации и паттерны под 6 таргетов

### 4.1. Linux (`linux/amd64`, `linux/arm64`)

Рекомендации:

- **Форматы**:
  - минимум: `deb` + `rpm`;
  - дополнительно: `apk` (Alpine), `archlinux` (pacman), архивы `.tar.gz`.
- **Инструменты**:
  - для Go‑проектов: `goreleaser` + `nfpm`;
  - для смешанных проектов: `nfpm` (через общий YAML) или `fpm`;
  - для C/C++ с CMake: `cpack`.
- **Типовой пайплайн**:
  - кросс‑компиляция бинарников для `linux/amd64` и `linux/arm64`;
  - подготовка общего дерева файлов (layout под FHS);
  - генерация пакетов через `nfpm`/`fpm`/`cpack`;
  - публикация в репозитории (apt/yum/dnf/apk/pacman‑repo).

### 4.2. Windows (`windows/amd64`, `windows/arm64`)

Рекомендации:

- **Форматы**:
  - MSI (enterprise‑friendly);
  - EXE‑инсталлятор (NSIS) для более гибкого UI;
  - zip как самый простой артефакт.
- **Инструменты**:
  - `msitools`/`wixl` — MSI‑пакеты из Linux;
  - `makensis` (NSIS) — EXE‑инсталляторы;
  - при необходимости — `fpm` для генерации zip/dir.
- **Подпись**:
  - если есть возможность — использовать Authenticode‑подпись (чаще на Windows‑runner’е);
  - из Linux можно использовать `osslsigncode`, но управление сертификатами удобнее на Windows.

Архитектуры:

- раздельные артефакты: `myapp-1.2.3-windows-amd64.msi`, `myapp-1.2.3-windows-arm64.msi`;
- в MSI отражать правильную архитектуру/платформу.

### 4.3. macOS (`darwin/amd64`, `darwin/arm64`, универсальные)

С точки зрения **содержимого пакета**:

- из Linux можно:
  - кросс‑скомпилировать бинарники (`darwin/amd64`, `darwin/arm64`);
  - собрать `.tar.gz`/`.zip` с CLI;
  - подготовить `.app`‑bundle (структура каталогов, Info.plist, иконки) как набор файлов.

С точки зрения **подписи и дистрибуции**:

- для нормального UX в macOS надо:
  - собрать `.pkg` или `.dmg`;
  - подписать `codesign` и отправить на notarization;
  - это почти всегда делают на macOS (GitHub Actions macOS runner, self‑hosted Mac‑мини и т.п.).

Реалистичный compromise:

- из Linux:
  - генерировать архивы `myapp-1.2.3-darwin-amd64.tar.gz`, `myapp-1.2.3-darwin-arm64.tar.gz`;
  - генерировать Homebrew formula и/или manifest для других менеджеров.
- на macOS:
  - собирать и подписывать `.pkg`/`.dmg` (через `pkgbuild`/`productbuild`, `fpm osxpkg`, `appdmg`, `dmgbuild`).

---

## 5. Пример комплексного пайплайна для кроссплатформенного проекта

Допустим, есть один репозиторий с несколькими бинарями (Go/Rust/C++).

### 5.1. Структурирование артефактов

- Единственный шаг сборки (Linux CI) кросс‑компилирует бинарники для:
  - `linux/amd64`, `linux/arm64`;
  - `windows/amd64`, `windows/arm64`;
  - `darwin/amd64`, `darwin/arm64`.
- Для каждого бинаря и таргета:
  - складываем их в предсказуемую структуру: `dist/<os>_<arch>/<app>/...`.

### 5.2. Linux‑пакеты через nFPM

- Один или несколько YAML‑файлов `nfpm-<app>.yaml`, параметризованных через переменные окружения:
  - `ARCH`, `VERSION`, `APP_NAME` и т.п.
- В CI:
  - для каждого приложения и архитектуры вызываем `nfpm pkg` для `deb`/`rpm`/`apk`/`archlinux`.

### 5.3. Windows MSI через msitools

- Для каждого приложения — свой `.wxs` (можно генерировать частично из шаблона):
  - описывает пути, сервисы, ярлыки, конфиги, PATH и пр.;
  - для `amd64` и `arm64` делаются отдельные варианции.
- В CI:
  - подставляем пути к бинарям для нужной архитектуры;
  - вызываем `wixl` для генерации `.msi`.

### 5.4. Windows EXE через NSIS (опционально)

- Общий NSIS‑скрипт с параметризованными путями к бинарям;
- Сборка через `makensis` для каждой архитектуры.

### 5.5. macOS артефакты

- Из Linux:
  - создаём `tar.gz`/`zip` с CLI бинарями и/или `.app`‑bundle;
  - публикуем как часть релиза (GitHub/GitLab Releases).
- На macOS‑runner’е:
  - собираем и подписываем `.pkg`/`.dmg` при необходимости;
  - выполняем notarization.

---

## 6. Краткое сравнение ключевых инструментов

| Инструмент   | Основные форматы                      | Платформенный фокус         | Язык реализации | Сильные стороны                                        | Ограничения                                          |
|-------------|----------------------------------------|-----------------------------|-----------------|--------------------------------------------------------|------------------------------------------------------|
| **nFPM**    | deb, rpm, apk, archlinux, ipk, srpm   | Linux‑пакеты                | Go              | Простой YAML, zero‑dep, отлично для CI                | Только Linux, без MSI/macOS pkg                      |
| **FPM**     | deb, rpm, osxpkg, tar, zip, sh, др.   | Многие OS, акцент на Linux  | Ruby            | Очень гибкий, много форматов, конвертация пакетов      | Требует Ruby, сложные сценарии всё равно руками      |
| **msitools**| msi                                    | Windows MSI из Linux        | C/Vala          | WiX‑подобный формат, enterprise‑friendly MSI           | Подмножество WiX, подписание отдельно                |
| **NSIS**    | exe‑инсталляторы                      | Windows                     | C/C++           | Лёгкие скриптовые инсталляторы, гибкий UI              | Не MSI, отдельный DSL, подпись отдельно              |
| **mkisofs/xorriso** | iso                           | ISO‑образы                  | C               | ISO для офлайн/бутовых образов                        | Не пакетный формат, не интегрируется с пакет. менеджерами |
| **CPack**   | deb, rpm, архивы, NSIS, dmg (на macOS)| Зависит от генератора       | C++             | Нативен для CMake‑проектов                             | Требует понимания CMake/CPack                        |
| **GoReleaser** | архивы, Linux‑пакеты (через nFPM), Homebrew и др. | Кроссплатформенные релизы | Go | Автоматизация релизов Go‑проектов, матрица OS/arch | По сути оркестратор, сам по себе не генерирует MSI/pkg |

---

Этот документ даёт обзор основных инструментов и паттернов, которые можно использовать для построения кроссплатформенной системы пакетов из Linux для проектов на Go, Rust и C/C++. Для практической реализации можно начать с:

1. nFPM (Linux‑пакеты) + GoReleaser для Go‑сервисов.
2. msitools (MSI) и/или NSIS (EXE) для Windows.
3. Архивы и Homebrew + отдельный macOS‑runner для подписанных `.pkg`/`.dmg`.


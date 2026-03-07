# Сравнительный анализ backend-упаковщиков

Анализ четырёх инструментов: wixl (.msi), nfpm (.deb/.rpm/.apk), pkgbuild (.pkg), hdiutil (.dmg).

---

## 1. Общий подход к описанию содержимого пакета

Фундаментальное различие — в форме декларации пакета:

| Инструмент | Формат описания | Ориентация |
|------------|-----------------|------------|
| wixl | XML (.wxs) — декларативный, подробный | Компонентно-ориентированный |
| nfpm | YAML (.yaml) — компактный | Файлово-ориентированный |
| pkgbuild | CLI-аргументы + filesystem | Filesystem-ориентированный |
| hdiutil | CLI-аргументы | Образ-ориентированный |

**wixl** требует подробного XML с явными идентификаторами (GUID) для каждого компонента, реестровых записей, ярлыков. Описание пакета «плоское» — всё в одном файле или явно модульное.

**nfpm** использует компактный YAML, ближайший аналог «конфига» в обычном понимании. Один файл описывает пакет для нескольких форматов одновременно.

**pkgbuild** не имеет «конфига» — пакет описывается структурой директорий и аргументами командной строки. Конфиг — это сам filesystem.

**hdiutil** ещё проще — просто «возьми эту директорию и сделай из неё образ».

### Сниппет: "описать пакет с именем, версией, описанием"

**wixl (.wxs):**
```xml
<Product
  Id="*"
  Name="crossler"
  Language="1033"
  Version="1.0.0.0"
  Manufacturer="PowerTech Center"
  UpgradeCode="FIXED-GUID">
  <Package
    InstallerVersion="200"
    Compressed="yes"
    InstallScope="perMachine"
    Description="Cross-platform package creation tool" />
```

**nfpm (nfpm.yaml):**
```yaml
name: crossler
version: 1.0.0
arch: amd64
maintainer: "PowerTech Center <dev@powertech.center>"
description: Cross-platform package creation tool
homepage: https://github.com/powertech-center/crossler
license: MIT
```

**pkgbuild (CLI):**
```bash
pkgbuild \
  --identifier com.powertech.crossler.pkg \
  --version 1.0.0 \
  --root payload/ \
  --install-location / \
  crossler.pkg
# Описание/метаданные — только в distribution.xml (productbuild)
```

**hdiutil (CLI):**
```bash
hdiutil create \
  -volname "Crossler 1.0.0" \
  -srcfolder payload/ \
  -format ULFO \
  crossler.dmg
# Нет полей описания/версии — только имя тома
```

---

## 2. Метаданные пакета

| Поле | wixl | nfpm | pkgbuild | hdiutil |
|------|:----:|:----:|:--------:|:-------:|
| Имя | `Product/@Name` | `name` | `--identifier` (ID, не имя) | `-volname` (имя тома) |
| Версия | `Product/@Version` | `version` | `--version` | — (нет) |
| Описание | `Package/@Description` | `description` | через distribution.xml | — (нет) |
| Производитель | `Product/@Manufacturer` | `vendor` | — (нет) | — (нет) |
| Сопровождающий | — | `maintainer` | — (нет) | — (нет) |
| Лицензия | — | `license` | через distribution.xml | — (нет) |
| Homepage | — | `homepage` | — (нет) | — (нет) |
| Epoch | — | `epoch` (rpm) | — (нет) | — (нет) |

**Вывод:** nfpm обладает наиболее полным набором стандартных метаданных. wixl достаточен для Windows-специфичных. pkgbuild и hdiutil — минималисты.

---

## 3. Установка файлов

Это главная задача всех упаковщиков, но подходы кардинально различаются.

### wixl — компонентная модель

Каждый файл явно объявлен в `<Component>` с GUID:

```xml
<DirectoryRef Id="INSTALLFOLDER">
  <Component Id="MainBinary" Guid="AAAA-...">
    <File Id="AppExe"
          Source="dist/crossler.exe"
          Name="crossler.exe"
          KeyPath="yes"
          Vital="yes" />
  </Component>
</DirectoryRef>
```

Особенности:
- Каждый компонент отслеживается Windows Installer по GUID
- Поддерживает ref-counting (один файл в нескольких пакетах)
- Требует явного `KeyPath` для каждого компонента
- Нет типов файлов (config, doc и т.д.) — только обычные файлы

### nfpm — декларативный список с типами

```yaml
contents:
  - src: dist/crossler
    dst: /usr/bin/crossler
    type: file
    file_info:
      mode: 0755
      owner: root
      group: root

  - src: config/default.yaml
    dst: /etc/crossler/config.yaml
    type: config|noreplace    # не перезаписывать при обновлении

  - src: /usr/bin/crossler
    dst: /usr/local/bin/crossler
    type: symlink

  - dst: /var/lib/crossler
    type: dir
    file_info:
      mode: 0750
      owner: crossler
```

Особенности:
- Богатая типизация: file, config, config|noreplace, dir, symlink, ghost, doc
- Явные права и владельцы на уровне файлов
- Glob-паттерны: `src: docs/*.md`
- Нет GUID — нет ref-counting

### pkgbuild — filesystem как конфиг

```bash
# "Описание" файлов = структура директорий
mkdir -p payload/usr/local/bin
cp dist/crossler payload/usr/local/bin/crossler
chmod 755 payload/usr/local/bin/crossler

pkgbuild --root payload/ --install-location / crossler.pkg
```

Особенности:
- Нет декларативного описания — структура filesystem IS the config
- Права устанавливаются до упаковки chmod/chown
- `--ownership recommended` автоматически задаёт root:wheel для системных путей
- Нет типов файлов — все файлы равнозначны

### hdiutil — образ директории

```bash
# Файлы просто копируются в образ
cp -R MyApp.app staging/
ln -s /Applications staging/Applications
hdiutil create -srcfolder staging/ -format ULFO output.dmg
```

Особенности:
- Самый простой — snapshot директории в образ
- Нет прав доступа при установке (файлы копирует пользователь вручную)
- Нет типов файлов
- DMG — это образ диска, не пакет установщика

### Сравнительная таблица установки файлов

| Возможность | wixl | nfpm | pkgbuild | hdiutil |
|-------------|:----:|:----:|:--------:|:-------:|
| Явные права (mode) | Нет | Да | chmod до упаковки | Нет |
| Владелец файла (owner) | Нет (root) | Да | `--ownership` | Нет |
| Типы файлов | Нет | Да (7 типов) | Нет | Нет |
| Config-файлы (не перезаписывать) | Нет | `config\|noreplace` | Нет | Нет |
| Символические ссылки | Нет | Да | Да (в payload) | Да (в staging) |
| Пустые директории | `<CreateFolder>` | `type: dir` | mkdir в staging | mkdir в staging |
| Ghost-файлы (RPM) | Нет | `type: ghost` | Нет | Нет |
| Glob-паттерны | Нет (wixl-heat) | Да | Нет | Нет |

---

## 4. Скрипты жизненного цикла

| Хук | wixl | nfpm | pkgbuild | hdiutil |
|-----|:----:|:----:|:--------:|:-------:|
| Pre-install | `CustomAction` (сложно) | `preinstall` | `preinstall` | — |
| Post-install | `CustomAction` (сложно) | `postinstall` | `postinstall` | — |
| Pre-remove | — | `preremove` | — | — |
| Post-remove | — | `postremove` | — | — |
| Pre-transaction (RPM) | — | `pretrans` (overrides.rpm) | — | — |
| Post-transaction (RPM) | — | `posttrans` (overrides.rpm) | — | — |

**Особенности wixl:** скрипты реализуются через `CustomAction` + `InstallExecuteSequence`. Это значительно сложнее, чем в nfpm/pkgbuild — нужно объявить действие, указать условия, встроить в последовательность установки. Запуск EXE-файлов поддерживается.

```xml
<!-- wixl: запуск exe после установки -->
<CustomAction Id="PostInstall"
              Directory="INSTALLFOLDER"
              ExeCommand="[INSTALLFOLDER]setup.exe --init"
              Return="asyncNoWait"
              Execute="deferred" />
<InstallExecuteSequence>
  <Custom Action="PostInstall" After="InstallFinalize">NOT Installed</Custom>
</InstallExecuteSequence>
```

**nfpm:** четыре скрипта — простые shell-файлы, работают «из коробки»:

```bash
# scripts/postinstall.sh
#!/bin/bash
set -e
systemctl daemon-reload
systemctl enable myapp.service
```

**pkgbuild:** два скрипта (pre/post install), выполняются с правами root:

```bash
# scripts/postinstall
#!/bin/bash
chmod 755 "$3/usr/local/bin/crossler"
```

**hdiutil:** скриптов нет — пользователь вручную копирует файлы.

### Сниппет: "запустить постустановочную инициализацию"

**nfpm (postinstall.sh):**
```bash
#!/bin/bash
set -e
/usr/bin/crossler --init-config || true
echo "crossler configured"
```

**pkgbuild (scripts/postinstall):**
```bash
#!/bin/bash
set -e
"$3/usr/local/bin/crossler" --init-config || true
echo "crossler configured"
```

**wixl (WXS):**
```xml
<CustomAction Id="InitConfig"
              Directory="INSTALLFOLDER"
              ExeCommand="[INSTALLFOLDER]crossler.exe --init-config"
              Return="ignore"
              Execute="deferred"
              Impersonate="yes" />
<InstallExecuteSequence>
  <Custom Action="InitConfig" After="InstallFinalize">NOT Installed</Custom>
</InstallExecuteSequence>
```

---

## 5. Зависимости

| Тип зависимости | wixl | nfpm | pkgbuild | hdiutil |
|-----------------|:----:|:----:|:--------:|:-------:|
| Обязательные (`depends`) | Нет | Да | Нет | Нет |
| Рекомендуемые (`recommends`) | Нет | Да | Нет | Нет |
| Предложения (`suggests`) | Нет | Да | Нет | Нет |
| Конфликты (`conflicts`) | Нет | Да | Нет | Нет |
| Замещение (`replaces`) | Нет | Да | Нет | Нет |
| Виртуальные (`provides`) | Нет | Да | Нет | Нет |
| OR-зависимости | Нет | Да (deb: `a \| b`) | Нет | Нет |
| Версионные ограничения | Нет | Да | Нет | Нет |

**wixl** не имеет зависимостей. Windows Installer не поддерживает пакетные зависимости в стандартном смысле. Для prerequisites используется Burn Bootstrapper (которого нет в wixl).

**nfpm** — единственный из четырёх инструментов с полноценной системой зависимостей (унаследованной от deb/rpm/apk форматов).

**pkgbuild / hdiutil** — нет механизма зависимостей. В distribution.xml можно указать минимальную версию macOS, но не зависимости от других пакетов.

### Сниппет: "зависеть от curl >= 7.0"

**nfpm (nfpm.yaml) — единственный поддерживает:**
```yaml
overrides:
  deb:
    depends:
      - curl (>= 7.0)
  rpm:
    depends:
      - curl >= 7.0
  apk:
    depends:
      - curl>=7.0
```

**wixl, pkgbuild, hdiutil:** не поддерживается нативно.

---

## 6. Условная логика

### wixl — препроцессор + Property/Condition

```xml
<!-- Препроцессор (compile-time) -->
<?if $(var.Platform) = "x64" ?>
  <Package Platform="x64" />
  <Component Id="App" Guid="..." Win64="yes">
    <File Source="bin/x64/app.exe" KeyPath="yes" />
  </Component>
<?else ?>
  <Package Platform="x86" />
  <Component Id="App" Guid="...">
    <File Source="bin/x86/app.exe" KeyPath="yes" />
  </Component>
<?endif ?>

<!-- Runtime условия -->
<Condition Message="Requires Windows 7+.">
  <![CDATA[VersionNT >= 601]]>
</Condition>

<!-- Условная установка компонента -->
<Component Id="X64Only" Win64="yes">
  <Condition>Intel64</Condition>
  <File Source="app64.exe" KeyPath="yes" />
</Component>
```

### nfpm — overrides по форматам

nfpm не имеет условий в смысле runtime — вместо этого `overrides` для статических различий по форматам:

```yaml
depends:
  - bash

overrides:
  deb:
    depends:
      - bash (>= 4.0)
      - curl (>= 7.0)
  rpm:
    release: 1.el8
    depends:
      - bash >= 4.0
  apk:
    depends:
      - bash>=4.0
```

### pkgbuild — нет условий

pkgbuild не поддерживает условную логику. Условия можно реализовать:
- В скриптах preinstall/postinstall (shell-условия)
- В distribution.xml (минимальная версия OS)

```bash
# В скрипте preinstall
#!/bin/bash
if [[ "$(sw_vers -productVersion)" < "11.0" ]]; then
    echo "Requires macOS 11.0 or later"
    exit 1
fi
```

### hdiutil — нет условий

Нет никакой условной логики. hdiutil — просто упаковщик образа.

---

## 7. Архитектурная мультиплатформенность

### wixl — флаг -a

```bash
# x64
wixl -a x64 -o app-x64.msi installer.wxs

# x86
wixl -a x86 -o app-x86.msi installer.wxs
```

В WXS файле:
```xml
<Package Platform="x64" />
<Component Win64="yes">...</Component>
```

### nfpm — поле arch с GOARCH нотацией

```yaml
arch: amd64   # или arm64, 386
```

Единый конфиг = один пакет для одной архитектуры. Для нескольких архитектур — запустить несколько раз:

```bash
for arch in amd64 arm64; do
  VERSION=$VERSION ARCH=$arch envsubst < nfpm.yaml.tmpl > /tmp/nfpm.yaml
  nfpm package -c /tmp/nfpm.yaml -p deb -t dist/
done
```

### pkgbuild — из бинарника

pkgbuild создаёт пакет из уже скомпилированного бинарника. Архитектура наследуется от бинарника. Universal binary (lipo) создаётся до упаковки.

```bash
# ARM64 пакет
pkgbuild --root payload_arm64/ ... crossler-arm64.pkg

# AMD64 пакет
pkgbuild --root payload_amd64/ ... crossler-amd64.pkg
```

### hdiutil — без архитектуры

hdiutil не знает об архитектурах. DMG просто содержит файлы.

---

## 8. Уникальный функционал каждого инструмента

### Только в wixl/WiX

**Системный реестр Windows:**
```xml
<RegistryKey Root="HKLM" Key="Software\ACME\App" Action="createAndRemoveOnUninstall">
  <RegistryValue Name="InstallPath" Value="[INSTALLFOLDER]" Type="string" />
  <RegistryValue Name="Version" Value="1.0.0" Type="string" />
</RegistryKey>
```

**Ярлыки (Shortcuts):**
```xml
<Shortcut Id="Desktop" Directory="DesktopFolder"
          Name="My App" Target="[INSTALLFOLDER]app.exe"
          WorkingDirectory="INSTALLFOLDER" Icon="AppIcon" />
```

**GUID-компонентная модель** — ref-counting, апгрейды, shared components.

**Иконка в Add/Remove Programs:**
```xml
<Icon Id="AppIcon" SourceFile="app.ico" />
<Property Id="ARPPRODUCTICON" Value="AppIcon" />
```

**Файловые ассоциации (ProgId):**
```xml
<ProgId Id="app.document" Description="App Document">
  <Extension Id="myapp">
    <Verb Id="open" Command="Open" TargetFile="app.exe" Argument='"%1"' />
  </Extension>
</ProgId>
```

### Только в nfpm

**Единый конфиг → несколько форматов** — без аналогов в других инструментах:
```bash
# Один конфиг, три формата
nfpm package -c nfpm.yaml -p deb -t dist/
nfpm package -c nfpm.yaml -p rpm -t dist/
nfpm package -c nfpm.yaml -p apk -t dist/
```

**Типизированные файлы** — `config|noreplace`, `ghost`, `doc`:
```yaml
- src: config.yaml
  dst: /etc/app/config.yaml
  type: config|noreplace    # нет у других инструментов
```

**Зависимости с OR:**
```yaml
# deb
depends:
  - libssl1.1 | libssl3   # установить одно из двух
```

**Epoch для форсированного обновления:**
```yaml
epoch: 1   # пакет с epoch 1 всегда "новее" без epoch
```

**Ghost-файлы (RPM):**
```yaml
- dst: /var/log/app.log
  type: ghost    # rpm знает о файле, но не устанавливает его
```

### Только в pkgbuild

**Component plist** — управление поведением бандлов:
```xml
<key>BundleIsRelocatable</key>
<false/>          <!-- запретить перемещение приложения -->

<key>BundleOverwriteAction</key>
<string>upgrade</string>    <!-- только если новее -->
```

**Payload-free пакеты** — только скрипты, без файлов:
```bash
pkgbuild --nopayload --scripts scripts/ setup.pkg
```

**Связка с productbuild** — создание полноценного дистрибутивного инсталлятора с UI, лицензией, README, требованиями к системе.

### Только в hdiutil

**Drag-and-drop UX** — стандарт macOS для установки приложений:
```
[MyApp.app]  →  [Applications]
```

**Форматы образов** — UDSP (sparse, растущий), UDSB (sparse bundle), конвертация между форматами:
```bash
hdiutil convert dev.sparseimage -format ULFO -o final.dmg
```

**Шифрование образа:**
```bash
hdiutil create -encryption AES-256 -size 1g ... secure.dmg
```

**Монтирование как том** — образ доступен как устройство хранения:
```bash
hdiutil attach myapp.dmg
ls /Volumes/MyApp/
```

---

## 9. Сниппет одной задачи: "установить бинарник с постустановочным скриптом"

Задача: установить `crossler` бинарник в системный путь и вывести сообщение после установки.

**wixl (installer.wxs + build.sh):**

```xml
<!-- installer.wxs -->
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="Crossler" Language="1033" Version="1.0.0.0"
           Manufacturer="PowerTech" UpgradeCode="FIXED-GUID">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="crossler" />
      </Directory>
    </Directory>

    <Feature Id="ProductFeature" Level="1">
      <ComponentRef Id="MainBinary" />
    </Feature>

    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="MainBinary" Guid="AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE">
        <File Source="dist/crossler.exe" KeyPath="yes" Vital="yes" />
      </Component>
    </DirectoryRef>

    <!-- Post-install action (отображает диалог, если нет /quiet) -->
    <Property Id="WIXUI_EXITDIALOGOPTIONALTEXT"
              Value="crossler installed to [INSTALLFOLDER]" />
  </Product>
</Wix>
```

```bash
wixl -v -o dist/crossler.msi -a x64 installer.wxs
```

---

**nfpm (nfpm.yaml + scripts/postinstall.sh):**

```yaml
# nfpm.yaml
name: crossler
version: 1.0.0
arch: amd64

contents:
  - src: dist/crossler
    dst: /usr/bin/crossler
    type: file
    file_info:
      mode: 0755

scripts:
  postinstall: scripts/postinstall.sh
```

```bash
# scripts/postinstall.sh
#!/bin/bash
echo "crossler installed to /usr/bin/crossler"
echo "Run 'crossler --help' to get started"
```

```bash
nfpm package -c nfpm.yaml -p deb -t dist/
nfpm package -c nfpm.yaml -p rpm -t dist/
nfpm package -c nfpm.yaml -p apk -t dist/
```

---

**pkgbuild (build.sh):**

```bash
#!/bin/bash
# Подготовить payload
mkdir -p payload/usr/local/bin
cp dist/crossler-darwin-arm64 payload/usr/local/bin/crossler
chmod 755 payload/usr/local/bin/crossler

# Подготовить скрипт
mkdir -p scripts
cat > scripts/postinstall << 'EOF'
#!/bin/bash
echo "crossler installed to /usr/local/bin/crossler"
echo "Run 'crossler --help' to get started"
EOF
chmod 755 scripts/postinstall

# Упаковать
pkgbuild \
    --root payload/ \
    --identifier com.powertech.crossler.pkg \
    --version 1.0.0 \
    --install-location / \
    --scripts scripts/ \
    dist/crossler-darwin-arm64.pkg

rm -rf payload scripts
```

---

**hdiutil (build.sh — без постустановочного скрипта):**

```bash
#!/bin/bash
# hdiutil не поддерживает post-install скрипты
mkdir -p staging
cp dist/crossler-darwin-arm64 staging/crossler
chmod 755 staging/crossler
cat > staging/INSTALL.txt << 'EOF'
# crossler installation

Run: sudo cp crossler /usr/local/bin/

Then: crossler --help
EOF

hdiutil create \
    -volname "Crossler 1.0.0" \
    -srcfolder staging/ \
    -ov \
    -format ULFO \
    dist/crossler-darwin-arm64.dmg

rm -rf staging
```

---

## 10. Матрица возможностей

| Возможность | wixl | nfpm | pkgbuild | hdiutil |
|-------------|:----:|:----:|:--------:|:-------:|
| **Метаданные** | | | | |
| Имя/версия/описание | ✓ | ✓ | Частично | Только имя тома |
| Производитель/сопровождающий | ✓ | ✓ | — | — |
| Homepage/лицензия | — | ✓ | — | — |
| **Установка файлов** | | | | |
| Установка файлов | ✓ | ✓ | ✓ | ✓ (вручную) |
| Права доступа (mode) | — | ✓ | chmod до упаковки | — |
| Владелец файла (owner:group) | — | ✓ | `--ownership` | — |
| Символические ссылки | — | ✓ | ✓ | ✓ |
| Пустые директории | `<CreateFolder>` | `type: dir` | mkdir | mkdir |
| Config-файлы (noreplace) | — | ✓ | — | — |
| Glob-паттерны | (wixl-heat) | ✓ | — | — |
| **Зависимости** | | | | |
| Обязательные зависимости | — | ✓ | — | — |
| Рекомендации/предложения | — | ✓ | — | — |
| Конфликты/замещения | — | ✓ | — | — |
| OR-зависимости | — | ✓ (deb) | — | — |
| Версионные ограничения | — | ✓ | — | — |
| **Скрипты** | | | | |
| Pre-install | Через CustomAction | ✓ | ✓ | — |
| Post-install | Через CustomAction | ✓ | ✓ | — |
| Pre-remove | — | ✓ | — | — |
| Post-remove | — | ✓ | — | — |
| **Условная логика** | | | | |
| Compile-time условия | ✓ (препроцессор) | Через envsubst | — | — |
| Runtime условия | ✓ (Condition) | — | В скриптах | — |
| Условия по архитектуре | ✓ | — | — | — |
| Условия по версии OS | ✓ (VersionNT) | — | В скриптах | — |
| **Windows-специфика** | | | | |
| Системный реестр | ✓ | — | — | — |
| Ярлыки (Shortcuts) | ✓ | — | — | — |
| Файловые ассоциации | ✓ | — | — | — |
| Иконка в ARP | ✓ | — | — | — |
| **macOS-специфика** | | | | |
| Component plist | — | — | ✓ | — |
| Payload-free пакет | — | — | ✓ | — |
| Drag-and-drop UX | — | — | — | ✓ |
| Шифрование образа | — | — | — | ✓ |
| **Форматы и вывод** | | | | |
| Один вход → несколько форматов | — | ✓ | — | — |
| Сжатие | ✓ (CAB) | ✓ (формат-зависимо) | ✓ | ✓ (ULFO/UDZO) |
| Подпись | osslsigncode | gpg/rsa | `--sign` | codesign |

---

## 11. Ключевые фундаментальные различия

### Различие 1: Статические vs динамические компоненты

**wixl** требует явных GUID для каждого компонента — это позволяет Windows Installer отслеживать установку, управлять ref-counting, корректно обновлять. Это делает wixl verbatim-декларативным, но надёжным.

**nfpm** не имеет GUID — просто список файлов. Нет ref-counting, нет component tracking. Достаточно для Linux-пакетов, которые не используют эту концепцию.

### Различие 2: Управление конфиг-файлами

Только **nfpm** имеет нативный механизм `config|noreplace` — конфигурационный файл не перезаписывается при обновлении пакета. Это важная концепция в Linux-пакетировании. В wixl, pkgbuild и hdiutil этого нет в принципе — нужно реализовывать в скриптах.

### Различие 3: Зависимости

Только **nfpm** имеет систему зависимостей. Остальные три инструмента предполагают, что пользователь или CI-система сами управляют prerequisites.

### Различие 4: Рабочий процесс установки

- **wixl**: автоматическая установка через Windows Installer, с правами, регистром, ярлыками
- **nfpm**: автоматическая установка через apt/rpm/apk, со скриптами и зависимостями
- **pkgbuild**: автоматическая установка через macOS Installer, со скриптами
- **hdiutil**: ручная установка пользователем (drag-and-drop или копирование бинарника)

### Различие 5: Число форматов из одного конфига

**nfpm** уникален тем, что один `nfpm.yaml` → deb + rpm + apk + archlinux. Остальные инструменты — один формат на запуск.

---

## Выводы для проектирования Crossler

1. **Общее ядро** для всех форматов: name, version, arch, description, maintainer, homepage, license — это intersection метаданных.

2. **Установка файлов** — общий паттерн для всех: src + dst + mode. Концепция типов файлов (`config|noreplace`) важна для Linux и стоит поддержки.

3. **Скрипты** — общий паттерн для wixl/nfpm/pkgbuild (hdiutil исключение). Четыре хука: pre/post install/remove.

4. **Зависимости** — только Linux-форматы. Для Windows и macOS этот концепт отсутствует.

5. **Windows-специфика** (реестр, ярлыки) — нужно либо вынести в отдельную секцию, либо полностью опустить в первой версии.

6. **macOS-специфика** (component plist) — слишком низкоуровнево для Crossler, pkgbuild использует напрямую.

7. **Config-файлы** — концепция `config|noreplace` ценна и стоит реализации в конфиге Crossler.

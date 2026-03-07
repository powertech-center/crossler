# wixl — создание MSI-пакетов на Linux

## Что такое wixl

**wixl** — инструмент из пакета **msitools** (проект GNOME), позволяющий создавать Windows Installer (.msi) пакеты прямо в Linux-окружении. Это лёгкая альтернатива официальному WiX Toolset, который требует .NET и работает только на Windows.

msitools включает набор вспомогательных утилит:
- `wixl` — основной компилятор XML → MSI
- `wixl-heat` — генератор XML-фрагментов из списков файлов (harvesting)
- `msiinfo` — просмотр метаданных MSI
- `msidump` — дамп таблиц MSI в текстовый формат
- `msiextract` — распаковка файлов из MSI
- `msibuild` — низкоуровневое создание MSI

### Установка

```bash
# Alpine Linux (dev-контейнер Crossler)
apk add msitools

# Debian/Ubuntu
apt install msitools

# macOS
brew install msitools
```

### Отличие от полного WiX Toolset

| Критерий | wixl (msitools) | WiX Toolset |
|----------|-----------------|-------------|
| Платформа | Linux, macOS | Windows (требует .NET) |
| Зависимости | GLib, libmsi | .NET Framework/SDK |
| Формат входного файла | .wxs (совместим) | .wxs |
| UI-диалоги | Нет | Да (WixUI) |
| Custom Actions | Ограниченные | Полные (C#, VBScript, JS) |
| Burn Bootstrapper | Нет | Да |
| Merge Modules (.msm) | Нет | Да |
| Расширения (IIS, SQL, .NET) | Нет | Да |
| Идеален для | Кросс-компиляция в CI/CD | Сложные корпоративные инсталляторы |

**Вывод для Crossler:** wixl работает на Linux-бинарнике (основном), не требует зависимостей, достаточен для консольных утилит.

---

## Аргументы командной строки wixl

```
wixl [OPTION...] INPUT_FILE [INPUT_FILE2...]
```

| Флаг | Описание |
|------|---------|
| `-o FILE`, `--output FILE` | Выходной MSI-файл (по умолчанию: имя входного + .msi) |
| `-v`, `--verbose` | Подробный вывод — рекомендуется при отладке |
| `-a ARCH`, `--arch ARCH` | Целевая архитектура: `x86` (по умолчанию) или `x64` |
| `-D VAR=VAL`, `--define VAR=VAL` | Определить переменную препроцессора (можно несколько) |
| `-I DIR`, `--includedir DIR` | Добавить директорию поиска для include-файлов |
| `-E`, `--only-preproc` | Остановиться после препроцессинга, вывести обработанный XML |
| `--extdir DIR` | Системная директория расширений |
| `--wxidir DIR` | Системная директория include-файлов |
| `--version` | Показать версию и выйти |
| `-h`, `--help` | Справка |

### Примеры использования

```bash
# Базовая компиляция
wixl -v -o dist/app.msi installer.wxs

# С переменными и архитектурой
wixl -v -o dist/app-x64.msi -a x64 -D Version=1.2.3 -D Company="ACME" installer.wxs

# Только препроцессинг (для отладки)
wixl -E installer.wxs > preprocessed.wxs

# Несколько входных файлов (фрагменты)
wixl -v -o dist/app.msi -D SourceDir=bin/release product.wxs files.wxs shortcuts.wxs
```

---

## Инструмент wixl-heat (harvesting файлов)

wixl-heat генерирует WiX XML-фрагменты из списка файлов — автоматически создаёт `Component` и `ComponentGroup` элементы для каждого файла.

```bash
find /path/to/files -type f | wixl-heat [OPTIONS]
```

| Флаг | Описание |
|------|---------|
| `--directory-ref DIR` | ID директории назначения (обязателен) |
| `--component-group NAME` | Имя группы компонентов |
| `--var VAR` | Переменная для пути к источнику (`$(var.VAR)/file.txt`) |
| `-p PREFIX` | Префикс для удаления из путей |
| `-x PATTERN` | Исключить файлы по шаблону |
| `--win64` | Добавить атрибут `Win64="yes"` ко всем компонентам |

```bash
# Сгенерировать фрагмент для всех файлов в bin/
find bin/ -type f | wixl-heat \
  --directory-ref INSTALLFOLDER \
  --component-group CG.AppFiles \
  --var var.SourceDir \
  > fragments.wxs

# Затем собрать вместе
wixl -v -D SourceDir=bin -o app.msi product.wxs fragments.wxs
```

---

## Формат входного файла .wxs (WiX XML)

### Корневая структура

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <!-- Дочерние элементы: Product, Fragment -->
</Wix>
```

Допустимые прямые дочерние элементы `<Wix>`:
- `<Product>` — основной пакет (только один)
- `<Fragment>` — переиспользуемые фрагменты (неограниченно)
- `<Module>` — merge module (только один)

### Типичная иерархия

```
Wix
└── Product
    ├── Package
    ├── Media / MediaTemplate
    ├── Icon
    ├── Property
    ├── Condition
    ├── Directory (TARGETDIR)
    │   └── Directory (ProgramFilesFolder)
    │       └── Directory (INSTALLFOLDER)
    ├── DirectoryRef → Component → File, Shortcut, RegistryValue
    └── Feature
        └── ComponentRef
```

---

## Ключевые элементы WiX XML

### `<Product>` — корневой элемент установщика

```xml
<Product
  Id="*"
  Name="My Application"
  Language="1033"
  Version="1.0.0.0"
  Manufacturer="ACME Corp"
  UpgradeCode="12345678-1234-1234-1234-123456789012">
```

| Атрибут | Описание |
|---------|---------|
| `Id` | GUID версии продукта. `*` = автогенерация (рекомендуется) |
| `Name` | Название продукта |
| `Language` | LCID: 1033 = English US |
| `Version` | Версия в формате Major.Minor.Build.Revision |
| `Manufacturer` | Производитель |
| `UpgradeCode` | GUID линии продукта — **НИКОГДА не менять между версиями** |

### `<Package>` — метаданные MSI-пакета

```xml
<Package
  InstallerVersion="200"
  Compressed="yes"
  InstallScope="perMachine"
  Description="My Application Installer"
  Manufacturer="ACME Corp"
/>
```

| Атрибут | Описание |
|---------|---------|
| `InstallerVersion` | Минимальная версия Windows Installer (200 = 2.0, достаточно для большинства) |
| `Compressed` | `yes` — встроить файлы в MSI |
| `InstallScope` | `perMachine` — для всех пользователей, `perUser` — для текущего |
| `Platform` | `x86` или `x64` (можно также указать через `-a` в CLI) |

### `<MediaTemplate>` / `<Media>` — упаковка файлов

```xml
<!-- Простой вариант — встроить всё в MSI -->
<MediaTemplate EmbedCab="yes" />

<!-- Явный контроль -->
<Media Id="1" Cabinet="product.cab" EmbedCab="yes" CompressionLevel="high" />
```

### `<Directory>` — структура директорий

```xml
<Directory Id="TARGETDIR" Name="SourceDir">
  <Directory Id="ProgramFilesFolder">
    <Directory Id="INSTALLFOLDER" Name="MyApp" />
  </Directory>
  <Directory Id="DesktopFolder" />
  <Directory Id="ProgramMenuFolder" />
</Directory>
```

Предопределённые ID директорий Windows:

| ID | Путь |
|----|------|
| `TARGETDIR` | Корень (обязателен как первый Directory) |
| `ProgramFilesFolder` | C:\Program Files (x86 или x64 автоматически) |
| `ProgramFiles64Folder` | C:\Program Files (явно x64) |
| `CommonAppDataFolder` | C:\ProgramData |
| `LocalAppDataFolder` | %APPDATA%\Local |
| `AppDataFolder` | %APPDATA%\Roaming |
| `DesktopFolder` | Рабочий стол пользователя |
| `ProgramMenuFolder` | Меню Пуск |
| `StartupFolder` | Автозагрузка |
| `SystemFolder` | C:\Windows\System32 |
| `WindowsFolder` | C:\Windows |

### `<Component>` — атомарная единица установки

Каждый Component — атомарная единица: либо всё установлено, либо ничего. Windows Installer отслеживает установку именно по компонентам.

```xml
<Component Id="MainExe" Guid="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" Directory="INSTALLFOLDER">
  <File Id="AppExe" Source="bin/app.exe" KeyPath="yes" />
</Component>
```

| Атрибут | Описание |
|---------|---------|
| `Id` | Уникальный идентификатор компонента |
| `Guid` | GUID для отслеживания компонента. Должен быть уникальным и стабильным |
| `Directory` | ID директории установки |
| `Win64` | `yes` для 64-битных компонентов |

**Правила GUID компонентов:**
- Каждый компонент — уникальный GUID
- GUID не меняется, пока содержимое (файлы/ключи) не изменилось
- При изменении содержимого → новый GUID
- Нельзя использовать один GUID в двух разных продуктах

### `<Feature>` — набор компонентов для установки

```xml
<Feature Id="ProductFeature" Title="My Application" Level="1" Display="expand">
  <ComponentRef Id="MainExe" />
  <ComponentRef Id="DesktopShortcut" />
  <Feature Id="OptionalDocs" Title="Documentation" Level="2">
    <ComponentRef Id="Docs" />
  </Feature>
</Feature>
```

| Атрибут | Описание |
|---------|---------|
| `Level` | 0 = не устанавливать, 1 = установить по умолчанию, 2+ = опционально |
| `Display` | `hidden`, `collapse`, `expand` — отображение в UI |

### `<File>` — файл для установки

```xml
<File
  Id="AppExe"
  Source="bin/release/app.exe"
  Name="app.exe"
  KeyPath="yes"
  Vital="yes"
/>
```

| Атрибут | Описание |
|---------|---------|
| `Source` | Путь к файлу на машине сборки (относительный к CWD или к директории .wxs) |
| `Name` | Имя файла на целевой машине (если отличается от Source) |
| `KeyPath` | `yes` — этот файл является ключом компонента (один на Component) |
| `Vital` | `yes` — отменить установку при ошибке копирования файла |
| `Compressed` | `yes`/`no` — переопределить сжатие для этого файла |

### `<Shortcut>` — ярлыки

```xml
<Shortcut
  Id="DesktopShortcut"
  Directory="DesktopFolder"
  Name="My App"
  Target="[INSTALLFOLDER]app.exe"
  Arguments="--start"
  Description="Launch My Application"
  WorkingDirectory="INSTALLFOLDER"
  Icon="ProductIcon"
  IconIndex="0"
/>
```

Ярлыки должны находиться в Component, который также содержит `<RegistryValue>` или `<File KeyPath="yes">`.

### `<RegistryValue>` и `<RegistryKey>` — записи в реестр

```xml
<!-- Одна запись -->
<RegistryValue
  Root="HKLM"
  Key="Software\ACME\MyApp"
  Name="InstallPath"
  Value="[INSTALLFOLDER]"
  Type="string"
/>

<!-- Группа записей -->
<RegistryKey Root="HKLM" Key="Software\ACME\MyApp" Action="createAndRemoveOnUninstall">
  <RegistryValue Name="Version" Value="1.0.0" Type="string" />
  <RegistryValue Name="Build" Value="123" Type="integer" />
</RegistryKey>
```

| Root | Описание |
|------|---------|
| `HKLM` | HKEY_LOCAL_MACHINE |
| `HKCU` | HKEY_CURRENT_USER |
| `HKCR` | HKEY_CLASSES_ROOT |
| `HKMU` | HKCU для perUser-установок, HKLM для perMachine |

| Type | REG-тип |
|------|---------|
| `string` | REG_SZ |
| `integer` | REG_DWORD |
| `binary` | REG_BINARY |
| `expandable` | REG_EXPAND_SZ |

### `<Condition>` — условия установки

```xml
<!-- На уровне Product (остановить установку если не выполнено) -->
<Condition Message="This application requires Windows 7 or later.">
  <![CDATA[VersionNT >= 601]]>
</Condition>

<!-- На уровне Component (не устанавливать компонент) -->
<Component Id="App64" Guid="..." Win64="yes">
  <Condition>Intel64</Condition>
  <File Source="bin/x64/app.exe" KeyPath="yes" />
</Component>
```

Встроенные свойства для условий:

| Свойство | Описание |
|----------|---------|
| `VersionNT` | Версия Windows: 501=XP, 600=Vista, 601=Win7, 1000+=Win10 |
| `Intel64` | Система 64-бит |
| `Privileged` | Запущено с правами администратора |
| `Installed` | Продукт уже установлен |
| `REMOVE` | Выполняется удаление |
| `ALLUSERS` | 1 = установка для всех, 0 = для текущего |

### `<Icon>` — иконки

```xml
<Icon Id="ProductIcon" SourceFile="resources/app.ico" />

<!-- Иконка в Add/Remove Programs -->
<Property Id="ARPPRODUCTICON" Value="ProductIcon" />
```

### `<CustomAction>` — пользовательские действия (ограниченно в wixl)

```xml
<CustomAction
  Id="LaunchApp"
  Directory="INSTALLFOLDER"
  ExeCommand="[INSTALLFOLDER]app.exe --init"
  Return="asyncNoWait"
  Execute="deferred"
  Impersonate="no"
/>

<InstallExecuteSequence>
  <Custom Action="LaunchApp" After="InstallFinalize">NOT Installed</Custom>
</InstallExecuteSequence>
```

---

## GUID-идентификаторы: правила

### Три вида GUID в WiX

| GUID | Элемент | Правило |
|------|---------|---------|
| **ProductCode** | `Product/@Id` | Меняется с каждой версией. Используйте `*` для автогенерации |
| **UpgradeCode** | `Product/@UpgradeCode` | **НИКОГДА не меняется** — идентифицирует линию продукта |
| **ComponentCode** | `Component/@Guid` | Стабилен пока содержимое компонента не изменилось. Меняется при изменении файлов |

### Правило UpgradeCode

```xml
<!-- v1.0 -->
<Product Id="*" UpgradeCode="FIXED-UUID-HERE" Version="1.0.0.0" />

<!-- v1.1 — ТОЛЬКО Version меняется, UpgradeCode тот же -->
<Product Id="*" UpgradeCode="FIXED-UUID-HERE" Version="1.1.0.0" />

<!-- v2.0 — UpgradeCode всё равно тот же! -->
<Product Id="*" UpgradeCode="FIXED-UUID-HERE" Version="2.0.0.0" />
```

### Правило Component GUID

```xml
<!-- v1.0 -->
<Component Id="MainExe" Guid="COMP-GUID-1">
  <File Source="app-1.0.exe" />  <!-- Файл версии 1.0 -->
</Component>

<!-- v1.1 — бинарник изменился, меняем GUID -->
<Component Id="MainExe" Guid="COMP-GUID-2">
  <File Source="app-1.1.exe" />  <!-- Файл версии 1.1 -->
</Component>
```

---

## Препроцессор WiX

### Определение переменных

В .wxs файле:
```xml
<?define ProductVersion = "1.2.3" ?>
<?define CompanyName = "ACME Corp" ?>
<?define SourceDir = "bin/release" ?>
```

Из командной строки:
```bash
wixl -D Version=1.2.3 -D Company="ACME Corp" -D SourceDir=bin/release installer.wxs
```

### Использование переменных

```xml
<Product Name="My App" Version="$(var.ProductVersion)" Manufacturer="$(var.CompanyName)" />
<File Source="$(var.SourceDir)/app.exe" />
```

Типы переменных:

| Синтаксис | Тип | Пример |
|-----------|-----|--------|
| `$(var.Name)` | Пользовательская | `$(var.Version)` |
| `$(env.VAR)` | Переменная окружения | `$(env.BUILD_NUMBER)` |
| `$(sys.SOURCEFILEDIR)` | Системная | Путь к директории .wxs |

### Условная компиляция

```xml
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

<?ifdef DEBUG ?>
  <Property Id="DEBUGMODE" Value="1" />
<?endif ?>
```

### Include-файлы

product.wxs:
```xml
<?include "common/directories.wxi" ?>
<?include "common/components.wxi" ?>
```

directories.wxi:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Include>
  <Directory Id="TARGETDIR" Name="SourceDir">
    <Directory Id="ProgramFilesFolder">
      <Directory Id="INSTALLFOLDER" Name="MyApp" />
    </Directory>
  </Directory>
</Include>
```

---

## Что поддерживает и не поддерживает wixl

### Поддерживается

- `<Product>`, `<Package>`, `<Directory>`, `<Component>`, `<Feature>`, `<File>`
- `<Shortcut>` — ярлыки на рабочий стол и в меню
- `<RegistryValue>`, `<RegistryKey>` — базовые операции с реестром
- `<Icon>`, `<Property>` — метаданные ARP
- `<Condition>` — условия установки
- `<Fragment>`, `<DirectoryRef>`, `<ComponentRef>` — модульная организация
- `<MediaTemplate>` / `<Media>` — встраивание CAB
- Препроцессор — переменные, условия, include-файлы
- `<CustomAction>` — базовые (EXE-based)
- wixl-heat — автоматический harvesting файлов

### Не поддерживается

- **UI диалоги** — нет WixUI, нет пользовательских экранов установщика
- **Сложные CustomActions** — нет поддержки DLL, COM, .NET managed actions
- **Burn Bootstrapper** — нет создания bundle-установщиков с prerequisites
- **Merge Modules (.msm)** — нет импорта переиспользуемых компонентов
- **WiX Extensions** — нет IIS, SQL Server, .NET, DirectX extensions
- **MajorUpgrade** — нет встроенной логики обновления (нужно писать вручную через InstallExecuteSequence)
- **Локализация (.wxl)** — нет полноценной поддержки файлов локализации
- **ServiceInstall** — нет управления Windows Services

---

## Практические примеры

### Минимальный MSI для консольного приложения

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <?define Version = "1.0.0.0" ?>
  <?define Manufacturer = "ACME Corp" ?>

  <Product
    Id="*"
    Name="My CLI Tool"
    Language="1033"
    Version="$(var.Version)"
    Manufacturer="$(var.Manufacturer)"
    UpgradeCode="12345678-1234-1234-1234-123456789012">

    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />

    <Condition Message="This application requires Windows 7 or later.">
      <![CDATA[VersionNT >= 601]]>
    </Condition>

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="mycli" />
      </Directory>
    </Directory>

    <Feature Id="ProductFeature" Level="1">
      <ComponentRef Id="MainBinary" />
    </Feature>

    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="MainBinary" Guid="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA">
        <File Id="AppExe" Source="dist/windows-amd64/mycli.exe" KeyPath="yes" Vital="yes" />
        <RegistryValue Root="HKLM"
          Key="Software\ACME\mycli"
          Name="InstallPath"
          Value="[INSTALLFOLDER]"
          Type="string" />
      </Component>
    </DirectoryRef>
  </Product>
</Wix>
```

```bash
wixl -v -o dist/mycli-windows-amd64.msi -a x64 -D Version=1.0.0.0 installer.wxs
```

### MSI с ярлыком на рабочем столе и в меню Пуск

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="MyApp" Language="1033" Version="1.0.0.0"
           Manufacturer="ACME" UpgradeCode="UPGRADE-CODE-GUID">

    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />

    <Icon Id="ProductIcon" SourceFile="resources/app.ico" />
    <Property Id="ARPPRODUCTICON" Value="ProductIcon" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="MyApp" />
      </Directory>
      <Directory Id="DesktopFolder" />
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ProgramMenuSubfolder" Name="MyApp" />
      </Directory>
    </Directory>

    <Feature Id="ProductFeature" Level="1">
      <ComponentRef Id="AppFiles" />
      <ComponentRef Id="DesktopShortcutComp" />
      <ComponentRef Id="StartMenuShortcutComp" />
    </Feature>

    <!-- Основные файлы -->
    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="AppFiles" Guid="BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB">
        <File Id="AppExe" Source="bin/myapp.exe" KeyPath="yes" Vital="yes" />
      </Component>
    </DirectoryRef>

    <!-- Ярлык на рабочем столе -->
    <DirectoryRef Id="DesktopFolder">
      <Component Id="DesktopShortcutComp" Guid="CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC">
        <Shortcut Id="DesktopShortcut" Directory="DesktopFolder"
                  Name="My App" Target="[INSTALLFOLDER]myapp.exe"
                  WorkingDirectory="INSTALLFOLDER" Icon="ProductIcon" />
        <RegistryValue Root="HKCU" Key="Software\ACME\MyApp"
                       Name="DesktopShortcut" Value="1" Type="integer" />
      </Component>
    </DirectoryRef>

    <!-- Ярлык в меню Пуск -->
    <DirectoryRef Id="ProgramMenuSubfolder">
      <Component Id="StartMenuShortcutComp" Guid="DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD">
        <Shortcut Id="StartMenuShortcut" Directory="ProgramMenuSubfolder"
                  Name="My App" Target="[INSTALLFOLDER]myapp.exe"
                  WorkingDirectory="INSTALLFOLDER" Icon="ProductIcon" />
        <RemoveFolder Id="ProgramMenuSubfolder" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\ACME\MyApp"
                       Name="StartMenuShortcut" Value="1" Type="integer" />
      </Component>
    </DirectoryRef>
  </Product>
</Wix>
```

### MSI с условием по архитектуре (x86 vs x64)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <?define Version = "1.0.0.0" ?>

  <Product Id="*" Name="MyApp" Language="1033" Version="$(var.Version)"
           Manufacturer="ACME" UpgradeCode="UPGRADE-GUID">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="MyApp" />
      </Directory>
    </Directory>

    <Feature Id="ProductFeature" Level="1">
      <ComponentRef Id="App_x64" />
      <ComponentRef Id="App_x86" />
    </Feature>

    <!-- 64-bit вариант -->
    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="App_x64" Guid="EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE" Win64="yes">
        <Condition>Intel64</Condition>
        <File Source="dist/windows-amd64/app.exe" Name="app.exe" KeyPath="yes" />
      </Component>
    </DirectoryRef>

    <!-- 32-bit вариант -->
    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="App_x86" Guid="FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF">
        <Condition>NOT Intel64</Condition>
        <File Source="dist/windows-386/app.exe" Name="app.exe" KeyPath="yes" />
      </Component>
    </DirectoryRef>
  </Product>
</Wix>
```

### Модульная организация через Fragment и Include

Главный файл `product.wxs`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <?define Version = "1.0.0.0" ?>
  <?define SourceDir = "bin/release" ?>

  <Product Id="*" Name="MyApp" Language="1033" Version="$(var.Version)"
           Manufacturer="ACME" UpgradeCode="UPGRADE-GUID">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />

    <?include "directories.wxi" ?>

    <Feature Id="ProductFeature" Level="1">
      <ComponentGroupRef Id="AppFiles" />
    </Feature>
  </Product>
</Wix>
```

Фрагмент с файлами `fragments.wxs` (сгенерирован wixl-heat):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Fragment>
    <ComponentGroup Id="AppFiles" Directory="INSTALLFOLDER">
      <Component Id="comp_app_exe" Guid="GUID-1">
        <File Source="$(var.SourceDir)/app.exe" KeyPath="yes" />
      </Component>
      <Component Id="comp_app_config" Guid="GUID-2">
        <File Source="$(var.SourceDir)/config.yaml" />
      </Component>
    </ComponentGroup>
  </Fragment>
</Wix>
```

```bash
wixl -v -o dist/app.msi -D Version=1.0.0.0 -D SourceDir=bin/release product.wxs fragments.wxs
```

---

## Best Practices и подводные камни

### Правила, нарушение которых ведёт к багам

1. **UpgradeCode не меняется никогда.** Изменение UpgradeCode означает, что старая версия не будет найдена и удалена при обновлении — на машине окажутся две версии.

2. **Component GUID уникален и стабилен.** Нельзя использовать одинаковый GUID для двух компонентов. Нельзя менять GUID компонента без изменения его содержимого.

3. **Один KeyPath на Component.** Каждый Component должен иметь ровно один `KeyPath="yes"` файл или ключ реестра.

4. **Product Version — только 3 части для обновлений.** Windows Installer сравнивает только первые три части версии (`1.2.3.x` и `1.2.3.y` считаются одинаковыми).

5. **Ярлыки требуют RegistryValue в том же Component.** Без RegistryValue компонент с ярлыком не имеет KeyPath и не будет правильно отслеживаться.

### Рекомендации

- Всегда запускайте с `-v` — wixl молча игнорирует многие ошибки
- Используйте `wixl -E installer.wxs` для проверки препроцессора
- Держите UpgradeCode в отдельной переменной: `<?define UpgradeCode = "..." ?>`
- Разделяйте файлы на фрагменты: основной product.wxs + fragments.wxs для файлов
- Используйте wixl-heat для автоматической генерации компонентов из директории
- Тестируйте обновление с v1 на v2 перед релизом v1

### Диагностика

```bash
# Verbose режим
wixl -v installer.wxs

# Только препроцессинг
wixl -E installer.wxs > out.wxs && cat out.wxs

# Инспекция готового MSI
msiinfo list app.msi
msidump app.msi

# Распаковка содержимого MSI
msiextract app.msi -C extracted/
```

---

## Ссылки

- [msitools на GNOME GitLab](https://gitlab.gnome.org/GNOME/msitools)
- [msitools HowTo на GNOME Wiki](https://wiki.gnome.org/msitools/HowTo/CreateMSI)
- [Ubuntu Manpage: wixl](https://manpages.ubuntu.com/manpages/noble/man1/wixl.1.html)
- [Ubuntu Manpage: wixl-heat](https://manpages.ubuntu.com/manpages/jammy/man1/wixl-heat.1.html)
- [WiX Toolset официальная документация](https://wixtoolset.org/docs/)
- [FireGiant WiX 3 документация (синтаксис совместим с wixl)](https://docs.firegiant.com/wix3/)
- [WiX Schema Reference](https://docs.firegiant.com/wix3/xsd/)

# Интеграция с окружением ОС — исследование для Crossler

> Перевод и дополнение документа `environment-integration.md`. Анализ того, как пакеты программ интегрируются с окружением операционной системы в Windows, macOS и Linux. Рассмотрены механизмы в каждом бэкенде (WiX/wixl для MSI, nfpm для deb/rpm/apk, pkgbuild для macOS .pkg) и то, как другие инструменты (GoReleaser, fpm, electron-builder, Inno Setup, NSIS) реализуют эти возможности. В разделе [6. Дополнения к исследованию](#6-дополнения-к-исследованию) добавлены уточнения по wixl, рекомендации по systemd postinstall, заметки о Flatpak/Snap и безопасности.

---

## Содержание

1. [Интеграция в Windows](#1-интеграция-в-windows)
2. [Интеграция в macOS](#2-интеграция-в-macos)
3. [Интеграция в Linux](#3-интеграция-в-linux)
4. [Сравнение инструментов](#4-сравнение-инструментов)
5. [Единая конфигурация для Crossler](#5-единая-конфигурация-для-crossler)
6. [Дополнения к исследованию](#6-дополнения-к-исследованию)

---

## 1. Интеграция в Windows

### 1.1 Переменная окружения PATH

**Что это:** добавление каталога установки приложения в системную или пользовательскую переменную `PATH`, чтобы исполняемый файл можно было вызывать из любого терминала без полного пути. Критично для CLI-инструментов.

**Как реализуется в WiX/wixl:**

В WiX для изменения переменных окружения (в том числе PATH) используется элемент `<Environment>` внутри `<Component>`:

```xml
<Component Id="PathEnv" Guid="GUID-HERE">
  <Environment
    Id="PATH_ENTRY"
    Name="PATH"
    Value="[INSTALLFOLDER]"
    Permanent="no"
    Part="last"
    Action="set"
    System="yes" />
  <RegistryValue Root="HKLM" Key="Software\MyCompany\MyApp"
                 Name="PathAdded" Value="1" Type="integer" KeyPath="yes" />
</Component>
```

Ключевые атрибуты:
- `Part="last"` — добавление в конец PATH (или `first` — в начало, `all` — замена целиком)
- `System="yes"` — системный PATH; `System="no"` — пользовательский
- `Permanent="no"` — запись удаляется при деинсталляции; `Permanent="yes"` — остаётся
- `Action="set"` — добавить значение; `Action="remove"` — удалить

Элемент `<Environment>` меняет `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\Path` (системный) или `HKCU\Environment\Path` (пользовательский) и рассылает `WM_SETTINGCHANGE`, чтобы уже запущенные оболочки подхватили изменение.

**Поддержка в wixl:** элемент `<Environment>` поддерживается. Это стандартный механизм.

**Inno Setup:** секция `[Registry]` или директива `ChangesEnvironment=yes` с кодом в `[Code]`. В новых версиях есть флаг `AppendToPath`.

**NSIS:** плагин `EnVar` или запись в реестр через `WriteRegExpandStr`.

**electron-builder (на базе NSIS):** по умолчанию в PATH не добавляет; нужны кастомные NSIS-скрипты.

**GoReleaser (MSI через WiX, Pro):** настройки добавления в PATH в конфиге нет; требуются кастомные шаблоны WiX.

**Параметры единой конфигурации:**
```toml
[windows]
path = true  # или path = "append" / "prepend"
# Более детально:
# path_scope = "system"  # "system" или "user"
```

**Общее:** необходимо для CLI-инструментов. Для большинства GUI-приложений не требуется.

---

### 1.2 Переменные окружения (прочие)

**Что это:** установка произвольных переменных окружения (не PATH), сохраняющихся после перезагрузки. Используются для путей конфигурации, лицензий и т.п.

**Как в WiX/wixl:** тот же элемент `<Environment>` с `Part="all"` (задать значение целиком):

```xml
<Environment
  Id="MY_ENV_VAR"
  Name="MYAPP_HOME"
  Value="[INSTALLFOLDER]"
  Permanent="no"
  Part="all"
  Action="set"
  System="yes" />
```

**Поддержка в wixl:** да, через `<Environment>`.

**Inno Setup / NSIS:** запись в реестр в `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment` или `HKCU\Environment`.

**Параметры единой конфигурации:**
```toml
[windows]
env = { "MYAPP_HOME" = "{install_dir}", "MYAPP_CONFIG" = "{install_dir}\\config" }
```

**Общее:** редко. В Windows чаще используют конфиг-файлы или реестр. Иногда полезны переменные вида `*_HOME` (например, `JAVA_HOME`).

---

### 1.3 Ярлыки в меню «Пуск»

**Что это:** создание ярлыков (`.lnk`) в папке меню «Пуск», чтобы приложение можно было запускать из меню.

**Как в WiX/wixl:**

```xml
<Directory Id="TARGETDIR" Name="SourceDir">
  <Directory Id="ProgramMenuFolder">
    <Directory Id="AppMenuFolder" Name="My Application" />
  </Directory>
</Directory>

<DirectoryRef Id="AppMenuFolder">
  <Component Id="StartMenuShortcut" Guid="GUID-HERE">
    <Shortcut
      Id="AppShortcut"
      Name="My Application"
      Description="Launch My Application"
      Target="[INSTALLFOLDER]myapp.exe"
      Arguments=""
      WorkingDirectory="INSTALLFOLDER"
      Icon="AppIcon"
      IconIndex="0" />
    <RemoveFolder Id="AppMenuFolder" On="uninstall" />
    <RegistryValue Root="HKCU" Key="Software\MyCompany\MyApp"
                   Name="StartMenuShortcut" Value="1" Type="integer" KeyPath="yes" />
  </Component>
</DirectoryRef>
```

Важно:
- `ProgramMenuFolder` — стандартный идентификатор каталога «Пуск» в WiX
- У компонента с ярлыком должен быть `RegistryValue` с `KeyPath="yes"` (у самого ярлыка KeyPath быть не может)
- `RemoveFolder` обеспечивает удаление папки при деинсталляции
- Иконки объявляются отдельно через `<Icon>` и указываются по Id

**Поддержка в wixl:** да. `<Shortcut>` и `<RemoveFolder>` работают.

**Inno Setup:** секция `[Icons]` с `{autoprograms}`.  
**NSIS:** функция `CreateShortCut`.  
**electron-builder:** создаёт ярлыки в меню «Пуск» для NSIS и MSI; настраивается через `shortcutName`.

**Параметры единой конфигурации:**
```toml
[windows.shortcuts]
start_menu = true
start_menu_folder = "My App"   # подпапка (по умолчанию — имя приложения)
```

**Общее:** важно для GUI; для CLI тоже полезно (запуск терминала с нужным окружением).

---

### 1.4 Ярлык на рабочем столе

**Что это:** создание `.lnk` на рабочем столе пользователя.

**Как в WiX/wixl:** используется предопределённый `DesktopFolder`, правила компонентов те же, что для меню «Пуск».

**Параметры единой конфигурации:**
```toml
[windows.shortcuts]
desktop = true
```

**Общее:** типично для GUI; для CLI редко. Часто делают опцией при установке (галочка).

---

### 1.5 Ассоциации файлов

**Что это:** регистрация приложения как обработчика расширений (например, `.myext`): двойной щелчок открывает файл в приложении. Требуется ProgID, привязка расширений и описание действий (open, edit, print).

**Как в WiX/wixl:**

```xml
<Component Id="FileAssoc" Guid="GUID-HERE" Directory="INSTALLFOLDER">
  <File Id="AppExe" Source="myapp.exe" KeyPath="yes" />
  <ProgId Id="MyApp.Document" Description="My Application Document" Icon="AppIcon">
    <Extension Id="myext" ContentType="application/x-myext">
      <Verb Id="open" Command="Open" TargetFile="AppExe" Argument='"%1"' />
    </Extension>
  </ProgId>
</Component>
```

Создаётся связь `.myext` → ProgID и команда открытия. Для ассоциаций «на пользователя» (Vista+) используется `HKCU\Software\Classes` (при `InstallScope="perUser"`).

**Поддержка в wixl:** `<ProgId>` и `<Extension>` поддерживаются.

**Параметры единой конфигурации:**
```toml
[[file_associations]]
extension = "myext"
mime_type = "application/x-myext"
description = "My Application Document"
icon = "icons/document.ico"
role = "editor"   # editor, viewer, shell, none
```

**Общее:** важно для приложений, работающих с документами. Для CLI обычно не нужно. Концепция кросс-платформенная (macOS — UTI, Linux — MIME).

---

### 1.6 Контекстное меню (расширения оболочки)

**Что это:** пункты в контекстном меню проводника («Открыть в MyApp», «Редактировать в MyApp» и т.п.).

**Простой вариант — через реестр:** ключи в `HKCR\*\shell\MyApp`, `HKCR\Directory\shell\MyApp`, `HKCR\Directory\Background\shell\MyApp` и т.д., с подразделом `command`. Цели: все файлы (`*\shell\`), папки (`Directory\shell\`), фон папки (`Directory\Background\shell\`), диски (`Drive\shell\`).

**Сложный вариант — COM shell extensions:** требуется регистрация DLL; в wixl непрактично (нет поддержки COM). Реализуется только полным WiX Toolset или кастомными инсталляторами.

**Поддержка в wixl:** контекстное меню через `<RegistryKey>` / `<RegistryValue>` поддерживается. COM-расширения — нет.

**Windows 11:** по умолчанию используется новое контекстное меню; старые пункты попадают в «Дополнительно». Чтобы попасть в новое меню, нужна регистрация через shell extension DLL в `HKCU\Software\Classes\CLSID\{...}\InprocServer32` — для простых инсталляторов непрактично.

**Параметры единой конфигурации:**
```toml
[[windows.context_menu]]
target = "files"   # "files", "directories", "directory_background", "extension:.myext"
label = "Open with MyApp"
command = "{install_dir}\\myapp.exe \"%1\""
icon = "{install_dir}\\myapp.exe,0"
```

**Общее:** полезно для «Открыть в терминале», редакторов, архиваторов. Для типичных CLI не обязательно.

---

### 1.7 Службы Windows

**Что это:** регистрация исполняемого файла как службы Windows (фоновый процесс, автозапуск, управление через `sc.exe` или оснастку «Службы»).

**В полном WiX:** используются элементы `<ServiceInstall>` и `<ServiceControl>` в компоненте с исполняемым файлом. Атрибуты: тип процесса, тип запуска (auto, demand, disabled), учётная запись, обработка ошибок. `ServiceControl` — запуск/остановка при установке и удалении.

**Поддержка в wixl:** `<ServiceInstall>` в wixl **не поддерживается**. Обходной путь — CustomAction с вызовом `sc.exe create` и `sc.exe delete` (deferred, без impersonation), с правильной последовательностью в `InstallExecuteSequence`.

**Inno Setup / NSIS:** вызов `sc.exe` или плагины (например, nsSCM) в скриптах установки/удаления.

**Параметры единой конфигурации:**
```toml
[windows.service]
name = "myservice"
display_name = "My Application Service"
description = "Background tasks for MyApp"
start_type = "auto"      # "auto", "manual", "disabled"
account = "LocalSystem"  # "LocalSystem", "LocalService", "NetworkService"
```

**Общее:** необходимо для серверных/демон-приложений в Windows. Для обычных GUI/CLI не нужно.

---

### 1.8 Автозапуск при входе

**Что это:** запуск приложения при входе пользователя в систему (пользовательская сессия, не служба).

**Механизмы:**
1. Ярлык в папке автозагрузки — WiX `StartupFolder`, компонент с `<Shortcut>` и KeyPath.
2. Реестр: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (пользователь) или `HKLM\...\Run` (все пользователи).

**Поддержка в wixl:** оба варианта реализуемы.

**Параметры единой конфигурации:**
```toml
[windows]
autostart = true
autostart_args = "--background"
```

**Общее:** типично для приложений в трее и фоновых утилит.

---

### 1.9 Записи реестра

**Что это:** запись в реестр для конфигурации, App Paths и данных приложения.

**Типичные места:**
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\myapp.exe` — запуск из диалога «Выполнить» без изменения PATH (не добавляет в PATH для cmd/PowerShell).
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{GUID}` — запись в «Программы и компоненты» (MSI создаёт автоматически).
- `HKLM` или `HKCU\SOFTWARE\MyCompany\MyApp` — свои настройки.

**App Paths в WiX:** ключ `App Paths\myapp.exe` с значениями пути к exe и каталогу. Позволяет Win+R и `CreateProcess("myapp.exe")` находить приложение без PATH.

**Параметры единой конфигурации:**
```toml
[windows]
app_paths = true

[[windows.registry]]
root = "HKLM"
key = "SOFTWARE\\MyCompany\\MyApp"
values = { "InstallPath" = "{install_dir}", "Version" = "{version}" }
```

**Общее:** App Paths — альтернатива PATH для CLI. Кастомный реестр — по необходимости.

---

### 1.10 Правила брандмауэра

**Что это:** исключения в брандмауэре Windows, чтобы приложение могло принимать входящие подключения.

**В полном WiX:** расширение `WixFirewallExtension`, элемент `FirewallException`.  
**В wixl:** расширения WiX не поддерживаются. Обход — CustomAction с `netsh advfirewall firewall add rule ...`.

**Параметры единой конфигурации:**
```toml
[windows.firewall]
program = true
# или port = 8080, protocol = "tcp"
```

**Общее:** нужно только для приложений, слушающих порты.

---

### 1.11 Обработчики протоколов (URL-схемы)

**Что это:** регистрация схемы URL (например, `myapp://`) для запуска приложения по ссылке из браузера или других программ.

**В WiX/wixl:** ключи реестра `HKCR\myapp`, `HKCR\myapp\DefaultIcon`, `HKCR\myapp\shell\open\command`; в корне схемы обязателен параметр `URL Protocol`.

**Параметры единой конфигурации:**
```toml
[[protocol_handlers]]
scheme = "myapp"
description = "My Application Protocol"
```

**Общее:** нишево; типично для веб-ориентированных приложений (Slack, VS Code и т.п.).

---

### 1.12 Запланированные задачи

**Что это:** задачи в Планировщике заданий Windows (ежедневно, при входе и т.д.).

**В полном WiX:** расширение WixUtilExtension, элемент `<ScheduledTask>` — в wixl недоступно. Обход — CustomAction с `schtasks.exe /Create` и `schtasks.exe /Delete`.

**Параметры единой конфигурации:**
```toml
[[windows.scheduled_tasks]]
name = "MyApp Maintenance"
command = "{install_dir}\\myapp.exe --maintenance"
schedule = "daily"
time = "02:00"
```

**Общее:** нишево; обновления, обслуживание, резервное копирование.

---

## 2. Интеграция в macOS

### 2.1 PATH

**Что это:** возможность вызывать установленный бинарник из терминала. В PATH по умолчанию есть `/usr/local/bin`, но не пути внутри `/opt/` или внутри .app.

**Механизмы:**
1. Установка в `/usr/local/bin` — payload с `usr/local/bin/myapp`.
2. Символическая ссылка из `/usr/local/bin` на бинарник в другом месте (например, в postinstall).
3. **paths.d (macOS 10.13+):** файл в `/etc/paths.d/` с путём; подхватывается `path_helper` в профиле оболочки.
4. Правка профиля оболочки — не рекомендуется.

**pkgbuild:** сам PATH не настраивает; делается в postinstall (symlink или запись в `/etc/paths.d/myapp`). Переменная `$2` в скриптах — том установки.

**Homebrew:** ставит в `/opt/homebrew/bin` (Apple Silicon) или `/usr/local/bin` (Intel), эти пути уже в PATH.

**Параметры единой конфигурации:**
```toml
[macos]
path = true   # symlink в /usr/local/bin или запись в paths.d
```

**Общее:** необходимо для CLI на macOS.

---

### 2.2 Переменные окружения

**Что это:** постоянные переменные окружения в macOS.

**Механизмы:** `launchctl setenv` (не переживает перезагрузку без LaunchDaemon); устаревший `launchd.conf`; LaunchDaemon plist, вызывающий `launchctl setenv` при загрузке; правка профиля оболочки (хрупко).

**pkgbuild:** только через postinstall. Единая конфигурация — `[macos] env = { "MYAPP_HOME" = "/opt/myapp" }`.

**Общее:** на macOS редко; чаще используют plist в `~/Library/Preferences` и `~/Library/Application Support`.

---

### 2.3 Launch Services (ассоциации файлов)

**Что это:** регистрация приложения в Launch Services для «Открыть с помощью» и обработки типов файлов. Эквивалент ассоциаций файлов в Windows.

**Механизм:** для .app ассоциации задаются в `Info.plist`: `CFBundleDocumentTypes`, расширения, роль (Editor/Viewer/Shell), иконка; для своих типов — `UTExportedTypeDeclarations` с UTI (reverse-DNS), `LSItemContentTypes`. UTI — замена старых Creator/Type.

**pkgbuild:** только упаковывает payload; если в нём .app с правильным Info.plist, Launch Services подхватит после установки.

**Параметры единой конфигурации:** `[[file_associations]]` с полями extension, mime_type, description, role, uti (macOS), icon (.icns).

**Общее:** важно для приложений, работающих с документами. Для CLI не применимо.

---

### 2.4 Док

**Что это:** добавление приложения в док macOS.

Программно добавлять в док при установке Apple не разрешает. Варианты: пользователь перетаскивает .app в док; сторонние утилиты (dockutil); прямая правка plist дока — не рекомендуется.

**Вывод:** в единой конфигурации Crossler это не должно быть действием инсталлятора; остаётся на усмотрение пользователя.

---

### 2.5 Элементы входа (автозапуск)

**Что это:** запуск приложения при входе пользователя.

**Механизмы:** SMAppService (macOS 13+, API приложения, не инсталлятора); LaunchAgent plist в `/Library/LaunchAgents/` или `~/Library/LaunchAgents/` с `RunAtLoad=true`; устаревшие Login Items через Shared File Lists.

**pkgbuild:** plist в payload, в postinstall — `launchctl load ...`. Для пользовательского LaunchAgent файл просто кладётся в `~/Library/LaunchAgents/`, загрузка при следующем входе.

**Параметры единой конфигурации:**
```toml
[macos.login_item]
enabled = true
args = ["--background"]
keep_alive = false
```

**Общее:** типично для приложений в меню-баре и фоновых агентов.

---

### 2.6 Службы launchd (демоны и агенты)

**Что это:** регистрация фоновых процессов в launchd (аналог systemd и служб Windows).

**Типы:** LaunchDaemon (`/Library/LaunchDaemons/`, от root) — системные сервисы; LaunchAgent (системные или пользовательские каталоги) — пользовательские фоновые задачи.

**plist:** Label, ProgramArguments, RunAtLoad, KeepAlive, StandardOutPath/StandardErrorPath, UserName/GroupName, WorkingDirectory; при необходимости — StartInterval, StartCalendarInterval, WatchPaths, Sockets (socket activation).

**pkgbuild:** plist в payload; в postinstall для LaunchDaemon — `launchctl load -w ...`. Для LaunchAgent при установке из-под root лучше только установить файл.

**Параметры единой конфигурации:** `[macos.service]` с type (daemon/agent), label, args, keep_alive, run_at_load, user, group, log_path.

**Общее:** необходимо для серверов/демонов на macOS.

---

### 2.7 Spotlight (плагины mdimporter)

**Что это:** плагины индексации Spotlight для своих форматов файлов. Устанавливаются в `/Library/Spotlight/`. Для Crossler выходить за рамки «упаковать готовый .mdimporter» не рекомендуется — это отдельная разработка плагина.

---

### 2.8 Плагины Quick Look

**Что это:** генераторы превью в Finder (пробел по файлу). Устанавливаются в `/Library/QuickLook/` или `~/Library/QuickLook/`. В macOS 12+ Apple перешла на App Extensions; старые .qlgenerator по-прежнему работают, но помечены как устаревшие. Для Crossler — упаковка готового плагина, без генерации.

---

### 2.9 Расширения Finder

**Что это:** расширения для Finder (Share, панель инструментов, оверлеи вроде Dropbox). Это App Extensions внутри .app, с подписью и нотаризацией. В конфигурации упаковщика выделять отдельно не обязательно.

---

### 2.10 URL-схемы (обработчики протоколов)

**Что это:** регистрация схемы (например, `myapp://`) в Info.plist приложения (`CFBundleURLTypes`, `CFBundleURLSchemes`). При открытии ссылки macOS запускает приложение и передаёт URL. Для CLI без .app не применимо.

**Параметры единой конфигурации:** `[[protocol_handlers]] scheme, description` — общие для платформ.

---

### 2.11 Уведомления и TCC (доступ/безопасность)

**Уведомления:** отправляются в рантайме через API; к упаковке не относятся.  
**TCC (Transparency, Consent, and Control):** права доступа (доступность, камера, микрофон и т.д.) выдаёт пользователь или MDM; инсталлятор не может их выдать. Важно: корректный Info.plist (usage descriptions), подпись и нотаризация приложения.

---

## 3. Интеграция в Linux

### 3.1 PATH

**Что это:** бинарник доступен из командной строки. Стандартные каталоги в PATH: `/usr/bin`, `/usr/local/bin`, `/usr/sbin`; для приложения — часто `/opt/myapp/bin`.

**nfpm:** файлы в `contents` с `dst: /usr/bin/myapp` или установка в `/opt/myapp/bin` плюс symlink в `/usr/bin/myapp`. Альтернатива — скрипт в `/etc/profile.d/` с `export PATH="..."`.

**Параметры единой конфигурации:** фактически задаётся группой файлов `bin` (установка в `/usr/bin/` или symlink).

**Общее:** для Crossler достаточно файловой группы и путей установки.

---

### 3.2 Переменные окружения

**Механизмы:** `/etc/environment` (ключ=значение); `/etc/profile.d/myapp.sh` (export); для сервисов — `systemd environment.d`.

**nfpm:** установка файла в contents (profile.d или environment.d). Единая конфигурация: `[linux] env = { ... }` с генерацией, например, `/etc/profile.d/myapp.sh`.

**Общее:** редко; чаще конфиг в `/etc/myapp/`.

---

### 3.3 Desktop-записи (.desktop)

**Что это:** файлы по спецификации XDG Desktop Entry; отображаются в меню приложений (GNOME, KDE и т.д.). Стандартное расположение: `/usr/share/applications/myapp.desktop`. Поля: Type, Name, GenericName, Comment, Exec, Icon, Terminal, Categories, Keywords, MimeType, StartupNotify, StartupWMClass, Actions. Иконки — по Icon Theme Spec в `/usr/share/icons/hicolor/`. После установки желательно вызывать `update-desktop-database` и при необходимости `gtk-update-icon-cache`.

**nfpm / fpm:** установка .desktop и иконок через contents; скрипты — по необходимости. **electron-builder:** генерирует .desktop.

**Параметры единой конфигурации:** `[linux.desktop]` с name, generic_name, comment, icon, terminal, categories, keywords, mime_types, startup_notify и опционально `[[linux.desktop.actions]]`.

**Общее:** необходимо для GUI в Linux.

---

### 3.4 Ассоциации файлов (MIME)

**Что это:** приложение зарегистрировано как обработчик MIME-типов. Механизмы: XML в `/usr/share/mime/packages/` (shared-mime-info); поле `MimeType=` в .desktop; после установки — `update-mime-database`. В deb можно использовать triggers для автоматического вызова.

**Параметры единой конфигурации:** общий блок `[[file_associations]]` (extension, mime_type, description, icon) маппится на shared-mime-info и .desktop.

---

### 3.5 Контекстное меню

**Что это:** пункты в контекстном меню файлового менеджера. Реализация зависит от окружения: Nautilus (скрипты/расширения), Dolphin (ServiceMenus в `/usr/share/kservices5/ServiceMenus/`), Thunar/Nemo — свои механизмы. Единая абстракция для всех DE непрактична; в Crossler выносить в конфиг не рекомендуется.

---

### 3.6 Службы systemd

**Что это:** юниты systemd для демонов, таймеров, сокетов и т.д. Стандартное расположение юнитов — `/lib/systemd/system/`. Типы: Service, Timer, Socket, Path, Mount. В .service задаются Description, ExecStart, ExecReload, Restart, User, Group, WorkingDirectory, ограничения (NoNewPrivileges, ProtectSystem, ReadWritePaths и т.д.). В .timer — OnCalendar, Persistent, RandomizedDelaySec. Установка: положить юниты, в postinstall — `systemctl daemon-reload`, `enable`, `start`; в preremove/postremove — stop, disable, daemon-reload. В deb/rpm есть макросы для systemd; nfpm использует свои скрипты.

**Параметры единой конфигурации:** `[linux.service]` (type, description, exec_start, exec_reload, restart, user, group, after, wants, wanted_by) и при необходимости `[[linux.timers]]`.

**Общее:** ключевая интеграция для демонов в Linux.

---

### 3.7 D-Bus-сервисы

**Что это:** файлы сервисов D-Bus для автозапуска при обращении к имени на шине. Расположение: `/usr/share/dbus-1/services/` (сессия) или `.../system-services/` (система). nfpm — установка файла через contents. В единой конфигурации выделять отдельно не обязательно; достаточно включать файл в пакет.

---

### 3.8 Автозапуск (XDG Autostart)

**Что это:** запуск при входе в графическую сессию. Файлы .desktop в `/etc/xdg/autostart/` (системно) или `~/.config/autostart/`. Дополнительные поля: Hidden, NoDisplay, X-GNOME-Autostart-enabled, X-GNOME-Autostart-Delay, OnlyShowIn, NotShowIn. Установка через contents. Единая конфигурация: `[linux.autostart]` (enabled, args, delay, no_display).

**Общее:** типично для трей-приложений и фоновых агентов.

---

### 3.9 Дополнения для оболочек (completions)

**Что это:** скрипты автодополнения для bash, zsh, fish. Стандартные каталоги: bash — `/usr/share/bash-completion/completions/`, zsh — `/usr/share/zsh/vendor-completions/`, fish — `/usr/share/fish/vendor_completions.d/`. Установка через contents. Многие Go-инструменты генерируют completions командой вида `myapp completion bash`.

**Параметры единой конфигурации:** `[completions]` с путями для bash, zsh, fish.

**Общее:** ожидаемо для CLI.

---

### 3.10 Man-страницы

**Что это:** страницы руководства `man`. Каталоги: `/usr/share/man/man{1,5,8}/`, файлы обычно сжаты (.gz). Установка через contents; при необходимости в postinstall — `mandb`. В Debian man-страницы для команд рекомендуются.

**Параметры единой конфигурации:** через группу share или отдельный параметр `[man]`.

---

### 3.11 Polkit, udev, cron, AppArmor/SELinux, alternatives, tmpfiles.d, sysusers.d

**Polkit:** политики для привилегированных действий; XML в `/usr/share/polkit-1/actions/`. Устанавливаются как обычные файлы; в конфиг Crossler выносить не обязательно.

**udev:** правила в `/etc/udev/rules.d/` или `/lib/udev/rules.d/`; после установки — `udevadm control --reload-rules` и `udevadm trigger`. Нишево для приложений, работающих с устройствами.

**Cron:** файлы в `/etc/cron.d/` или скрипты; предпочтительнее systemd timers. Единая конфигурация — при необходимости `[[linux.cron]]`.

**AppArmor/SELinux:** профили/модули для ограничения возможностей приложения. Установка файлов и при необходимости загрузка (apparmor_parser, semodule). В конфиг не выносить.

**Alternatives:** `update-alternatives` (Debian) / `alternatives` (RHEL) для выбора реализации команды (editor, pager и т.д.). Реализуется в postinstall/preremove; в конфиг не выносить.

**tmpfiles.d:** конфиги в `/usr/lib/tmpfiles.d/` для создания каталогов/файлов с правами и очистки. **sysusers.d:** конфиги в `/usr/lib/sysusers.d/` для создания пользователя/группы сервиса (современная замена useradd в скриптах). После установки — `systemd-tmpfiles --create`, `systemd-sysusers`. Единая конфигурация при желании: `[linux.system_user]`, `[[linux.tmpfiles]]`.

**Общее:** tmpfiles.d и sysusers.d — хорошая практика для демонов; остальное — по необходимости и через файлы/скрипты.

---

## 4. Сравнение инструментов

### 4.1 GoReleaser

Интеграция в окружение в основном через nfpm (Linux) и кастомные шаблоны WiX (Windows MSI):

| Возможность | Поддержка |
|-------------|-----------|
| PATH (Linux) | Через contents (установка в `/usr/bin/`) |
| PATH (Windows) | Нет в конфиге — нужен кастомный WiX |
| Службы systemd | contents + scripts |
| Completions, man, .desktop | Через contents (файлы готовит пользователь) |
| Ассоциации файлов | Нет |
| Ярлыки Windows | Нет в конфиге — кастомный WiX (Pro) |
| Службы Windows, launchd, обработчики протоколов | Нет |

Абстракции над интеграцией в ОС нет; всё через contents и скрипты.

### 4.2 fpm

Универсальный упаковщик (Ruby). Интеграция — через размещение файлов и скрипты: `--before-install`, `--after-install`, `--before-remove`, `--after-remove`, `--config-files`, `--directories`. Специфичных абстракций для ярлыков, служб, ассоциаций нет.

### 4.3 electron-builder

Богатая поддержка интеграции под GUI: ассоциации файлов и протоколы — кросс-платформенно; ярлыки Windows (меню «Пуск», рабочий стол); генерация .desktop и MIME на Linux; UTI/Launch Services на macOS; подпись и нотаризация. Ближе всего к идее единой конфигурации Crossler.

### 4.4 Inno Setup

Только Windows. PATH и переменные — `[Registry]` и при необходимости `ChangesEnvironment=yes`. Ярлыки — `[Icons]` с `{autoprograms}`, `{autodesktop}`. Ассоциации, контекстное меню, службы, автозапуск, брандмауэр, протоколы, задачи — через `[Registry]` и `[Run]`.

### 4.5 NSIS

Всё через скрипты: EnVar или реестр для PATH, CreateShortCut для ярлыков, реестр для ассоциаций и контекстного меню, nsSCM или sc.exe для служб, реестр для автозапуска и протоколов. Декларативной конфигурации нет.

---

## 5. Единая конфигурация для Crossler

### 5.1 Приоритеты (по целевой аудитории: в основном CLI, часть GUI)

**Уровень 1 — необходимо в v1:** PATH (все ОС), shell completions и man (Linux), службы: systemd (Linux), launchd (macOS), службы Windows (CustomAction/sc.exe).

**Уровень 2 — важно для v2:** ярлыки (меню «Пуск», рабочий стол) и desktop-записи (Linux), ассоциации файлов и обработчики протоколов, автозапуск/элементы входа, создание системного пользователя (sysusers.d и т.п.).

**Уровень 3 — позже:** переменные окружения, контекстное меню, произвольные записи реестра, брандмауэр, запланированные задачи, tmpfiles.d, polkit/udev/AppArmor, Spotlight/Quick Look, alternatives, D-Bus.

### 5.2 Рекомендуемая структура конфигурации

Идея: один блок `[service]` маппится на systemd, launchd и службу Windows; PATH — явно только для Windows/macOS (на Linux задаётся установкой в `/usr/bin/`); completions — отдельный параметр; ассоциации файлов и протоколы — кросс-платформенные секции; desktop-записи — генерировать из метаданных; нишевые вещи — файлы в группах и при необходимости pre/post скрипты.

(Полный пример TOML см. в оригинальном документе `environment-integration.md`; структура секций `[windows]`, `[macos]`, `[linux]`, `[service]`, `[shortcuts]`, `[desktop_entry]`, `[[file_associations]]`, `[[protocol_handlers]]`, `[autostart]` сохраняется.)

### 5.3 Важные решения для Crossler

1. **PATH:** на Linux — автоматически за счёт установки в `/usr/bin/`; в Windows нужен явный `windows.path = true`; на macOS — symlink или paths.d в зависимости от места установки.
2. **Службы:** единая абстракция `[service]` → systemd, launchd, Windows Service; в Windows из-за ограничений wixl — реализация через CustomAction и sc.exe/netsh.
3. **Completions:** первый класс поддержки, не только «файлы в share».
4. **Ассоциации файлов:** кросс-платформенный `[[file_associations]]` с генерацией артефактов под каждую ОС.
5. **Desktop-записи:** генерация из метаданных, а не ручное написание .desktop.
6. **Скрипты** остаются запасным вариантом для нишевых интеграций (udev, polkit, контекстное меню и т.д.).
7. **Ограничения wixl:** нет `<ServiceInstall>`, расширений WiX (в т.ч. Firewall); службы и брандмауэр — только через CustomAction и консольные утилиты.

---

## 6. Дополнения к исследованию

### 6.1 Различие WiX Toolset и wixl

- **WiX Toolset** — полный набор инструментов для MSI (candle, light, расширения). Поддерживает `<ServiceInstall>`, `WixFirewallExtension`, `WixUtilExtension` (ScheduledTask) и т.д.
- **wixl** — облегчённый компилятор WXS → MSI (проект из мира Linux/минималистичной сборки). Не поддерживает расширения WiX и элементы вроде `<ServiceInstall>`. Для Crossler при выборе wixl все сценарии со службами и брандмауэром нужно реализовывать через CustomAction (`sc.exe`, `netsh`, `schtasks`).

### 6.2 Рекомендации по postinstall для systemd (nfpm / Linux)

При установке и обновлении пакета со службой systemd в postinstall рекомендуется:

1. Вызвать `systemctl daemon-reload`.
2. При необходимости `systemctl unmask <unit>`.
3. Использовать `systemctl preset <unit>` для соблюдения политики дистрибутива.
4. Включить и при необходимости перезапустить: `systemctl enable`, `systemctl start` или `systemctl restart`.
5. Учитывать различие «первая установка» и «обновление» (например, по аргументам, передаваемым скрипту пакетным менеджером).
6. На системах без systemd предусмотреть fallback (chkconfig, init.d) или не выполнять действия systemd.

Для старых версий systemd (< 231) синтаксис некоторых опций может отличаться — при генерации скриптов это стоит учитывать.

### 6.3 Альтернативные форматы распространения (Flatpak, Snap)

Flatpak и Snap — изолированные форматы распространения приложений в Linux. Интеграция с «классическим» окружением ограничена:

- **PATH:** среда изолирована; CLI-доступ через `flatpak run` или команды-обёртки.
- **Файловая система:** песочница, доступ к хосту через порталы и разрешения.
- **Службы systemd:** не используются в традиционном виде; автозапуск и фоновые задачи реализуются механизмами самого Flatpak/Snap.
- **.desktop и MIME:** генерируются метаданными пакета (manifest), а не установкой файлов в `/usr/share/...`.

Для Crossler, ориентированного на нативные пакеты (deb, rpm, apk, MSI, pkg), Flatpak/Snap остаются отдельным каналом распространения; единая конфигурация «интеграции в ОС» к ним напрямую не применяется, но учёт форматов полезен при планировании поддержки нескольких способов доставки.

### 6.4 Безопасность и права

- **Windows:** установка в `Program Files` и запись в HKLM требуют повышенных прав; пользовательская установка (HKCU, папка в профиле) снижает требования. Службы и правила брандмауэра всегда требуют прав администратора.
- **macOS:** установка в `/Applications` и системные каталоги — права администратора; нотаризация и подпись обязательны для распространения вне Mac App Store. TCC не выдаётся инсталлятором.
- **Linux:** установка в `/usr` и создание пользователя/группы сервиса — root; рекомендуется использовать sysusers.d и ограничения в unit systemd (NoNewPrivileges, ProtectSystem, PrivateTmp и т.д.). AppArmor/SELinux при необходимости задаются отдельными профилями.

Учёт этих аспектов помогает формулировать рекомендации в документации Crossler (например, «как создавать пакет с минимальными привилегиями» или «как включить системного пользователя для демона»).

---

## Ссылки

### Windows / MSI / WiX
- [Документация WiX Toolset](https://wixtoolset.org/docs/)
- [WiX Environment Element](https://wixtoolset.org/docs/v3/xsd/wix/environment/)
- [WiX ServiceInstall Element](https://wixtoolset.org/docs/v3/xsd/wix/serviceinstall/)
- [WiX Shortcut Element](https://wixtoolset.org/docs/v3/xsd/wix/shortcut/)
- [WiX ProgId Element](https://wixtoolset.org/docs/v3/xsd/wix/progid/)
- [Документация Inno Setup](https://jrsoftware.org/ishelp/)
- [Документация NSIS](https://nsis.sourceforge.io/Docs/)

### macOS
- [Apple pkgbuild (man)](https://www.manpagez.com/man/1/pkgbuild/)
- [Apple Launch Services Programming Guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/)
- [Apple Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers)
- [launchd.plist (man)](https://www.manpagez.com/man/5/launchd.plist/)
- [Apple Info.plist Key Reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/)

### Linux
- [XDG Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- [XDG MIME Applications Specification](https://specifications.freedesktop.org/mime-apps-spec/latest/)
- [Shared MIME-info Specification](https://specifications.freedesktop.org/shared-mime-info-spec/latest/)
- [systemd.service (man)](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd.timer (man)](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [tmpfiles.d (man)](https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html)
- [sysusers.d (man)](https://www.freedesktop.org/software/systemd/man/sysusers.d.html)
- [Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/)
- [Документация nfpm](https://nfpm.goreleaser.com/)
- [fpm Wiki](https://fpm.readthedocs.io/)

### Кросс-платформенные инструменты
- [Документация GoReleaser](https://goreleaser.com/customization/)
- [Документация electron-builder](https://www.electron.build/)

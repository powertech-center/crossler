# OS Environment Integration — Research for Crossler

> Comprehensive analysis of how software packages integrate with the operating system environment across Windows, macOS, and Linux. Covers mechanisms available in each packaging backend (WiX/wixl for MSI, nfpm for deb/rpm/apk, pkgbuild for macOS .pkg) and how other packaging tools (GoReleaser, fpm, electron-builder, Inno Setup, NSIS) handle these features.

---

## Table of Contents

1. [Windows Environment Integration](#1-windows-environment-integration)
2. [macOS Environment Integration](#2-macos-environment-integration)
3. [Linux Environment Integration](#3-linux-environment-integration)
4. [Cross-Tool Comparison](#4-cross-tool-comparison)
5. [Unified Config Considerations for Crossler](#5-unified-config-considerations-for-crossler)

---

## 1. Windows Environment Integration

### 1.1 PATH Environment Variable

**What it is:** Adding the application's installation directory to the system or user `PATH` so the binary can be invoked from any terminal without specifying the full path. Essential for CLI tools.

**How WiX/wixl handles it:**

WiX uses the `<Environment>` element inside a `<Component>` to modify environment variables, including PATH:

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

Key attributes:
- `Part="last"` appends to PATH (vs `first` to prepend, or `all` to replace entirely)
- `System="yes"` modifies the system-wide PATH; `System="no"` modifies per-user PATH
- `Permanent="no"` removes the entry on uninstall; `Permanent="yes"` leaves it
- `Action="set"` adds the value; `Action="remove"` removes it

The `<Environment>` element modifies `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\Path` (system) or `HKCU\Environment\Path` (user) and broadcasts `WM_SETTINGCHANGE` so running shells pick up the change.

**wixl support:** The `<Environment>` element is supported in wixl. This is the standard mechanism.

**Inno Setup:** Uses `[Registry]` section or the `ChangesEnvironment=yes` directive with `[Code]` pascal script. Also has a convenience `AppendToPath` flag in newer versions.

**NSIS:** Uses the `EnVar` plugin or direct registry manipulation via `WriteRegExpandStr`.

**electron-builder (NSIS-based):** Does not add to PATH by default; requires custom NSIS scripts.

**GoReleaser (MSI via WiX, Pro):** Does not expose PATH modification in config; requires custom WiX templates.

**Unified config parameters:**
```toml
[windows]
path = true  # or path = "append" / "prepend"
# Alternatively, more granular:
# path_scope = "system"  # "system" or "user"
```

**Commonality:** Essential for CLI tools. Most GUI apps do not need this.

---

### 1.2 Environment Variables

**What it is:** Setting custom environment variables (beyond PATH) that persist across reboots. Used for configuration paths, runtime settings, license keys, etc.

**How WiX/wixl handles it:**

Same `<Environment>` element as PATH, but with `Part="all"` (replace/set entire value):

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

**wixl support:** Supported via `<Environment>`.

**Inno Setup / NSIS:** Both support setting environment variables via registry writes to `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment` or `HKCU\Environment`.

**Unified config parameters:**
```toml
[windows]
env = { "MYAPP_HOME" = "{install_dir}", "MYAPP_CONFIG" = "{install_dir}\\config" }
```

**Commonality:** Niche. Most tools use config files or registry entries instead of env vars on Windows. Occasionally useful for setting `*_HOME` variables (like `JAVA_HOME`).

---

### 1.3 Start Menu Shortcuts

**What it is:** Creating `.lnk` shortcut files in the Windows Start Menu folder so users can find and launch the application via the Start Menu.

**How WiX/wixl handles it:**

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

Important rules:
- `ProgramMenuFolder` is a predefined WiX directory ID pointing to the Start Menu Programs folder
- A shortcut component requires a `RegistryValue` with `KeyPath="yes"` (shortcuts themselves cannot be KeyPath)
- `RemoveFolder` ensures the subfolder is cleaned up on uninstall
- Icons must be declared separately with `<Icon>` and referenced by ID

**wixl support:** Fully supported. `<Shortcut>` and `<RemoveFolder>` work in wixl.

**Inno Setup:** `[Icons]` section:
```ini
[Icons]
Name: "{autoprograms}\My Application"; Filename: "{app}\myapp.exe"; IconFilename: "{app}\myapp.ico"
Name: "{autoprograms}\My Application\Uninstall"; Filename: "{uninstallexe}"
```

**NSIS:** `CreateShortCut` function:
```nsis
CreateDirectory "$SMPROGRAMS\My Application"
CreateShortCut "$SMPROGRAMS\My Application\My Application.lnk" "$INSTDIR\myapp.exe"
```

**electron-builder:** Creates Start Menu shortcuts automatically for NSIS and MSI installers. Configurable via `shortcutName` in the config.

**GoReleaser (MSI, Pro):** WiX template can include shortcuts; not directly exposed in config.

**Unified config parameters:**
```toml
[windows.shortcuts]
start_menu = true              # create Start Menu entry
start_menu_folder = "My App"   # subfolder name (optional, defaults to app name)
```

**Commonality:** Essential for GUI applications. Useful for CLI tools too (launching a terminal with the tool).

---

### 1.4 Desktop Shortcuts

**What it is:** Creating a `.lnk` file on the user's Desktop for quick access.

**How WiX/wixl handles it:**

```xml
<Directory Id="TARGETDIR" Name="SourceDir">
  <Directory Id="DesktopFolder" />
</Directory>

<DirectoryRef Id="DesktopFolder">
  <Component Id="DesktopShortcut" Guid="GUID-HERE">
    <Shortcut
      Id="DeskShortcut"
      Name="My Application"
      Target="[INSTALLFOLDER]myapp.exe"
      WorkingDirectory="INSTALLFOLDER"
      Icon="AppIcon" />
    <RegistryValue Root="HKCU" Key="Software\MyCompany\MyApp"
                   Name="DesktopShortcut" Value="1" Type="integer" KeyPath="yes" />
  </Component>
</DirectoryRef>
```

`DesktopFolder` is a predefined WiX directory ID. Same component rules as Start Menu shortcuts apply.

**wixl support:** Fully supported.

**Inno Setup:** `[Icons]` with `{autodesktop}`:
```ini
[Icons]
Name: "{autodesktop}\My Application"; Filename: "{app}\myapp.exe"; Tasks: desktopicon
```

**NSIS:** `CreateShortCut "$DESKTOP\My Application.lnk" "$INSTDIR\myapp.exe"`

**electron-builder:** Configurable via `win.shortcutName` and the `createDesktopShortcut` option (default: true for NSIS).

**Unified config parameters:**
```toml
[windows.shortcuts]
desktop = true
```

**Commonality:** Common for GUI applications. Rarely needed for CLI tools. Often presented as an optional checkbox during installation.

---

### 1.5 File Associations

**What it is:** Registering the application as a handler for specific file extensions, so that double-clicking a `.myext` file opens it with the application. Involves creating a ProgID, associating extensions with it, and defining verbs (open, edit, print).

**How WiX/wixl handles it:**

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

This creates:
- `HKCR\.myext` default value = `MyApp.Document`
- `HKCR\MyApp.Document\shell\open\command` = `"C:\...\myapp.exe" "%1"`
- `HKCR\MyApp.Document\DefaultIcon` = the specified icon

For per-user associations (Windows Vista+), use `HKCU\Software\Classes` instead, which happens automatically with `InstallScope="perUser"`.

**wixl support:** `<ProgId>` and `<Extension>` are supported in wixl.

**Inno Setup:**
```ini
[Registry]
Root: HKA; Subkey: "Software\Classes\.myext"; ValueType: string; ValueData: "MyApp.Document"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\MyApp.Document\shell\open\command"; ValueType: string; ValueData: """{app}\myapp.exe"" ""%1"""
```

**NSIS:** Direct registry writes to `HKCR`.

**electron-builder:** Supports `fileAssociations` in config:
```json
{
  "fileAssociations": [
    { "ext": "myext", "name": "My Document", "role": "Editor", "icon": "icon.ico" }
  ]
}
```

**GoReleaser:** Not directly supported; requires custom WiX templates.

**fpm:** Not supported (fpm does not generate MSI with file associations).

**Unified config parameters:**
```toml
[[file_associations]]
extension = "myext"
mime_type = "application/x-myext"
description = "My Application Document"
icon = "icons/document.ico"      # Windows .ico
role = "editor"                  # editor, viewer, shell, none
```

**Commonality:** Essential for document-oriented GUI apps. Rarely needed for CLI tools. Cross-platform (macOS has UTI, Linux has MIME types).

---

### 1.6 Context Menu (Shell Extensions)

**What it is:** Adding entries to the Windows Explorer right-click context menu. Examples: "Open with MyApp", "Edit with MyApp", "Compress with MyApp".

**Simple approach — registry-based:**

```xml
<!-- Add "Open with MyApp" for all files -->
<RegistryKey Root="HKCR" Key="*\shell\MyApp" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="Open with MyApp" Type="string" />
  <RegistryValue Name="Icon" Value="[INSTALLFOLDER]myapp.exe,0" Type="string" />
</RegistryKey>
<RegistryKey Root="HKCR" Key="*\shell\MyApp\command" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="&quot;[INSTALLFOLDER]myapp.exe&quot; &quot;%1&quot;" Type="string" />
</RegistryKey>

<!-- For directories -->
<RegistryKey Root="HKCR" Key="Directory\shell\MyApp" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="Open with MyApp" Type="string" />
</RegistryKey>
<RegistryKey Root="HKCR" Key="Directory\shell\MyApp\command" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="&quot;[INSTALLFOLDER]myapp.exe&quot; &quot;%V&quot;" Type="string" />
</RegistryKey>

<!-- For directory background (right-click on empty space) -->
<RegistryKey Root="HKCR" Key="Directory\Background\shell\MyApp" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="Open MyApp here" Type="string" />
</RegistryKey>
<RegistryKey Root="HKCR" Key="Directory\Background\shell\MyApp\command" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="&quot;[INSTALLFOLDER]myapp.exe&quot; &quot;%V&quot;" Type="string" />
</RegistryKey>
```

Context menu targets:
- `*\shell\` — all files
- `.ext\shell\` — specific extension
- `Directory\shell\` — folders
- `Directory\Background\shell\` — folder background (empty space)
- `Drive\shell\` — drive icons

**Complex approach — COM shell extensions:** Requires DLL registration, not practical for wixl (no COM support). Only achievable via full WiX Toolset or custom installers.

**wixl support:** Registry-based context menus are fully supported via `<RegistryKey>` / `<RegistryValue>`. COM-based shell extensions are not supported.

**Windows 11 note:** Windows 11 uses a new context menu by default. Legacy entries appear under "Show more options". To appear in the new menu, apps need to register via `HKCU\Software\Classes\CLSID\{...}\InprocServer32` with a shell extension DLL — not practical for simple tools.

**Inno Setup / NSIS:** Both support registry-based context menus via direct registry writes.

**electron-builder:** Not directly supported. Users add via custom NSIS scripts.

**Unified config parameters:**
```toml
[[windows.context_menu]]
target = "files"                    # "files", "directories", "directory_background", "extension:.myext"
label = "Open with MyApp"
command = "{install_dir}\\myapp.exe \"%1\""
icon = "{install_dir}\\myapp.exe,0"
```

**Commonality:** Moderately common. Essential for tools like "Open in Terminal", text editors, archive managers. Not needed for most CLI tools.

---

### 1.7 Windows Services

**What it is:** Registering an executable as a Windows Service (daemon) that runs in the background, starts automatically, and is managed through `sc.exe` or the Services MMC snap-in.

**How WiX handles it (full WiX Toolset only):**

```xml
<Component Id="ServiceComponent" Guid="GUID-HERE">
  <File Id="ServiceExe" Source="myservice.exe" KeyPath="yes" />
  <ServiceInstall
    Id="ServiceInstaller"
    Type="ownProcess"
    Name="MyService"
    DisplayName="My Application Service"
    Description="Runs the MyApp background tasks"
    Start="auto"
    Account="LocalSystem"
    ErrorControl="normal" />
  <ServiceControl
    Id="ServiceControl"
    Name="MyService"
    Start="install"
    Stop="both"
    Remove="uninstall"
    Wait="yes" />
</Component>
```

Key `ServiceInstall` attributes:
- `Type`: `ownProcess` (standalone), `shareProcess` (shared svchost)
- `Start`: `auto` (automatic), `demand` (manual), `disabled`, `boot`, `system`
- `Account`: `LocalSystem`, `LocalService`, `NetworkService`, or a named account
- `ErrorControl`: `ignore`, `normal`, `critical`

`ServiceControl` manages the service lifecycle during install/uninstall:
- `Start="install"` — start the service after installation
- `Stop="both"` — stop the service before install and uninstall
- `Remove="uninstall"` — remove the service on uninstall

**wixl support:** `<ServiceInstall>` is **NOT supported** in wixl. This is a significant limitation. Workaround: use a `CustomAction` to run `sc.exe create` and `sc.exe delete`:

```xml
<CustomAction Id="InstallService"
              Directory="SystemFolder"
              ExeCommand="sc.exe create MyService binPath= &quot;[INSTALLFOLDER]myservice.exe&quot; start= auto"
              Return="check"
              Execute="deferred"
              Impersonate="no" />
<CustomAction Id="RemoveService"
              Directory="SystemFolder"
              ExeCommand="sc.exe delete MyService"
              Return="ignore"
              Execute="deferred"
              Impersonate="no" />

<InstallExecuteSequence>
  <Custom Action="InstallService" After="InstallFiles">NOT Installed AND NOT REMOVE</Custom>
  <Custom Action="RemoveService" Before="RemoveFiles">REMOVE="ALL"</Custom>
</InstallExecuteSequence>
```

**Inno Setup:** `[Run]` section with `sc.exe` or a custom service installer.

**NSIS:** `nsSCM` plugin or direct `nsExec::ExecToLog 'sc.exe create ...'`.

**electron-builder:** Not supported. Use `node-windows` or `windows-service` npm packages separately.

**GoReleaser:** Not supported (no service management in nfpm or WiX templates).

**Unified config parameters:**
```toml
[windows.service]
name = "myservice"
display_name = "My Application Service"
description = "Background tasks for MyApp"
start_type = "auto"                 # "auto", "manual", "disabled"
account = "LocalSystem"             # "LocalSystem", "LocalService", "NetworkService"
```

**Commonality:** Essential for server/daemon applications on Windows. Not needed for CLI tools or typical GUI apps.

---

### 1.8 Autostart / Startup

**What it is:** Configuring the application to launch automatically when the user logs in. Different from Windows Services — autostart runs in the user session, not as a background service.

**Mechanisms:**

1. **Startup folder shortcut:** Place a `.lnk` in `StartupFolder` (WiX predefined directory ID):

```xml
<Directory Id="TARGETDIR" Name="SourceDir">
  <Directory Id="StartupFolder" />
</Directory>

<DirectoryRef Id="StartupFolder">
  <Component Id="AutostartShortcut" Guid="GUID-HERE">
    <Shortcut Id="AutostartLink"
              Name="MyApp"
              Target="[INSTALLFOLDER]myapp.exe"
              Arguments="--background"
              WorkingDirectory="INSTALLFOLDER" />
    <RegistryValue Root="HKCU" Key="Software\MyCompany\MyApp"
                   Name="Autostart" Value="1" Type="integer" KeyPath="yes" />
  </Component>
</DirectoryRef>
```

2. **Registry Run key:**

```xml
<RegistryValue Root="HKCU"
               Key="Software\Microsoft\Windows\CurrentVersion\Run"
               Name="MyApp"
               Value="[INSTALLFOLDER]myapp.exe --background"
               Type="string" />
```

`HKLM\...\Run` for all users, `HKCU\...\Run` for current user.

**wixl support:** Both approaches are supported.

**Inno Setup:** Registry approach in `[Registry]` section.

**NSIS:** Registry approach via `WriteRegStr`.

**Unified config parameters:**
```toml
[windows]
autostart = true
autostart_args = "--background"
```

**Commonality:** Common for tray applications and background tools. Not needed for CLI tools.

---

### 1.9 Registry Entries

**What it is:** Writing to the Windows Registry for application configuration, App Paths, uninstall information, and custom data.

**Standard registry locations for installed apps:**

| Registry Key | Purpose |
|---|---|
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\myapp.exe` | Allows running `myapp` from Run dialog without PATH modification |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{GUID}` | Add/Remove Programs entry (MSI handles automatically) |
| `HKLM\SOFTWARE\MyCompany\MyApp` | Custom application settings |
| `HKCU\SOFTWARE\MyCompany\MyApp` | Per-user application settings |

**App Paths example (alternative to PATH modification):**

```xml
<RegistryKey Root="HKLM"
             Key="SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\myapp.exe"
             Action="createAndRemoveOnUninstall">
  <RegistryValue Value="[INSTALLFOLDER]myapp.exe" Type="string" />
  <RegistryValue Name="Path" Value="[INSTALLFOLDER]" Type="string" />
</RegistryKey>
```

This allows `Win+R` > `myapp` to find the executable, and allows `CreateProcess("myapp.exe")` to find it without PATH. However, it does NOT add to PATH for cmd.exe or PowerShell command-line use.

**wixl support:** `<RegistryKey>` and `<RegistryValue>` are fully supported.

**MSI automatic uninstall registry:** MSI automatically creates the `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{ProductCode}` entry with ARP (Add/Remove Programs) information. Properties like `ARPPRODUCTICON`, `ARPHELPLINK`, `ARPURLINFOABOUT` control what is displayed.

**Unified config parameters:**
```toml
[windows]
app_paths = true    # register in App Paths for Win+R

[[windows.registry]]
root = "HKLM"
key = "SOFTWARE\\MyCompany\\MyApp"
values = { "InstallPath" = "{install_dir}", "Version" = "{version}" }
```

**Commonality:** App Paths is useful for CLI tools (alternative to PATH). Custom registry is niche. ARP is handled automatically by MSI.

---

### 1.10 Firewall Rules

**What it is:** Adding Windows Firewall exceptions so the application can accept incoming network connections.

**How WiX handles it (full WiX only):**

Requires the WiX Firewall Extension (`WixFirewallExtension`):

```xml
<firewall:FirewallException
  Id="MyAppFirewall"
  Name="My Application"
  Description="Allow incoming connections for MyApp"
  Protocol="tcp"
  Port="8080"
  Scope="any"
  Profile="all" />
```

**wixl support:** WiX extensions including `WixFirewallExtension` are **NOT supported** in wixl. Workaround: use `CustomAction` with `netsh.exe`:

```xml
<CustomAction Id="AddFirewallRule"
              Directory="SystemFolder"
              ExeCommand="netsh advfirewall firewall add rule name=&quot;MyApp&quot; dir=in action=allow program=&quot;[INSTALLFOLDER]myapp.exe&quot; enable=yes"
              Return="ignore"
              Execute="deferred"
              Impersonate="no" />
```

**Inno Setup / NSIS:** Use `netsh` commands in post-install scripts.

**electron-builder:** Not directly supported.

**Unified config parameters:**
```toml
[windows.firewall]
program = true          # allow the installed executable through firewall
# or more specific:
# port = 8080
# protocol = "tcp"
```

**Commonality:** Niche. Only needed for server applications that listen on ports. Not needed for CLI tools or typical GUI apps.

---

### 1.11 Protocol Handlers (URL Schemes)

**What it is:** Registering custom URL schemes (e.g., `myapp://action/data`) so that clicking such links in browsers or other apps launches the application.

**How WiX/wixl handles it:**

```xml
<RegistryKey Root="HKCR" Key="myapp" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="MyApp Protocol" Type="string" />
  <RegistryValue Name="URL Protocol" Value="" Type="string" />
</RegistryKey>
<RegistryKey Root="HKCR" Key="myapp\DefaultIcon" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="[INSTALLFOLDER]myapp.exe,0" Type="string" />
</RegistryKey>
<RegistryKey Root="HKCR" Key="myapp\shell\open\command" Action="createAndRemoveOnUninstall">
  <RegistryValue Value="&quot;[INSTALLFOLDER]myapp.exe&quot; &quot;%1&quot;" Type="string" />
</RegistryKey>
```

Key registry structure:
- `HKCR\myapp` — `(Default)` = description, `URL Protocol` = "" (required marker)
- `HKCR\myapp\shell\open\command` — `(Default)` = command with `%1` for the full URL

**wixl support:** Fully supported via `<RegistryKey>`.

**electron-builder:** Supports `protocols` in config:
```json
{ "protocols": [{ "name": "My App Protocol", "schemes": ["myapp"] }] }
```

**Unified config parameters:**
```toml
[[protocol_handlers]]
scheme = "myapp"
description = "My Application Protocol"
```

**Commonality:** Niche. Used by web-connected apps (Slack, Spotify, VS Code, etc.). Rarely needed for CLI tools.

---

### 1.12 Scheduled Tasks

**What it is:** Creating Windows Task Scheduler tasks that run the application on a schedule (daily, hourly, at logon, etc.).

**How WiX handles it:** Requires WiX Util Extension (`WixUtilExtension`) for `<ScheduledTask>` — **not available in wixl**.

Workaround via `CustomAction` with `schtasks.exe`:

```xml
<CustomAction Id="CreateScheduledTask"
              Directory="SystemFolder"
              ExeCommand="schtasks.exe /Create /SC DAILY /TN &quot;MyApp Maintenance&quot; /TR &quot;[INSTALLFOLDER]myapp.exe --maintenance&quot; /ST 02:00 /F"
              Return="ignore"
              Execute="deferred"
              Impersonate="no" />
<CustomAction Id="RemoveScheduledTask"
              Directory="SystemFolder"
              ExeCommand="schtasks.exe /Delete /TN &quot;MyApp Maintenance&quot; /F"
              Return="ignore"
              Execute="deferred"
              Impersonate="no" />
```

**Inno Setup / NSIS:** Same `schtasks.exe` approach via post-install scripts.

**Unified config parameters:**
```toml
[[windows.scheduled_tasks]]
name = "MyApp Maintenance"
command = "{install_dir}\\myapp.exe --maintenance"
schedule = "daily"
time = "02:00"
```

**Commonality:** Niche. Used by maintenance tools, updaters, and backup software.

---

## 2. macOS Environment Integration

### 2.1 PATH

**What it is:** Making the installed binary accessible from the terminal. On macOS, `/usr/local/bin` is in PATH by default, but `/opt/` paths or application bundle paths are not.

**Mechanisms:**

1. **Install directly to /usr/local/bin:** The simplest approach. pkgbuild installs files to `--install-location /` with a payload containing `usr/local/bin/myapp`.

2. **Symlink from /usr/local/bin:** If the app is installed elsewhere (e.g., `/opt/myapp/bin/myapp`), create a symlink:
```bash
# In postinstall script:
ln -sf /opt/myapp/bin/myapp /usr/local/bin/myapp
```

3. **paths.d (macOS 10.13+):** Create a file in `/etc/paths.d/`:
```bash
# In postinstall script:
echo "/opt/myapp/bin" > /etc/paths.d/myapp
```
This is read by `/usr/libexec/path_helper` which is invoked by the default shell profile. New terminal sessions will include the path.

4. **Shell profile modification:** Append to `/etc/profile`, `~/.zprofile`, `~/.bash_profile` — fragile and not recommended.

**How pkgbuild handles it:** pkgbuild itself does not manage PATH. The postinstall script handles it:

```bash
#!/bin/bash
# postinstall script for PATH integration
ln -sf "$2/usr/local/bin/myapp" /usr/local/bin/myapp 2>/dev/null || true
# OR for paths.d:
echo "/opt/myapp/bin" > /etc/paths.d/myapp
```

The `$2` variable in pkgbuild scripts is the install target volume.

**Homebrew:** Installs to `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel), which is already in PATH. Uses symlinks from the Cellar.

**Unified config parameters:**
```toml
[macos]
path = true   # create symlink in /usr/local/bin or paths.d entry
```

**Commonality:** Essential for CLI tools on macOS.

---

### 2.2 Environment Variables

**What it is:** Setting persistent environment variables on macOS.

**Mechanisms:**

1. **launchctl setenv (modern approach):**
```bash
# In postinstall script:
launchctl setenv MYAPP_HOME /opt/myapp
```
Sets the variable for all future processes launched by launchd (GUI apps, services). However, does not persist across reboots unless set via a LaunchDaemon.

2. **launchd.conf (deprecated since 10.10):** No longer supported.

3. **/etc/launchd.conf replacement — LaunchDaemon plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.mycompany.myapp.env</string>
  <key>ProgramArguments</key>
  <array>
    <string>launchctl</string>
    <string>setenv</string>
    <string>MYAPP_HOME</string>
    <string>/opt/myapp</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

4. **Shell profile:** Append `export MYAPP_HOME=/opt/myapp` to shell profile — fragile.

**pkgbuild support:** Via postinstall scripts only.

**Unified config parameters:**
```toml
[macos]
env = { "MYAPP_HOME" = "/opt/myapp" }
```

**Commonality:** Very niche on macOS. Most macOS apps use `~/Library/Preferences/` plists or `~/Library/Application Support/` for configuration instead of environment variables.

---

### 2.3 Launch Services (File Associations)

**What it is:** Registering an application with macOS Launch Services so it appears in "Open With..." menus and can handle specific file types. This is the macOS equivalent of Windows file associations.

**Mechanisms:**

For `.app` bundles, file associations are declared in `Info.plist`:

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>
    <string>My Document</string>
    <key>CFBundleTypeExtensions</key>
    <array>
      <string>myext</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleTypeIconFile</key>
    <string>MyDocIcon</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>com.mycompany.myapp.document</string>
    </array>
  </dict>
</array>

<!-- Declare Uniform Type Identifiers -->
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>
    <string>com.mycompany.myapp.document</string>
    <key>UTTypeConformsTo</key>
    <array>
      <string>public.data</string>
    </array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array>
        <string>myext</string>
      </array>
      <key>public.mime-type</key>
      <string>application/x-myext</string>
    </dict>
  </dict>
</array>
```

Key concepts:
- **UTI (Uniform Type Identifier):** Apple's system for identifying data types, using reverse-DNS notation (e.g., `com.mycompany.myapp.document`). Replaces the older Creator/Type code system.
- **CFBundleTypeRole:** `Editor` (can read and write), `Viewer` (read-only), `Shell` (execute), `None`
- **LSItemContentTypes:** Links to UTI declarations
- **UTExportedTypeDeclarations:** Defines new UTIs owned by the app
- **UTImportedTypeDeclarations:** References UTIs owned by others

**For CLI tools without .app bundles:** File associations are not applicable. CLI tools do not register with Launch Services.

**pkgbuild support:** pkgbuild packages whatever is in the payload. If the payload includes a `.app` bundle with a properly configured `Info.plist`, Launch Services will pick it up after installation. pkgbuild itself does not provide any configuration for file associations.

**Homebrew:** Homebrew Cask supports the `app` stanza which copies `.app` bundles to `/Applications`, triggering Launch Services registration.

**electron-builder:** Supports `fileAssociations` in config, which generates the proper `Info.plist` entries.

**Unified config parameters:**
```toml
[[file_associations]]
extension = "myext"
mime_type = "application/x-myext"
description = "My Application Document"
role = "editor"
uti = "com.mycompany.myapp.document"  # macOS UTI
icon = "icons/document.icns"          # macOS .icns
```

**Commonality:** Essential for document-oriented GUI apps on macOS. Not applicable to CLI tools.

---

### 2.4 Dock Integration

**What it is:** Adding the application to the macOS Dock for quick launch.

**Mechanisms:**

There is no supported API for adding items to the Dock programmatically during installation. Apple deliberately prevents this.

Options:
1. **User action:** The user drags the `.app` to the Dock manually.
2. **dockutil (third-party tool):** `dockutil --add /Applications/MyApp.app` — requires installing dockutil first.
3. **defaults write (fragile):** Direct manipulation of `com.apple.dock` plist — not recommended as the format changes between macOS versions.

**pkgbuild support:** Not applicable — pkgbuild cannot manipulate the Dock.

**Homebrew Cask:** Does not add to Dock.

**electron-builder:** Does not add to Dock.

**Unified config parameters:** Not recommended. This should be a user action, not an installer action.

**Commonality:** Not supported by any standard packaging tool. Deliberately left to the user.

---

### 2.5 Login Items (Autostart)

**What it is:** Configuring an application to launch automatically when the user logs in. The macOS equivalent of Windows autostart.

**Mechanisms:**

1. **SMAppService (macOS 13+, modern approach):**
The app registers itself at runtime using the `SMAppService` API. Not applicable to packaging — this is a runtime API call.

2. **LaunchAgent plist (traditional approach):**
Install a plist in `/Library/LaunchAgents/` (all users) or `~/Library/LaunchAgents/` (current user):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.mycompany.myapp.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/myapp</string>
    <string>--background</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
```

3. **Login Items via Shared File Lists (deprecated):** Using `LSSharedFileListCreate` — deprecated since macOS 13.

**pkgbuild support:** Include the plist file in the payload at `/Library/LaunchAgents/com.mycompany.myapp.plist`. The postinstall script can `launchctl load` it:

```bash
#!/bin/bash
launchctl load /Library/LaunchAgents/com.mycompany.myapp.plist 2>/dev/null || true
```

**Homebrew:** Homebrew supports `service` blocks in formulae that generate LaunchAgent plists and manage them via `brew services start/stop`.

**Unified config parameters:**
```toml
[macos.login_item]
enabled = true
args = ["--background"]
keep_alive = false
```

**Commonality:** Common for menu bar apps, sync tools, and background utilities.

---

### 2.6 launchd Services (Daemons and Agents)

**What it is:** Registering background processes with launchd, macOS's init system and service manager. This is the macOS equivalent of systemd services and Windows Services.

**Two types:**

| Type | Location | Runs as | Use case |
|------|----------|---------|----------|
| LaunchDaemon | `/Library/LaunchDaemons/` | root | System services, servers |
| LaunchAgent | `/Library/LaunchAgents/` or `~/Library/LaunchAgents/` | user | User-facing background tasks, menu bar apps |

**LaunchDaemon plist example:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.mycompany.myapp</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/myapp</string>
    <string>serve</string>
    <string>--port</string>
    <string>8080</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/myapp.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/myapp.stderr.log</string>
  <key>UserName</key>
  <string>_myapp</string>
  <key>GroupName</key>
  <string>_myapp</string>
  <key>WorkingDirectory</key>
  <string>/var/lib/myapp</string>
</dict>
</plist>
```

Key plist keys:
- `Label` — unique identifier (reverse-DNS)
- `ProgramArguments` — command and arguments
- `RunAtLoad` — start immediately when loaded
- `KeepAlive` — restart if crashed; can be conditional (`SuccessfulExit`, `NetworkState`, etc.)
- `StartInterval` — periodic timer (seconds)
- `StartCalendarInterval` — cron-like schedule
- `WatchPaths` — start when files change
- `QueueDirectories` — start when directories become non-empty
- `Sockets` — socket activation (like systemd socket activation)

**pkgbuild support:** Include the plist in the payload. The postinstall script loads it:

```bash
#!/bin/bash
# For LaunchDaemon (system-wide, runs as root)
launchctl load -w /Library/LaunchDaemons/com.mycompany.myapp.plist

# For LaunchAgent (user context) — trickier from postinstall since it runs as root
# Best to just install the file; it will load on next login
```

**Homebrew:** `service` blocks in formulae:
```ruby
service do
  run [opt_bin/"myapp", "serve"]
  keep_alive true
  log_path var/"log/myapp.log"
  error_log_path var/"log/myapp.error.log"
end
```

**Unified config parameters:**
```toml
[macos.service]
type = "daemon"                    # "daemon" or "agent"
label = "com.mycompany.myapp"
args = ["serve", "--port", "8080"]
keep_alive = true
run_at_load = true
user = "_myapp"
group = "_myapp"
log_path = "/var/log/myapp.log"
```

**Commonality:** Essential for server/daemon applications on macOS. Equivalent to systemd services on Linux.

---

### 2.7 Spotlight Metadata (mdimporter Plugins)

**What it is:** Custom Spotlight metadata importers that allow Spotlight to index and search custom file types. An mdimporter is a plugin bundle (`.mdimporter`) installed in `/Library/Spotlight/`.

**How it works:** The plugin tells Spotlight how to extract metadata (title, author, content) from custom file formats. When the user searches in Spotlight, indexed metadata is searchable.

**pkgbuild support:** Install the `.mdimporter` bundle to `/Library/Spotlight/` in the payload.

**Unified config parameters:** Not recommended for Crossler scope. This requires developing a native macOS plugin, far beyond what a packaging tool should generate.

**Commonality:** Very niche. Only relevant for apps that create custom document formats and want them searchable.

---

### 2.8 Quick Look Plugins

**What it is:** Plugins that provide file previews in Finder (press Space on a file). Quick Look generators (`.qlgenerator`) are installed in `/Library/QuickLook/` or `~/Library/QuickLook/`.

**macOS 12+ change:** Apple moved to a new Quick Look extension model based on App Extensions. Legacy `.qlgenerator` plugins still work but are deprecated.

**pkgbuild support:** Install the `.qlgenerator` bundle in the payload.

**Unified config parameters:** Not recommended for Crossler scope. Requires native plugin development.

**Commonality:** Niche. Used by developer tools (Markdown previewers, code file previewers), graphics apps, and document apps.

---

### 2.9 Finder Extensions

**What it is:** Extensions that add functionality to Finder: Share menu items, toolbar buttons, sync status badges (like Dropbox overlay icons). These are App Extensions that must be embedded in an `.app` bundle.

**Requirements:** Must be code-signed and notarized. Must be distributed inside a `.app` bundle with proper entitlements.

**pkgbuild support:** Not directly relevant — the extension is part of the `.app` bundle.

**Unified config parameters:** Not recommended for Crossler scope.

**Commonality:** Niche. Only relevant for file sync apps (Dropbox, OneDrive) and similar deep-integration tools.

---

### 2.10 URL Schemes (Protocol Handlers)

**What it is:** Registering custom URL schemes (e.g., `myapp://`) so clicking such links opens the application. The macOS equivalent of Windows protocol handlers.

**How it works:** Declared in the `.app` bundle's `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>My App Protocol</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myapp</string>
    </array>
  </dict>
</array>
```

When a URL like `myapp://some-action` is opened, macOS launches the app and passes the URL as an Apple Event.

**For CLI tools:** URL schemes require an `.app` bundle. Not applicable to command-line tools.

**pkgbuild support:** The Info.plist is part of the `.app` bundle in the payload.

**electron-builder:** Supports `protocols` in config (same as Windows).

**Unified config parameters:**
```toml
[[protocol_handlers]]
scheme = "myapp"
description = "My App Protocol"
```

**Commonality:** Same as Windows — used by web-connected apps, not CLI tools.

---

### 2.11 Notification Center Integration

**What it is:** Sending system notifications and displaying them in the Notification Center.

**How it works:** Notifications are sent at runtime via `NSUserNotificationCenter` (deprecated) or `UNUserNotificationCenter` (modern). This is purely a runtime API, not a packaging concern.

**Packaging relevance:** None. Notification capability is determined by the app's code and entitlements, not by the installer.

**Unified config parameters:** Not applicable.

**Commonality:** Not a packaging concern.

---

### 2.12 Accessibility / Security Permissions (TCC)

**What it is:** macOS's Transparency, Consent, and Control (TCC) framework requires explicit user permission for apps to access sensitive resources: accessibility features, screen recording, microphone, camera, contacts, etc.

**Packaging relevance:** The installer cannot grant TCC permissions. macOS requires interactive user consent. However, enterprise MDM (Mobile Device Management) profiles can pre-approve TCC entries via a Privacy Preferences Policy Control (PPPC) profile.

**What a packager CAN do:**
- Include proper `Info.plist` usage descriptions (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, etc.) in the `.app` bundle
- Ensure the app is properly code-signed and notarized (required for TCC to work)

**Unified config parameters:** Not applicable for Crossler scope. TCC management is an MDM/enterprise concern.

**Commonality:** Important for GUI apps that need accessibility/privacy permissions, but not a packaging-time concern.

---

## 3. Linux Environment Integration

### 3.1 PATH

**What it is:** Ensuring the installed binary is accessible from the command line.

**Standard locations:**

| Path | Owner | Use |
|------|-------|-----|
| `/usr/bin/` | Package manager | System packages (standard) |
| `/usr/local/bin/` | Local admin | Locally compiled/installed software |
| `/usr/sbin/` | Package manager | System administration binaries |
| `/opt/myapp/bin/` | Application | Self-contained application |

All of `/usr/bin`, `/usr/local/bin`, `/usr/sbin` are in PATH by default on all major distributions.

**How nfpm handles it:** Simply install the binary to `/usr/bin/` in the `contents` section:

```yaml
contents:
  - src: dist/myapp
    dst: /usr/bin/myapp
    file_info:
      mode: 0755
```

If the binary is installed elsewhere (e.g., `/opt/myapp/bin/myapp`), create a symlink:

```yaml
contents:
  - src: dist/myapp
    dst: /opt/myapp/bin/myapp
    file_info:
      mode: 0755
  - src: /opt/myapp/bin/myapp
    dst: /usr/bin/myapp
    type: symlink
```

**Alternative: profile.d scripts:** Create a script in `/etc/profile.d/`:

```bash
# /etc/profile.d/myapp.sh
export PATH="/opt/myapp/bin:$PATH"
```

```yaml
contents:
  - src: packaging/myapp.sh
    dst: /etc/profile.d/myapp.sh
    file_info:
      mode: 0644
```

**fpm:** Same approach — install to `/usr/bin/` or `/usr/local/bin/`.

**GoReleaser (nfpm):** Uses nfpm's contents with `dst: /usr/bin/...`.

**Unified config parameters:**
```toml
bin = { "myapp" = "dist/myapp" }   # Already handled by Crossler's file groups
```

**Commonality:** Handled implicitly by the `bin` file group in Crossler. Installing to `/usr/bin/` is the standard approach.

---

### 3.2 Environment Variables

**What it is:** Setting system-wide environment variables on Linux.

**Mechanisms:**

1. **/etc/environment:** Key=value pairs, read by PAM modules:
```
MYAPP_HOME=/opt/myapp
```

2. **/etc/profile.d/myapp.sh:** Sourced by login shells:
```bash
export MYAPP_HOME=/opt/myapp
export MYAPP_CONFIG=/etc/myapp
```

3. **systemd environment.d (for services):**
```ini
# /etc/environment.d/50-myapp.conf
MYAPP_HOME=/opt/myapp
```

**nfpm support:** Install the profile.d script or environment file as a regular file in contents:

```yaml
contents:
  - src: packaging/myapp-env.sh
    dst: /etc/profile.d/myapp.sh
    file_info:
      mode: 0644
```

**Unified config parameters:**
```toml
[linux]
env = { "MYAPP_HOME" = "/opt/myapp" }
# Generates /etc/profile.d/myapp.sh
```

**Commonality:** Niche. Most Linux apps use config files (`/etc/myapp/`) rather than environment variables.

---

### 3.3 Desktop Entries (.desktop Files)

**What it is:** `.desktop` files are the Linux equivalent of Windows shortcuts and Start Menu entries. They follow the [XDG Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/) and appear in application launchers (GNOME Activities, KDE Application Menu, etc.).

**Standard location:** `/usr/share/applications/myapp.desktop`

**Example .desktop file:**

```ini
[Desktop Entry]
Type=Application
Name=My Application
GenericName=Text Editor
Comment=Edit text files
Exec=/usr/bin/myapp %F
Icon=myapp
Terminal=false
Categories=Development;TextEditor;
Keywords=text;editor;code;
MimeType=text/plain;text/x-python;
StartupNotify=true
StartupWMClass=myapp
Actions=new-window;

[Desktop Action new-window]
Name=New Window
Exec=/usr/bin/myapp --new-window
```

Key fields:
- `Type` — always `Application` for apps
- `Name` — display name in launcher
- `Exec` — command to run (`%F` = list of files, `%U` = list of URIs, `%f` = single file)
- `Icon` — icon name (without extension) looked up via icon theme spec
- `Terminal` — `true` for CLI apps that need a terminal
- `Categories` — semicolon-separated list from the [menu specification](https://specifications.freedesktop.org/menu-spec/latest/)
- `MimeType` — MIME types the app handles (file associations)
- `Keywords` — additional search terms
- `StartupNotify` — show "loading" cursor
- `Actions` — additional actions shown in right-click on the launcher icon

**How nfpm handles it:** Install the `.desktop` file via contents:

```yaml
contents:
  - src: packaging/myapp.desktop
    dst: /usr/share/applications/myapp.desktop
    file_info:
      mode: 0644
```

The postinstall script should update the desktop database:

```bash
#!/bin/bash
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications 2>/dev/null || true
fi
```

**Icon installation:** Icons should follow the [Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/):

```yaml
contents:
  - src: icons/48x48/myapp.png
    dst: /usr/share/icons/hicolor/48x48/apps/myapp.png
  - src: icons/128x128/myapp.png
    dst: /usr/share/icons/hicolor/128x128/apps/myapp.png
  - src: icons/scalable/myapp.svg
    dst: /usr/share/icons/hicolor/scalable/apps/myapp.svg
```

The postinstall script should update the icon cache:

```bash
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi
```

**fpm:** Same approach — user provides the `.desktop` file and icons.

**GoReleaser (nfpm):** Uses nfpm's contents. Does not generate `.desktop` files.

**electron-builder:** Generates `.desktop` files automatically for Linux targets with configurable categories, icons, etc.

**Unified config parameters:**
```toml
[linux.desktop]
name = "My Application"
generic_name = "Text Editor"
comment = "Edit text files"
icon = "myapp"                      # references installed icon
terminal = false
categories = ["Development", "TextEditor"]
keywords = ["text", "editor"]
mime_types = ["text/plain"]
startup_notify = true

[[linux.desktop.actions]]
name = "New Window"
exec_args = "--new-window"
```

**Commonality:** Essential for GUI applications on Linux. Not needed for CLI tools (though some CLI tools provide desktop entries for launching in a terminal).

---

### 3.4 File Associations (MIME Types)

**What it is:** Registering the application as a handler for specific MIME types, so file managers and other apps know which application can open which files.

**Mechanisms:**

1. **shared-mime-info XML:** Register custom MIME types in `/usr/share/mime/packages/myapp.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-myapp">
    <comment>MyApp Document</comment>
    <glob pattern="*.myext"/>
    <magic priority="50">
      <match type="string" value="MYAPP" offset="0"/>
    </magic>
    <icon name="application-x-myapp"/>
  </mime-type>
</mime-info>
```

2. **MimeType= in .desktop file:** For existing MIME types, just reference them in the `.desktop` file:

```ini
MimeType=text/plain;text/x-python;application/x-myapp;
```

3. **Update MIME database:** The postinstall script must run:

```bash
if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database /usr/share/mime 2>/dev/null || true
fi
```

**nfpm support:** Install the MIME XML file and .desktop file via contents. Postinstall script runs `update-mime-database`.

**deb-specific:** Debian's `triggers` mechanism can automatically run `update-mime-database` when files change in `/usr/share/mime/packages/`:

```yaml
overrides:
  deb:
    deb:
      triggers:
        interest:
          - /usr/share/mime/packages
```

**Unified config parameters:**

Already covered via `[[file_associations]]` which maps to:
- Windows: Registry ProgID
- macOS: Info.plist UTI/CFBundleDocumentTypes
- Linux: shared-mime-info XML + .desktop MimeType

```toml
[[file_associations]]
extension = "myext"
mime_type = "application/x-myapp"
description = "MyApp Document"
icon = "application-x-myapp"
```

**Commonality:** Common for GUI document-oriented apps. Not needed for CLI tools.

---

### 3.5 Context Menu

**What it is:** Adding entries to file manager context menus (right-click). Unlike Windows where this is OS-level, Linux context menus are file-manager-specific.

**Mechanisms by file manager:**

1. **Nautilus (GNOME Files):** Scripts in `~/.local/share/nautilus/scripts/` or Nautilus extensions (Python). Not installable system-wide via packages in a standard way.

2. **KDE Dolphin ServiceMenus:** `.desktop` files in `/usr/share/kservices5/ServiceMenus/`:

```ini
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=all/allfiles;
Actions=openWithMyApp

[Desktop Action openWithMyApp]
Name=Open with MyApp
Exec=/usr/bin/myapp %F
Icon=myapp
```

3. **Thunar (Xfce):** Custom actions stored in `~/.config/Thunar/uca.xml`. Not easily installable via packages.

4. **Nemo (Cinnamon):** Scripts in `~/.local/share/nemo/scripts/` or action files in `/usr/share/nemo/actions/`.

**nfpm support:** Install the service menu file via contents for the specific DE being targeted.

**Unified config parameters:** Not recommended for Crossler scope due to extreme fragmentation across desktop environments.

**Commonality:** Niche and highly fragmented. Not practical for cross-desktop support.

---

### 3.6 Systemd Services (Unit Files)

**What it is:** Registering the application as a systemd service for automatic management (start/stop/restart/enable/disable). Systemd is the init system on all major modern Linux distributions.

**Unit file types:**

| Type | Extension | Purpose |
|------|-----------|---------|
| Service | `.service` | Long-running daemons |
| Timer | `.timer` | Scheduled tasks (cron replacement) |
| Socket | `.socket` | Socket activation |
| Path | `.path` | File system monitoring |
| Mount | `.mount` | Mount points |

**Service unit example (`/lib/systemd/system/myapp.service`):**

```ini
[Unit]
Description=My Application Server
Documentation=https://myapp.example.com/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/myapp serve --config /etc/myapp/config.yaml
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
User=myapp
Group=myapp
WorkingDirectory=/var/lib/myapp
LimitNOFILE=65536

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/myapp /var/log/myapp

[Install]
WantedBy=multi-user.target
```

**Timer unit example (`/lib/systemd/system/myapp-cleanup.timer`):**

```ini
[Unit]
Description=MyApp Cleanup Timer

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
```

With companion service (`myapp-cleanup.service`):

```ini
[Unit]
Description=MyApp Cleanup Task

[Service]
Type=oneshot
ExecStart=/usr/bin/myapp cleanup
User=myapp
```

**How nfpm handles it:** Install the unit file and manage it via scripts:

```yaml
contents:
  - src: systemd/myapp.service
    dst: /lib/systemd/system/myapp.service
    file_info:
      mode: 0644

scripts:
  postinstall: scripts/postinstall.sh
  preremove: scripts/preremove.sh
  postremove: scripts/postremove.sh
```

```bash
# postinstall.sh
#!/bin/bash
systemctl daemon-reload
systemctl enable myapp.service
systemctl start myapp.service

# preremove.sh
#!/bin/bash
systemctl stop myapp.service || true
systemctl disable myapp.service || true

# postremove.sh
#!/bin/bash
systemctl daemon-reload
```

**deb-specific:** Debian has `dh_installsystemd` which auto-generates maintainer scripts for systemd unit management. nfpm does not use this — manual scripts needed.

**rpm-specific:** RPM has `%systemd_post`, `%systemd_preun`, `%systemd_postun` macros. nfpm does not use these — manual scripts needed.

**fpm:** Same approach as nfpm — user provides the unit file and scripts.

**GoReleaser (nfpm):** Uses nfpm's contents and scripts. Does not generate systemd units.

**Unified config parameters:**
```toml
[linux.service]
type = "simple"                      # simple, forking, oneshot, notify, dbus, idle
description = "My Application Server"
exec_start = "/usr/bin/myapp serve"
exec_reload = "/bin/kill -HUP $MAINPID"
restart = "on-failure"
user = "myapp"
group = "myapp"
after = ["network-online.target"]
wants = ["network-online.target"]
wanted_by = ["multi-user.target"]

[[linux.timers]]
description = "MyApp Cleanup Timer"
on_calendar = "daily"
persistent = true
service_exec = "/usr/bin/myapp cleanup"
```

**Commonality:** Essential for server/daemon applications on Linux. The single most important integration point for non-interactive services.

---

### 3.7 D-Bus Services

**What it is:** D-Bus (Desktop Bus) is an IPC (inter-process communication) system. D-Bus service files allow D-Bus to automatically start (activate) an application when another process sends a message to its well-known bus name.

**D-Bus service file example (`/usr/share/dbus-1/services/com.mycompany.MyApp.service`):**

```ini
[D-BUS Service]
Name=com.mycompany.MyApp
Exec=/usr/bin/myapp --dbus
```

For system services: `/usr/share/dbus-1/system-services/`

**nfpm support:** Install the D-Bus service file via contents:

```yaml
contents:
  - src: dbus/com.mycompany.MyApp.service
    dst: /usr/share/dbus-1/services/com.mycompany.MyApp.service
    file_info:
      mode: 0644
```

**Unified config parameters:** Not recommended for Crossler scope. D-Bus service files are simple enough to include as regular files.

**Commonality:** Niche. Primarily used by desktop applications that integrate with GNOME or KDE desktop environment services.

---

### 3.8 Autostart (XDG Autostart)

**What it is:** Starting an application automatically when the user logs into a graphical desktop session. Uses `.desktop` files in `/etc/xdg/autostart/` (system-wide) or `~/.config/autostart/` (per-user).

**Autostart .desktop file (`/etc/xdg/autostart/myapp.desktop`):**

```ini
[Desktop Entry]
Type=Application
Name=MyApp Background Agent
Exec=/usr/bin/myapp --background
Icon=myapp
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=10
```

Key fields beyond standard `.desktop`:
- `Hidden=false` — if `true`, the entry is disabled
- `NoDisplay=true` — don't show in application menus
- `X-GNOME-Autostart-enabled` — GNOME-specific enable flag
- `X-GNOME-Autostart-Delay` — delay in seconds before starting
- `OnlyShowIn=GNOME;KDE;` — restrict to specific desktops
- `NotShowIn=MATE;` — exclude specific desktops

**nfpm support:** Install the autostart `.desktop` file via contents:

```yaml
contents:
  - src: packaging/myapp-autostart.desktop
    dst: /etc/xdg/autostart/myapp.desktop
    file_info:
      mode: 0644
```

**Unified config parameters:**
```toml
[linux.autostart]
enabled = true
args = ["--background"]
delay = 10
no_display = true
```

**Commonality:** Common for tray applications, sync tools, and background agents. Not needed for CLI tools or server applications (which use systemd instead).

---

### 3.9 Shell Completions

**What it is:** Tab-completion scripts for bash, zsh, and fish shells that provide command-line completion for the application's subcommands, flags, and arguments.

**Standard locations:**

| Shell | System-wide | Per-user |
|-------|-------------|----------|
| bash | `/usr/share/bash-completion/completions/myapp` | `~/.local/share/bash-completion/completions/myapp` |
| zsh | `/usr/share/zsh/vendor-completions/_myapp` | various, depends on `$fpath` |
| fish | `/usr/share/fish/vendor_completions.d/myapp.fish` | `~/.config/fish/completions/myapp.fish` |

**How nfpm handles it:**

```yaml
contents:
  - src: completions/myapp.bash
    dst: /usr/share/bash-completion/completions/myapp
    file_info:
      mode: 0644

  - src: completions/_myapp
    dst: /usr/share/zsh/vendor-completions/_myapp
    file_info:
      mode: 0644

  - src: completions/myapp.fish
    dst: /usr/share/fish/vendor_completions.d/myapp.fish
    file_info:
      mode: 0644
```

Many Go CLI tools can generate their own completions at runtime (e.g., `myapp completion bash`), but pre-generated completions installed by the package are preferred.

**fpm:** Same approach — user provides completion files.

**GoReleaser:** Does not install shell completions by default, but the nfpm contents section can include them.

**Unified config parameters:**
```toml
[completions]
bash = "completions/myapp.bash"
zsh = "completions/_myapp"
fish = "completions/myapp.fish"
```

**Commonality:** Essential for CLI tools. One of the most commonly requested features for command-line applications.

---

### 3.10 Man Pages

**What it is:** Manual pages accessible via the `man` command, providing offline documentation for CLI tools.

**Standard locations:**
- `/usr/share/man/man1/myapp.1.gz` — user commands (section 1)
- `/usr/share/man/man5/myapp.conf.5.gz` — file formats (section 5)
- `/usr/share/man/man8/myapp.8.gz` — system administration commands (section 8)

**How nfpm handles it:**

```yaml
contents:
  - src: man/myapp.1.gz
    dst: /usr/share/man/man1/myapp.1.gz
    file_info:
      mode: 0644
    type: doc
```

The postinstall script should update the man database (though most distros do this automatically via triggers):

```bash
if command -v mandb >/dev/null 2>&1; then
  mandb -q 2>/dev/null || true
fi
```

**deb-specific:** Debian policy requires man pages for all commands. `dh_installman` handles compression and placement automatically. With nfpm, the user must pre-compress.

**fpm:** Same approach.

**GoReleaser:** Does not generate man pages but nfpm contents can include them.

**Unified config parameters:**
```toml
[man]
pages = { "myapp.1.gz" = "man/myapp.1.gz" }
# Or simply include in the share file group:
# share = { "man/man1/myapp.1.gz" = "man/myapp.1.gz" }
```

**Commonality:** Expected for CLI tools on Linux. Many modern tools skip man pages in favor of `--help` output, but proper packages should include them.

---

### 3.11 Polkit Policies

**What it is:** PolicyKit (polkit) rules that define which privileged operations users can perform without being root. Used for "Run as administrator" style prompts in GUI applications.

**Policy file example (`/usr/share/polkit-1/actions/com.mycompany.myapp.policy`):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="com.mycompany.myapp.admin-action">
    <description>Run MyApp administrative action</description>
    <message>Authentication is required to run MyApp admin</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/myapp</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
```

**nfpm support:** Install the policy file via contents.

**Unified config parameters:** Not recommended for Crossler scope. Polkit policies are application-specific XML files that should be included as regular files.

**Commonality:** Niche. Only needed for GUI applications that perform privileged operations (like system configuration tools, package managers).

---

### 3.12 udev Rules

**What it is:** udev rules that run when specific hardware devices are connected (USB devices, serial ports, etc.). Rules files in `/etc/udev/rules.d/` or `/lib/udev/rules.d/`.

**Example (`/lib/udev/rules.d/99-mydevice.rules`):**

```
# Allow users in the "myapp" group to access MyDevice
SUBSYSTEM=="usb", ATTR{idVendor}=="1234", ATTR{idProduct}=="5678", MODE="0666", GROUP="myapp"
```

**nfpm support:** Install the rules file via contents. Postinstall script:

```bash
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules
  udevadm trigger
fi
```

**Unified config parameters:** Not recommended for Crossler scope. Include as regular file.

**Commonality:** Niche. Only for hardware-interfacing applications.

---

### 3.13 Cron Jobs

**What it is:** Scheduled tasks using the traditional cron daemon.

**Mechanisms:**

1. **cron.d files (`/etc/cron.d/myapp`):**

```
# Run maintenance daily at 2am
0 2 * * * myapp /usr/bin/myapp maintenance --quiet
```

2. **System-wide crontab entries:** Added via postinstall scripts.

3. **Systemd timers (preferred):** Modern replacement for cron jobs. See section 3.6.

**nfpm support:** Install cron.d file via contents:

```yaml
contents:
  - src: packaging/myapp.cron
    dst: /etc/cron.d/myapp
    file_info:
      mode: 0644
```

**Unified config parameters:** Prefer systemd timers. If cron is needed:
```toml
[[linux.cron]]
schedule = "0 2 * * *"
command = "/usr/bin/myapp maintenance --quiet"
user = "myapp"
```

**Commonality:** Being replaced by systemd timers. Still relevant on older systems or non-systemd distributions (Alpine with OpenRC, for example).

---

### 3.14 AppArmor / SELinux Profiles

**What it is:** Mandatory Access Control (MAC) security profiles that restrict what an application can do (file access, network, capabilities).

**AppArmor profile (`/etc/apparmor.d/usr.bin.myapp`):**

```
#include <tunables/global>

/usr/bin/myapp {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  /usr/bin/myapp mr,
  /etc/myapp/** r,
  /var/lib/myapp/** rw,
  /var/log/myapp/** w,
  network inet tcp,
}
```

**SELinux policy module:** Requires compiling a `.te` policy file into a `.pp` module, which is installed via `semodule`.

**nfpm support:** Install the profile file via contents. Postinstall script loads it:

```bash
# AppArmor
if command -v apparmor_parser >/dev/null 2>&1; then
  apparmor_parser -r /etc/apparmor.d/usr.bin.myapp 2>/dev/null || true
fi
```

**Unified config parameters:** Not recommended for Crossler scope. Include as regular files.

**Commonality:** Important for production server applications. Niche for desktop tools. Ubuntu uses AppArmor by default; RHEL/CentOS use SELinux.

---

### 3.15 Alternatives System

**What it is:** A system for managing multiple implementations of the same command (e.g., `editor`, `pager`, `java`). `update-alternatives` (Debian) or `alternatives` (RHEL) manages symlinks in `/etc/alternatives/`.

**Example usage in postinstall script:**

```bash
#!/bin/bash
# Register myapp as an alternative for "text-editor"
update-alternatives --install /usr/bin/text-editor text-editor /usr/bin/myapp 50
```

In preremove:

```bash
#!/bin/bash
update-alternatives --remove text-editor /usr/bin/myapp
```

**nfpm support:** Handled entirely through postinstall/preremove scripts.

**deb-specific:** Debian packages commonly use `update-alternatives` in maintainer scripts.

**Unified config parameters:** Not recommended for Crossler scope. Handle via scripts.

**Commonality:** Common for packages providing standard commands (editor, browser, terminal). Niche for most applications.

---

### 3.16 tmpfiles.d / sysusers.d

**What it is:** Systemd integrations for managing temporary files/directories and system users/groups declaratively.

**tmpfiles.d (`/usr/lib/tmpfiles.d/myapp.conf`):**

```ini
# Type  Path                  Mode  User   Group  Age
d       /run/myapp            0755  myapp  myapp  -
d       /var/cache/myapp      0750  myapp  myapp  30d
f       /var/log/myapp.log    0640  myapp  myapp  -
```

Types: `d` (directory), `f` (file), `L` (symlink), `D` (directory, clean on boot), `z` (set permissions)

**sysusers.d (`/usr/lib/sysusers.d/myapp.conf`):**

```ini
# Type  Name   ID    GECOS             Home
u       myapp  -     "MyApp Service"   /var/lib/myapp
g       myapp  -     -                 -
```

This is the modern alternative to `useradd` in preinstall scripts. Processed by `systemd-sysusers` during package installation or early boot.

**nfpm support:** Install the config files via contents:

```yaml
contents:
  - src: systemd/myapp-tmpfiles.conf
    dst: /usr/lib/tmpfiles.d/myapp.conf
    file_info:
      mode: 0644

  - src: systemd/myapp-sysusers.conf
    dst: /usr/lib/sysusers.d/myapp.conf
    file_info:
      mode: 0644
```

Postinstall script:

```bash
systemd-tmpfiles --create /usr/lib/tmpfiles.d/myapp.conf 2>/dev/null || true
systemd-sysusers /usr/lib/sysusers.d/myapp.conf 2>/dev/null || true
```

**rpm-specific:** RPM has `%sysusers_create_package` macro for automatic sysusers.d integration.

**Unified config parameters:**
```toml
[linux.system_user]
name = "myapp"
description = "MyApp Service"
home = "/var/lib/myapp"

[[linux.tmpfiles]]
type = "d"
path = "/run/myapp"
mode = "0755"
user = "myapp"
group = "myapp"
```

**Commonality:** tmpfiles.d is common for daemon applications. sysusers.d is the modern best practice for creating service accounts (replacing `useradd` in scripts).

---

## 4. Cross-Tool Comparison

### 4.1 What GoReleaser Supports

GoReleaser handles environment integration primarily through its nfpm configuration for Linux packages and WiX templates for Windows MSI:

| Feature | GoReleaser Support |
|---------|-------------------|
| PATH (Linux) | Via nfpm `contents` (install to `/usr/bin/`) |
| PATH (Windows) | Not directly — requires custom WiX template |
| Systemd services | Via nfpm `contents` + `scripts` |
| Shell completions | Via nfpm `contents` (user must generate completion files) |
| Man pages | Via nfpm `contents` |
| Desktop entries | Via nfpm `contents` (user must create `.desktop` file) |
| File associations | Not directly supported |
| Windows shortcuts | Not directly — requires custom WiX template (Pro) |
| Windows services | Not supported |
| macOS launchd | Not directly supported |
| Protocol handlers | Not supported |

GoReleaser's philosophy is to use nfpm's `contents` for Linux and let users customize WiX templates for Windows-specific features. There is no abstraction layer for environment integration.

### 4.2 What fpm Supports

fpm (Effing Package Management) is a Ruby-based tool for creating packages in multiple formats. Its environment integration approach:

| Feature | fpm Support |
|---------|-------------|
| Contents/files | `--input-type dir` + path mapping |
| Config files | `--config-files /etc/myapp/config.yaml` |
| Systemd services | Include unit file + postinstall scripts |
| Shell completions | Include via file mapping |
| Man pages | Include via file mapping |
| Desktop entries | Include via file mapping |
| Pre/post scripts | `--before-install`, `--after-install`, `--before-remove`, `--after-remove` |
| Dependencies | `--depends`, `--conflicts`, `--provides`, `--replaces` |
| Directories | `--directories /var/lib/myapp` |

fpm does not provide any abstraction for OS-specific features (shortcuts, services, file associations). Everything is done through file placement and scripts, same as nfpm.

### 4.3 What electron-builder Supports

electron-builder is the most feature-rich in terms of environment integration, because it targets GUI applications:

| Feature | electron-builder Support |
|---------|--------------------------|
| File associations | Cross-platform via `fileAssociations` config |
| Protocol handlers | Cross-platform via `protocols` config |
| Windows shortcuts | Automatic (Start Menu + Desktop) |
| Windows auto-updater | Built-in via `autoUpdater` |
| macOS UTI/Launch Services | Via `Info.plist` generation |
| macOS DMG customization | Visual DMG with background image, icon positioning |
| macOS Dock icon | Not supported (by design) |
| Linux .desktop generation | Automatic |
| Linux MIME types | Via `fileAssociations` |
| Linux AppImage | Self-contained, no system integration |
| Windows signing | Via `win.certificateFile` / `win.certificateSubjectName` |
| macOS signing + notarization | Built-in |

electron-builder generates most OS integration artifacts automatically from its config, which is the closest to what Crossler aspires to do.

### 4.4 What Inno Setup Supports

Inno Setup is a Windows-only installer compiler, but has the richest Windows integration:

| Feature | Inno Setup Config Section |
|---------|---------------------------|
| PATH | `[Registry]` + `ChangesEnvironment=yes` |
| Environment variables | `[Registry]` |
| Start Menu shortcuts | `[Icons]` with `{autoprograms}` |
| Desktop shortcuts | `[Icons]` with `{autodesktop}` |
| File associations | `[Registry]` |
| Context menu | `[Registry]` |
| Windows Services | `[Run]` with service commands |
| Autostart | `[Registry]` Run key |
| Registry entries | `[Registry]` |
| Firewall rules | `[Run]` with netsh |
| Protocol handlers | `[Registry]` |
| Scheduled tasks | `[Run]` with schtasks |

Inno Setup's `[Registry]` section is its universal mechanism for most OS integration.

### 4.5 What NSIS Supports

NSIS (Nullsoft Scriptable Install System) is scripting-based, so everything is possible but nothing is declarative:

| Feature | NSIS Mechanism |
|---------|---------------|
| PATH | `EnVar` plugin or registry manipulation |
| Shortcuts | `CreateShortCut` function |
| File associations | Registry writes in `.onInstSuccess` |
| Context menu | Registry writes |
| Windows Services | `nsSCM` plugin or `sc.exe` via `nsExec` |
| Autostart | Registry writes to Run key |
| Firewall | `nsExec` with `netsh` |
| Protocol handlers | Registry writes |

Everything in NSIS is imperative scripting rather than declarative config.

---

## 5. Unified Config Considerations for Crossler

### 5.1 Priority Matrix

Based on Crossler's target audience (80% CLI tools, 20% GUI apps), here is a priority ranking:

#### Tier 1 — Essential (should be in v1)

| Feature | Windows | macOS | Linux | Why |
|---------|---------|-------|-------|-----|
| PATH | `<Environment>` | symlink / paths.d | install to `/usr/bin/` | Core for CLI tools |
| Shell completions | — | — | contents | Expected for CLI tools |
| Man pages | — | — | contents | Expected for CLI tools |
| Systemd services | — | — | unit file + scripts | Essential for daemons |
| launchd services | — | plist + scripts | — | Essential for daemons on macOS |
| Windows services | CustomAction/sc.exe | — | — | Essential for daemons on Windows |

#### Tier 2 — Important (should be in v2)

| Feature | Windows | macOS | Linux | Why |
|---------|---------|-------|-------|-----|
| Start Menu shortcuts | `<Shortcut>` | N/A | N/A | Basic Windows integration |
| Desktop shortcuts | `<Shortcut>` | N/A | N/A | Basic Windows integration |
| Desktop entries | N/A | N/A | .desktop file | Basic Linux desktop integration |
| File associations | ProgID/Extension | UTI/CFBundle | shared-mime-info | Document-oriented apps |
| Protocol handlers | Registry | Info.plist | .desktop | Web-connected apps |
| Autostart/Login items | Registry Run / StartupFolder | LaunchAgent | XDG autostart | Background tools |
| System user creation | — | — | sysusers.d / scripts | Daemon applications |

#### Tier 3 — Niche (consider for later)

| Feature | Windows | macOS | Linux | Why |
|---------|---------|-------|-------|-----|
| Environment variables | `<Environment>` | launchctl/profile | profile.d | Rarely needed |
| Context menu | Registry | N/A (requires app extension) | File-manager-specific | Fragmented |
| Registry entries | `<RegistryKey>` | N/A | N/A | Custom Windows data |
| Firewall rules | netsh | N/A | N/A | Server apps only |
| Scheduled tasks | schtasks | launchd timer | systemd timer / cron | Maintenance apps |
| tmpfiles.d | — | — | tmpfiles.d | Advanced daemons |
| Polkit / udev / AppArmor | — | — | Various | Very specialized |
| Spotlight / Quick Look | — | Plugin bundles | — | macOS-specific |
| Alternatives system | — | — | update-alternatives | Specific use case |
| D-Bus services | — | — | .service file | Desktop integration |

### 5.2 Recommended Config Structure

Based on the research, here is a proposed unified config structure for environment integration features:

```toml
# === Tier 1: Essential for CLI tools ===

# PATH: handled implicitly by the `bin` file group
# Shell completions: handled by a dedicated file group or parameter
completions = {
  "bash" = "completions/myapp.bash",
  "zsh"  = "completions/_myapp",
  "fish" = "completions/myapp.fish",
}

# Man pages: handled by the `share` file group
# share = { "man/man1/myapp.1.gz" = "man/myapp.1.gz" }

# === Tier 1: Essential for daemons ===

# Unified service definition — maps to systemd, launchd, Windows Service
[service]
description = "My Application Server"
command = "serve --config /etc/myapp/config.yaml"
type = "simple"              # simple, forking, oneshot, notify
restart = "on-failure"
user = "myapp"
group = "myapp"

# === Tier 2: GUI applications ===

[shortcuts]
start_menu = true            # Windows: Start Menu; ignored on other platforms
desktop = true               # Windows: Desktop shortcut; ignored on other platforms

[desktop_entry]              # Linux .desktop file generation
categories = ["Development", "Utility"]
terminal = false
keywords = ["tool", "utility"]

[[file_associations]]
extension = "myext"
mime_type = "application/x-myext"
description = "My Document"
icon = "document"

[[protocol_handlers]]
scheme = "myapp"
description = "My App Protocol"

# === Tier 2: Background tools ===

[autostart]
enabled = true
args = "--background"

# === Platform-specific overrides ===

[windows]
path = true                  # add install dir to PATH
app_paths = true             # register in App Paths

[macos]
path = true                  # create symlink or paths.d entry

[linux]
system_user = "myapp"        # create via sysusers.d
```

### 5.3 Key Design Decisions for Crossler

1. **PATH handling should be automatic** for the `bin` file group — no extra config needed on Linux (files go to `/usr/bin/`). On Windows, an explicit `windows.path = true` toggle is needed (for `<Environment>` generation). On macOS, a symlink or `paths.d` entry may be needed depending on the install location.

2. **Services should be a unified abstraction.** A single `[service]` section should map to systemd unit files (Linux), launchd plists (macOS), and Windows Service registration. This is the highest-value abstraction Crossler can provide.

3. **Shell completions deserve first-class support** as a dedicated parameter, not just regular files in `share`. They are the most commonly requested integration for CLI tools.

4. **File associations should be cross-platform** via `[[file_associations]]`, generating the appropriate platform-specific artifacts (WiX ProgID, Info.plist UTI, shared-mime-info XML, .desktop MimeType).

5. **Desktop entries should be auto-generated** from metadata (name, description, icon, categories) rather than requiring the user to write a `.desktop` file manually.

6. **Scripts remain the escape hatch.** For niche integrations (udev, polkit, AppArmor, context menus, etc.), Crossler should not try to abstract them. The user provides the files in the appropriate file groups, and optionally uses pre/post install scripts for activation.

7. **wixl limitations matter.** Since wixl does not support `<ServiceInstall>`, `<FirewallException>`, or WiX extensions, Windows service registration and firewall rules must be implemented via `CustomAction` with `sc.exe` and `netsh.exe`. This affects the implementation complexity of the `[service]` abstraction for Windows.

---

## References

### Windows / MSI / WiX
- [WiX Toolset Documentation](https://wixtoolset.org/docs/)
- [WiX Environment Element](https://wixtoolset.org/docs/v3/xsd/wix/environment/)
- [WiX ServiceInstall Element](https://wixtoolset.org/docs/v3/xsd/wix/serviceinstall/)
- [WiX Shortcut Element](https://wixtoolset.org/docs/v3/xsd/wix/shortcut/)
- [WiX ProgId Element](https://wixtoolset.org/docs/v3/xsd/wix/progid/)
- [Inno Setup Documentation](https://jrsoftware.org/ishelp/)
- [NSIS Documentation](https://nsis.sourceforge.io/Docs/)

### macOS
- [Apple pkgbuild man page](https://www.manpagez.com/man/1/pkgbuild/)
- [Apple Launch Services Programming Guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/)
- [Apple Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers)
- [launchd.plist man page](https://www.manpagez.com/man/5/launchd.plist/)
- [Apple Info.plist Key Reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/)

### Linux
- [XDG Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)
- [XDG MIME Applications Specification](https://specifications.freedesktop.org/mime-apps-spec/latest/)
- [Shared MIME-info Specification](https://specifications.freedesktop.org/shared-mime-info-spec/latest/)
- [systemd.service man page](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd.timer man page](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [tmpfiles.d man page](https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html)
- [sysusers.d man page](https://www.freedesktop.org/software/systemd/man/sysusers.d.html)
- [Icon Theme Specification](https://specifications.freedesktop.org/icon-theme-spec/latest/)
- [nfpm Documentation](https://nfpm.goreleaser.com/)
- [fpm Wiki](https://fpm.readthedocs.io/)

### Cross-Platform Tools
- [GoReleaser Documentation](https://goreleaser.com/customization/)
- [electron-builder Documentation](https://www.electron.build/)

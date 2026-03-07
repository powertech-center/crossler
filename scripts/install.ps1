#!/usr/bin/env pwsh
# Install Crossler and its external tool dependencies for Windows.
# Installed: crossler, nfpm, rcodesign, signtool (via Windows SDK), wix (.NET global tool)
#
# Usage:
#   .\scripts\install.ps1               # install all tools
#   .\scripts\install.ps1 -DryRun       # show what would be done
#   .\scripts\install.ps1 -NoPause      # skip "press any key" at the end
#   .\scripts\install.ps1 -InstallDir "C:\Tools\crossler"  # custom binary install dir

param(
    [switch]$DryRun,
    [switch]$NoPause,
    [string]$InstallDir = "$env:ProgramData\crossler-tools"
)

$InstalledTools = [System.Collections.Generic.List[string]]::new()
$SkippedTools   = [System.Collections.Generic.List[string]]::new()

# Detect architecture
$ArchType      = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
$ArchNfpm      = if ($ArchType -eq "arm64") { "arm64" } else { "x86_64" }  # nfpm uses Windows_x86_64 / Windows_arm64
$ArchRust      = "x86_64"  # rcodesign has no Windows arm64 build; x64 runs via emulation on arm64
$ArchCrossler  = $ArchType  # crossler uses windows-x64 / windows-arm64

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------

function Write-Info  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "[ OK ]  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Skip  { param($msg) Write-Host "[SKIP]  $msg" -ForegroundColor Gray }

function Exit-WithPause {
    param([int]$ExitCode = 0)
    if (-not $NoPause) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit $ExitCode
}

# -----------------------------------------------------------------------------
# Utility functions
# -----------------------------------------------------------------------------

function Get-GitHubHeaders {
    $headers = @{}
    if ($env:GITHUB_TOKEN) {
        $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    }
    return $headers
}

function Get-GitHubLatestVersion {
    param([string]$Repo, [string]$Fallback = "")
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $response = Invoke-RestMethod -Uri $url -UseBasicParsing -Headers (Get-GitHubHeaders)
        $tag = $response.tag_name -replace '^v', ''
        return $tag
    } catch {
        if ($Fallback) {
            Write-Warn "Could not fetch latest version for $Repo, using fallback $Fallback"
            return $Fallback
        }
        Write-Warn "Could not fetch latest version for $Repo : $_"
        return ""
    }
}

function Get-RcodesignLatestVersion {
    $url = "https://api.github.com/repos/indygreg/apple-platform-rs/releases/latest"
    try {
        $response = Invoke-RestMethod -Uri $url -UseBasicParsing -Headers (Get-GitHubHeaders)
        # tag_name is like "apple-codesign/0.29.0"
        $tag = $response.tag_name -replace '^apple-codesign/', ''
        return $tag
    } catch {
        Write-Warn "Could not fetch latest rcodesign version, using fallback 0.29.0"
        return "0.29.0"
    }
}

function Download-File {
    param([string]$Url, [string]$Destination)
    if ($DryRun) {
        Write-Info "DRY RUN: would download $([System.IO.Path]::GetFileName($Destination)) from $Url"
        return
    }
    Write-Info "Downloading $([System.IO.Path]::GetFileName($Destination))..."
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Add-ToPath {
    param([string]$NewDir)
    # Update current session
    if ($env:PATH -notlike "*$NewDir*") {
        $env:PATH = "$env:PATH;$NewDir"
    }
    if ($DryRun) {
        Write-Info "DRY RUN: would add $NewDir to system PATH"
        return
    }
    # In GitHub Actions — write to GITHUB_PATH so subsequent steps pick it up
    if ($env:GITHUB_PATH) {
        Add-Content -Path $env:GITHUB_PATH -Value $NewDir -Encoding utf8
        Write-Info "Added $NewDir to GITHUB_PATH"
        return
    }
    # Persist to Machine PATH
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($machinePath -notlike "*$NewDir*") {
        try {
            [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$NewDir", "Machine")
            Write-Info "Added $NewDir to system PATH"
        } catch {
            # Fallback to user PATH if not elevated
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -notlike "*$NewDir*") {
                [Environment]::SetEnvironmentVariable("PATH", "$userPath;$NewDir", "User")
                Write-Warn "Added $NewDir to user PATH (restart shell to apply)"
            }
        }
    }
}

function Find-SigntoolExe {
    $sdkRoots = @(
        "$env:ProgramFiles\Windows Kits\10\bin",
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    )
    foreach ($root in $sdkRoots) {
        if (Test-Path $root) {
            $found = Get-ChildItem -Path $root -Filter "signtool.exe" -Recurse -ErrorAction SilentlyContinue |
                     Sort-Object FullName -Descending |
                     Select-Object -First 1
            if ($found) { return $found }
        }
    }
    return $null
}

# -----------------------------------------------------------------------------
# Tool installers
# -----------------------------------------------------------------------------

function Install-Crossler {
    Write-Info "Installing crossler (latest release)..."
    $url  = "https://github.com/powertech-center/crossler/releases/latest/download/crossler-windows-${ArchCrossler}.exe"
    $dest = Join-Path $InstallDir "crossler.exe"
    if ($DryRun) {
        Write-Info "DRY RUN: would download crossler for windows/$ArchCrossler and install to $dest"
        $InstalledTools.Add("crossler (dry-run)")
        return
    }
    try {
        Download-File $url $dest
        Add-ToPath $InstallDir
        Write-Ok "crossler installed"
        $InstalledTools.Add("crossler")
    } catch {
        Write-Warn "crossler installation failed: $_"
        $InstalledTools.Add("crossler (FAILED)")
    }
}

function Install-Nfpm {
    if (Get-Command nfpm -ErrorAction SilentlyContinue) {
        $ver = & nfpm --version 2>&1
        Write-Skip "nfpm already installed: $ver"
        $SkippedTools.Add("nfpm")
        return
    }
    Write-Info "Installing nfpm..."
    $version = Get-GitHubLatestVersion -Repo "goreleaser/nfpm" -Fallback "2.40.0"
    if ($DryRun) {
        Write-Info "DRY RUN: would download nfpm v$version for Windows/$ArchNfpm"
        $InstalledTools.Add("nfpm (dry-run)")
        return
    }
    $archive = "nfpm_${version}_Windows_${ArchNfpm}.zip"
    $url     = "https://github.com/goreleaser/nfpm/releases/download/v${version}/${archive}"
    $tmpZip  = Join-Path $env:TEMP $archive
    $tmpDir  = Join-Path $env:TEMP "nfpm_extract"
    try {
        Download-File $url $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
        $exe = Get-ChildItem -Path $tmpDir -Filter "nfpm.exe" -Recurse | Select-Object -First 1
        if (-not $exe) { throw "nfpm.exe not found in archive" }
        $dest = Join-Path $InstallDir "nfpm.exe"
        Move-Item $exe.FullName $dest -Force
        Add-ToPath $InstallDir
        $ver = & $dest --version 2>&1
        Write-Ok "nfpm installed: $ver"
        $InstalledTools.Add("nfpm")
    } catch {
        Write-Warn "nfpm installation failed: $_"
        $InstalledTools.Add("nfpm (FAILED)")
    } finally {
        Remove-Item $tmpZip -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-Rcodesign {
    if (Get-Command rcodesign -ErrorAction SilentlyContinue) {
        $ver = & rcodesign --version 2>&1
        Write-Skip "rcodesign already installed: $ver"
        $SkippedTools.Add("rcodesign")
        return
    }
    Write-Info "Installing rcodesign..."
    $version = Get-RcodesignLatestVersion
    if ($DryRun) {
        Write-Info "DRY RUN: would download rcodesign v$version for windows/$ArchRust"
        $InstalledTools.Add("rcodesign (dry-run)")
        return
    }
    $archive   = "apple-codesign-${version}-${ArchRust}-pc-windows-msvc.zip"
    $tagEnc    = "apple-codesign%2F${version}"
    $url       = "https://github.com/indygreg/apple-platform-rs/releases/download/${tagEnc}/${archive}"
    $tmpZip    = Join-Path $env:TEMP $archive
    $tmpDir    = Join-Path $env:TEMP "rcodesign_extract"
    try {
        Download-File $url $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
        $exe = Get-ChildItem -Path $tmpDir -Filter "rcodesign.exe" -Recurse | Select-Object -First 1
        if (-not $exe) { throw "rcodesign.exe not found in archive" }
        $dest = Join-Path $InstallDir "rcodesign.exe"
        Move-Item $exe.FullName $dest -Force
        Add-ToPath $InstallDir
        $ver = & $dest --version 2>&1
        Write-Ok "rcodesign installed: $ver"
        $InstalledTools.Add("rcodesign")
    } catch {
        Write-Warn "rcodesign installation failed: $_"
        $InstalledTools.Add("rcodesign (FAILED)")
    } finally {
        Remove-Item $tmpZip -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-Signtool {
    # Check if already available
    $existing = Find-SigntoolExe
    if ($existing) {
        Write-Skip "signtool.exe already present: $($existing.FullName)"
        $SkippedTools.Add("signtool")
        return
    }
    if (Get-Command signtool -ErrorAction SilentlyContinue) {
        Write-Skip "signtool already on PATH"
        $SkippedTools.Add("signtool")
        return
    }
    Write-Info "Installing Windows SDK (signtool) via winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn "winget not available. Install Windows SDK manually:"
        Write-Warn "  https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
        $InstalledTools.Add("signtool (MANUAL REQUIRED)")
        return
    }
    if ($DryRun) {
        Write-Info "DRY RUN: would run: winget install --id Microsoft.WindowsSDK.10.0.26100 --silent"
        $InstalledTools.Add("signtool (dry-run)")
        return
    }
    winget install --id Microsoft.WindowsSDK.10.0.26100 --silent --accept-package-agreements --accept-source-agreements
    # Locate signtool.exe after install and add to PATH
    $found = Find-SigntoolExe
    if ($found) {
        Add-ToPath $found.DirectoryName
        Write-Ok "signtool installed: $($found.FullName)"
        $InstalledTools.Add("signtool")
    } else {
        Write-Warn "signtool not found after SDK install. A reboot may be required."
        $InstalledTools.Add("signtool (reboot may be needed)")
    }
}

function Install-Wix {
    if (Get-Command wix -ErrorAction SilentlyContinue) {
        $ver = & wix --version 2>&1
        Write-Skip "wix already installed: $ver"
        $SkippedTools.Add("wix")
        return
    }
    Write-Info "Installing WiX Toolset v4 (.NET global tool)..."
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Warn ".NET SDK not found. Install it from: https://dotnet.microsoft.com/download"
        Write-Warn "Then run: dotnet tool install --global wix"
        $InstalledTools.Add("wix (MANUAL REQUIRED — dotnet missing)")
        return
    }
    if ($DryRun) {
        Write-Info "DRY RUN: would run: dotnet tool install --global wix"
        $InstalledTools.Add("wix (dry-run)")
        return
    }
    dotnet tool install --global wix
    if ($LASTEXITCODE -ne 0) {
        # May already be installed but not on PATH — try update
        dotnet tool update --global wix
    }
    # Ensure dotnet tools directory is on PATH
    $dotnetTools = Join-Path $env:USERPROFILE ".dotnet\tools"
    if (Test-Path $dotnetTools) {
        Add-ToPath $dotnetTools
    }
    $wixExe = Join-Path $dotnetTools "wix.exe"
    if ((Get-Command wix -ErrorAction SilentlyContinue) -or (Test-Path $wixExe)) {
        $ver = if (Test-Path $wixExe) { & $wixExe --version 2>&1 } else { & wix --version 2>&1 }
        Write-Ok "wix installed: $ver"
        $InstalledTools.Add("wix")
    } else {
        Write-Warn "wix installed but not on PATH yet. Restart shell or add $dotnetTools to PATH."
        $InstalledTools.Add("wix (PATH refresh needed)")
    }
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

function Write-Summary {
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "Installation summary" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    if ($InstalledTools.Count -gt 0) {
        Write-Host "Newly installed:" -ForegroundColor Green
        $InstalledTools | ForEach-Object { Write-Host "  + $_" }
    }
    if ($SkippedTools.Count -gt 0) {
        Write-Host "Already present:" -ForegroundColor Gray
        $SkippedTools | ForEach-Object { Write-Host "  - $_" }
    }
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Crossler installer" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Info "OS:          Windows"
Write-Info "Arch:        $ArchType"
Write-Info "Install dir: $InstallDir"
if ($DryRun) { Write-Host "[DRY RUN MODE — no changes will be made]" -ForegroundColor Yellow }
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Create install directory
if (-not $DryRun) {
    New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction SilentlyContinue | Out-Null
}

Install-Crossler
Install-Nfpm
Install-Rcodesign
Install-Signtool
Install-Wix

Write-Summary
Exit-WithPause 0

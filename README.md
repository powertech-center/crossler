# Crossler

A cross-platform packaging tool — build installers for Windows, Linux, and macOS from a single config file.

## How it works

Crossler reads a single config file and delegates package creation to the right backend for each target format. You run one tool, get packages for all platforms.

Crossler ships as **6 binaries** (Linux, macOS, Windows × x64/arm64). Each binary covers a different set of formats:

| Format / capability | Linux | macOS | Windows |
|---------------------|:-----:|:-----:|:-------:|
| `.msi` | ✓ `wixl` | ✓ `wixl` | ✓ `wix` |
| `.deb`, `.rpm`, `.apk`, `.pkg.tar.zst`, `.ipk` | ✓ `nfpm` | ✓ `nfpm` | ✓ `nfpm` |
| `.tar.gz` | ✓ | ✓ | ✓ |
| `.rb` (Homebrew) | ✓ | ✓ | ✓ |
| `.pkg` (macOS installer) | ✓ `xar`+`bomutils` | ✓ `pkgbuild` | ✓ `xar`+`bomutils` |
| `.dmg` (macOS disk image) | — | ✓ `hdiutil` | — |
| Windows signing | ✓ `osslsigncode` | ✓ `osslsigncode` | ✓ `signtool` |
| macOS signing | ✓ `rcodesign` | ✓ `codesign` `notarytool` | ✓ `rcodesign` |

The **Linux binary** is the primary one — it can build and sign packages for all platforms, including macOS signing via `rcodesign`. The **macOS binary** handles everything that requires native macOS tooling, including signing binaries before packaging into `tar.gz`, `.pkg`, or `.dmg`. The **Windows binary** covers MSI creation and signing via `signtool`.

> **Note:** `nfpm` is a pure Go binary and works on all platforms — `.deb`, `.rpm`, and `.apk` packages can be built from Linux, macOS, or Windows. In practice, Linux is the typical host for building Linux packages.

## Config file

Each project defines its packaging in a single config file (format TBD). The config supports layered settings — shared options apply to all targets, with platform- and architecture-specific overrides on top. Binaries and assets (icons, docs) are configured separately, since they typically live in different locations.

## Installation

A bootstrap script installs Crossler and all its dependencies in one step.

**Linux / macOS:**
```sh
curl -fsSL https://raw.githubusercontent.com/powertech-center/crossler/master/scripts/install.sh | sh
```

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/powertech-center/crossler/master/scripts/install.ps1 | iex
```

Running the script again always upgrades Crossler to the latest release. External tools are reinstalled only if missing.

## Scope

Crossler is optimized for **CLI tools** (80% of use cases). GUI applications are supported but secondary. It's not meant to cover every packaging scenario — the goal is to standardize and simplify packaging for our own projects.

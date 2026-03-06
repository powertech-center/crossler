# Crossler

A cross-platform packaging tool — build installers for Windows, Linux, and macOS from a single config file.

## How it works

Crossler reads a single config file and delegates package creation to the right backend for each target format. You run one tool, get packages for all platforms.

Crossler ships as **6 binaries** (Linux, macOS, Windows × x64/arm64). Each binary covers a different set of formats:

| Format / capability | Linux | macOS | Windows |
|---------------------|:-----:|:-----:|:-------:|
| `.msi` | ✓ `wixl` | — | ✓ `wix` |
| `.deb`, `.rpm`, `.apk` | ✓ `nfpm` | — | — |
| `.tar.gz` | ✓ | ✓ | ✓ |
| `.rb` (Homebrew) | ✓ | ✓ | ✓ |
| `.pkg` (macOS installer) | — | ✓ `pkgbuild` | — |
| `.dmg` (macOS disk image) | — | ✓ `hdiutil` | — |
| Windows signing | ✓ `osslsigncode` | — | ✓ `signtool` |
| macOS signing | — | ✓ `codesign` `notarytool` | — |

The **Linux binary** is the primary one — it can build and sign packages for all platforms except macOS signing. The **macOS binary** handles everything that requires native macOS tooling, including signing binaries before packaging into `tar.gz`, `.pkg`, or `.dmg`. The **Windows binary** covers MSI creation and signing via `signtool`.

## Config file

Each project defines its packaging in a single config file (format TBD). The config supports layered settings — shared options apply to all targets, with platform- and architecture-specific overrides on top. Binaries and assets (icons, docs) are configured separately, since they typically live in different locations.

## Installation

A bootstrap script is available from the `master` branch to install Crossler with all dependencies in one step — useful for CI/CD Docker images.

## Scope

Crossler is optimized for **CLI tools** (80% of use cases). GUI applications are supported but secondary. It's not meant to cover every packaging scenario — the goal is to standardize and simplify packaging for our own projects.

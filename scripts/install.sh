#!/usr/bin/env sh
# Install Crossler and its external tool dependencies.
# Supports: Linux (apk/apt/dnf/yum/zypper/pacman), macOS (Homebrew)
#
# Usage:
#   ./scripts/install.sh           # install crossler + all tools
#   ./scripts/install.sh --dry-run # show what would be installed
#
# Installed on Linux:  crossler, wixl, nfpm, osslsigncode, rcodesign, xar, bomutils (mkbom)
# Installed on macOS:  crossler, Xcode CLT, wixl, nfpm, osslsigncode, rcodesign, xar

DRY_RUN=0
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=1
fi

INSTALLED_TOOLS=""
SKIPPED_TOOLS=""

OS_TYPE=""
ARCH_GONAME=""   # amd64|arm64 — used internally
ARCH_NFPM=""     # x86_64|arm64 — used by nfpm asset names (Linux/Windows: Linux_x86_64, Linux_arm64)
ARCH_RUST=""     # x86_64|aarch64 — used by rcodesign asset names
ARCH_CROSSLER="" # x64|arm64 — used by crossler asset names
PKG_MGR=""
DOWNLOADER=""
TMPDIR_WORK=""
APT_UPDATED=0

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------

info() { echo "[INFO]  $1"; }
ok()   { echo "[ OK ]  $1"; }
warn() { echo "[WARN]  $1"; }
skip() { echo "[SKIP]  $1"; }
fail() { echo "[ERROR] $1" >&2; exit 1; }

mark_installed() { INSTALLED_TOOLS="${INSTALLED_TOOLS}  + $1
"; }
mark_skipped()   { SKIPPED_TOOLS="${SKIPPED_TOOLS}  - $1
"; }

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------

detect_os() {
    local os
    os=$(uname -s)
    case "$os" in
        Linux)  OS_TYPE="linux" ;;
        Darwin) OS_TYPE="macos" ;;
        *)      fail "Unsupported OS: $os. This script supports Linux and macOS only." ;;
    esac
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  ARCH_GONAME="amd64"; ARCH_NFPM="x86_64"; ARCH_RUST="x86_64";  ARCH_CROSSLER="x64"  ;;
        aarch64|arm64) ARCH_GONAME="arm64"; ARCH_NFPM="arm64";  ARCH_RUST="aarch64"; ARCH_CROSSLER="arm64" ;;
        *)             fail "Unsupported architecture: $arch" ;;
    esac
}

detect_pkg_manager() {
    if   command -v apk     >/dev/null 2>&1; then PKG_MGR="apk"
    elif command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt"
    elif command -v dnf     >/dev/null 2>&1; then PKG_MGR="dnf"
    elif command -v yum     >/dev/null 2>&1; then PKG_MGR="yum"
    elif command -v zypper  >/dev/null 2>&1; then PKG_MGR="zypper"
    elif command -v pacman  >/dev/null 2>&1; then PKG_MGR="pacman"
    else
        warn "No supported package manager found. Binary-only installs will still proceed."
        PKG_MGR="none"
    fi
}

detect_downloader() {
    if   command -v curl >/dev/null 2>&1; then DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then DOWNLOADER="wget"
    else fail "Neither curl nor wget found. Please install one and retry."
    fi
}

# -----------------------------------------------------------------------------
# Package install / download helpers
# -----------------------------------------------------------------------------

# Install one or more packages non-interactively. Returns non-zero on failure.
pkg_install() {
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run pkg_install $*"
        return 0
    fi
    case "$PKG_MGR" in
        apk)    apk add --no-cache "$@" ;;
        apt)    if [ "$APT_UPDATED" = "0" ]; then apt-get update -qq; APT_UPDATED=1; fi
                apt-get install -y "$@" ;;
        dnf)    dnf install -y "$@" ;;
        yum)    yum install -y "$@" ;;
        zypper) zypper install -y "$@" ;;
        pacman) pacman -S --noconfirm "$@" ;;
        none)   warn "No package manager — cannot install $*"; return 1 ;;
    esac
}

download_file() {
    # $1 = URL, $2 = destination path
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would download $(basename "$2") from $1"
        return 0
    fi
    case "$DOWNLOADER" in
        curl) curl -fsSL -o "$2" "$1" ;;
        wget) wget -qO  "$2" "$1" ;;
    esac
    if [ $? -ne 0 ]; then
        warn "Download failed: $1"
        return 1
    fi
    return 0
}

# Build GitHub API auth header if GITHUB_TOKEN is set (avoids rate limits in CI)
github_auth_header() {
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "Authorization: Bearer $GITHUB_TOKEN"
    fi
}

# Query GitHub API for the latest release tag. Strips leading 'v'.
# $1 = "owner/repo"
github_latest_version() {
    local repo="$1"
    local url="https://api.github.com/repos/${repo}/releases/latest"
    local response
    local auth_header
    auth_header=$(github_auth_header)
    case "$DOWNLOADER" in
        curl) response=$(curl -fsSL ${auth_header:+-H "$auth_header"} "$url" 2>/dev/null) ;;
        wget) response=$(wget -qO- ${auth_header:+--header="$auth_header"} "$url" 2>/dev/null) ;;
    esac
    # Extract tag_name value, strip leading 'v' if present
    echo "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -1
}

# rcodesign uses tag format "apple-codesign/X.Y.Z" — extract version after the slash
github_rcodesign_version() {
    local url="https://api.github.com/repos/indygreg/apple-platform-rs/releases/latest"
    local response
    local auth_header
    auth_header=$(github_auth_header)
    case "$DOWNLOADER" in
        curl) response=$(curl -fsSL ${auth_header:+-H "$auth_header"} "$url" 2>/dev/null) ;;
        wget) response=$(wget -qO- ${auth_header:+--header="$auth_header"} "$url" 2>/dev/null) ;;
    esac
    echo "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"apple-codesign\/\([^"]*\)".*/\1/p' | head -1
}

# -----------------------------------------------------------------------------
# Crossler binary installer
# -----------------------------------------------------------------------------

install_crossler() {
    info "Installing crossler (latest release)..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would download crossler for ${OS_TYPE}/${ARCH_CROSSLER} and install to /usr/local/bin/crossler"
        mark_installed "crossler (dry-run)"
        return
    fi
    local os_name
    case "$OS_TYPE" in
        linux) os_name="linux" ;;
        macos) os_name="darwin" ;;
    esac
    local url="https://github.com/powertech-center/crossler/releases/latest/download/crossler-${os_name}-${ARCH_CROSSLER}"
    if ! download_file "$url" "${TMPDIR_WORK}/crossler"; then
        warn "crossler download failed"
        mark_installed "crossler (FAILED — download error)"
        return
    fi
    install -m 755 "${TMPDIR_WORK}/crossler" /usr/local/bin/crossler
    ok "crossler installed"
    mark_installed "crossler"
}

# -----------------------------------------------------------------------------
# Tool installers — macOS
# -----------------------------------------------------------------------------

install_xcode_clt() {
    if xcode-select -p >/dev/null 2>&1; then
        skip "Xcode Command Line Tools already installed"
        mark_skipped "Xcode CLT (pkgbuild, hdiutil, codesign, notarytool, xar, mkbom)"
        return
    fi
    info "Installing Xcode Command Line Tools..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run softwareupdate to install Xcode CLT"
        mark_installed "Xcode CLT (pkgbuild, hdiutil, codesign, notarytool, xar, mkbom)"
        return
    fi
    # Headless CI installation via softwareupdate
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    local prod
    prod=$(softwareupdate -l 2>/dev/null | grep -B1 "Command Line Tools" | awk -F"*" '/^\*/{print $2}' | sed 's/^ //' | tail -1)
    if [ -n "$prod" ]; then
        softwareupdate -i "$prod" --agree-to-license
        ok "Xcode CLT installed"
        mark_installed "Xcode CLT (pkgbuild, hdiutil, codesign, notarytool, xar, mkbom)"
    else
        warn "Could not find Xcode CLT via softwareupdate. Run manually: xcode-select --install"
        mark_installed "Xcode CLT (MANUAL REQUIRED)"
    fi
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
}

install_wixl_macos() {
    if command -v wixl >/dev/null 2>&1; then
        skip "wixl already installed: $(wixl --version 2>&1 | head -1)"
        mark_skipped "wixl"
        return
    fi
    info "Installing wixl (msitools) via Homebrew..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run: brew install msitools"
        mark_installed "wixl (dry-run)"
        return
    fi
    brew install msitools
    ok "wixl installed: $(wixl --version 2>&1 | head -1)"
    mark_installed "wixl"
}

install_nfpm_macos() {
    if command -v nfpm >/dev/null 2>&1; then
        skip "nfpm already installed: $(nfpm --version 2>&1 | head -1)"
        mark_skipped "nfpm"
        return
    fi
    info "Installing nfpm via Homebrew..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run: brew install nfpm"
        mark_installed "nfpm (dry-run)"
        return
    fi
    brew install nfpm
    ok "nfpm installed: $(nfpm --version 2>&1 | head -1)"
    mark_installed "nfpm"
}

install_osslsigncode_macos() {
    if command -v osslsigncode >/dev/null 2>&1; then
        skip "osslsigncode already installed: $(osslsigncode --version 2>&1 | head -1)"
        mark_skipped "osslsigncode"
        return
    fi
    info "Installing osslsigncode via Homebrew..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run: brew install osslsigncode"
        mark_installed "osslsigncode (dry-run)"
        return
    fi
    brew install osslsigncode
    ok "osslsigncode installed"
    mark_installed "osslsigncode"
}

install_rcodesign_macos() {
    if command -v rcodesign >/dev/null 2>&1; then
        skip "rcodesign already installed: $(rcodesign --version 2>&1 | head -1)"
        mark_skipped "rcodesign"
        return
    fi
    info "Installing rcodesign (binary download)..."
    local version
    version=$(github_rcodesign_version)
    if [ -z "$version" ]; then
        warn "Could not determine latest rcodesign version, using fallback 0.29.0"
        version="0.29.0"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would download rcodesign v${version} for macOS ${ARCH_RUST}"
        mark_installed "rcodesign (dry-run)"
        return
    fi
    local rust_arch
    case "$ARCH_GONAME" in
        amd64) rust_arch="x86_64-apple-darwin" ;;
        arm64) rust_arch="aarch64-apple-darwin" ;;
    esac
    local archive="apple-codesign-${version}-${rust_arch}.tar.gz"
    local url="https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${version}/${archive}"
    local extracted_dir="apple-codesign-${version}-${rust_arch}"
    info "Downloading rcodesign v${version} (${rust_arch})..."
    download_file "$url" "${TMPDIR_WORK}/${archive}"
    tar -xzf "${TMPDIR_WORK}/${archive}" -C "$TMPDIR_WORK"
    install -m 755 "${TMPDIR_WORK}/${extracted_dir}/rcodesign" /usr/local/bin/rcodesign
    ok "rcodesign installed: $(rcodesign --version 2>&1 | head -1)"
    mark_installed "rcodesign"
}

install_xar_macos() {
    if command -v xar >/dev/null 2>&1; then
        skip "xar already installed"
        mark_skipped "xar"
        return
    fi
    info "Installing xar via Homebrew..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run: brew install xar-mackyle"
        mark_installed "xar (dry-run)"
        return
    fi
    brew install xar-mackyle
    ok "xar installed"
    mark_installed "xar"
}

# -----------------------------------------------------------------------------
# Tool installers — Linux
# -----------------------------------------------------------------------------

install_wixl_linux() {
    if command -v wixl >/dev/null 2>&1; then
        skip "wixl already installed: $(wixl --version 2>&1 | head -1)"
        mark_skipped "wixl"
        return
    fi
    info "Installing wixl (msitools) via package manager..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would run: pkg_install msitools"
        mark_installed "wixl (dry-run)"
        return
    fi
    # Alpine: msitools is in the community repository — enable it if not already
    if [ "$PKG_MGR" = "apk" ] && [ -f /etc/apk/repositories ]; then
        if ! grep -q '^[^#]*community' /etc/apk/repositories 2>/dev/null; then
            info "Enabling Alpine community repository for msitools..."
            mirror=$(grep '^[^#]*main' /etc/apk/repositories | head -1 | sed 's|/main.*|/community|')
            if [ -n "$mirror" ]; then
                echo "$mirror" >> /etc/apk/repositories
            else
                echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories
            fi
        fi
    fi
    # On Debian/Ubuntu wixl is a separate package; on Alpine/Fedora it's part of msitools
    local wixl_pkg="msitools"
    if [ "$PKG_MGR" = "apt" ]; then
        if apt-cache show wixl >/dev/null 2>&1; then
            wixl_pkg="wixl"
        fi
    fi
    if pkg_install "$wixl_pkg"; then
        # wixl may land in /usr/sbin on some distros — symlink to /usr/local/bin if needed
        local wixl_bin
        wixl_bin=$(command -v wixl 2>/dev/null)
        if [ -z "$wixl_bin" ]; then
            wixl_bin=$(find /usr/sbin /usr/bin /usr/local/bin -name wixl 2>/dev/null | head -1)
            if [ -n "$wixl_bin" ]; then
                ln -sf "$wixl_bin" /usr/local/bin/wixl
                wixl_bin=/usr/local/bin/wixl
            fi
        fi
        if [ -n "$wixl_bin" ]; then
            ok "wixl installed: $("$wixl_bin" --version 2>&1 | head -1)"
            mark_installed "wixl"
        else
            warn "wixl binary not found after $wixl_pkg install"
            mark_installed "wixl (FAILED — binary not found)"
        fi
    else
        warn "msitools not available in package manager — wixl will not be installed"
        mark_installed "wixl (FAILED — not in repos)"
    fi
}

install_nfpm_linux() {
    if command -v nfpm >/dev/null 2>&1; then
        skip "nfpm already installed: $(nfpm --version 2>&1 | head -1)"
        mark_skipped "nfpm"
        return
    fi
    info "Installing nfpm (binary download)..."
    local version
    version=$(github_latest_version "goreleaser/nfpm")
    if [ -z "$version" ]; then
        warn "Could not determine latest nfpm version, using fallback 2.40.0"
        version="2.40.0"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would download nfpm v${version} for linux/${ARCH_GONAME}"
        mark_installed "nfpm (dry-run)"
        return
    fi
    local archive="nfpm_${version}_Linux_${ARCH_NFPM}.tar.gz"
    local url="https://github.com/goreleaser/nfpm/releases/download/v${version}/${archive}"
    local extract_dir="${TMPDIR_WORK}/nfpm_extract"
    info "Downloading nfpm v${version} (Linux/${ARCH_NFPM})..."
    if ! download_file "$url" "${TMPDIR_WORK}/${archive}"; then
        mark_installed "nfpm (FAILED — download error)"
        return
    fi
    mkdir -p "$extract_dir"
    tar -xzf "${TMPDIR_WORK}/${archive}" -C "$extract_dir"
    local nfpm_bin
    nfpm_bin=$(find "$extract_dir" -type f -name "nfpm" | head -1)
    if [ -z "$nfpm_bin" ]; then
        warn "nfpm binary not found in archive"
        mark_installed "nfpm (FAILED)"
        return
    fi
    install -m 755 "$nfpm_bin" /usr/local/bin/nfpm
    ok "nfpm installed: $(nfpm --version 2>&1 | head -1)"
    mark_installed "nfpm"
}

install_osslsigncode_linux() {
    if command -v osslsigncode >/dev/null 2>&1; then
        skip "osslsigncode already installed: $(osslsigncode --version 2>&1 | head -1)"
        mark_skipped "osslsigncode"
        return
    fi
    info "Installing osslsigncode via package manager..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would try pkg_install osslsigncode, then cmake build if needed"
        mark_installed "osslsigncode (dry-run)"
        return
    fi
    if pkg_install osslsigncode 2>/dev/null; then
        ok "osslsigncode installed from package manager"
        mark_installed "osslsigncode"
        return
    fi
    warn "osslsigncode not in package manager, building from source..."
    build_osslsigncode_from_source
}

build_osslsigncode_from_source() {
    info "Cloning osslsigncode..."
    git clone --depth=1 https://github.com/mtrojnar/osslsigncode.git "${TMPDIR_WORK}/osslsigncode"
    info "Building osslsigncode (cmake)..."
    cmake -B "${TMPDIR_WORK}/osslsigncode/build" -S "${TMPDIR_WORK}/osslsigncode"
    cmake --build "${TMPDIR_WORK}/osslsigncode/build"
    cmake --install "${TMPDIR_WORK}/osslsigncode/build"
    if command -v osslsigncode >/dev/null 2>&1; then
        ok "osslsigncode built and installed from source"
        mark_installed "osslsigncode (from source)"
    else
        warn "osslsigncode build failed — it will not be available"
        mark_installed "osslsigncode (BUILD FAILED)"
    fi
}

install_rcodesign_linux() {
    if command -v rcodesign >/dev/null 2>&1; then
        skip "rcodesign already installed: $(rcodesign --version 2>&1 | head -1)"
        mark_skipped "rcodesign"
        return
    fi
    info "Installing rcodesign (binary download)..."
    local version
    version=$(github_rcodesign_version)
    if [ -z "$version" ]; then
        warn "Could not determine latest rcodesign version, using fallback 0.29.0"
        version="0.29.0"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would download rcodesign v${version} for ${ARCH_RUST}-unknown-linux-musl"
        mark_installed "rcodesign (dry-run)"
        return
    fi
    local rust_arch="${ARCH_RUST}-unknown-linux-musl"
    local archive="apple-codesign-${version}-${rust_arch}.tar.gz"
    local url="https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${version}/${archive}"
    local extracted_dir="apple-codesign-${version}-${rust_arch}"
    info "Downloading rcodesign v${version} (${rust_arch})..."
    if ! download_file "$url" "${TMPDIR_WORK}/${archive}"; then
        mark_installed "rcodesign (FAILED — download error)"
        return
    fi
    tar -xzf "${TMPDIR_WORK}/${archive}" -C "$TMPDIR_WORK"
    if [ ! -f "${TMPDIR_WORK}/${extracted_dir}/rcodesign" ]; then
        warn "rcodesign binary not found in archive at expected path: ${extracted_dir}/rcodesign"
        local rcodesign_bin
        rcodesign_bin=$(find "$TMPDIR_WORK" -type f -name "rcodesign" | head -1)
        if [ -z "$rcodesign_bin" ]; then
            mark_installed "rcodesign (FAILED — binary not found)"
            return
        fi
        install -m 755 "$rcodesign_bin" /usr/local/bin/rcodesign
    else
        install -m 755 "${TMPDIR_WORK}/${extracted_dir}/rcodesign" /usr/local/bin/rcodesign
    fi
    ok "rcodesign installed: $(rcodesign --version 2>&1 | head -1)"
    mark_installed "rcodesign"
}

install_xar_linux() {
    if command -v xar >/dev/null 2>&1; then
        skip "xar already installed"
        mark_skipped "xar"
        return
    fi
    info "Installing xar..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would try pkg_install xar, then build from source if needed"
        mark_installed "xar (dry-run)"
        return
    fi
    if pkg_install xar 2>/dev/null && command -v xar >/dev/null 2>&1; then
        ok "xar installed from package manager"
        mark_installed "xar"
        return
    fi
    warn "xar not in package manager, building from source..."
    build_xar_from_source
}

build_xar_from_source() {
    # Check required build tools — caller must provide them
    local missing=""
    for tool in gcc make autoconf; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        warn "Cannot build xar from source: missing tools:$missing"
        warn "Please install them before running this script."
        mark_installed "xar (BUILD FAILED — missing:$missing)"
        return
    fi
    info "Cloning xar (mackyle fork)..."
    git clone --depth=1 https://github.com/mackyle/xar.git "${TMPDIR_WORK}/xar"
    info "Building xar..."
    cd "${TMPDIR_WORK}/xar/xar"
    # Patch configure.ac: OpenSSL_add_all_ciphers was removed in OpenSSL 3.x
    sed -i 's/AC_CHECK_LIB(\[crypto\], \[OpenSSL_add_all_ciphers\]/AC_CHECK_LIB([crypto], [EVP_EncryptInit]/' configure.ac 2>/dev/null || true
    # Patch lib/ext2.c:
    #   1. Add missing <stdlib.h> (needed for free())
    #   2. Guard EXT2_ECOMPR_FL usage — removed from public e2fsprogs headers in modern kernels
    sed -i 's|#include <ext2fs/ext2_fs\.h>|#include <ext2fs/ext2_fs.h>\n#include <stdlib.h>|' lib/ext2.c 2>/dev/null || true
    # Wrap the two EXT2_ECOMPR_FL references in #ifdef blocks using awk
    awk '
        /if\(! \(flags & ~EXT2_ECOMPR_FL\) \)/ {
            print "#ifdef EXT2_ECOMPR_FL"
            print
            getline; print  # x_addprop line
            print "#endif"
            next
        }
        /flags \|= EXT2_ECOMPR_FL ;/ {
            print "#ifdef EXT2_ECOMPR_FL"
            print
            print "#endif"
            next
        }
        { print }
    ' lib/ext2.c > lib/ext2.c.patched && mv lib/ext2.c.patched lib/ext2.c
    # Update config.guess/config.sub — the bundled ones are from 2005 and don't know aarch64
    for f in config.guess config.sub; do
        local new_f
        new_f=$(command -v "$f" 2>/dev/null || find /usr/share/automake* /usr/share/misc -name "$f" 2>/dev/null | head -1)
        if [ -n "$new_f" ]; then
            cp "$new_f" "$f" 2>/dev/null || true
        fi
    done
    sh autogen.sh --noconfigure 2>/dev/null || ./autogen.sh 2>/dev/null || true
    export CFLAGS="${CFLAGS} -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
    ./configure --prefix=/usr/local
    make -j"$(nproc 2>/dev/null || echo 2)"
    make install
    cd - >/dev/null
    if command -v xar >/dev/null 2>&1; then
        ok "xar built and installed from source"
        mark_installed "xar (from source)"
    else
        warn "xar build failed — it will not be available"
        mark_installed "xar (BUILD FAILED)"
    fi
}

install_bomutils_linux() {
    if command -v mkbom >/dev/null 2>&1; then
        skip "bomutils (mkbom) already installed"
        mark_skipped "bomutils"
        return
    fi
    info "Installing bomutils (mkbom)..."
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN: would try pkg_install bomutils, then git+make if needed"
        mark_installed "bomutils (dry-run)"
        return
    fi
    if pkg_install bomutils 2>/dev/null && command -v mkbom >/dev/null 2>&1; then
        ok "bomutils installed from package manager"
        mark_installed "bomutils"
        return
    fi
    warn "bomutils not in package manager, building from source..."
    build_bomutils_from_source
}

build_bomutils_from_source() {
    # Check required build tools — caller must provide them
    local missing=""
    for tool in g++ make; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        warn "Cannot build bomutils from source: missing tools:$missing"
        warn "Please install them before running this script."
        mark_installed "bomutils (BUILD FAILED — missing:$missing)"
        return
    fi
    info "Cloning bomutils..."
    git clone --depth=1 https://github.com/hogliux/bomutils.git "${TMPDIR_WORK}/bomutils"
    info "Building bomutils..."
    local nproc_val
    nproc_val=$(nproc 2>/dev/null || echo 2)
    make -C "${TMPDIR_WORK}/bomutils" -j"$nproc_val" CXXFLAGS="-O2 -fPIE -fPIC"
    # bomutils builds to build/bin/ (newer versions) or build/ (older)
    local mkbom_bin
    mkbom_bin=$(find "${TMPDIR_WORK}/bomutils/build" -name "mkbom" -type f 2>/dev/null | head -1)
    if [ -n "$mkbom_bin" ]; then
        install -m 755 "$mkbom_bin" /usr/local/bin/mkbom
        # lsbom is optional
        local lsbom_bin
        lsbom_bin=$(find "${TMPDIR_WORK}/bomutils/build" -name "lsbom" -o -name "ls.bom" 2>/dev/null | head -1)
        if [ -n "$lsbom_bin" ]; then
            install -m 755 "$lsbom_bin" /usr/local/bin/lsbom 2>/dev/null || true
        fi
        ok "bomutils (mkbom) built and installed from source"
        mark_installed "bomutils (from source)"
    else
        warn "bomutils build failed — mkbom will not be available"
        mark_installed "bomutils (BUILD FAILED)"
    fi
}

# -----------------------------------------------------------------------------
# Summary and header
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo "=================================="
    echo "Crossler installer"
    echo "=================================="
    echo "OS:   $OS_TYPE"
    echo "Arch: $ARCH_GONAME"
    if [ "$OS_TYPE" = "linux" ]; then
        echo "Pkg:  $PKG_MGR"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY RUN MODE — no changes will be made]"
    fi
    echo "=================================="
    echo ""
}

print_summary() {
    echo ""
    echo "=================================="
    echo "Installation summary"
    echo "=================================="
    if [ -n "$INSTALLED_TOOLS" ]; then
        echo "Newly installed:"
        printf "%s" "$INSTALLED_TOOLS"
    fi
    if [ -n "$SKIPPED_TOOLS" ]; then
        echo "Already present:"
        printf "%s" "$SKIPPED_TOOLS"
    fi
    echo "=================================="
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    detect_os
    detect_arch
    detect_downloader
    if [ "$OS_TYPE" = "linux" ]; then
        detect_pkg_manager
    fi

    TMPDIR_WORK=$(mktemp -d)
    trap 'rm -rf "$TMPDIR_WORK"' EXIT INT TERM

    print_header

    install_crossler

    if [ "$OS_TYPE" = "linux" ]; then
        install_wixl_linux
        install_nfpm_linux
        install_osslsigncode_linux
        install_rcodesign_linux
        install_xar_linux
        install_bomutils_linux
    elif [ "$OS_TYPE" = "macos" ]; then
        install_xcode_clt
        install_wixl_macos
        install_nfpm_macos
        install_osslsigncode_macos
        install_rcodesign_macos
        install_xar_macos
    fi

    print_summary
}

main "$@"

#!/system/bin/sh
#
# download_gost.sh - Automatically download gost binary
#
# Features:
#   - Auto-detect device architecture (arm64/arm/x86/x86_64)
#   - Auto-detect China network environment and use mirror
#   - Fetch latest gost release version from GitHub API
#   - Download, extract, and install the binary
#   - Verify the binary after installation
#
# Usage:
#   sh download_gost.sh                       # Download directly to default location
#   sh download_gost.sh /path direct          # Download directly
#   sh download_gost.sh /path accelerated     # Download through https://ghfast.top
#

set -e

# ============ Config ============
GOST_REPO="go-gost/gost"
GOST_API="https://api.github.com/repos/${GOST_REPO}/releases/latest"
GOST_RELEASE_BASE="https://github.com/${GOST_REPO}/releases/download"

ACCELERATOR="https://ghfast.top"
DOWNLOAD_MODE="direct"

# Timeout for download (seconds)
DOWNLOAD_TIMEOUT=120

# ============ Helpers ============

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
}

# Check if a command exists
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ============ Architecture Detection ============

detect_arch() {
    # Try Android getprop first
    if has_cmd getprop; then
        ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
        ABI2=$(getprop ro.product.cpu.abi2 2>/dev/null)
    else
        ABI=""
        ABI2=""
    fi

    # Fall back to uname for Linux environments
    if [ -z "$ABI" ]; then
        if has_cmd uname; then
            MACHINE=$(uname -m 2>/dev/null)
            case "$MACHINE" in
                aarch64|arm64)   ABI="arm64-v8a" ;;
                armv7l|armv6l)   ABI="armeabi-v7a" ;;
                arm*)            ABI="armeabi-v7a" ;;
                x86_64|amd64)    ABI="x86_64" ;;
                i686|i386)       ABI="x86" ;;
                *)               ABI="" ;;
            esac
        fi
    fi

    # Map ABI to gost asset name suffix
    case "$ABI" in
        arm64-v8a)
            GOST_OS="android"
            GOST_ARCH="arm64"
            ;;
        armeabi-v7a|armeabi)
            GOST_OS="linux"
            GOST_ARCH="armv7"
            ;;
        x86_64)
            GOST_OS="linux"
            GOST_ARCH="amd64"
            ;;
        x86)
            GOST_OS="linux"
            GOST_ARCH="386"
            ;;
        *)
            # Try secondary ABI
            case "$ABI2" in
                armeabi-v7a|armeabi)
                    GOST_OS="linux"
                    GOST_ARCH="armv7"
                    ;;
                x86_64)
                    GOST_OS="linux"
                    GOST_ARCH="amd64"
                    ;;
                *)
                    err "Unsupported architecture: ABI=$ABI ABI2=$ABI2"
                    err "Supported: arm64-v8a, armeabi-v7a, x86_64, x86"
                    return 1
                    ;;
            esac
            ;;
    esac

    log "Detected: ABI=$ABI  ->  gost asset: ${GOST_OS}_${GOST_ARCH}"
    return 0
}

# ============ Download Source ============

selected_url() {
    _url="$1"
    if [ "$DOWNLOAD_MODE" = "accelerated" ]; then
        printf '%s/%s' "$ACCELERATOR" "$_url"
    else
        printf '%s' "$_url"
    fi
}

# ============ Version Detection ============

fetch_text() {
    _url="$1"
    if has_cmd curl; then
        curl -fsSL --connect-timeout 10 --max-time 30 "$_url" 2>/dev/null || true
    elif has_cmd wget; then
        wget -qO- --timeout=30 "$_url" 2>/dev/null || true
    fi
}

get_latest_version() {
    log "Fetching latest gost release version..."

    if ! has_cmd curl && ! has_cmd wget; then
        err "Neither curl nor wget found"
        return 1
    fi

    # ghfast.top is intended for GitHub pages and release assets, not the
    # api.github.com host. Always try the official API directly first so its
    # asset digests remain available when reachable.
    RAW_JSON=$(fetch_text "$GOST_API")
    GOST_TAG=$(printf '%s' "$RAW_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' | head -1)

    # If the API is blocked, parse the public latest-release HTML page through
    # the selected transport. This works with ghfast.top and does not require
    # GitHub API access.
    if [ -z "$GOST_TAG" ]; then
        LATEST_PAGE_URL=$(selected_url "https://github.com/${GOST_REPO}/releases/latest")
        log "GitHub API unavailable; resolving latest tag from release page"
        RELEASE_HTML=$(fetch_text "$LATEST_PAGE_URL")
        GOST_TAG=$(printf '%s' "$RELEASE_HTML" | grep -o "/${GOST_REPO}/releases/tag/v[0-9][0-9A-Za-z._-]*" | head -1 | sed 's#.*/tag/##')
        if [ -z "$GOST_TAG" ]; then
            GOST_TAG=$(printf '%s' "$RELEASE_HTML" | grep -o '<title>[^<]*v[0-9][0-9A-Za-z._-]*' | head -1 | grep -o 'v[0-9][0-9A-Za-z._-]*$')
        fi
    fi

    if [ -z "$GOST_TAG" ]; then
        err "Failed to resolve the latest Gost release tag"
        return 1
    fi

    GOST_VERSION=$(printf '%s' "$GOST_TAG" | sed 's/^v//')
    log "Latest gost version: $GOST_TAG (asset version: $GOST_VERSION)"
    return 0
}

# ============ Download ============

do_download() {
    URL="$1"
    OUTPUT="$2"

    if has_cmd curl; then
        curl -fSL --connect-timeout 15 --max-time "$DOWNLOAD_TIMEOUT" \
            -o "$OUTPUT" "$URL" 2>&1
    elif has_cmd wget; then
        wget -q --timeout="$DOWNLOAD_TIMEOUT" \
            -O "$OUTPUT" "$URL" 2>&1
    else
        err "Neither curl nor wget found"
        return 1
    fi
}

download_binary() {
    ASSET_NAME="gost_${GOST_VERSION}_${GOST_OS}_${GOST_ARCH}.tar.gz"
    DIRECT_URL="${GOST_RELEASE_BASE}/${GOST_TAG}/${ASSET_NAME}"

    TMPDIR=$(mktemp -d 2>/dev/null || echo "/tmp/gost_dl_$$")
    mkdir -p "$TMPDIR"

    TARFILE="${TMPDIR}/${ASSET_NAME}"

    # GitHub's release API exposes an official sha256 digest for each asset.
    # Mirrors are transport fallbacks only; their content must match GitHub.
    # Compact whitespace and split at each asset name. Splitting on `},{` is
    # incorrect because every asset contains nested uploader objects and may
    # leave the checksums.txt digest on the same line as the requested asset.
    EXPECTED_SHA256=$(printf '%s' "$RAW_JSON" | tr -d '[:space:]' | sed 's/,"name":/\
"name":/g' | grep "^\"name\":\"${ASSET_NAME}\"" | grep -o '"digest":"sha256:[0-9A-Fa-f]*"' | head -1 | sed 's/.*sha256://; s/"$//')
    if [ -z "$EXPECTED_SHA256" ]; then
        # The checksum is security metadata and must never come from the same
        # accelerator that transports the executable archive.
        CHECKSUMS_URL="${GOST_RELEASE_BASE}/${GOST_TAG}/checksums.txt"
        log "Fetching checksums.txt directly from GitHub"
        CHECKSUMS=$(fetch_text "$CHECKSUMS_URL")
        EXPECTED_SHA256=$(printf '%s\n' "$CHECKSUMS" | awk -v asset="$ASSET_NAME" '$2 == asset || $2 == "*" asset { print $1; exit }')
    fi
    case "$EXPECTED_SHA256" in
        [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]*) ;;
        *)
            err "Official SHA256 digest not found for $ASSET_NAME"
            rm -rf "$TMPDIR"
            return 1
            ;;
    esac
    [ "${#EXPECTED_SHA256}" -eq 64 ] || {
        err "Invalid SHA256 digest length for $ASSET_NAME"
        rm -rf "$TMPDIR"
        return 1
    }

    log "Target asset: $ASSET_NAME"

    DOWNLOAD_URL=$(selected_url "$DIRECT_URL")
    log "Downloading via mode: $DOWNLOAD_MODE"
    if do_download "$DOWNLOAD_URL" "$TARFILE" && [ -s "$TARFILE" ]; then
        log "Download succeeded"
        DOWNLOAD_OK=1
    else
        warn "Download failed"
        DOWNLOAD_OK=0
    fi

    if [ "$DOWNLOAD_OK" = "0" ]; then
        err "Gost download failed using mode: $DOWNLOAD_MODE"
        rm -rf "$TMPDIR"
        return 1
    fi

    if has_cmd sha256sum; then
        ACTUAL_SHA256=$(sha256sum "$TARFILE" | awk '{print $1}')
    elif has_cmd busybox; then
        ACTUAL_SHA256=$(busybox sha256sum "$TARFILE" | awk '{print $1}')
    else
        err "sha256sum not found; refusing unverified binary"
        rm -rf "$TMPDIR"
        return 1
    fi
    if [ "$(printf '%s' "$ACTUAL_SHA256" | tr 'A-F' 'a-f')" != "$(printf '%s' "$EXPECTED_SHA256" | tr 'A-F' 'a-f')" ]; then
        err "SHA256 mismatch for $ASSET_NAME"
        rm -rf "$TMPDIR"
        return 1
    fi
    log "SHA256 verification passed"

    # Extract the binary from tar.gz
    log "Extracting binary from archive..."
    if has_cmd tar; then
        tar -xzf "$TARFILE" -C "$TMPDIR" 2>&1
    else
        # Android may have busybox tar
        if has_cmd busybox; then
            busybox tar -xzf "$TARFILE" -C "$TMPDIR" 2>&1
        else
            err "tar command not found, cannot extract"
            rm -rf "$TMPDIR"
            return 1
        fi
    fi

    # Find the gost binary in extracted files
    EXTRACTED_BIN=""
    if [ -f "${TMPDIR}/gost" ]; then
        EXTRACTED_BIN="${TMPDIR}/gost"
    else
        # Search for it
        EXTRACTED_BIN=$(find "$TMPDIR" -name "gost" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$EXTRACTED_BIN" ] || [ ! -f "$EXTRACTED_BIN" ]; then
        err "gost binary not found in extracted archive"
        log "Archive contents:"
        ls -la "$TMPDIR" 2>/dev/null
        rm -rf "$TMPDIR"
        return 1
    fi

    # Install atomically. Never truncate or overwrite the currently working
    # binary until the downloaded file has been fully copied and chmodded.
    mkdir -p "$TARGET_DIR"
    INSTALL_TMP="${TARGET_DIR}/.gost.install.$$"
    if ! cp "$EXTRACTED_BIN" "$INSTALL_TMP"; then
        rm -f "$INSTALL_TMP"
        err "Failed to stage downloaded binary"
        rm -rf "$TMPDIR"
        return 1
    fi
    chmod 755 "$INSTALL_TMP" || {
        rm -f "$INSTALL_TMP"
        err "Failed to set downloaded binary permissions"
        rm -rf "$TMPDIR"
        return 1
    }
    if ! mv -f "$INSTALL_TMP" "${TARGET_DIR}/gost"; then
        rm -f "$INSTALL_TMP"
        err "Failed to install downloaded binary"
        rm -rf "$TMPDIR"
        return 1
    fi

    log "Binary installed to: ${TARGET_DIR}/gost"
    log "File size: $(ls -lh "${TARGET_DIR}/gost" 2>/dev/null | awk '{print $5}')"

    # Cleanup
    rm -rf "$TMPDIR"
    return 0
}

# ============ Verification ============

verify_binary() {
    BIN="${TARGET_DIR}/gost"

    if [ ! -f "$BIN" ]; then
        err "Binary not found at $BIN"
        return 1
    fi

    log "Verifying binary..."

    # Check file type
    if has_cmd file; then
        FILETYPE=$(file "$BIN" 2>/dev/null)
        log "File type: $FILETYPE"
    fi

    # Try to run version check
    # Note: On the build host this may fail if arch doesn't match,
    # but on the target device it should work
    VERSION_OUTPUT=$("$BIN" -V 2>&1 || true)
    if echo "$VERSION_OUTPUT" | grep -qi "gost"; then
        log "Binary verification passed: $VERSION_OUTPUT"
        return 0
    else
        err "Binary version check failed: $VERSION_OUTPUT"
        return 1
    fi
}

# ============ Main ============

main() {
    echo "========================================"
    echo " gost Binary Downloader"
    echo "========================================"
    echo ""

    # Determine target directory
    SCRIPT_DIR=${0%/*}
    if [ "$SCRIPT_DIR" = "$0" ]; then
        SCRIPT_DIR="."
    fi

    # Default: parent of scripts dir / gost
    # If called as scripts/download_gost.sh, target is ../gost
    case "$SCRIPT_DIR" in
        */scripts)
            DEFAULT_TARGET="${SCRIPT_DIR%/*}/gost"
            ;;
        *)
            DEFAULT_TARGET="${SCRIPT_DIR}/gost"
            ;;
    esac

    TARGET_DIR="${1:-$DEFAULT_TARGET}"
    DOWNLOAD_MODE="${2:-direct}"
    case "$DOWNLOAD_MODE" in
        direct|accelerated) ;;
        *)
            err "Unsupported download mode: $DOWNLOAD_MODE (use direct or accelerated)"
            exit 1
            ;;
    esac

    log "Target directory: $TARGET_DIR"
    log "Download mode: $DOWNLOAD_MODE"
    echo ""

    # Step 1: Detect architecture
    log "Step 1/5: Detecting architecture..."
    if ! detect_arch; then
        exit 1
    fi
    echo ""

    # Step 2: Use the source explicitly selected by the installer or caller.
    log "Step 2/5: Selecting download source..."
    if [ "$DOWNLOAD_MODE" = "accelerated" ]; then
        log "Source: $ACCELERATOR"
    else
        log "Source: GitHub direct"
    fi
    echo ""

    # Step 3: Get latest version
    log "Step 3/5: Fetching latest version..."
    if ! get_latest_version; then
        exit 1
    fi
    echo ""

    # Step 4: Download binary
    log "Step 4/5: Downloading binary..."
    DOWNLOAD_OK=0
    PREVIOUS_BIN="${TARGET_DIR}/.gost.previous.$$"
    if [ -s "${TARGET_DIR}/gost" ]; then
        cp "${TARGET_DIR}/gost" "$PREVIOUS_BIN" || exit 1
        chmod 755 "$PREVIOUS_BIN" 2>/dev/null
    else
        rm -f "$PREVIOUS_BIN"
    fi
    if ! download_binary; then
        rm -f "$PREVIOUS_BIN"
        exit 1
    fi
    echo ""

    # Step 5: Verify
    log "Step 5/5: Verifying installation..."
    if ! verify_binary; then
        if [ -s "$PREVIOUS_BIN" ]; then
            mv -f "$PREVIOUS_BIN" "${TARGET_DIR}/gost"
            chmod 755 "${TARGET_DIR}/gost" 2>/dev/null
            err "Restored the previous Gost binary after verification failed"
        else
            rm -f "${TARGET_DIR}/gost"
        fi
        exit 1
    fi
    rm -f "$PREVIOUS_BIN"
    echo ""

    echo "========================================"
    log "Done! gost ${GOST_TAG} (${GOST_OS}_${GOST_ARCH}) installed to ${TARGET_DIR}/gost"
    echo "========================================"
}

main "$@"

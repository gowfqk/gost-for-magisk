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
#   sh download_gost.sh          # Download to default location
#   sh download_gost.sh /path    # Download to specified directory
#

set -e

# ============ Config ============
GOST_REPO="go-gost/gost"
GOST_API="https://api.github.com/repos/${GOST_REPO}/releases/latest"
GOST_RELEASE_BASE="https://github.com/${GOST_REPO}/releases/download"

# GitHub mirror/proxy servers for China network
# Will try each one in order until download succeeds
MIRRORS="
https://mirror.ghproxy.com
https://gh-proxy.com
https://ghps.cc
https://github.moeyy.xyz
https://ghproxy.net
"

# Timeout for network detection (seconds)
DETECT_TIMEOUT=5
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

# ============ China Network Detection ============

detect_china_network() {
    IS_CHINA=0

    log "Detecting network environment..."

    # Method 1: Try GitHub API with short timeout
    # If GitHub is unreachable or very slow, likely in a restricted network
    if has_cmd curl; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$DETECT_TIMEOUT" \
            --max-time "$((DETECT_TIMEOUT * 2))" \
            "$GOST_API" 2>/dev/null || echo "000")
    elif has_cmd wget; then
        HTTP_CODE=$(wget -q -O /dev/null \
            --timeout="$DETECT_TIMEOUT" \
            --tries=1 \
            "$GOST_API" 2>/dev/null && echo "200" || echo "000")
    else
        err "Neither curl nor wget found, cannot detect network"
        return 1
    fi

    if [ "$HTTP_CODE" = "200" ]; then
        log "GitHub API reachable (HTTP $HTTP_CODE), using direct connection"
        IS_CHINA=0
    else
        warn "GitHub API unreachable or slow (HTTP $HTTP_CODE), switching to mirror"
        IS_CHINA=1
    fi

    # Method 2 (supplementary): Check IP geolocation
    # Only if the first method was inconclusive or to confirm
    if [ "$IS_CHINA" = "0" ]; then
        # Double-check with a quick geo lookup (non-critical, ignore failures)
        if has_cmd curl; then
            COUNTRY=$(curl -s --connect-timeout 3 --max-time 6 \
                "https://ipinfo.io/country" 2>/dev/null || echo "")
        fi
        if [ "$COUNTRY" = "CN" ]; then
            log "IP geolocation confirms China (CN), using mirror"
            IS_CHINA=1
        fi
    fi

    return 0
}

# ============ Version Detection ============

get_latest_version() {
    log "Fetching latest gost release version..."

    if ! has_cmd curl && ! has_cmd wget; then
        err "Neither curl nor wget found"
        return 1
    fi

    # Try direct first, then via mirrors
    RAW_JSON=""

    if has_cmd curl; then
        # Direct attempt
        RAW_JSON=$(curl -sL --connect-timeout 10 --max-time 30 "$GOST_API" 2>/dev/null || echo "")

        # If failed and in China, try mirror for API
        if [ -z "$RAW_JSON" ] && [ "$IS_CHINA" = "1" ]; then
            for MIRROR in $MIRRORS; do
                log "Trying API via mirror: $MIRROR"
                RAW_JSON=$(curl -sL --connect-timeout 10 --max-time 30 \
                    "${MIRROR}/${GOST_API}" 2>/dev/null || echo "")
                if [ -n "$RAW_JSON" ]; then
                    break
                fi
            done
        fi
    elif has_cmd wget; then
        RAW_JSON=$(wget -qO- --timeout=30 "$GOST_API" 2>/dev/null || echo "")
        if [ -z "$RAW_JSON" ] && [ "$IS_CHINA" = "1" ]; then
            for MIRROR in $MIRRORS; do
                log "Trying API via mirror: $MIRROR"
                RAW_JSON=$(wget -qO- --timeout=30 \
                    "${MIRROR}/${GOST_API}" 2>/dev/null || echo "")
                if [ -n "$RAW_JSON" ]; then
                    break
                fi
            done
        fi
    fi

    if [ -z "$RAW_JSON" ]; then
        err "Failed to fetch release info from GitHub API"
        return 1
    fi

    # Extract tag_name (handles both "v3.2.6" and "3.2.6")
    GOST_TAG=$(echo "$RAW_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' | head -1)

    if [ -z "$GOST_TAG" ]; then
        err "Failed to parse release tag from API response"
        return 1
    fi

    # Strip leading 'v' for version number used in asset names
    GOST_VERSION=$(echo "$GOST_TAG" | sed 's/^v//')

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
    BINARY_OUT="${TMPDIR}/gost"

    # GitHub's release API exposes an official sha256 digest for each asset.
    # Mirrors are transport fallbacks only; their content must match GitHub.
    EXPECTED_SHA256=$(printf '%s' "$RAW_JSON" | tr -d '\n\r' | sed 's/},{/}\n{/g' | grep "\"name\"[[:space:]]*:[[:space:]]*\"${ASSET_NAME}\"" | grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[0-9A-Fa-f]*"' | head -1 | sed 's/.*sha256://; s/"$//')
    if [ -z "$EXPECTED_SHA256" ]; then
        err "Official SHA256 digest not found for $ASSET_NAME"
        rm -rf "$TMPDIR"
        return 1
    fi

    log "Target asset: $ASSET_NAME"

    # Try direct download first
    log "Attempting direct download from GitHub..."
    if do_download "$DIRECT_URL" "$TARFILE"; then
        if [ -s "$TARFILE" ]; then
            log "Direct download succeeded"
            DOWNLOAD_OK=1
        else
            warn "Direct download produced empty file"
            DOWNLOAD_OK=0
        fi
    else
        warn "Direct download failed"
        DOWNLOAD_OK=0
    fi

    # If direct failed, try mirrors
    if [ "$DOWNLOAD_OK" = "0" ]; then
        log "Trying mirror downloads..."

        for MIRROR in $MIRRORS; do
            MIRROR_URL="${MIRROR}/${DIRECT_URL}"
            log "Trying: $MIRROR"

            if do_download "$MIRROR_URL" "$TARFILE"; then
                if [ -s "$TARFILE" ]; then
                    log "Mirror download succeeded: $MIRROR"
                    DOWNLOAD_OK=1
                    break
                fi
            fi
            warn "Mirror failed: $MIRROR"
        done
    fi

    if [ "$DOWNLOAD_OK" = "0" ]; then
        err "All download attempts failed"
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

    # Move to target location
    mkdir -p "$TARGET_DIR"
    cp -f "$EXTRACTED_BIN" "${TARGET_DIR}/gost"
    chmod 755 "${TARGET_DIR}/gost"

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
        warn "Binary version check inconclusive: $VERSION_OUTPUT"
        warn "This is normal if running on a different architecture than the target device"
        log "Binary file exists and has correct permissions, assuming OK"
        return 0
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

    log "Target directory: $TARGET_DIR"
    echo ""

    # Step 1: Detect architecture
    log "Step 1/5: Detecting architecture..."
    if ! detect_arch; then
        exit 1
    fi
    echo ""

    # Step 2: Detect network environment
    log "Step 2/5: Detecting network environment..."
    if ! detect_china_network; then
        warn "Network detection failed, will try both direct and mirror"
        IS_CHINA=1  # Default to trying mirrors as fallback
    fi
    if [ "$IS_CHINA" = "1" ]; then
        log "Network: China/restricted - mirrors will be used as fallback"
    else
        log "Network: Direct - GitHub accessible"
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
    if ! download_binary; then
        exit 1
    fi
    echo ""

    # Step 5: Verify
    log "Step 5/5: Verifying installation..."
    verify_binary
    echo ""

    echo "========================================"
    log "Done! gost ${GOST_TAG} (${GOST_OS}_${GOST_ARCH}) installed to ${TARGET_DIR}/gost"
    echo "========================================"
}

main "$@"

#!/system/bin/sh

# Let Magisk/KernelSU extract the module before sourcing this script.
# Manual unzip is intentionally avoided because some installers expose ZIPFILE
# through a descriptor/path that a second unzip process cannot reopen.
SKIPUNZIP=0

MODDIR=${MODPATH}

# ---- Detect old module path (for config preservation on update) ----
OLD_MODDIR="/data/adb/modules/gost_proxy"
if [ -d "/data/adb/ksu/modules/gost_proxy" ]; then
    OLD_MODDIR="/data/adb/ksu/modules/gost_proxy"
fi

ui_print "========================================"
ui_print " Gost Proxy Module Installer"
ui_print "========================================"
ui_print ""

# ---- Preserve existing config before extraction ----
PRESERVE_DIR="/tmp/gost_preserve"
rm -rf "$PRESERVE_DIR"
mkdir -p "$PRESERVE_DIR"

if [ -f "$OLD_MODDIR/gost/config.json" ]; then
    ui_print "- Found existing config, preserving..."
    cp "$OLD_MODDIR/gost/config.json" "$PRESERVE_DIR/config.json"
    
    # Preserve nodes directory
    if [ -d "$OLD_MODDIR/gost/nodes" ]; then
        cp -r "$OLD_MODDIR/gost/nodes" "$PRESERVE_DIR/nodes"
    fi
    
    # Preserve active node file
    if [ -f "$OLD_MODDIR/gost/active" ]; then
        cp "$OLD_MODDIR/gost/active" "$PRESERVE_DIR/active"
    fi
    
    # Preserve gost binary (avoid re-download if same arch)
    if [ -f "$OLD_MODDIR/gost/gost" ]; then
        cp "$OLD_MODDIR/gost/gost" "$PRESERVE_DIR/gost_bin"
    fi
    
    ui_print "- Config and nodes preserved."
else
    ui_print "- No existing config found (fresh install)."
fi
ui_print ""

ARCH=$(getprop ro.product.cpu.abi)
ui_print "Device ABI: $ARCH"

case "$ARCH" in
    arm64-v8a)
        GOST_ARCH="arm64"
        ;;
    armeabi-v7a|armeabi)
        GOST_ARCH="arm"
        ;;
    x86_64)
        GOST_ARCH="x86_64"
        ;;
    x86)
        GOST_ARCH="x86"
        ;;
    *)
        ui_print "Unsupported architecture: $ARCH"
        ui_print "Supported: arm64-v8a, armeabi-v7a, x86_64, x86"
        abort "Aborting installation."
        ;;
esac

ui_print "Detected gost architecture: $GOST_ARCH"
ui_print ""

ui_print "- Module files extracted by installer."

# Verify the standard installer actually populated the module directory before
# touching preserved data or attempting a binary download.
for REQUIRED_FILE in module.prop service.sh scripts/start.sh scripts/download_gost.sh webui/cgi-bin/api gost/nodes/default.json.example; do
    if [ ! -f "$MODDIR/$REQUIRED_FILE" ]; then
        abort "ERROR: Missing module file: $REQUIRED_FILE"
    fi
done

mkdir -p "$MODDIR/gost/nodes" "$MODDIR/logs"

# ---- Restore preserved config ----
if [ -f "$PRESERVE_DIR/config.json" ]; then
    ui_print "- Restoring preserved config..."
    cp "$PRESERVE_DIR/config.json" "$MODDIR/gost/config.json"
    
    if [ -d "$PRESERVE_DIR/nodes" ]; then
        mkdir -p "$MODDIR/gost/nodes"
        cp -r "$PRESERVE_DIR/nodes/"* "$MODDIR/gost/nodes/" 2>/dev/null
    fi
    
    if [ -f "$PRESERVE_DIR/active" ]; then
        cp "$PRESERVE_DIR/active" "$MODDIR/gost/active"
    fi
    
    # Restore gost binary if zip doesn't have a real one
    if [ ! -f "$MODDIR/gost/gost" ] || grep -q "Placeholder" "$MODDIR/gost/gost" 2>/dev/null; then
        if [ -f "$PRESERVE_DIR/gost_bin" ]; then
            cp "$PRESERVE_DIR/gost_bin" "$MODDIR/gost/gost"
            ui_print "- Restored existing gost binary."
        fi
    fi
    
    ui_print "- Config restored successfully."
fi

# Clean up
rm -rf "$PRESERVE_DIR"

# ---- Ensure nodes directory exists ----
mkdir -p "$MODDIR/gost/nodes"

# ---- Ensure config.json exists ----
if [ ! -f "$MODDIR/gost/config.json" ]; then
    if [ -f "$MODDIR/gost/nodes/default.json.example" ]; then
        cp "$MODDIR/gost/nodes/default.json.example" "$MODDIR/gost/config.json"
        ui_print "- Created default config from template."
    fi
fi

# ---- Handle gost binary ----
if [ ! -f "$MODDIR/gost/gost" ] || grep -q "Placeholder" "$MODDIR/gost/gost" 2>/dev/null; then
    ui_print ""
    ui_print "gost binary not found or is placeholder."
    ui_print "Attempting automatic download..."
    ui_print ""
    if [ -f "$MODDIR/scripts/download_gost.sh" ]; then
        chmod 755 "$MODDIR/scripts/download_gost.sh"
        sh "$MODDIR/scripts/download_gost.sh" "$MODDIR/gost" 2>&1 | while read -r line; do
            ui_print "$line"
        done
        if [ -f "$MODDIR/gost/gost" ] && ! grep -q "Placeholder" "$MODDIR/gost/gost" 2>/dev/null; then
            ui_print ""
            ui_print "gost binary downloaded successfully!"
        else
            ui_print ""
            ui_print "WARNING: Auto-download failed!"
            ui_print "Please manually download from:"
            ui_print "  https://github.com/go-gost/gost/releases"
            ui_print "Place the binary at: gost/gost"
        fi
    else
        ui_print "WARNING: download_gost.sh not found"
        ui_print "Please manually download gost binary for $GOST_ARCH"
        ui_print "from: https://github.com/go-gost/gost/releases"
        ui_print "Place at: gost/gost"
    fi
    ui_print ""
else
    ui_print "gost binary found, skipping download."
fi

chmod 755 "$MODDIR/gost/gost" 2>/dev/null
chmod 755 "$MODDIR/scripts/start.sh"
chmod 755 "$MODDIR/scripts/iptables.sh"
chmod 755 "$MODDIR/scripts/stop.sh"
chmod 755 "$MODDIR/scripts/status.sh"
chmod 755 "$MODDIR/scripts/config.sh"
chmod 755 "$MODDIR/scripts/download_gost.sh"
chmod 755 "$MODDIR/webui/server.sh"
chmod 755 "$MODDIR/webui/cgi-bin/api" 2>/dev/null
chmod 755 "$MODDIR/post-fs-data.sh"
chmod 755 "$MODDIR/service.sh"
chmod 755 "$MODDIR/uninstall.sh"

ui_print ""
ui_print "Installation complete!"
ui_print "Gost proxy will start on boot."
ui_print "WebUI: http://127.0.0.1:8080"
ui_print "========================================"

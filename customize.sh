#!/system/bin/sh

SKIPUNZIP=1

MODDIR=${MODPATH}

ui_print "========================================"
ui_print " Gost Proxy Module Installer"
ui_print "========================================"
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

ui_print "Creating module directories..."
mkdir -p "$MODDIR/gost"
mkdir -p "$MODDIR/webui"
mkdir -p "$MODDIR/scripts"
mkdir -p "$MODDIR/system"
mkdir -p "$MODDIR/logs"

ui_print "Extracting module files..."
unzip -o "$ZIPFILE" -d "$MODDIR" >/dev/null 2>&1

if [ ! -f "$MODDIR/gost/gost" ]; then
    ui_print ""
    ui_print "WARNING: gost binary not found!"
    ui_print "Please place the gost binary for $GOST_ARCH in gost/gost/"
    ui_print "before installing this module."
    ui_print ""
fi

chmod 755 "$MODDIR/gost/gost" 2>/dev/null
chmod 755 "$MODDIR/scripts/start.sh"
chmod 755 "$MODDIR/scripts/stop.sh"
chmod 755 "$MODDIR/scripts/status.sh"
chmod 755 "$MODDIR/scripts/config.sh"
chmod 755 "$MODDIR/post-fs-data.sh"
chmod 755 "$MODDIR/service.sh"
chmod 755 "$MODDIR/uninstall.sh"

if command -v python3 >/dev/null 2>&1; then
    ui_print "Python3 detected - WebUI will be available."
else
    ui_print "WARNING: Python3 not found."
    ui_print "WebUI requires Python3. Install via Termux if needed."
fi

ui_print ""
ui_print "Installation complete!"
ui_print "Gost proxy will start on boot."
ui_print "WebUI will be available at http://127.0.0.1:8080"
ui_print "========================================"

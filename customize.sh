#!/system/bin/sh

# Let Magisk/KernelSU extract the module before sourcing this script.
# Manual unzip is intentionally avoided because some installers expose ZIPFILE
# through a descriptor/path that a second unzip process cannot reopen.
SKIPUNZIP=0

# KernelSU may expose MODPATH as a path relative to /data/adb (for example
# modules_update/gost_proxy). Normalize it before any file checks or writes.
case "$MODPATH" in
    /*) MODDIR="$MODPATH" ;;
    *)  MODDIR="/data/adb/$MODPATH" ;;
esac

ui_print "- Target module directory: $MODDIR"

# ---- Detect old module path (for config preservation on update) ----
# Different root managers expose the currently installed module in different
# locations while MODPATH points at the new staging directory.
OLD_MODDIR=""
for _candidate in \
    /data/adb/modules/gost_proxy \
    /data/adb/modules_update/gost_proxy \
    /data/adb/ksu/modules/gost_proxy \
    /data/adb/ksu/modules_update/gost_proxy \
    /data/adb/ap/modules/gost_proxy \
    /data/adb/ap/modules_update/gost_proxy; do
    if [ -d "$_candidate" ] && [ "$_candidate" != "$MODDIR" ]; then
        OLD_MODDIR="$_candidate"
        break
    fi
done

ui_print "========================================"
ui_print " Gost Proxy Module Installer"
ui_print "========================================"
ui_print ""

# ---- Preserve existing config before extraction ----
# Gost itself is intentionally not preserved: every installation downloads a
# fresh, checksum-verified binary from the source selected with the volume keys.
PRESERVE_DIR="/tmp/gost_preserve"
PERSIST_DIR="/data/adb/gost_proxy"
rm -rf "$PRESERVE_DIR"
mkdir -p "$PRESERVE_DIR"

if [ -n "$OLD_MODDIR" ] && [ -f "$OLD_MODDIR/gost/config.json" ]; then
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

    # Preserve geodata cache (avoid re-download)
    if [ -d "$OLD_MODDIR/gost/geodata" ]; then
        cp -r "$OLD_MODDIR/gost/geodata" "$PRESERVE_DIR/geodata"
    fi

    # Preserve geoview tool
    if [ -f "$OLD_MODDIR/gost/tools/geoview" ]; then
        cp "$OLD_MODDIR/gost/tools/geoview" "$PRESERVE_DIR/geoview"
    fi

    ui_print "- Config, nodes, and geodata preserved."
else
    ui_print "- No existing config found."
fi
ui_print ""

ARCH=$(getprop ro.product.cpu.abi)
ui_print "Device ABI: $ARCH"

case "$ARCH" in
    arm64-v8a)
        GOST_ARCH="arm64"
        ;;
    *)
        ui_print "Unsupported architecture: $ARCH"
        ui_print "Supported: arm64-v8a only"
        abort "Aborting installation."
        ;;
esac

ui_print "Detected gost architecture: $GOST_ARCH"
ui_print ""

ui_print "- Module files extracted by installer."

# Verify the standard installer actually populated the module directory before
# touching preserved data or finishing the offline installation.
for REQUIRED_FILE in module.prop service.sh scripts/start.sh scripts/dns_filter.sh scripts/download_gost.sh scripts/update_geodata.sh webui/cgi-bin/api gost/nodes/default.json.example dns/ipv4-only-domains.txt dns/bin/dns-filter-arm64; do
    if [ ! -f "$MODDIR/$REQUIRED_FILE" ]; then
        abort "ERROR: Missing module file: $REQUIRED_FILE"
    fi
done

mkdir -p "$MODDIR/gost/nodes" "$MODDIR/gost/geodata" "$MODDIR/gost/tools" "$MODDIR/logs"

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

    # Restore geodata cache
    mkdir -p "$MODDIR/gost/geodata" "$MODDIR/gost/tools"
    if [ -d "$PRESERVE_DIR/geodata" ]; then
        cp -r "$PRESERVE_DIR/geodata/"* "$MODDIR/gost/geodata/" 2>/dev/null
        ui_print "- Restored geodata cache."
    fi
    if [ -f "$PRESERVE_DIR/geoview" ]; then
        cp "$PRESERVE_DIR/geoview" "$MODDIR/gost/tools/geoview"
        chmod 755 "$MODDIR/gost/tools/geoview"
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

# ---- Optional Gost download with volume keys ----
GETEVENT=$(command -v getevent 2>/dev/null)
[ -z "$GETEVENT" ] && [ -x /system/bin/getevent ] && GETEVENT=/system/bin/getevent

wait_volume_key() {
    [ -n "$GETEVENT" ] || return 2
    while :; do
        KEY_EVENT=$($GETEVENT -qlc 1 2>/dev/null)
        case "$KEY_EVENT" in
            *KEY_VOLUMEUP*|*VOLUMEUP*) return 0 ;;
            *KEY_VOLUMEDOWN*|*VOLUMEDOWN*) return 1 ;;
        esac
    done
}

ui_print ""
ui_print "Download the latest Gost during installation?"
ui_print "  Volume Up   = download now"
ui_print "  Volume Down = skip (download later in WebUI)"
ui_print ""

DOWNLOAD_GOST=false
wait_volume_key
KEY_RESULT=$?
case "$KEY_RESULT" in
    0) DOWNLOAD_GOST=true ;;
    1) DOWNLOAD_GOST=false ;;
    *)
        DOWNLOAD_GOST=false
        ui_print "- Volume-key input unavailable; skipping Gost download."
        ;;
esac

# Never silently restore an old persistent binary when download was skipped.
# The WebUI remains available and can download Gost later.
rm -f "$MODDIR/gost/gost" "$PERSIST_DIR/gost" 2>/dev/null

if [ "$DOWNLOAD_GOST" = "true" ]; then
    ui_print ""
    ui_print "Choose Gost download source:"
    ui_print "  Volume Up   = use https://ghfast.top accelerator"
    ui_print "  Volume Down = download directly from GitHub"
    ui_print ""

    DOWNLOAD_MODE="direct"
    wait_volume_key
    KEY_RESULT=$?
    case "$KEY_RESULT" in
        0) DOWNLOAD_MODE="accelerated" ;;
        1) DOWNLOAD_MODE="direct" ;;
        *) ui_print "- Volume-key input unavailable; using GitHub direct." ;;
    esac

    if [ "$DOWNLOAD_MODE" = "accelerated" ]; then
        ui_print "- Selected accelerated download: https://ghfast.top"
    else
        ui_print "- Selected direct GitHub download."
    fi

    ui_print "- Downloading the latest Gost binary..."
    if ! sh "$MODDIR/scripts/download_gost.sh" "$MODDIR/gost" "$DOWNLOAD_MODE"; then
        abort "ERROR: Gost download failed. Check the network or reinstall and choose the other source."
    fi
    if [ ! -s "$MODDIR/gost/gost" ]; then
        abort "ERROR: Downloaded Gost binary is missing."
    fi
    chmod 755 "$MODDIR/gost/gost"
    GOST_VERSION_OUTPUT=$("$MODDIR/gost/gost" -V 2>&1 || true)
    if ! printf '%s' "$GOST_VERSION_OUTPUT" | grep -qi 'gost'; then
        abort "ERROR: Downloaded Gost binary failed the version check: $GOST_VERSION_OUTPUT"
    fi
    ui_print "- Fresh Gost binary downloaded and verified: $GOST_VERSION_OUTPUT"
else
    ui_print "- Gost download skipped. Open WebUI after installation to download it."
fi

chmod 755 "$MODDIR/gost/gost" 2>/dev/null
chmod 755 "$MODDIR/scripts/start.sh"
chmod 755 "$MODDIR/scripts/iptables.sh"
chmod 755 "$MODDIR/scripts/dns_filter.sh"
chmod 755 "$MODDIR/scripts/stop.sh"
chmod 755 "$MODDIR/scripts/status.sh"
chmod 755 "$MODDIR/scripts/test_proxy.sh"
chmod 755 "$MODDIR/scripts/config.sh"
chmod 755 "$MODDIR/scripts/download_gost.sh"
chmod 755 "$MODDIR/scripts/update_geodata.sh"
chmod 755 "$MODDIR/webui/server.sh"
chmod 755 "$MODDIR/webui/cgi-bin/api" 2>/dev/null
chmod 755 "$MODDIR/post-fs-data.sh"
chmod 755 "$MODDIR/service.sh"
chmod 755 "$MODDIR/uninstall.sh"
chmod 755 "$MODDIR/dns/bin/"* 2>/dev/null

# ---- Remove legacy IPv6 fallback rule ----
# v1.9.19 installed a global public-IPv6 TCP REJECT chain. On IPv6-only/NAT64
# networks this can cut off connectivity instead of causing an IPv4 retry.
# Remove the live rule immediately during update; no reboot is required.
IP6T=$(command -v ip6tables 2>/dev/null)
[ -z "$IP6T" ] && IP6T="/system/bin/ip6tables"
if [ -x "$IP6T" ]; then
    while "$IP6T" -t filter -C OUTPUT -p tcp -j GOST_IPV6_FALLBACK 2>/dev/null; do
        "$IP6T" -t filter -D OUTPUT -p tcp -j GOST_IPV6_FALLBACK 2>/dev/null || break
    done
    "$IP6T" -t filter -F GOST_IPV6_FALLBACK 2>/dev/null
    "$IP6T" -t filter -X GOST_IPV6_FALLBACK 2>/dev/null
    ui_print "- Removed legacy IPv6 fallback rule."
fi

# ---- Hot-restart WebUI ----
# Module updates may be extracted to modules_update while the old server keeps
# serving files from the active module directory. Restart only WebUI from the
# newly installed tree so frontend/API changes take effect without rebooting;
# the running gost proxy is deliberately left untouched.
WEBUI_PIDFILE="/tmp/gost-webui.pid"
OLD_WEBUI_PID=""
if [ -f "$WEBUI_PIDFILE" ]; then
    OLD_WEBUI_PID=$(cat "$WEBUI_PIDFILE" 2>/dev/null)
fi

case "$OLD_WEBUI_PID" in
    ''|*[!0-9]*) OLD_WEBUI_PID="" ;;
esac

if [ -n "$OLD_WEBUI_PID" ] && kill -0 "$OLD_WEBUI_PID" 2>/dev/null; then
    OLD_WEBUI_CMD=$(tr '\000' ' ' < "/proc/$OLD_WEBUI_PID/cmdline" 2>/dev/null)
    case "$OLD_WEBUI_CMD" in
        *gost_proxy*|*gost-webui*|*webui/server.sh*)
            ui_print "- Stopping previous WebUI (PID: $OLD_WEBUI_PID)..."
            # Stop listener children first (notably nc/FIFO mode), otherwise a
            # detached child could keep the port occupied after its shell exits.
            OLD_WEBUI_CHILDREN=$(cat "/proc/$OLD_WEBUI_PID/task/$OLD_WEBUI_PID/children" 2>/dev/null)
            for _child in $OLD_WEBUI_CHILDREN; do
                case "$_child" in
                    ''|*[!0-9]*) continue ;;
                esac
                kill "$_child" 2>/dev/null
            done
            kill "$OLD_WEBUI_PID" 2>/dev/null
            _wait=0
            while kill -0 "$OLD_WEBUI_PID" 2>/dev/null && [ "$_wait" -lt 5 ]; do
                sleep 1
                _wait=$((_wait + 1))
            done
            if kill -0 "$OLD_WEBUI_PID" 2>/dev/null; then
                kill -9 "$OLD_WEBUI_PID" 2>/dev/null
            fi
            ;;
        *)
            ui_print "- Ignoring stale WebUI PID file (PID belongs to another process)."
            ;;
    esac
fi
rm -f "$WEBUI_PIDFILE"

CONFIG_PORT=$(grep -o '"webui_port"[[:space:]]*:[[:space:]]*[0-9]*' "$MODDIR/gost/config.json" 2>/dev/null | grep -o '[0-9]*')
WEBUI_PORT=${CONFIG_PORT:-8080}
sh "$MODDIR/webui/server.sh" "$MODDIR" "$WEBUI_PORT" >> "$MODDIR/logs/service.log" 2>&1 &
NEW_WEBUI_PID=$!
sleep 1
if kill -0 "$NEW_WEBUI_PID" 2>/dev/null; then
    echo "$NEW_WEBUI_PID" > "$WEBUI_PIDFILE"
    ui_print "- WebUI restarted from the new module files (PID: $NEW_WEBUI_PID)."
else
    ui_print "- WARNING: WebUI hot restart failed; it will start normally after reboot."
fi

ui_print ""
ui_print "Installation complete!"
ui_print "Gost proxy will start on boot."
ui_print "WebUI: http://127.0.0.1:$WEBUI_PORT"
ui_print "========================================"

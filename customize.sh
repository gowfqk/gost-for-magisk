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
PRESERVE_DIR="/tmp/gost_preserve"
PERSIST_DIR="/data/adb/gost_proxy"
rm -rf "$PRESERVE_DIR"
mkdir -p "$PRESERVE_DIR" "$PERSIST_DIR"

# Preserve a usable installed binary independently of config.json. WebUI keeps
# a persistent copy outside the module directory, so root-manager replacement
# cannot remove the only copy during updates.
for _binary in \
    "$PERSIST_DIR/gost" \
    "$OLD_MODDIR/gost/gost" \
    /data/adb/modules/gost_proxy/gost/gost \
    /data/adb/modules_update/gost_proxy/gost/gost \
    /data/adb/ksu/modules/gost_proxy/gost/gost \
    /data/adb/ksu/modules_update/gost_proxy/gost/gost \
    /data/adb/ap/modules/gost_proxy/gost/gost \
    /data/adb/ap/modules_update/gost_proxy/gost/gost; do
    [ -s "$_binary" ] || continue
    grep -q "Placeholder" "$_binary" 2>/dev/null && continue
    if cp "$_binary" "$PRESERVE_DIR/gost_bin"; then
        cp "$_binary" "$PERSIST_DIR/gost" 2>/dev/null
        chmod 755 "$PERSIST_DIR/gost" 2>/dev/null
        ui_print "- Found existing gost binary: $_binary"
        break
    fi
done

# If the old module directory is hidden during an update, recover the binary
# from a currently running gost process. /proc/<pid>/exe remains accessible
# even when the original path has been replaced or moved by the root manager.
if [ ! -s "$PRESERVE_DIR/gost_bin" ]; then
    for _pid_dir in /proc/[0-9]*; do
        _proc_exe=$(readlink "$_pid_dir/exe" 2>/dev/null)
        case "$_proc_exe" in
            */gost|*/gost\ \(deleted\)) ;;
            *) continue ;;
        esac
        [ -s "$_pid_dir/exe" ] || continue
        grep -q "Placeholder" "$_pid_dir/exe" 2>/dev/null && continue
        if cp "$_pid_dir/exe" "$PRESERVE_DIR/gost_bin" 2>/dev/null; then
            ui_print "- Recovered running gost binary: $_proc_exe"
            break
        fi
    done
fi

# Also reuse a manually installed gost from PATH when no module copy exists.
if [ ! -s "$PRESERVE_DIR/gost_bin" ]; then
    _path_gost=$(command -v gost 2>/dev/null)
    if [ -n "$_path_gost" ] && [ -s "$_path_gost" ]; then
        cp "$_path_gost" "$PRESERVE_DIR/gost_bin" && ui_print "- Found system gost binary: $_path_gost"
    fi
fi

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
# touching preserved data or finishing the offline installation.
for REQUIRED_FILE in module.prop service.sh scripts/start.sh scripts/download_gost.sh scripts/update_geodata.sh webui/cgi-bin/api gost/nodes/default.json.example; do
    if [ ! -f "$MODDIR/$REQUIRED_FILE" ]; then
        abort "ERROR: Missing module file: $REQUIRED_FILE"
    fi
done

mkdir -p "$MODDIR/gost/nodes" "$MODDIR/gost/geodata" "$MODDIR/gost/tools" "$MODDIR/logs"

# ---- Restore preserved binary/config ----
# The release ZIP intentionally does not bundle gost. Prefer the device-local
# binary and only download when no usable binary is available.
if [ -s "$PRESERVE_DIR/gost_bin" ]; then
    cp "$PRESERVE_DIR/gost_bin" "$MODDIR/gost/gost"
    chmod 755 "$MODDIR/gost/gost"
    ui_print "- Reused existing gost binary; download will be skipped."
fi

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

# ---- Handle gost binary ----
# Installation must remain offline and deterministic. Never remove an existing
# file here: update managers may expose the live module as MODPATH. If no usable
# binary is available, finish installing and let the user download it via WebUI.
if [ ! -s "$MODDIR/gost/gost" ] || grep -q "Placeholder" "$MODDIR/gost/gost" 2>/dev/null; then
    ui_print ""
    ui_print "- Gost binary is not installed; no download will run during installation."
    ui_print "- After reboot, open WebUI and tap Download Gost."
    ui_print ""
else
    ui_print "- Existing gost binary is ready; no download needed."
fi

chmod 755 "$MODDIR/gost/gost" 2>/dev/null
chmod 755 "$MODDIR/scripts/start.sh"
chmod 755 "$MODDIR/scripts/iptables.sh"
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

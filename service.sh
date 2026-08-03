#!/system/bin/sh

MODDIR=${0%/*}
LOGFILE="$MODDIR/logs/service.log"
PERSIST_DIR="/data/adb/gost_proxy"
PERSIST_BIN="$PERSIST_DIR/gost"
MODULE_BIN="$MODDIR/gost/gost"

mkdir -p "$MODDIR/logs" "$PERSIST_DIR"

usable_gost_binary() {
    _bin="$1"
    [ -s "$_bin" ] || return 1
    [ -x "$_bin" ] || chmod 755 "$_bin" 2>/dev/null || return 1
    _version=$("$_bin" -V 2>&1 || true)
    printf '%s' "$_version" | grep -qi 'gost'
}

atomic_copy() {
    _src="$1" _dst="$2" _dir=${2%/*}
    _tmp="$_dir/.gost.tmp.$$"
    mkdir -p "$_dir" || return 1
    cp "$_src" "$_tmp" || { rm -f "$_tmp"; return 1; }
    chmod 755 "$_tmp" 2>/dev/null
    mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; return 1; }
}

# post-fs-data is not guaranteed to run on every root manager. Repeat the
# restore/sync here before auto-start so the module and persistent copies heal
# each other on every boot.
if usable_gost_binary "$MODULE_BIN"; then
    atomic_copy "$MODULE_BIN" "$PERSIST_BIN" 2>/dev/null || true
elif usable_gost_binary "$PERSIST_BIN"; then
    atomic_copy "$PERSIST_BIN" "$MODULE_BIN" 2>/dev/null || true
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh started" >> "$LOGFILE"

sleep 10

# ---- Start gost proxy ----
if ! usable_gost_binary "$MODULE_BIN"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: usable gost binary not found, skipping auto-start" >> "$LOGFILE"
else
    if [ -f "$MODDIR/scripts/start.sh" ]; then
        if sh "$MODDIR/scripts/start.sh" "$MODDIR" >> "$LOGFILE" 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] gost proxy started" >> "$LOGFILE"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: gost proxy failed to start" >> "$LOGFILE"
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: start.sh not found" >> "$LOGFILE"
    fi
fi

# ---- Start WebUI ----
# Get WebUI port from config
CONFIG_PORT=$(cat "$MODDIR/gost/config.json" 2>/dev/null | grep -o '"webui_port"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
WEBUI_PORT=${CONFIG_PORT:-8080}

# Use shell-based server (no python3 dependency)
if [ -f "$MODDIR/webui/server.sh" ]; then
    sh "$MODDIR/webui/server.sh" "$MODDIR" "$WEBUI_PORT" >> "$LOGFILE" 2>&1 &
    WEBUI_PID=$!
    echo "$WEBUI_PID" > /tmp/gost-webui.pid
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WebUI started on port $WEBUI_PORT (PID: $WEBUI_PID, shell mode)" >> "$LOGFILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: server.sh not found, WebUI not started" >> "$LOGFILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh completed" >> "$LOGFILE"

# ---- Optional: auto-update geodata on boot ----
GEODATA_AUTO=$(grep -o '"auto_update"[[:space:]]*:[[:space:]]*true' "$MODDIR/gost/config.json" 2>/dev/null)
if [ -n "$GEODATA_AUTO" ] && [ -f "$MODDIR/scripts/update_geodata.sh" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] geodata auto-update enabled, starting background update" >> "$LOGFILE"
    sh "$MODDIR/scripts/update_geodata.sh" "$MODDIR" >> "$MODDIR/logs/geodata-update.log" 2>&1 &
fi

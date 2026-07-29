#!/system/bin/sh

MODDIR=${0%/*}
LOGFILE="$MODDIR/logs/service.log"

mkdir -p "$MODDIR/logs"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh started" >> "$LOGFILE"

sleep 10

# ---- Start gost proxy ----
if [ ! -f "$MODDIR/gost/gost" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: gost binary not found, skipping auto-start" >> "$LOGFILE"
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

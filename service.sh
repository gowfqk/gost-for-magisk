#!/system/bin/sh

MODDIR=${0%/*}
LOGFILE="$MODDIR/logs/service.log"

mkdir -p "$MODDIR/logs"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh started" >> "$LOGFILE"

sleep 10

if [ ! -f "$MODDIR/gost/gost" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: gost binary not found, skipping auto-start" >> "$LOGFILE"
    exit 1
fi

if [ -f "$MODDIR/scripts/start.sh" ]; then
    sh "$MODDIR/scripts/start.sh" >> "$LOGFILE" 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] gost proxy started" >> "$LOGFILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: start.sh not found" >> "$LOGFILE"
fi

if command -v python3 >/dev/null 2>&1; then
    if [ -f "$MODDIR/webui/server.py" ]; then
        CONFIG_PORT=$(cat "$MODDIR/gost/config.json" 2>/dev/null | grep -o '"webui_port":[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        WEBUI_PORT=${CONFIG_PORT:-8080}
        python3 "$MODDIR/webui/server.py" "$MODDIR" "$WEBUI_PORT" >> "$LOGFILE" 2>&1 &
        WEBUI_PID=$!
        echo "$WEBUI_PID" > /tmp/gost-webui.pid
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WebUI started on port $WEBUI_PORT (PID: $WEBUI_PID)" >> "$LOGFILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: server.py not found, WebUI not started" >> "$LOGFILE"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: python3 not found, WebUI not started" >> "$LOGFILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh completed" >> "$LOGFILE"

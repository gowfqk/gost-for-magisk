#!/system/bin/sh

MODDIR=/data/adb/modules/gost_proxy
LOGFILE="$MODDIR/logs/uninstall.log"

mkdir -p "$MODDIR/logs"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] uninstall.sh started" >> "$LOGFILE"

[ -f "$MODDIR/scripts/iptables.sh" ] && sh "$MODDIR/scripts/iptables.sh" "$MODDIR" stop >/dev/null 2>&1

if [ -f /tmp/gost.pid ]; then
    GOST_PID=$(cat /tmp/gost.pid)
    if kill -0 "$GOST_PID" 2>/dev/null; then
        kill "$GOST_PID" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopped gost process (PID: $GOST_PID)" >> "$LOGFILE"
    fi
    rm -f /tmp/gost.pid
fi

if [ -f /tmp/gost-webui.pid ]; then
    WEBUI_PID=$(cat /tmp/gost-webui.pid)
    if kill -0 "$WEBUI_PID" 2>/dev/null; then
        kill "$WEBUI_PID" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopped WebUI process (PID: $WEBUI_PID)" >> "$LOGFILE"
    fi
    rm -f /tmp/gost-webui.pid
fi

pkill -f "gost" 2>/dev/null
pkill -f "server.sh.*gost" 2>/dev/null
pkill -f "server.sh.*gost" 2>/dev/null

rm -f /tmp/gost.pid
rm -f /tmp/gost-webui.pid

echo "[$(date '+%Y-%m-%d %H:%M:%S')] All gost processes stopped" >> "$LOGFILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] uninstall.sh completed" >> "$LOGFILE"

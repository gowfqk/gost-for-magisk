#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
LOGFILE="$MODDIR/logs/gost.log"
PIDFILE="/tmp/gost.pid"

mkdir -p "$MODDIR/logs"

# Remove traffic interception before stopping gost to avoid breaking networking.
[ -f "$MODDIR/scripts/iptables.sh" ] && sh "$MODDIR/scripts/iptables.sh" "$MODDIR" stop >/dev/null 2>&1

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

if [ -f "$PIDFILE" ]; then
    GOST_PID=$(cat "$PIDFILE")
    if kill -0 "$GOST_PID" 2>/dev/null; then
        kill "$GOST_PID" 2>/dev/null
        sleep 1
        if kill -0 "$GOST_PID" 2>/dev/null; then
            kill -9 "$GOST_PID" 2>/dev/null
            log_msg "Force killed gost (PID: $GOST_PID)"
        else
            log_msg "gost stopped gracefully (PID: $GOST_PID)"
        fi
        rm -f "$PIDFILE"
        echo "gost stopped (PID: $GOST_PID)"
        exit 0
    else
        rm -f "$PIDFILE"
        log_msg "Stale PID file removed"
    fi
fi

pkill -f "$MODDIR/gost/gost" 2>/dev/null
if [ $? -eq 0 ]; then
    log_msg "gost stopped via pkill"
    echo "gost stopped"
else
    log_msg "gost is not running"
    echo "gost is not running"
fi

rm -f "$PIDFILE"

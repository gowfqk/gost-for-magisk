#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
LOGFILE="$MODDIR/logs/gost.log"
PIDFILE="/tmp/gost.pid"
CONFIG="$MODDIR/gost/config.json"
GOST_BIN="$MODDIR/gost/gost"

mkdir -p "$MODDIR/logs"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log_msg "gost is already running (PID: $OLD_PID)"
        echo "gost is already running (PID: $OLD_PID)"
        exit 0
    fi
    rm -f "$PIDFILE"
fi

if [ ! -f "$GOST_BIN" ]; then
    log_msg "ERROR: gost binary not found at $GOST_BIN"
    echo "ERROR: gost binary not found"
    exit 1
fi

if [ ! -x "$GOST_BIN" ]; then
    chmod 755 "$GOST_BIN"
fi

if [ ! -f "$CONFIG" ]; then
    log_msg "ERROR: config file not found at $CONFIG"
    echo "ERROR: config file not found"
    exit 1
fi

log_msg "Starting gost proxy..."

cd "$MODDIR/gost"
"$GOST_BIN" -C "$CONFIG" >> "$LOGFILE" 2>&1 &
GOST_PID=$!

sleep 1

if kill -0 "$GOST_PID" 2>/dev/null; then
    echo "$GOST_PID" > "$PIDFILE"
    log_msg "gost started successfully (PID: $GOST_PID)"
    echo "gost started successfully (PID: $GOST_PID)"
else
    log_msg "ERROR: gost failed to start"
    echo "ERROR: gost failed to start"
    exit 1
fi

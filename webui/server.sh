#!/system/bin/sh
#
# server.sh - WebUI server for Gost proxy using busybox httpd
# No Python dependency, no nc, uses Magisk busybox httpd with CGI
#
# Usage: sh server.sh [MODDIR] [PORT]
#

MODDIR="${1:-/data/adb/modules/gost_proxy}"
PORT="${2:-8080}"
WEBUI_DIR="$MODDIR/webui"
LOGFILE="$MODDIR/logs/webui.log"
PIDFILE="/tmp/gost-webui.pid"

mkdir -p "$MODDIR/logs"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

log_msg "=========================================="
log_msg "Starting WebUI server (busybox httpd + CGI)"
log_msg "MODDIR=$MODDIR  PORT=$PORT"
log_msg "WEBUI_DIR=$WEBUI_DIR"

# Write PID
echo $$ > "$PIDFILE"

# ---- Find busybox ----
BB=""
for path in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox /system/xbin/busybox; do
    if [ -x "$path" ]; then
        BB="$path"
        break
    fi
done
if [ -z "$BB" ]; then
    BB=$(command -v busybox 2>/dev/null)
fi
if [ -z "$BB" ]; then
    log_msg "ERROR: busybox not found anywhere"
    echo "ERROR: busybox not found"
    exit 1
fi
log_msg "busybox=$BB"

# ---- Verify httpd applet exists ----
if ! "$BB" httpd --help 2>&1 | head -1 | grep -qi "httpd"; then
    log_msg "ERROR: busybox httpd applet not available"
    echo "ERROR: httpd not available in busybox"
    exit 1
fi
log_msg "httpd applet: OK"

# ---- Verify CGI script exists and is executable ----
CGI_SCRIPT="$WEBUI_DIR/cgi-bin/api"
if [ ! -f "$CGI_SCRIPT" ]; then
    log_msg "ERROR: CGI script not found: $CGI_SCRIPT"
    echo "ERROR: CGI script not found"
    exit 1
fi
chmod 755 "$CGI_SCRIPT" 2>/dev/null
log_msg "CGI script: OK"

# ---- Kill any existing httpd on this port ----
OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$$" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log_msg "Killing existing server (PID: $OLD_PID)"
    kill "$OLD_PID" 2>/dev/null
    sleep 1
fi

# ---- Start httpd ----
# -f: stay in foreground (don't daemonize)
# -p: port to listen on
# -h: home/document root directory
log_msg "Starting httpd: $BB httpd -f -p $PORT -h $WEBUI_DIR"
log_msg "WebUI will be available at http://127.0.0.1:$PORT"
log_msg "=========================================="

exec "$BB" httpd -f -p "$PORT" -h "$WEBUI_DIR"

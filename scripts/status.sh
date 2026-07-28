#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
PIDFILE="/tmp/gost.pid"
WEBUI_PIDFILE="/tmp/gost-webui.pid"
CONFIG="$MODDIR/gost/config.json"

gost_status="stopped"
gost_pid=""
webui_status="stopped"
webui_pid=""

if [ -f "$PIDFILE" ]; then
    GOST_PID=$(cat "$PIDFILE")
    if kill -0 "$GOST_PID" 2>/dev/null; then
        gost_status="running"
        gost_pid="$GOST_PID"
    else
        rm -f "$PIDFILE"
    fi
fi

if [ -f "$WEBUI_PIDFILE" ]; then
    WEBUI_PID=$(cat "$WEBUI_PIDFILE")
    if kill -0 "$WEBUI_PID" 2>/dev/null; then
        webui_status="running"
        webui_pid="$WEBUI_PID"
    else
        rm -f "$WEBUI_PIDFILE"
    fi
fi

ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "unknown")

LISTEN_PORT=""
PROXY_TYPE=""
if [ -f "$CONFIG" ]; then
    LISTEN_PORT=$(grep -o '"listen_port":[[:space:]]*[0-9]*' "$CONFIG" | grep -o '[0-9]*')
    PROXY_TYPE=$(grep -o '"proxy_type":[[:space:]]*"[^"]*"' "$CONFIG" | grep -o '"[^"]*"' | tr -d '"')
fi

echo "{"
echo "  \"gost\": {"
echo "    \"status\": \"$gost_status\","
echo "    \"pid\": \"$gost_pid\""
echo "  },"
echo "  \"webui\": {"
echo "    \"status\": \"$webui_status\","
echo "    \"pid\": \"$webui_pid\""
echo "  },"
echo "  \"arch\": \"$ARCH\","
echo "  \"listen_port\": \"$LISTEN_PORT\","
echo "    \"proxy_type\": \"$PROXY_TYPE\""
echo "}"

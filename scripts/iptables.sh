#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
ACTION=${2:-start}
CONFIG="$MODDIR/gost/config.json"
LOGFILE="$MODDIR/logs/gost.log"
CHAIN="GOST_REDIRECT"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] iptables: $1" >> "$LOGFILE"
}

jval() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

IPT=$(command -v iptables 2>/dev/null)
[ -z "$IPT" ] && IPT="/system/bin/iptables"
if [ ! -x "$IPT" ]; then
    log_msg "ERROR: iptables not found"
    exit 1
fi

cleanup_rules() {
    while "$IPT" -t nat -C OUTPUT -p tcp -j "$CHAIN" 2>/dev/null; do
        "$IPT" -t nat -D OUTPUT -p tcp -j "$CHAIN" 2>/dev/null || break
    done
    "$IPT" -t nat -F "$CHAIN" 2>/dev/null
    "$IPT" -t nat -X "$CHAIN" 2>/dev/null
}

if [ "$ACTION" = "stop" ]; then
    cleanup_rules
    log_msg "transparent proxy rules removed"
    exit 0
fi

LISTEN_PORT=$(jval listen_port)
WEBUI_PORT=$(jval webui_port)
case "$LISTEN_PORT" in ''|*[!0-9]*) LISTEN_PORT=1080 ;; esac
case "$WEBUI_PORT" in ''|*[!0-9]*) WEBUI_PORT=8080 ;; esac

cleanup_rules
"$IPT" -t nat -N "$CHAIN" || exit 1

# Keep local/control networks reachable directly. The gost process runs as
# root, so excluding UID 0 prevents the upstream connection being redirected
# back into gost. Android system/root services are excluded as a trade-off.
"$IPT" -t nat -A "$CHAIN" -m owner --uid-owner 0 -j RETURN || {
    log_msg "ERROR: owner match unavailable; refusing unsafe rules"
    cleanup_rules
    exit 1
}
"$IPT" -t nat -A "$CHAIN" -d 0.0.0.0/8 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 10.0.0.0/8 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 100.64.0.0/10 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 127.0.0.0/8 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 169.254.0.0/16 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 172.16.0.0/12 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 192.168.0.0/16 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 224.0.0.0/4 -j RETURN
"$IPT" -t nat -A "$CHAIN" -d 240.0.0.0/4 -j RETURN
"$IPT" -t nat -A "$CHAIN" -p tcp -m multiport --dports "$LISTEN_PORT,$WEBUI_PORT" -j RETURN 2>/dev/null
"$IPT" -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports "$LISTEN_PORT"
"$IPT" -t nat -A OUTPUT -p tcp -j "$CHAIN"

log_msg "transparent TCP proxy enabled on port $LISTEN_PORT"

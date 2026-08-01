#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
ACTION=${2:-start}
DNS_PORT=${3:-1053}
DNS_DIR="$MODDIR/dns"
DNS_BIN_DIR="$DNS_DIR/bin"
DNS_DOMAINS="$DNS_DIR/ipv4-only-domains.txt"
DNS_LOG="$MODDIR/logs/dns-filter.log"
DNS_PIDFILE="/tmp/gost-dns-filter.pid"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] dns-filter: $1" >> "$DNS_LOG"
}

stop_filter() {
    if [ -f "$DNS_PIDFILE" ]; then
        _pid=$(cat "$DNS_PIDFILE" 2>/dev/null)
        case "$_pid" in ''|*[!0-9]*) _pid="" ;; esac
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _cmd=$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)
            if printf '%s' "$_cmd" | grep -Fq "$DNS_BIN_DIR/"; then
                kill "$_pid" 2>/dev/null
                sleep 1
                kill -0 "$_pid" 2>/dev/null && kill -9 "$_pid" 2>/dev/null
            fi
        fi
        rm -f "$DNS_PIDFILE"
    fi
}

if [ "$ACTION" = "stop" ]; then
    stop_filter
    exit 0
fi

case "$DNS_PORT" in ''|*[!0-9]*) DNS_PORT=1053 ;; esac
[ "$DNS_PORT" -ge 1 ] 2>/dev/null && [ "$DNS_PORT" -le 65535 ] 2>/dev/null || DNS_PORT=1053

stop_filter
mkdir -p "$MODDIR/logs"

ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
if [ "$ABI" != "arm64-v8a" ]; then
    log_msg "ERROR: unsupported ABI: $ABI (arm64-v8a required)"
    exit 1
fi
DNS_BIN="$DNS_BIN_DIR/dns-filter-arm64"

if [ ! -s "$DNS_BIN" ] || [ ! -s "$DNS_DOMAINS" ]; then
    log_msg "ERROR: DNS filter binary or domain list is missing"
    exit 1
fi
chmod 755 "$DNS_BIN"

# Use public IPv4 resolvers directly. The process runs as root, and the DNS
# interception chain excludes UID 0, preventing its upstream query from looping.
"$DNS_BIN" -listen "127.0.0.1:$DNS_PORT" -upstream "223.5.5.5:53" -domains "$DNS_DOMAINS" >> "$DNS_LOG" 2>&1 &
DNS_PID=$!
sleep 1
if ! kill -0 "$DNS_PID" 2>/dev/null; then
    log_msg "ERROR: DNS filter failed to start"
    return 1 2>/dev/null || exit 1
fi

echo "$DNS_PID" > "$DNS_PIDFILE"
log_msg "started on 127.0.0.1:$DNS_PORT (PID: $DNS_PID)"

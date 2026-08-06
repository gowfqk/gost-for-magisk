#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
ACTION=${2:-start}
DNS_PORT=${3:-1053}
FILTER_MODE=${4:-domains}
DNS_DIR="$MODDIR/dns"
DNS_BIN_DIR="$DNS_DIR/bin"
DNS_DOMAINS="$DNS_DIR/ipv4-only-domains.txt"
DNS_LOG="$MODDIR/logs/dns-filter.log"
DNS_PIDFILE="/tmp/gost-dns-filter.pid"
DNS_UPSTREAM_FILE="/tmp/gost-dns-upstreams.txt"
DNS_FILTER_UID=2000

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

# dns_upstreams is a top-level comma-separated config value. Only literal IPv4
# addresses are accepted so malformed values or hostnames cannot create a DNS
# bootstrap loop. If it is absent, prefer Android's active-network DNS and then
# use domestic public resolvers. 1.1.1.1 and 8.8.8.8 are deliberately excluded
# from defaults because several mainland mobile networks silently drop them.
CONFIG="$MODDIR/gost/config.json"
CONFIGURED_UPSTREAMS=$(grep -o '"dns_upstreams"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*"//' | sed 's/"$//')
: > "$DNS_UPSTREAM_FILE"
if [ -n "$CONFIGURED_UPSTREAMS" ]; then
    OLD_IFS=$IFS
    IFS=','
    for DNS_ITEM in $CONFIGURED_UPSTREAMS; do
        DNS_ITEM=$(printf '%s' "$DNS_ITEM" | tr -d '[:space:]')
        DNS_IP=${DNS_ITEM%:*}
        case "$DNS_IP" in ''|*:*|*[!0-9.]*) continue ;; esac
        case "$DNS_ITEM" in *:*) DNS_PORT_VALUE=${DNS_ITEM##*:} ;; *) DNS_PORT_VALUE=53 ;; esac
        case "$DNS_PORT_VALUE" in ''|*[!0-9]*) continue ;; esac
        [ "$DNS_PORT_VALUE" -ge 1 ] 2>/dev/null && [ "$DNS_PORT_VALUE" -le 65535 ] 2>/dev/null || continue
        printf '%s:%s\n' "$DNS_IP" "$DNS_PORT_VALUE" >> "$DNS_UPSTREAM_FILE"
    done
    IFS=$OLD_IFS
else
    for PROP in net.dns1 net.dns2 net.dns3 net.dns4; do
        DNS_IP=$(getprop "$PROP" 2>/dev/null)
        case "$DNS_IP" in ''|*:*|*[!0-9.]*) continue ;; esac
        printf '%s:53\n' "$DNS_IP" >> "$DNS_UPSTREAM_FILE"
    done
    printf '%s\n' "223.5.5.5:53" "119.29.29.29:53" >> "$DNS_UPSTREAM_FILE"
fi
DNS_UPSTREAMS=$(awk '!seen[$0]++ { if (out != "") out=out ","; out=out $0 } END { print out }' "$DNS_UPSTREAM_FILE")
rm -f "$DNS_UPSTREAM_FILE"
[ -n "$DNS_UPSTREAMS" ] || DNS_UPSTREAMS="223.5.5.5:53,119.29.29.29:53"
case "$FILTER_MODE" in
    all) FILTER_ARG="-filter-all-aaaa" ;;
    domains) FILTER_ARG="" ;;
    *) log_msg "ERROR: unsupported DNS filter mode: $FILTER_MODE"; exit 1 ;;
esac
DNS_CMD="$DNS_BIN -listen 127.0.0.1:$DNS_PORT -upstream $DNS_UPSTREAMS -domains $DNS_DOMAINS -timeout 2s $FILTER_ARG"
if ! command -v su >/dev/null 2>&1; then
    log_msg "ERROR: su is required to run the DNS filter without a redirect loop"
    exit 1
fi
su "$DNS_FILTER_UID" -c "$DNS_CMD" >> "$DNS_LOG" 2>&1 &
DNS_PID=$!
sleep 1
if ! kill -0 "$DNS_PID" 2>/dev/null; then
    log_msg "ERROR: DNS filter failed to start"
    return 1 2>/dev/null || exit 1
fi

echo "$DNS_PID" > "$DNS_PIDFILE"
log_msg "started on 127.0.0.1:$DNS_PORT with upstreams $DNS_UPSTREAMS mode=$FILTER_MODE (PID: $DNS_PID)"

#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
ACTION=${2:-start}
CONFIG="$MODDIR/gost/config.json"
LOGFILE="$MODDIR/logs/gost.log"
CHAIN="GOST_REDIRECT"
IP6_CHAIN="GOST_IPV6_FALLBACK"
IP6_REDIRECT_CHAIN="GOST_REDIRECT6"
QUIC_CHAIN="GOST_QUIC_BLOCK"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] iptables: $1" >> "$LOGFILE"
}

jval() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

jsection_val() {
    _section="$1" _key="$2"
    awk -v section="$_section" -v key="$_key" '
        function find_object(json, section,    pattern, rest, start, i, ch, escaped, quoted, depth) {
            pattern = "\\\"" section "\\\"[[:space:]]*:"
            if (!match(json, pattern)) return ""
            start = RSTART + RLENGTH
            rest = substr(json, start)
            if (!match(rest, /^[[:space:]]*\{/)) return ""
            start += RSTART + RLENGTH - 2
            depth = 0; quoted = 0; escaped = 0
            for (i = start; i <= length(json); i++) {
                ch = substr(json, i, 1)
                if (quoted) {
                    if (escaped) escaped = 0
                    else if (ch == "\\") escaped = 1
                    else if (ch == "\"") quoted = 0
                    continue
                }
                if (ch == "\"") quoted = 1
                else if (ch == "{") depth++
                else if (ch == "}" && --depth == 0) return substr(json, start, i - start + 1)
            }
            return ""
        }
        function get_scalar(object, key,    pattern, rest, i, ch, escaped, value) {
            pattern = "\\\"" key "\\\"[[:space:]]*:"
            if (!match(object, pattern)) return ""
            rest = substr(object, RSTART + RLENGTH)
            sub(/^[[:space:]]*/, "", rest)
            if (substr(rest, 1, 1) == "[") {
                if (match(rest, /^\[[^]]*\]/)) return substr(rest, 2, RLENGTH - 2)
                return ""
            }
            if (substr(rest, 1, 1) != "\"") {
                if (match(rest, /^[^,}]*/)) {
                    value = substr(rest, RSTART, RLENGTH)
                    sub(/[[:space:]]*$/, "", value)
                    return value
                }
                return ""
            }
            value = ""; escaped = 0
            for (i = 2; i <= length(rest); i++) {
                ch = substr(rest, i, 1)
                if (escaped) { value = value ch; escaped = 0 }
                else if (ch == "\\") escaped = 1
                else if (ch == "\"") return value
                else value = value ch
            }
            return ""
        }
        { json = json $0 "\n" }
        END {
            object = find_object(json, section)
            if (object != "") print get_scalar(object, key)
        }
    ' "$CONFIG" 2>/dev/null
}

IPT=$(command -v iptables 2>/dev/null)
[ -z "$IPT" ] && IPT="/system/bin/iptables"
if [ ! -x "$IPT" ]; then
    log_msg "ERROR: iptables not found"
    exit 1
fi
IP6T=$(command -v ip6tables 2>/dev/null)
[ -z "$IP6T" ] && IP6T="/system/bin/ip6tables"

cleanup_chain() {
    _bin="$1" _table="$2" _hook="$3" _proto="$4" _chain="$5"
    [ -x "$_bin" ] || return 0
    while "$_bin" -t "$_table" -C "$_hook" -p "$_proto" -j "$_chain" 2>/dev/null; do
        "$_bin" -t "$_table" -D "$_hook" -p "$_proto" -j "$_chain" 2>/dev/null || break
    done
    "$_bin" -t "$_table" -F "$_chain" 2>/dev/null
    "$_bin" -t "$_table" -X "$_chain" 2>/dev/null
}

cleanup_rules() {
    cleanup_chain "$IPT" nat OUTPUT tcp "$CHAIN"
    cleanup_chain "$IPT" filter OUTPUT udp "$QUIC_CHAIN"
    cleanup_chain "$IP6T" nat OUTPUT tcp "$IP6_REDIRECT_CHAIN"
    cleanup_chain "$IP6T" filter OUTPUT udp "$QUIC_CHAIN"
    # v1.9.19 legacy chain used TCP and globally rejected public IPv6.
    cleanup_chain "$IP6T" filter OUTPUT tcp "$IP6_CHAIN"
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
if [ "$LISTEN_PORT" -lt 65535 ] 2>/dev/null; then
    IPV6_LISTEN_PORT=$((LISTEN_PORT + 1))
else
    IPV6_LISTEN_PORT=$((LISTEN_PORT - 1))
fi

cleanup_rules
"$IPT" -t nat -N "$CHAIN" || exit 1

# Android reserves socket marks for network selection and policy routing. An
# arbitrary GOST so_mark can make every direct or upstream dial fail with
# ENETUNREACH. GOST runs as root, so exclude UID 0 instead to prevent its own
# outbound connections from being redirected back into the RED listener.
"$IPT" -t nat -A "$CHAIN" -m owner --uid-owner 0 -j RETURN || {
    log_msg "ERROR: owner match unavailable; refusing unsafe rules"
    cleanup_rules
    exit 1
}
ROUTING_ENABLED=$(jsection_val routing enabled)
DIRECT_UIDS=$(jsection_val routing direct_uids | tr -d ' []')
if [ "$ROUTING_ENABLED" = "true" ] && [ -n "$DIRECT_UIDS" ]; then
    OLD_IFS=$IFS
    IFS=','
    for UID_VALUE in $DIRECT_UIDS; do
        case "$UID_VALUE" in ''|*[!0-9]*) continue ;; esac
        "$IPT" -t nat -A "$CHAIN" -m owner --uid-owner "$UID_VALUE" -j RETURN || {
            IFS=$OLD_IFS
            log_msg "ERROR: failed to add direct UID $UID_VALUE"
            cleanup_rules
            exit 1
        }
    done
    IFS=$OLD_IFS
fi
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

# Intercept IPv6 TCP when the kernel provides ip6table_nat. A number of Android
# kernels ship ip6tables but omit the IPv6 nat table; that is a capability
# limitation, not a fatal error. Never tear down the working IPv4 proxy merely
# because optional IPv6 interception cannot be installed.
IPV6_PROXY_ENABLED=false
if [ -x "$IP6T" ] && "$IP6T" -t nat -L OUTPUT -n >/dev/null 2>&1; then
    if "$IP6T" -t nat -N "$IP6_REDIRECT_CHAIN" 2>/dev/null && \
       "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -m owner --uid-owner 0 -j RETURN 2>/dev/null; then
        IPV6_PROXY_ENABLED=true
        if [ "$ROUTING_ENABLED" = "true" ] && [ -n "$DIRECT_UIDS" ]; then
            OLD_IFS=$IFS
            IFS=','
            for UID_VALUE in $DIRECT_UIDS; do
                case "$UID_VALUE" in ''|*[!0-9]*) continue ;; esac
                if ! "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -m owner --uid-owner "$UID_VALUE" -j RETURN 2>/dev/null; then
                    IPV6_PROXY_ENABLED=false
                    break
                fi
            done
            IFS=$OLD_IFS
        fi
        if [ "$IPV6_PROXY_ENABLED" = "true" ]; then
            "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -d ::1/128 -j RETURN
            "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -d fe80::/10 -j RETURN
            "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -d fc00::/7 -j RETURN
            "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -d ff00::/8 -j RETURN
            "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -p tcp -m multiport --dports "$IPV6_LISTEN_PORT,$WEBUI_PORT" -j RETURN 2>/dev/null
            "$IP6T" -t nat -A "$IP6_REDIRECT_CHAIN" -p tcp -j REDIRECT --to-ports "$IPV6_LISTEN_PORT" 2>/dev/null || IPV6_PROXY_ENABLED=false
            if [ "$IPV6_PROXY_ENABLED" = "true" ]; then
                "$IP6T" -t nat -A OUTPUT -p tcp -j "$IP6_REDIRECT_CHAIN" 2>/dev/null || IPV6_PROXY_ENABLED=false
            fi
        fi
    fi
fi

if [ "$IPV6_PROXY_ENABLED" = "true" ]; then
    log_msg "IPv4 and IPv6 TCP transparent proxy enabled"
else
    cleanup_chain "$IP6T" nat OUTPUT tcp "$IP6_REDIRECT_CHAIN"
    log_msg "WARNING: IPv6 nat REDIRECT unavailable; IPv4 TCP proxy remains enabled and IPv6 stays direct"
fi

# Chrome/Google may use QUIC over UDP/443, which this TCP-only RED listener
# cannot proxy. Reject QUIC for non-root apps so they immediately retry HTTPS
# over TCP, which is handled above. This is protocol fallback, not IPv6 fallback.
for _fw in "$IPT" "$IP6T"; do
    [ -x "$_fw" ] || continue
    "$_fw" -t filter -N "$QUIC_CHAIN" 2>/dev/null || continue
    "$_fw" -t filter -A "$QUIC_CHAIN" -m owner --uid-owner 0 -j RETURN || continue
    if [ "$ROUTING_ENABLED" = "true" ] && [ -n "$DIRECT_UIDS" ]; then
        OLD_IFS=$IFS
        IFS=','
        for UID_VALUE in $DIRECT_UIDS; do
            case "$UID_VALUE" in ''|*[!0-9]*) continue ;; esac
            "$_fw" -t filter -A "$QUIC_CHAIN" -m owner --uid-owner "$UID_VALUE" -j RETURN 2>/dev/null
        done
        IFS=$OLD_IFS
    fi
    "$_fw" -t filter -A "$QUIC_CHAIN" -p udp --dport 443 -j REJECT
    "$_fw" -t filter -A OUTPUT -p udp -j "$QUIC_CHAIN"
done

if [ "$IPV6_PROXY_ENABLED" = "true" ]; then
    log_msg "transparent TCP proxy enabled on ports $LISTEN_PORT (IPv4) and $IPV6_LISTEN_PORT (IPv6)"
else
    log_msg "transparent TCP proxy enabled on port $LISTEN_PORT (IPv4 only; IPv6 kernel NAT unsupported)"
fi

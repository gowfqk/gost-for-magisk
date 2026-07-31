#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
ACTION=${2:-start}
CONFIG="$MODDIR/gost/config.json"
LOGFILE="$MODDIR/logs/gost.log"
CHAIN="GOST_REDIRECT"
IP6_CHAIN="GOST_IPV6_FALLBACK"

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

cleanup_ipv6_rules() {
    [ -x "$IP6T" ] || return 0
    while "$IP6T" -t filter -C OUTPUT -p tcp -j "$IP6_CHAIN" 2>/dev/null; do
        "$IP6T" -t filter -D OUTPUT -p tcp -j "$IP6_CHAIN" 2>/dev/null || break
    done
    "$IP6T" -t filter -F "$IP6_CHAIN" 2>/dev/null
    "$IP6T" -t filter -X "$IP6_CHAIN" 2>/dev/null
}

cleanup_rules() {
    while "$IPT" -t nat -C OUTPUT -p tcp -j "$CHAIN" 2>/dev/null; do
        "$IPT" -t nat -D OUTPUT -p tcp -j "$CHAIN" 2>/dev/null || break
    done
    "$IPT" -t nat -F "$CHAIN" 2>/dev/null
    "$IPT" -t nat -X "$CHAIN" 2>/dev/null
    cleanup_ipv6_rules
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

# Do not reject public IPv6 globally. Some Android networks are IPv6-only or
# depend on NAT64, and many applications do not reliably retry IPv4 after a
# firewall REJECT. cleanup_rules above still removes the v1.9.19 fallback chain
# during upgrades. IPv6 remains native/direct while IPv4 TCP uses REDIRECT.
if [ -x "$IP6T" ]; then
    log_msg "IPv6 left native; IPv4 TCP transparent proxy enabled"
else
    log_msg "WARNING: ip6tables not found; IPv4 proxy remains active"
fi

log_msg "transparent TCP proxy enabled on port $LISTEN_PORT"

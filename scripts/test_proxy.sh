#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
CONFIG="$MODDIR/gost/config.json"
PIDFILE="/tmp/gost.pid"
CHAIN="GOST_REDIRECT"
IP6_CHAIN="GOST_REDIRECT6"
QUIC_CHAIN="GOST_QUIC_BLOCK"
TEST_URL="https://www.gstatic.com/generate_204"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{if (NR > 1) printf "\\n"; printf "%s", $0}'
}

jval() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

TEST_DIR=""
TEST_CLIENT=""
cleanup() {
    [ -n "$TEST_CLIENT" ] && rm -f "$TEST_CLIENT" 2>/dev/null
    [ -n "$TEST_DIR" ] && rmdir "$TEST_DIR" 2>/dev/null
}

fail() {
    cleanup
    printf '{"success":false,"stage":"%s","message":"%s"}' "$1" "$(json_escape "$2")"
    exit 0
}

[ -f "$PIDFILE" ] || fail process "gost PID file not found"
GOST_PID=$(cat "$PIDFILE" 2>/dev/null)
[ -n "$GOST_PID" ] && kill -0 "$GOST_PID" 2>/dev/null || fail process "gost process is not running"

PROXY_TYPE=$(jval proxy_type)
case "$PROXY_TYPE" in
    socks|socks5) PROXY_TYPE="socks5" ;;
    ""|redirect|red|redir) PROXY_TYPE="redirect" ;;
    *) fail config "unsupported local proxy type: $PROXY_TYPE" ;;
esac
LISTEN_PORT=$(jval listen_port)
case "$LISTEN_PORT" in ''|*[!0-9]*) LISTEN_PORT=1080 ;; esac

BB=""
for path in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox /system/xbin/busybox; do
    [ -x "$path" ] && BB="$path" && break
done
[ -z "$BB" ] && BB=$(command -v busybox 2>/dev/null)
[ -n "$BB" ] || fail client "busybox not found"

if [ "$PROXY_TYPE" = "socks5" ]; then
    # Offer both no-auth and username/password methods. A valid SOCKS5 server
    # replies with version 5 and one selected method (00 or 02).
    HANDSHAKE=$(printf '\005\002\000\002' | "$BB" nc -w 5 127.0.0.1 "$LISTEN_PORT" 2>/dev/null | "$BB" od -An -tx1 -N2 | tr -d ' \n')
    case "$HANDSHAKE" in
        0500|0502)
            cleanup
            printf '{"success":true,"stage":"complete","message":"SOCKS5 listener handshake succeeded","proxy_type":"socks5","listen_port":%s}' "$LISTEN_PORT"
            exit 0
            ;;
        *) fail handshake "SOCKS5 handshake failed (reply=$HANDSHAKE)" ;;
    esac
fi

IPT=$(command -v iptables 2>/dev/null)
[ -z "$IPT" ] && IPT="/system/bin/iptables"
[ -x "$IPT" ] || fail iptables "iptables not found"
"$IPT" -t nat -C OUTPUT -p tcp -j "$CHAIN" 2>/dev/null || fail iptables "IPv4 OUTPUT redirect rule is missing"
"$IPT" -t nat -L "$CHAIN" -n 2>/dev/null | grep -q 'REDIRECT' || fail iptables "IPv4 transparent redirect target is missing"
"$IPT" -t filter -C OUTPUT -p udp -j "$QUIC_CHAIN" 2>/dev/null || fail iptables "QUIC fallback rule is missing"
IP6T=$(command -v ip6tables 2>/dev/null)
[ -z "$IP6T" ] && IP6T="/system/bin/ip6tables"
IPV6_PROXY_ENABLED=false
if [ -x "$IP6T" ] && "$IP6T" -t nat -L OUTPUT -n >/dev/null 2>&1; then
    if "$IP6T" -t nat -C OUTPUT -p tcp -j "$IP6_CHAIN" 2>/dev/null && \
       "$IP6T" -t nat -L "$IP6_CHAIN" -n 2>/dev/null | grep -q 'REDIRECT'; then
        IPV6_PROXY_ENABLED=true
    fi
fi
if [ -x "$IP6T" ]; then
    "$IP6T" -t filter -C OUTPUT -p udp -j "$QUIC_CHAIN" 2>/dev/null || fail iptables "IPv6 QUIC fallback rule is missing"
fi

# /data/adb is intentionally inaccessible to Android shell UID 2000 on many
# Magisk/KernelSU setups. Copy BusyBox to shell-accessible storage for this
# one diagnostic request, then remove it immediately.
TEST_DIR="/data/local/tmp/gost-test-$$"
TEST_CLIENT="$TEST_DIR/busybox"
mkdir "$TEST_DIR" 2>/dev/null || fail client "failed to create test directory in /data/local/tmp"
cp "$BB" "$TEST_CLIENT" 2>/dev/null || fail client "failed to stage busybox in /data/local/tmp"
chown 2000:2000 "$TEST_DIR" "$TEST_CLIENT" 2>/dev/null || true
chmod 755 "$TEST_DIR" "$TEST_CLIENT" 2>/dev/null || fail client "failed to make staged busybox executable"

# The module/API runs as root and UID 0 is deliberately bypassed to prevent
# gost's own upstream connections looping. Run the request as Android shell
# UID 2000 so it traverses the OUTPUT transparent redirect rule.
TEST_CMD="$TEST_CLIENT wget -q -T 12 -O /dev/null $TEST_URL"
START=$(date +%s 2>/dev/null)
TEST_OUTPUT=$(su 2000 -c "$TEST_CMD" 2>&1)
RC=$?
END=$(date +%s 2>/dev/null)
case "$START:$END" in *[!0-9:]*|:) ELAPSED=0 ;; *) ELAPSED=$((END - START)) ;; esac

if [ "$RC" -ne 0 ]; then
    fail request "proxy request failed (code=$RC): $TEST_OUTPUT"
fi

cleanup
printf '{"success":true,"stage":"complete","message":"REDIRECT transparent proxy request succeeded","proxy_type":"redirect","listen_port":%s,"ipv6_proxy":%s,"elapsed":%s,"test_url":"%s"}' \
    "$LISTEN_PORT" "$IPV6_PROXY_ENABLED" "$ELAPSED" "$TEST_URL"

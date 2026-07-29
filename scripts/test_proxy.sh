#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
CONFIG="$MODDIR/gost/config.json"
PIDFILE="/tmp/gost.pid"
CHAIN="GOST_REDIRECT"
TEST_URL="https://www.gstatic.com/generate_204"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{if (NR > 1) printf "\\n"; printf "%s", $0}'
}

jval() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

TEST_CLIENT=""
cleanup() {
    [ -n "$TEST_CLIENT" ] && rm -f "$TEST_CLIENT" 2>/dev/null
}

fail() {
    cleanup
    printf '{"success":false,"stage":"%s","message":"%s"}' "$1" "$(json_escape "$2")"
    exit 0
}

[ -f "$PIDFILE" ] || fail process "gost PID file not found"
GOST_PID=$(cat "$PIDFILE" 2>/dev/null)
[ -n "$GOST_PID" ] && kill -0 "$GOST_PID" 2>/dev/null || fail process "gost process is not running"

IPT=$(command -v iptables 2>/dev/null)
[ -z "$IPT" ] && IPT="/system/bin/iptables"
[ -x "$IPT" ] || fail iptables "iptables not found"
"$IPT" -t nat -C OUTPUT -p tcp -j "$CHAIN" 2>/dev/null || fail iptables "OUTPUT redirect rule is missing"
"$IPT" -t nat -L "$CHAIN" -n 2>/dev/null | grep -q 'REDIRECT' || fail iptables "transparent redirect target is missing"

LISTEN_PORT=$(jval listen_port)
case "$LISTEN_PORT" in ''|*[!0-9]*) LISTEN_PORT=1080 ;; esac

BB=""
for path in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox /system/xbin/busybox; do
    [ -x "$path" ] && BB="$path" && break
done
[ -z "$BB" ] && BB=$(command -v busybox 2>/dev/null)
[ -n "$BB" ] || fail client "busybox not found"

# /data/adb is intentionally inaccessible to Android shell UID 2000 on many
# Magisk/KernelSU setups. Copy BusyBox to shell-accessible storage for this
# one diagnostic request, then remove it immediately.
TEST_CLIENT="/data/local/tmp/gost-test-busybox-$$"
cp "$BB" "$TEST_CLIENT" 2>/dev/null || fail client "failed to stage busybox in /data/local/tmp"
chown 2000:2000 "$TEST_CLIENT" 2>/dev/null || true
chmod 755 "$TEST_CLIENT" 2>/dev/null || fail client "failed to make staged busybox executable"

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
printf '{"success":true,"stage":"complete","message":"Transparent proxy request succeeded","listen_port":%s,"elapsed":%s,"test_url":"%s"}' \
    "$LISTEN_PORT" "$ELAPSED" "$TEST_URL"

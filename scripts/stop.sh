#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
LOGFILE="$MODDIR/logs/gost.log"
PIDFILE="/tmp/gost.pid"
LOCKDIR="/tmp/gost-operation.lock"

mkdir -p "$MODDIR/logs"

acquire_lock() {
    _wait=0
    _missing_owner=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        if [ -f "$LOCKDIR/pid" ]; then
            _missing_owner=0
            _owner=$(cat "$LOCKDIR/pid" 2>/dev/null)
            case "$_owner" in ''|*[!0-9]*) _owner="" ;; esac
            [ -n "$_owner" ] && kill -0 "$_owner" 2>/dev/null || rm -rf "$LOCKDIR"
        else
            _missing_owner=$((_missing_owner + 1))
            [ "$_missing_owner" -ge 2 ] && rm -rf "$LOCKDIR"
        fi
        _wait=$((_wait + 1))
        [ "$_wait" -ge 30 ] && return 1
        sleep 1
    done
    printf '%s\n' "$$" > "$LOCKDIR/pid"
    trap 'rm -rf "$LOCKDIR"' EXIT INT TERM
}

if [ "${GOST_LOCK_HELD:-0}" != "1" ]; then
    if ! acquire_lock; then
        echo "ERROR: another gost operation is in progress"
        exit 1
    fi
fi

# Remove traffic interception before stopping gost to avoid breaking networking.
if [ -f "$MODDIR/scripts/iptables.sh" ] && ! sh "$MODDIR/scripts/iptables.sh" "$MODDIR" stop >/dev/null 2>&1; then
    echo "ERROR: failed to remove transparent proxy rules"
    exit 1
fi

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

if [ -f "$PIDFILE" ]; then
    GOST_PID=$(cat "$PIDFILE")
    case "$GOST_PID" in ''|*[!0-9]*) GOST_PID="" ;; esac
    GOST_CMD=$(tr '\0' ' ' < "/proc/$GOST_PID/cmdline" 2>/dev/null)
    if [ -n "$GOST_PID" ] && kill -0 "$GOST_PID" 2>/dev/null && printf '%s' "$GOST_CMD" | grep -Fq "$MODDIR/gost/gost"; then
        kill "$GOST_PID" 2>/dev/null
        sleep 1
        if kill -0 "$GOST_PID" 2>/dev/null; then
            kill -9 "$GOST_PID" 2>/dev/null
            log_msg "Force killed gost (PID: $GOST_PID)"
        else
            log_msg "gost stopped gracefully (PID: $GOST_PID)"
        fi
        rm -f "$PIDFILE"
        echo "gost stopped (PID: $GOST_PID)"
        exit 0
    else
        rm -f "$PIDFILE"
        log_msg "Stale PID file removed"
    fi
fi

pkill -f "$MODDIR/gost/gost" 2>/dev/null
if [ $? -eq 0 ]; then
    log_msg "gost stopped via pkill"
    echo "gost stopped"
else
    log_msg "gost is not running"
    echo "gost is not running"
fi

rm -f "$PIDFILE"

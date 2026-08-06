#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
LOCKDIR="/tmp/gost-operation.lock"

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

if ! acquire_lock; then
    echo "ERROR: another gost operation is in progress"
    exit 1
fi

GOST_LOCK_HELD=1 sh "$MODDIR/scripts/stop.sh" "$MODDIR" >/dev/null 2>&1 || {
    echo "ERROR: failed to stop gost during restart"
    exit 1
}
sleep 1
GOST_LOCK_HELD=1 sh "$MODDIR/scripts/start.sh" "$MODDIR"

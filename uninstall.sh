#!/system/bin/sh

MODDIR=/data/adb/modules/gost_proxy
LOGFILE="$MODDIR/logs/uninstall.log"

mkdir -p "$MODDIR/logs"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] uninstall.sh started" >> "$LOGFILE"

[ -f "$MODDIR/scripts/iptables.sh" ] && sh "$MODDIR/scripts/iptables.sh" "$MODDIR" stop >/dev/null 2>&1

stop_owned_pid() {
    _pidfile="$1" _expected="$2" _label="$3"
    [ -f "$_pidfile" ] || return
    _pid=$(cat "$_pidfile" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) _pid="" ;; esac
    _cmd=$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null && printf '%s' "$_cmd" | grep -Fq "$_expected"; then
        kill "$_pid" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopped $_label (PID: $_pid)" >> "$LOGFILE"
    fi
    rm -f "$_pidfile"
}

stop_owned_pid /tmp/gost.pid "$MODDIR/gost/gost" "gost process"
stop_owned_pid /tmp/gost-webui.pid "$MODDIR/webui/server.sh" "WebUI process"

# Clean up geodata update temp directories and the persistent binary backup.
rm -rf "$MODDIR/gost/geodata"/.update.* 2>/dev/null
rm -rf /data/adb/gost_proxy 2>/dev/null

rm -f /tmp/gost.pid
rm -f /tmp/gost-webui.pid

echo "[$(date '+%Y-%m-%d %H:%M:%S')] All gost processes stopped" >> "$LOGFILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] uninstall.sh completed" >> "$LOGFILE"

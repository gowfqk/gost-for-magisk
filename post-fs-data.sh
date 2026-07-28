#!/system/bin/sh

MODDIR=${0%/*}
LOGFILE="$MODDIR/logs/post-fs-data.log"

mkdir -p "$MODDIR/logs"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data.sh started" >> "$LOGFILE"

if [ ! -f "$MODDIR/gost/gost" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: gost binary not found" >> "$LOGFILE"
    exit 1
fi

if [ ! -x "$MODDIR/gost/gost" ]; then
    chmod 755 "$MODDIR/gost/gost"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Set gost binary permissions" >> "$LOGFILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data.sh completed" >> "$LOGFILE"

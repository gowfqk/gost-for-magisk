#!/system/bin/sh

MODDIR=${0%/*}
LOGFILE="$MODDIR/logs/post-fs-data.log"
PERSIST_BIN="/data/adb/gost_proxy/gost"

mkdir -p "$MODDIR/logs"

# Root managers may replace the whole module directory during an update. Keep
# the WebUI-downloaded binary outside that directory and restore it when needed.
if [ ! -s "$MODDIR/gost/gost" ] && [ -s "$PERSIST_BIN" ]; then
    mkdir -p "$MODDIR/gost"
    cp "$PERSIST_BIN" "$MODDIR/gost/gost"
    chmod 755 "$MODDIR/gost/gost"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restored gost binary from persistent storage" >> "$LOGFILE"
fi

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

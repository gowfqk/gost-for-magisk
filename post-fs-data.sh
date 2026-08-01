#!/system/bin/sh

MODDIR=${0%/*}
LOGFILE="$MODDIR/logs/post-fs-data.log"
PERSIST_DIR="/data/adb/gost_proxy"
PERSIST_BIN="$PERSIST_DIR/gost"
MODULE_BIN="$MODDIR/gost/gost"

mkdir -p "$MODDIR/logs" "$PERSIST_DIR"

usable_gost_binary() {
    [ -s "$1" ] && ! grep -q "Placeholder" "$1" 2>/dev/null
}

atomic_copy() {
    _src="$1" _dst="$2" _dir=${2%/*}
    _tmp="$_dir/.gost.tmp.$$"
    mkdir -p "$_dir" || return 1
    cp "$_src" "$_tmp" || { rm -f "$_tmp"; return 1; }
    chmod 755 "$_tmp" 2>/dev/null
    mv -f "$_tmp" "$_dst" || { rm -f "$_tmp"; return 1; }
}

# Keep an update-proof copy outside every root-manager module directory. This
# also covers binaries installed manually or inherited from versions predating
# the WebUI persistence logic.
if usable_gost_binary "$MODULE_BIN"; then
    if atomic_copy "$MODULE_BIN" "$PERSIST_BIN"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Synced gost binary to persistent storage" >> "$LOGFILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: failed to sync persistent gost binary" >> "$LOGFILE"
    fi
elif usable_gost_binary "$PERSIST_BIN"; then
    if atomic_copy "$PERSIST_BIN" "$MODULE_BIN"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restored gost binary from persistent storage" >> "$LOGFILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to restore persistent gost binary" >> "$LOGFILE"
    fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data.sh started" >> "$LOGFILE"

if ! usable_gost_binary "$MODULE_BIN"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: usable gost binary not found" >> "$LOGFILE"
    exit 1
fi

if [ ! -x "$MODULE_BIN" ]; then
    chmod 755 "$MODULE_BIN"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Set gost binary permissions" >> "$LOGFILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data.sh completed" >> "$LOGFILE"

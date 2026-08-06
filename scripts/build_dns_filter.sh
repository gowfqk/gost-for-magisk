#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
SRC_DIR="$REPO_DIR/dns/src"
OUTPUT="$REPO_DIR/dns/bin/dns-filter-arm64"
TMP="$OUTPUT.tmp.$$"

cleanup() {
    rm -f "$TMP"
}
trap cleanup EXIT INT TERM

cd "$SRC_DIR"
CGO_ENABLED=0 GOOS=android GOARCH=arm64 \
    go build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o "$TMP" .
chmod 755 "$TMP"
mv -f "$TMP" "$OUTPUT"
trap - EXIT INT TERM
printf 'Built %s\n' "$OUTPUT"

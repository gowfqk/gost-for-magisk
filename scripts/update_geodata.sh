#!/system/bin/sh
# Download and convert GeoSite/GeoIP data into GOST bypass rules.
# All replacements are atomic; a failed update keeps the previous cache.
MODDIR=${1:-/data/adb/modules/gost_proxy}
DATA_DIR="$MODDIR/gost/geodata"
TOOLS_DIR="$MODDIR/gost/tools"
TMP_DIR="$DATA_DIR/.update.$$"
STATUS="$DATA_DIR/status.json"

mkdir -p "$DATA_DIR" "$TOOLS_DIR" || exit 1
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" || exit 1
umask 077

GEOSITE_TAG="202607282253"
GEOIP_TAG="202607291055"
GEOVIEW_TAG="0.2.6"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/$GEOSITE_TAG/geosite.dat"
GEOIP_URL="https://github.com/Loyalsoldier/geoip/releases/download/$GEOIP_TAG/geoip-only-cn-private.dat"
MMDB_URL="https://github.com/Loyalsoldier/geoip/releases/download/$GEOIP_TAG/Country.mmdb"

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        busybox sha256sum "$1" | awk '{print $1}'
    fi
}

download() {
    curl -fL --retry 2 --connect-timeout 15 --max-time 300 "$2" -o "$1" >/dev/null 2>&1 || \
    wget -T 30 -t 2 -O "$1" "$2" >/dev/null 2>&1
    [ -s "$1" ]
}

verify() { [ "$(sha256 "$1")" = "$2" ]; }

fetch_one() {
    download "$1" "$2" && verify "$1" "$3" || {
        echo "download/checksum failed: $2" >&2
        rm -rf "$TMP_DIR"
        exit 1
    }
}

# ---- Download geoview binary (skip if already present and valid) ----
abi=$(getprop ro.product.cpu.abi 2>/dev/null)
case "$abi" in
    arm64-v8a)   gv_arch=arm64; gv_hash=f7250e82b0e688a2c535cdd4e935a953c41926490d7c48a970c68a2023d5e6d7 ;;
    armeabi-v7a|armeabi) gv_arch=armv7; gv_hash=cc7ccb43ddb1af8a6df0a7026acfb01ba9a4d4fcc736cac9c83e3d614bdaa43d ;;
    x86_64)      gv_arch=amd64; gv_hash=fbd309ba28f36f72c9f3c6a33b87c43136199164215fb7efbab289329193c722 ;;
    x86)         gv_arch=i386; gv_hash=ee8871dc99b01d8e62da09bf6c650103862ec57a0107bf51194f78f0022ebd5b ;;
    *) rm -rf "$TMP_DIR"; echo "unsupported ABI: $abi" >&2; exit 1 ;;
esac

if [ -x "$TOOLS_DIR/geoview" ] && verify "$TOOLS_DIR/geoview" "$gv_hash" 2>/dev/null; then
    cp "$TOOLS_DIR/geoview" "$TMP_DIR/geoview"
else
    GV_URL="https://github.com/snowie2000/geoview/releases/download/$GEOVIEW_TAG/geoview-linux-$gv_arch"
    download "$TMP_DIR/geoview" "$GV_URL" || { rm -rf "$TMP_DIR"; echo "geoview download failed" >&2; exit 1; }
    verify "$TMP_DIR/geoview" "$gv_hash" || { rm -rf "$TMP_DIR"; echo "geoview checksum mismatch" >&2; exit 1; }
fi
chmod 755 "$TMP_DIR/geoview"

# ---- Download geodata files ----
fetch_one "$TMP_DIR/GeoSite.dat" "$GEOSITE_URL" "7ba5768a73e86f1382349badd26d6f21f8b74fd7280d473fd636ad623f771b14"
fetch_one "$TMP_DIR/GeoIP.dat" "$GEOIP_URL" "e9cb5a5bd338a9e4a2b9161517e3362da667ce9ff884c62d560d762b526f7e58"
fetch_one "$TMP_DIR/Country.mmdb" "$MMDB_URL" "4ec13992731853fe3815a5e66cdc79be621eb51c447983de7bbd156a9d554080"

# ---- Convert rules with geoview ----
# `extract` intentionally emits untyped domain values, which loses the difference
# between exact and suffix matches. Convert to Quantumult X first, then translate
# its typed rules into the GOST bypass syntax.
"$TMP_DIR/geoview" -action convert -type geosite -input "$TMP_DIR/GeoSite.dat" \
    -list china-list,private -format quantumultx -output "$TMP_DIR/domains.qx" >/dev/null 2>&1 || {
    rm -rf "$TMP_DIR"; echo "geoview geosite conversion failed" >&2; exit 1; }

"$TMP_DIR/geoview" -action convert -type geoip -input "$TMP_DIR/GeoIP.dat" \
    -list cn,private -format quantumultx -output "$TMP_DIR/cidrs.qx" >/dev/null 2>&1 || {
    rm -rf "$TMP_DIR"; echo "geoview geoip conversion failed" >&2; exit 1; }

# GOST has no keyword/substring matcher. Translating `host-keyword,apple`
# into `.apple` would be incorrect: it misses apple.com and changes the rule.
# Keep only exact and suffix rules, and report omitted keyword rules explicitly.
awk -F ',' '
    $1 == "host" && $2 != "" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }
    $1 == "host-suffix" && $2 != "" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); sub(/^\./, "", $2); print "." $2 }
' "$TMP_DIR/domains.qx" | sort -u > "$TMP_DIR/direct-domains.txt"
keyword_count=$(awk -F ',' '$1 == "host-keyword" && $2 != "" { count++ } END { print count + 0 }' "$TMP_DIR/domains.qx")
awk -F ',' '
    ($1 == "ip-cidr" || $1 == "ip6-cidr") && $2 != "" { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }
' "$TMP_DIR/cidrs.qx" | sort -u > "$TMP_DIR/direct-cidrs.txt"
cat "$TMP_DIR/direct-domains.txt" "$TMP_DIR/direct-cidrs.txt" > "$TMP_DIR/direct-rules.txt"

domain_count=$(wc -l < "$TMP_DIR/direct-domains.txt")
cidr_count=$(wc -l < "$TMP_DIR/direct-cidrs.txt")
rule_count=$((domain_count + cidr_count))
if [ "$rule_count" -eq 0 ]; then
    rm -rf "$TMP_DIR"
    echo "geodata conversion produced no usable rules" >&2
    exit 1
fi
now=$(date '+%Y-%m-%dT%H:%M:%S%z')

printf '{"success":true,"updated_at":"%s","geosite_tag":"%s","geoip_tag":"%s","geoview":"%s","domain_rules":%s,"cidr_rules":%s,"keyword_rules_skipped":%s,"rules":%s,"skipped_types":"keyword,regexp"}\n' \
    "$now" "$GEOSITE_TAG" "$GEOIP_TAG" "$GEOVIEW_TAG" "$domain_count" "$cidr_count" "$keyword_count" "$rule_count" > "$TMP_DIR/status.json"

# ---- Atomic swap into place ----
for f in GeoSite.dat GeoIP.dat Country.mmdb direct-domains.txt direct-cidrs.txt direct-rules.txt status.json; do
    mv -f "$TMP_DIR/$f" "$DATA_DIR/$f" || { rm -rf "$TMP_DIR"; echo "atomic move failed: $f" >&2; exit 1; }
done
mv -f "$TMP_DIR/geoview" "$TOOLS_DIR/geoview"
rm -rf "$TMP_DIR"
chmod 755 "$TOOLS_DIR/geoview"

echo "geodata updated: $rule_count rules ($domain_count domains, $cidr_count CIDRs)"
exit 0

#!/system/bin/sh
# Test a domain or IPv4 address against the active custom and GeoData bypass rules.

MODDIR="${1:-/data/adb/modules/gost_proxy}"
TARGET="$2"
CONFIG="$MODDIR/gost/config.json"
GEODATA_RULES="$MODDIR/gost/geodata/direct-rules.txt"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{if (NR > 1) printf "\\n"; printf "%s", $0}'
}

respond() {
    printf '{"success":%s,"target":"%s","matched":%s,"action":"%s","source":"%s","rule":"%s","message":"%s"}' \
        "$1" "$(json_escape "$TARGET")" "$2" "$3" "$4" "$(json_escape "$5")" "$(json_escape "$6")"
}

case "$TARGET" in
    "") respond false false invalid none "" "Target is required"; exit 0 ;;
    *[!A-Za-z0-9._:-]*) respond false false invalid none "" "Target contains unsupported characters"; exit 0 ;;
esac
TARGET=$(printf '%s' "$TARGET" | tr 'A-Z' 'a-z' | sed 's/\.$//')

[ -f "$CONFIG" ] || { respond false false invalid none "" "Config not found"; exit 0; }

section_value() {
    awk -v section="$1" -v key="$2" '
        function object(json, name, p,r,s,i,c,q,e,d) {
            p="\\\"" name "\\\"[[:space:]]*:"; if (!match(json,p)) return ""
            s=RSTART+RLENGTH; r=substr(json,s); if (!match(r,/^[[:space:]]*\{/)) return ""
            s+=RSTART+RLENGTH-2; d=0
            for(i=s;i<=length(json);i++){c=substr(json,i,1); if(q){if(e)e=0;else if(c=="\\")e=1;else if(c=="\"")q=0;continue} if(c=="\"")q=1;else if(c=="{")d++;else if(c=="}"&&--d==0)return substr(json,s,i-s+1)}
            return ""
        }
        {json=json $0 "\n"}
        END {o=object(json,section); p="\\\"" key "\\\"[[:space:]]*:"; if(!match(o,p))exit; r=substr(o,RSTART+RLENGTH); sub(/^[[:space:]]*/,"",r); if(substr(r,1,1)=="["){if(match(r,/^\[[^]]*\]/))print substr(r,2,RLENGTH-2)}else if(match(r,/^[^,}]*/))print substr(r,RSTART,RLENGTH)}
    ' "$CONFIG" 2>/dev/null
}

match_rules() {
    _source="$1"
    awk -v target="$TARGET" -v source="$_source" '
        function ipv4num(ip, a) { if (split(ip,a,".") != 4) return -1; for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/||a[i]>255)return -1; return ((a[1]*256+a[2])*256+a[3])*256+a[4] }
        function cidrmatch(ip, rule, p,n,bits,size) { p=index(rule,"/"); if(!p)return 0; n=ipv4num(substr(rule,1,p-1)); bits=substr(rule,p+1)+0; ip=ipv4num(ip); if(n<0||ip<0||bits<0||bits>32)return 0; size=2^(32-bits); return int(ip/size)==int(n/size) }
        function globregex(s, out,i,c) { out="^"; for(i=1;i<=length(s);i++){c=substr(s,i,1); if(c=="*")out=out ".*"; else if(c=="?")out=out "."; else if(c~/[.\\+(){}|^$\[\]]/)out=out "\\" c; else out=out c} return out "$" }
        {
            rule=tolower($0); gsub(/^[[:space:],\[]+|[[:space:],\]]+$/, "", rule); gsub(/^"+|"+$/, "", rule); if(rule==""||substr(rule,1,1)=="#")next
            hit=0
            if(index(rule,"/")&&target~/^[0-9.]+$/) hit=cidrmatch(target,rule)
            else if(rule~/^[0-9.]+$/) hit=(target==rule)
            else if(substr(rule,1,1)==".") hit=(target==substr(rule,2)||length(target)>length(rule)&&substr(target,length(target)-length(rule)+1)==rule)
            else if(index(rule,"*")||index(rule,"?")) hit=(target~globregex(rule))
            else hit=(target==rule)
            if(hit){print source "\t" rule; exit}
        }
    '
}

ROUTING_ENABLED=$(section_value routing enabled | tr -d '[:space:]')
GEODATA_ENABLED=$(section_value geodata enabled | tr -d '[:space:]')
MATCH=""
if [ "$ROUTING_ENABLED" = "true" ]; then
    CUSTOM_RULES=$(section_value routing bypass | tr ',' '\n')
    MATCH=$(printf '%s\n' "$CUSTOM_RULES" | match_rules custom)
fi
if [ -z "$MATCH" ] && [ "$GEODATA_ENABLED" = "true" ] && [ -s "$GEODATA_RULES" ]; then
    MATCH=$(match_rules geodata < "$GEODATA_RULES")
fi

if [ -n "$MATCH" ]; then
    SOURCE=$(printf '%s' "$MATCH" | cut -f1)
    RULE=$(printf '%s' "$MATCH" | cut -f2-)
    respond true true direct "$SOURCE" "$RULE" "Matched bypass rule; traffic will go direct"
else
    respond true false proxy none "" "No enabled bypass rule matched; traffic will use the upstream proxy"
fi

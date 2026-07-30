#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
LOGFILE="$MODDIR/logs/gost.log"
PIDFILE="/tmp/gost.pid"
CONFIG="$MODDIR/gost/config.json"
GOST_BIN="$MODDIR/gost/gost"

mkdir -p "$MODDIR/logs"

# Keep GOST diagnostics useful without allowing an always-on proxy to consume
# unlimited module storage. Copy-truncate preserves the running process file
# descriptor, unlike renaming an active log file.
trim_log() {
    _max_bytes=262144
    _keep_bytes=131072
    [ -f "$LOGFILE" ] || return 0
    _size=$(wc -c < "$LOGFILE" 2>/dev/null)
    case "$_size" in ''|*[!0-9]*) return 0 ;; esac
    [ "$_size" -lt "$_max_bytes" ] && return 0
    _tmp="$LOGFILE.trim.$$"
    tail -c "$_keep_bytes" "$LOGFILE" > "$_tmp" 2>/dev/null && cat "$_tmp" > "$LOGFILE"
    rm -f "$_tmp"
}

start_log_guard() {
    _gost_pid="$1"
    (
        while kill -0 "$_gost_pid" 2>/dev/null; do
            sleep 30
            trim_log
        done
    ) &
}

trim_log

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log_msg "gost is already running (PID: $OLD_PID)"
        echo "gost is already running (PID: $OLD_PID)"
        exit 0
    fi
    rm -f "$PIDFILE"
fi

if [ ! -f "$GOST_BIN" ]; then
    log_msg "ERROR: gost binary not found at $GOST_BIN"
    echo "ERROR: gost binary not found"
    exit 1
fi

if [ ! -x "$GOST_BIN" ]; then
    chmod 755 "$GOST_BIN"
fi

if [ ! -f "$CONFIG" ]; then
    log_msg "ERROR: config file not found at $CONFIG"
    echo "ERROR: config file not found"
    exit 1
fi

# ---- Parse config and build gost command line ----
jval() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

jsection_val() {
    _section="$1" _key="$2"
    awk -v section="$_section" -v key="$_key" '
        function find_object(json, section,    pattern, rest, start, i, ch, escaped, quoted, depth) {
            pattern = "\\\"" section "\\\"[[:space:]]*:"
            if (!match(json, pattern)) return ""
            start = RSTART + RLENGTH
            rest = substr(json, start)
            if (!match(rest, /^[[:space:]]*\{/)) return ""
            start += RSTART + RLENGTH - 2
            depth = 0; quoted = 0; escaped = 0
            for (i = start; i <= length(json); i++) {
                ch = substr(json, i, 1)
                if (quoted) {
                    if (escaped) escaped = 0
                    else if (ch == "\\") escaped = 1
                    else if (ch == "\"") quoted = 0
                    continue
                }
                if (ch == "\"") quoted = 1
                else if (ch == "{") depth++
                else if (ch == "}" && --depth == 0) return substr(json, start, i - start + 1)
            }
            return ""
        }
        function get_scalar(object, key,    pattern, rest, i, ch, escaped, value) {
            pattern = "\\\"" key "\\\"[[:space:]]*:"
            if (!match(object, pattern)) return ""
            rest = substr(object, RSTART + RLENGTH)
            sub(/^[[:space:]]*/, "", rest)
            if (substr(rest, 1, 1) == "[") {
                if (match(rest, /^\[[^]]*\]/)) return substr(rest, 2, RLENGTH - 2)
                return ""
            }
            if (substr(rest, 1, 1) != "\"") {
                if (match(rest, /^[^,}]*/)) {
                    value = substr(rest, RSTART, RLENGTH)
                    sub(/[[:space:]]*$/, "", value)
                    return value
                }
                return ""
            }
            value = ""; escaped = 0
            for (i = 2; i <= length(rest); i++) {
                ch = substr(rest, i, 1)
                if (escaped) {
                    if (ch == "\"" || ch == "\\" || ch == "/") value = value ch
                    else if (ch == "n") value = value "\\n"
                    else if (ch == "r") value = value "\\r"
                    else if (ch == "t") value = value "\\t"
                    else value = value "\\" ch
                    escaped = 0
                } else if (ch == "\\") escaped = 1
                else if (ch == "\"") return value
                else value = value ch
            }
            return ""
        }
        { json = json $0 "\n" }
        END {
            object = find_object(json, section)
            if (object != "") print get_scalar(object, key)
        }
    ' "$CONFIG" 2>/dev/null
}

PROXY_TYPE="redirect"
LISTEN_ADDR=$(jval listen_addr)
[ -z "$LISTEN_ADDR" ] && LISTEN_ADDR="0.0.0.0"
LISTEN_PORT=$(jval listen_port)
[ -z "$LISTEN_PORT" ] && LISTEN_PORT="1080"

log_msg "Config: type=$PROXY_TYPE addr=$LISTEN_ADDR port=$LISTEN_PORT"

urlencode() {
    printf '%s' "$1" | od -An -tx1 | tr -d ' \n' | awk '
        BEGIN { safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~" }
        {
            for (i = 1; i <= length($0); i += 2) {
                hex = substr($0, i, 2)
                dec = (index("0123456789abcdef", substr(hex, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(hex, 2, 1)) - 1
                ch = sprintf("%c", dec)
                if (index(safe, ch)) printf "%s", ch
                else printf "%%%s", toupper(hex)
            }
        }
    '
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---- Build the -L (listen) argument ----
AUTH_ENABLED=$(jsection_val auth enabled)
AUTH_USER=$(jsection_val auth username)
AUTH_PASS=$(jsection_val auth password)

AUTH_PART=""
if [ "$AUTH_ENABLED" = "true" ] && [ -n "$AUTH_USER" ]; then
    AUTH_PART="$(urlencode "$AUTH_USER"):$(urlencode "$AUTH_PASS")@"
fi

case "$PROXY_TYPE" in
    redirect|red|redir) SCHEME="red" ;;
    http|socks5|socks4|relay) SCHEME="$PROXY_TYPE" ;;
    ss|shadowsocks)
        SCHEME="ss"
        SS_METHOD=$(jsection_val shadowsocks method)
        [ -z "$SS_METHOD" ] && SS_METHOD="aes-256-cfb"
        SS_PASS=$(jsection_val shadowsocks password)
        LISTEN_URL="${SCHEME}://$(urlencode "$SS_METHOD"):$(urlencode "$SS_PASS")@${LISTEN_ADDR}:${LISTEN_PORT}"
        ;;
    *) SCHEME="http" ;;
esac

if [ "$PROXY_TYPE" != "ss" ] && [ "$PROXY_TYPE" != "shadowsocks" ]; then
    TLS_CERT=$(jsection_val tls cert)
    TLS_KEY=$(jsection_val tls key)
    TLS_CA=$(jsection_val tls ca)
    TLS_ENABLED=false
    if [ "$PROXY_TYPE" = "tls" ] || [ -n "$TLS_CERT" ]; then
        TLS_ENABLED=true
        SCHEME="http+tls"
    fi
    WS_PATH=$(jsection_val websocket path)
    if [ "$PROXY_TYPE" = "ws" ]; then
        [ -z "$WS_PATH" ] && WS_PATH="/ws"
        if [ "$TLS_ENABLED" = "true" ]; then SCHEME="http+wss"; else SCHEME="http+ws"; fi
    elif [ -n "$WS_PATH" ]; then
        if [ "$TLS_ENABLED" = "true" ]; then SCHEME="http+wss"; else SCHEME="${SCHEME}+ws"; fi
    fi
    if [ "$SCHEME" = "red" ]; then AUTH_PART=""; fi
    LISTEN_URL="${SCHEME}://${AUTH_PART}${LISTEN_ADDR}:${LISTEN_PORT}"
    QUERY=""
    append_query() {
        _key="$1" _value="$2"
        [ -z "$_value" ] && return
        if [ -z "$QUERY" ]; then QUERY="?"; else QUERY="${QUERY}&"; fi
        QUERY="${QUERY}${_key}=$(urlencode "$_value")"
    }
    append_query path "$WS_PATH"
    WS_HOST=$(jsection_val websocket host)
    append_query host "$WS_HOST"
    append_query certFile "$TLS_CERT"
    append_query keyFile "$TLS_KEY"
    append_query caFile "$TLS_CA"
    if [ "$SCHEME" = "red" ]; then
        QUERY=""
        TRANSPARENT_SNIFFING=$(jsection_val transparent sniffing)
        TRANSPARENT_SNIFF_TIMEOUT=$(jsection_val transparent sniffing_timeout)
        TRANSPARENT_SNIFF_FALLBACK=$(jsection_val transparent sniffing_fallback)
        TRANSPARENT_DIAL_ORIGINAL_DST=$(jsection_val transparent sniffing_dial_original_dst)
        TRANSPARENT_MARK=$(jsection_val transparent mark)
        if [ "$TRANSPARENT_SNIFFING" != "false" ]; then
            [ -z "$TRANSPARENT_SNIFF_TIMEOUT" ] && TRANSPARENT_SNIFF_TIMEOUT="5s"
            [ "$TRANSPARENT_SNIFF_FALLBACK" = "false" ] && TRANSPARENT_SNIFF_FALLBACK=false || TRANSPARENT_SNIFF_FALLBACK=true
            [ "$TRANSPARENT_DIAL_ORIGINAL_DST" = "true" ] && TRANSPARENT_DIAL_ORIGINAL_DST=true || TRANSPARENT_DIAL_ORIGINAL_DST=false
            append_query sniffing true
            append_query sniffing.timeout "$TRANSPARENT_SNIFF_TIMEOUT"
            append_query sniffing.fallback "$TRANSPARENT_SNIFF_FALLBACK"
            append_query sniffing.dialOriginalDst "$TRANSPARENT_DIAL_ORIGINAL_DST"
        fi
        case "$TRANSPARENT_MARK" in ''|*[!0-9]*) TRANSPARENT_MARK=100 ;; esac
        append_query so_mark "$TRANSPARENT_MARK"
    fi
    LISTEN_URL="${LISTEN_URL}${QUERY}"
fi

log_msg "Listen configured: scheme=$SCHEME addr=$LISTEN_ADDR port=$LISTEN_PORT"

# ---- Build the -F (forward/upstream) argument ----
UPSTREAM_ENABLED=$(jsection_val upstream enabled)
log_msg "Debug: upstream.enabled raw = [$UPSTREAM_ENABLED]"
FORWARD_URL=""

if [ "$UPSTREAM_ENABLED" = "true" ]; then
    UP_TYPE=$(jsection_val upstream type)
    [ -z "$UP_TYPE" ] && UP_TYPE="http"
    UP_ADDR=$(jsection_val upstream addr)
    UP_PORT=$(jsection_val upstream port)
    UP_USER=$(jsection_val upstream username)
    UP_PASS=$(jsection_val upstream password)
    UP_WS_PATH=$(jsection_val upstream ws_path)
    UP_WS_HOST=$(jsection_val upstream ws_host)
    log_msg "Debug: upstream type=$UP_TYPE addr=$UP_ADDR port=$UP_PORT user=$UP_USER ws_path=$UP_WS_PATH"

    if [ -n "$UP_ADDR" ] && [ -n "$UP_PORT" ] && [ "$UP_PORT" != "0" ]; then
        UP_AUTH=""
        if [ -n "$UP_USER" ]; then
            UP_AUTH="$(urlencode "$UP_USER"):$(urlencode "$UP_PASS")@"
        fi
        UP_SCHEME="$UP_TYPE"
        case "$UP_TYPE" in *+ws*|*+wss*) ;; *)
            if [ -n "$UP_WS_PATH" ]; then UP_SCHEME="${UP_SCHEME}+ws"; fi ;;
        esac
        FORWARD_URL="${UP_SCHEME}://${UP_AUTH}${UP_ADDR}:${UP_PORT}"
        UP_QUERY=""
        append_up_query() {
            _key="$1" _value="$2"
            [ -z "$_value" ] && return
            if [ -z "$UP_QUERY" ]; then UP_QUERY="?"; else UP_QUERY="${UP_QUERY}&"; fi
            UP_QUERY="${UP_QUERY}${_key}=$(urlencode "$_value")"
        }
        case "$UP_TYPE" in socks|socks5|socks+ws|socks+wss|socks5+ws|socks5+wss)
            append_up_query notls true ;;
        esac
        TRANSPARENT_MARK=$(jsection_val transparent mark)
        case "$TRANSPARENT_MARK" in ''|*[!0-9]*) TRANSPARENT_MARK=100 ;; esac
        append_up_query so_mark "$TRANSPARENT_MARK"
        append_up_query resolver "223.5.5.5,1.1.1.1"
        if [ -n "$UP_WS_PATH" ]; then
            append_up_query path "$UP_WS_PATH"
            append_up_query host "$UP_WS_HOST"
        fi
        FORWARD_URL="${FORWARD_URL}${UP_QUERY}"
        log_msg "Forward configured: scheme=$UP_SCHEME addr=$UP_ADDR port=$UP_PORT"
    else
        log_msg "WARNING: upstream enabled but addr or port is empty/zero"
    fi
else
    log_msg "Debug: upstream not enabled, skipping -F"
fi

# ---- Parse geodata and routing config ----
GEODATA_ENABLED=$(jsection_val geodata enabled)
GEODATA_AUTO_UPDATE=$(jsection_val geodata auto_update)
GEODATA_DIR="$MODDIR/gost/geodata"
GEODATA_RULES="$GEODATA_DIR/direct-rules.txt"

ROUTING_ENABLED=$(jsection_val routing enabled)
ROUTING_BYPASS=$(jsection_val routing bypass)
ROUTING_DIRECT_UIDS=$(jsection_val routing direct_uids)

MULTI_LISTEN=$(jsection_val advanced multi_listen)
LOG_LEVEL=$(jsection_val advanced log_level)

# ---- Decide startup mode ----
# Config file mode is used when GeoData rules are ready or custom routing is
# configured. File-based bypasses avoid URL-length limits for large rule sets.
GEODATA_READY=false
if [ "$GEODATA_ENABLED" = "true" ] && [ -s "$GEODATA_RULES" ]; then
    GEODATA_READY=true
fi
USE_CONFIG=false
if [ -n "$FORWARD_URL" ] && { [ "$GEODATA_READY" = "true" ] || { [ "$ROUTING_ENABLED" = "true" ] && [ -n "$ROUTING_BYPASS" ]; }; }; then
    USE_CONFIG=true
fi
if [ "$GEODATA_ENABLED" = "true" ] && [ "$GEODATA_READY" = "false" ]; then
    log_msg "WARNING: geodata enabled but direct-rules.txt is missing or empty; run update_geodata.sh first. Starting without GeoData bypass."
fi

# ---- Generate GOST JSON config file (config file mode) ----
generate_runtime_config() {
    _out="$1"
    _esc_addr=$(json_escape "$UP_ADDR")
    _esc_port=$(json_escape "$UP_PORT")
    _esc_user=$(json_escape "$UP_USER")
    _esc_pass=$(json_escape "$UP_PASS")
    _esc_ws_path=$(json_escape "$UP_WS_PATH")
    _esc_ws_host=$(json_escape "$UP_WS_HOST")
    _esc_listen_addr=$(json_escape "$LISTEN_ADDR")

    # Parse connector and dialer types from upstream scheme
    _connector="${UP_TYPE%%+*}"
    _dialer="${UP_TYPE#*+}"
    if [ "$_connector" = "$_dialer" ]; then _dialer="tcp"; fi
    case "$_connector" in
        socks|socks5) _connector="socks5" ;;
        ss|shadowsocks) _connector="ss" ;;
        http|relay) ;;
        *) _connector="http" ;;
    esac
    case "$_dialer" in ws|wss|tls|tcp) ;; *) _dialer="tcp" ;; esac

    # Build connector metadata
    _conn_meta=""
    _need_meta=0
    case "$UP_TYPE" in socks|socks5|socks+ws|socks+wss|socks5+ws|socks5+wss)
        _conn_meta="${_conn_meta}\"notls\":\"true\""
        _need_meta=1 ;;
    esac
    if [ -n "$_esc_ws_path" ]; then
        [ $_need_meta -eq 1 ] && _conn_meta="${_conn_meta},"
        _conn_meta="${_conn_meta}\"path\":\"$_esc_ws_path\",\"host\":\"$_esc_ws_host\""
        _need_meta=1
    fi
    # For an SS upstream, the imported cipher and password are stored in the
    # same upstream username/password fields used to build the command-line URL.
    _conn_auth="null"
    if [ "$_connector" = "ss" ]; then
        _ss_method="$UP_USER"
        [ -z "$_ss_method" ] && _ss_method="aes-256-gcm"
        _conn_auth="{\"username\":\"$(json_escape "$_ss_method")\",\"password\":\"$_esc_pass\"}"
    elif [ -n "$UP_USER" ]; then
        _conn_auth="{\"username\":\"$_esc_user\",\"password\":\"$_esc_pass\"}"
    fi

    # Build dialer metadata (path/host for ws/wss)
    _dial_meta=""
    if [ -n "$_esc_ws_path" ]; then
        _dial_meta="\"path\":\"$_esc_ws_path\",\"host\":\"$_esc_ws_host\""
    fi

    # Build dialer TLS config (for wss/tls)
    _dial_tls="null"
    case "$_dialer" in wss|tls)
        _srv_name="$_esc_ws_host"
        [ -z "$_srv_name" ] && _srv_name="$_esc_addr"
        _dial_tls="{\"serverName\":\"$_srv_name\"}" ;;
    esac

    # Build bypass section
    _bypass_matchers=""
    if [ "$ROUTING_ENABLED" = "true" ] && [ -n "$ROUTING_BYPASS" ]; then
        _rules=$(printf '%s' "$ROUTING_BYPASS" | tr -d ' []"' | tr ',' '\n' | sed '/^$/d')
        if [ -n "$_rules" ]; then
            _bypass_matchers=$(printf '%s\n' "$_rules" | while IFS= read -r _r; do
                [ -z "$_r" ] && continue
                printf '"%s",' "$(json_escape "$_r")"
            done | sed 's/,$//')
        fi
    fi

    _bypass_fields=""
    if [ -n "$_bypass_matchers" ]; then
        _bypass_fields="\"matchers\":[$_bypass_matchers]"
    fi
    if [ "$GEODATA_READY" = "true" ]; then
        [ -n "$_bypass_fields" ] && _bypass_fields="${_bypass_fields},"
        _bypass_fields="${_bypass_fields}\"file\":{\"path\":\"$(json_escape "$GEODATA_RULES")\"},\"reload\":\"30s\""
    fi
    _bypass_json="{\"name\":\"bypass-0\""
    [ -n "$_bypass_fields" ] && _bypass_json="${_bypass_json},${_bypass_fields}"
    _bypass_json="${_bypass_json}}"

    # Build resolver section
    _resolver_json="{\"name\":\"resolver-0\",\"nameservers\":[{\"addr\":\"223.5.5.5\"},{\"addr\":\"1.1.1.1\"}]}"

    # Build services section (listener + optional multi-listen)
    _sniffing=$(jsection_val transparent sniffing)
    [ "$_sniffing" = "false" ] && _sniffing_val=false || _sniffing_val=true
    _sniff_timeout=$(jsection_val transparent sniffing_timeout)
    [ -z "$_sniff_timeout" ] && _sniff_timeout="5s"
    _sniff_fallback=$(jsection_val transparent sniffing_fallback)
    [ "$_sniff_fallback" = "false" ] && _sniff_fallback_val=false || _sniff_fallback_val=true
    _dial_original_dst=$(jsection_val transparent sniffing_dial_original_dst)
    [ "$_dial_original_dst" = "true" ] && _dial_original_dst_val=true || _dial_original_dst_val=false
    _so_mark=$(jsection_val transparent mark)
    case "$_so_mark" in ''|*[!0-9]*) _so_mark=100 ;; esac

    _services_json=""
    _add_service() {
        _port="$1"
        _svc="{\"name\":\"service-$_port\",\"addr\":\"$_esc_listen_addr:$_port\","
        _svc="${_svc}\"handler\":{\"type\":\"red\",\"chain\":\"chain-0\",\"metadata\":{\"sniffing\":$_sniffing_val,\"sniffing.timeout\":\"$(json_escape "$_sniff_timeout")\",\"sniffing.fallback\":$_sniff_fallback_val,\"sniffing.dialOriginalDst\":$_dial_original_dst_val}},"
        _svc="${_svc}\"listener\":{\"type\":\"red\"}}"
        if [ -n "$_services_json" ]; then _services_json="${_services_json},"; fi
        _services_json="${_services_json}$_svc"
    }
    _add_service "$LISTEN_PORT"
    if [ -n "$MULTI_LISTEN" ]; then
        OLD_IFS=$IFS
        IFS=','
        for _extra in $MULTI_LISTEN; do
            _extra=$(printf '%s' "$_extra" | tr -d ' []"')
            case "$_extra" in ''|*[!0-9]*) continue ;; esac
            [ "$_extra" -ge 1 ] 2>/dev/null && [ "$_extra" -le 65535 ] 2>/dev/null || continue
            [ "$_extra" = "$LISTEN_PORT" ] && continue
            _add_service "$_extra"
        done
        IFS=$OLD_IFS
    fi

    # Build chain section
    _conn_meta_json="null"
    [ -n "$_conn_meta" ] && _conn_meta_json="{$_conn_meta}"
    _dial_meta_json="null"
    [ -n "$_dial_meta" ] && _dial_meta_json="{$_dial_meta}"

    _chain_json="{\"name\":\"chain-0\",\"hops\":[{\"name\":\"hop-0\",\"sockopts\":{\"mark\":$_so_mark},\"resolver\":\"resolver-0\",\"bypass\":\"bypass-0\",\"nodes\":["
    _chain_json="${_chain_json}{\"name\":\"node-0\",\"addr\":\"$_esc_addr:$_esc_port\","
    _chain_json="${_chain_json}\"connector\":{\"type\":\"$_connector\",\"auth\":$_conn_auth,\"metadata\":$_conn_meta_json},"
    _chain_json="${_chain_json}\"dialer\":{\"type\":\"$_dialer\",\"tls\":$_dial_tls,\"metadata\":$_dial_meta_json}"
    _chain_json="${_chain_json}}]}]}"

    # Log level
    case "$LOG_LEVEL" in debug|trace) _log_level="debug" ;; *) _log_level="info" ;; esac

    # Assemble full config
    printf '%s\n' \
"{
  \"log\": {\"level\": \"$_log_level\"},
  \"bypasses\": [$_bypass_json],
  \"resolvers\": [$_resolver_json],
  \"services\": [$_services_json],
  \"chains\": [$_chain_json]
}" > "$_out"
}

# ---- Build optional extra listeners and log flags (command-line mode) ----
if [ "$USE_CONFIG" = "false" ]; then
    # Apply routing bypass as URL parameter (command-line mode only)
    if [ "$ROUTING_ENABLED" = "true" ] && [ -n "$ROUTING_BYPASS" ] && [ -n "$FORWARD_URL" ]; then
        ROUTING_BYPASS=$(printf '%s' "$ROUTING_BYPASS" | tr -d ' []"' | tr '\n' ',')
        [ -n "$ROUTING_BYPASS" ] && FORWARD_URL="${FORWARD_URL}&bypass=$(urlencode "$ROUTING_BYPASS")"
    fi

    set -- -L "$LISTEN_URL"
    OLD_IFS=$IFS
    IFS=','
    for EXTRA_PORT in $MULTI_LISTEN; do
        EXTRA_PORT=$(printf '%s' "$EXTRA_PORT" | tr -d ' []"')
        case "$EXTRA_PORT" in ''|*[!0-9]*) continue ;; esac
        if [ "$EXTRA_PORT" -ge 1 ] 2>/dev/null && [ "$EXTRA_PORT" -le 65535 ] 2>/dev/null; then
            if [ "$PROXY_TYPE" = "ss" ] || [ "$PROXY_TYPE" = "shadowsocks" ]; then
                EXTRA_URL="${SCHEME}://$(urlencode "$SS_METHOD"):$(urlencode "$SS_PASS")@${LISTEN_ADDR}:${EXTRA_PORT}"
            else
                EXTRA_URL="${SCHEME}://${AUTH_PART}${LISTEN_ADDR}:${EXTRA_PORT}${QUERY}"
            fi
            set -- "$@" -L "$EXTRA_URL"
        fi
    done
    IFS=$OLD_IFS
    [ "$LOG_LEVEL" = "debug" ] && set -- "$@" -D
    [ "$LOG_LEVEL" = "trace" ] && set -- "$@" -DD
    [ -n "$FORWARD_URL" ] && set -- "$@" -F "$FORWARD_URL"
fi

# ---- Start gost ----
log_msg "Starting gost proxy..."
if [ "$USE_CONFIG" = "true" ]; then
    log_msg "Mode: config file (geodata bypass enabled)"
    RUNTIME_CONFIG="$MODDIR/gost/runtime.json"
    if ! generate_runtime_config "$RUNTIME_CONFIG"; then
        log_msg "ERROR: failed to generate runtime config"
        echo "ERROR: failed to generate runtime config"
        exit 1
    fi
    cd "$MODDIR/gost" || {
        log_msg "ERROR: failed to enter $MODDIR/gost"
        echo "ERROR: failed to enter gost directory"
        exit 1
    }
    "$GOST_BIN" -C "$RUNTIME_CONFIG" >> "$LOGFILE" 2>&1 &
else
    if [ -n "$FORWARD_URL" ]; then
        log_msg "Mode: command-line (listener and upstream)"
    else
        log_msg "Mode: command-line (listener only)"
    fi
    cd "$MODDIR/gost" || {
        log_msg "ERROR: failed to enter $MODDIR/gost"
        echo "ERROR: failed to enter gost directory"
        exit 1
    }
    "$GOST_BIN" "$@" >> "$LOGFILE" 2>&1 &
fi

GOST_PID=$!
sleep 2

if kill -0 "$GOST_PID" 2>/dev/null; then
    echo "$GOST_PID" > "$PIDFILE"
    start_log_guard "$GOST_PID"
    if ! sh "$MODDIR/scripts/iptables.sh" "$MODDIR" start; then
        log_msg "ERROR: failed to install transparent proxy rules"
        kill "$GOST_PID" 2>/dev/null
        rm -f "$PIDFILE"
        echo "ERROR: failed to install transparent proxy rules"
        exit 1
    fi
    log_msg "gost transparent proxy started successfully (PID: $GOST_PID)"
    echo "gost transparent proxy started successfully (PID: $GOST_PID)"
else
    log_msg "ERROR: gost failed to start - check config"
    echo "ERROR: gost failed to start"
    exit 1
fi

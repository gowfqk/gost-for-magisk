#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
LOGFILE="$MODDIR/logs/gost.log"
PIDFILE="/tmp/gost.pid"
CONFIG="$MODDIR/gost/config.json"
GOST_BIN="$MODDIR/gost/gost"

mkdir -p "$MODDIR/logs"

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
# Helper: extract JSON value (simple, handles top-level string/number/bool)
jval() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

# Helper: extract a value from a top-level object section.
# Works with both pretty-printed and compact JSON and ignores braces/commas
# inside quoted strings. Sections used by this module contain scalar values.
# Usage: jsection_val "auth" "enabled"
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

            depth = 0
            quoted = 0
            escaped = 0
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

            value = ""
            escaped = 0
            for (i = 2; i <= length(rest); i++) {
                ch = substr(rest, i, 1)
                if (escaped) {
                    if (ch == "\"" || ch == "\\" || ch == "/") value = value ch
                    else if (ch == "n") value = value "\\n"
                    else if (ch == "r") value = value "\\r"
                    else if (ch == "t") value = value "\\t"
                    else value = value "\\" ch
                    escaped = 0
                } else if (ch == "\\") {
                    escaped = 1
                } else if (ch == "\"") {
                    return value
                } else {
                    value = value ch
                }
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

# Local traffic is always captured by a transparent REDIRECT listener.
# The upstream protocol remains configurable and may still be HTTP/SOCKS/SS.
PROXY_TYPE="redirect"

LISTEN_ADDR=$(jval listen_addr)
[ -z "$LISTEN_ADDR" ] && LISTEN_ADDR="0.0.0.0"

LISTEN_PORT=$(jval listen_port)
[ -z "$LISTEN_PORT" ] && LISTEN_PORT="1080"

log_msg "Config: type=$PROXY_TYPE addr=$LISTEN_ADDR port=$LISTEN_PORT"

# Percent-encode URL components before embedding user-provided values.
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

# ---- Build the -L (listen) argument ----
AUTH_ENABLED=$(jsection_val auth enabled)
AUTH_USER=$(jsection_val auth username)
AUTH_PASS=$(jsection_val auth password)

AUTH_PART=""
if [ "$AUTH_ENABLED" = "true" ] && [ -n "$AUTH_USER" ]; then
    AUTH_PART="$(urlencode "$AUTH_USER"):$(urlencode "$AUTH_PASS")@"
fi

# Map proxy_type to gost scheme
case "$PROXY_TYPE" in
    redirect|red|redir)
        SCHEME="red"
        ;;
    http|socks5|socks4|relay)
        SCHEME="$PROXY_TYPE"
        ;;
    ss|shadowsocks)
        SCHEME="ss"
        SS_METHOD=$(jsection_val shadowsocks method)
        [ -z "$SS_METHOD" ] && SS_METHOD="aes-256-cfb"
        SS_PASS=$(jsection_val shadowsocks password)
        # ss://method:password@addr:port
        LISTEN_URL="${SCHEME}://$(urlencode "$SS_METHOD"):$(urlencode "$SS_PASS")@${LISTEN_ADDR}:${LISTEN_PORT}"
        ;;
    *)
        SCHEME="http"
        ;;
esac

# For non-ss types, build the URL
if [ "$PROXY_TYPE" != "ss" ] && [ "$PROXY_TYPE" != "shadowsocks" ]; then
    # Check for TLS. A tls proxy type means HTTP over TLS.
    TLS_CERT=$(jsection_val tls cert)
    TLS_KEY=$(jsection_val tls key)
    TLS_CA=$(jsection_val tls ca)
    TLS_ENABLED=false
    if [ "$PROXY_TYPE" = "tls" ] || [ -n "$TLS_CERT" ]; then
        TLS_ENABLED=true
        SCHEME="http+tls"
    fi

    # Enable WebSocket only for the explicit ws proxy type or when a path is
    # configured. Use wss when TLS credentials are also configured.
    WS_PATH=$(jsection_val websocket path)
    if [ "$PROXY_TYPE" = "ws" ]; then
        [ -z "$WS_PATH" ] && WS_PATH="/ws"
        if [ "$TLS_ENABLED" = "true" ]; then SCHEME="http+wss"; else SCHEME="http+ws"; fi
    elif [ -n "$WS_PATH" ]; then
        if [ "$TLS_ENABLED" = "true" ]; then SCHEME="http+wss"; else SCHEME="${SCHEME}+ws"; fi
    fi

    if [ "$SCHEME" = "red" ]; then
        AUTH_PART=""
    fi
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
        TRANSPARENT_MARK=$(jsection_val transparent mark)
        [ "$TRANSPARENT_SNIFFING" != "false" ] && append_query sniffing true
        case "$TRANSPARENT_MARK" in
            ''|*[!0-9]*) TRANSPARENT_MARK=100 ;;
        esac
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

        # Use the upstream type directly as the scheme.
        # Do NOT append +ws if the type already contains ws or wss
        # (e.g. "socks5+wss" already includes WebSocket over TLS)
        UP_SCHEME="$UP_TYPE"
        case "$UP_TYPE" in
            *+ws*|*+wss*)
                # Type already includes ws/wss, don't append
                ;;
            *)
                # Type doesn't include ws, check if ws_path is set
                if [ -n "$UP_WS_PATH" ]; then
                    UP_SCHEME="${UP_SCHEME}+ws"
                fi
                ;;
        esac

        FORWARD_URL="${UP_SCHEME}://${UP_AUTH}${UP_ADDR}:${UP_PORT}"

        # GOST v3's SOCKS5 connector enables its TLS-negotiation extension by
        # default. Subscription links using socks:// with ws/wss normally point
        # to a plain SOCKS5 service inside the WebSocket tunnel, so disable that
        # extension. Otherwise TLS application data can be sent to the proxy as
        # if it were a TLS handshake, producing an HTTP 400/bad TLS record.
        UP_QUERY=""
        append_up_query() {
            _key="$1" _value="$2"
            [ -z "$_value" ] && return
            if [ -z "$UP_QUERY" ]; then UP_QUERY="?"; else UP_QUERY="${UP_QUERY}&"; fi
            UP_QUERY="${UP_QUERY}${_key}=$(urlencode "$_value")"
        }
        case "$UP_TYPE" in
            socks|socks5|socks+ws|socks+wss|socks5+ws|socks5+wss)
                append_up_query notls true
                ;;
        esac
        if [ -n "$UP_WS_PATH" ]; then
            append_up_query path "$UP_WS_PATH"
            append_up_query host "$UP_WS_HOST"
        fi
        FORWARD_URL="${FORWARD_URL}${UP_QUERY}"

        log_msg "Forward configured: scheme=$UP_SCHEME addr=$UP_ADDR port=$UP_PORT"
    else
        log_msg "WARNING: upstream enabled but addr or port is empty/zero (addr=$UP_ADDR port=$UP_PORT)"
    fi
else
    log_msg "Debug: upstream not enabled, skipping -F"
fi

# ---- Build optional extra listeners and log flags ----
MULTI_LISTEN=$(jsection_val advanced multi_listen)
LOG_LEVEL=$(jsection_val advanced log_level)

set -- -L "$LISTEN_URL"
OLD_IFS=$IFS
IFS=','
for EXTRA_PORT in $MULTI_LISTEN; do
    EXTRA_PORT=$(printf '%s' "$EXTRA_PORT" | tr -d ' []"')
    case "$EXTRA_PORT" in
        ''|*[!0-9]*) continue ;;
    esac
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

# ---- Start gost ----
log_msg "Starting gost proxy..."
if [ -n "$FORWARD_URL" ]; then
    log_msg "Starting with listener and upstream forwarding"
else
    log_msg "Starting with listener only"
fi

cd "$MODDIR/gost" || {
    log_msg "ERROR: failed to enter $MODDIR/gost"
    echo "ERROR: failed to enter gost directory"
    exit 1
}
"$GOST_BIN" "$@" >> "$LOGFILE" 2>&1 &
GOST_PID=$!

sleep 2

if kill -0 "$GOST_PID" 2>/dev/null; then
    echo "$GOST_PID" > "$PIDFILE"
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

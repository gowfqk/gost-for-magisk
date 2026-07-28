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

# Helper: extract nested JSON value from a section
# Usage: jsection_val "auth" "enabled"
jsection_val() {
    _section="$1" _key="$2"
    sed -n "/\"$_section\"/,/}/p" "$CONFIG" 2>/dev/null | grep -o "\"$_key\"[[:space:]]*:[[:space:]]*[^,}]*" | head -1 | sed 's/.*\":[[:space:]]*//' | tr -d '"'
}

PROXY_TYPE=$(jval proxy_type)
[ -z "$PROXY_TYPE" ] && PROXY_TYPE="http"

LISTEN_ADDR=$(jval listen_addr)
[ -z "$LISTEN_ADDR" ] && LISTEN_ADDR="0.0.0.0"

LISTEN_PORT=$(jval listen_port)
[ -z "$LISTEN_PORT" ] && LISTEN_PORT="1080"

log_msg "Config: type=$PROXY_TYPE addr=$LISTEN_ADDR port=$LISTEN_PORT"

# ---- Build the -L (listen) argument ----
AUTH_ENABLED=$(jsection_val auth enabled)
AUTH_USER=$(jsection_val auth username)
AUTH_PASS=$(jsection_val auth password)

AUTH_PART=""
if [ "$AUTH_ENABLED" = "true" ] && [ -n "$AUTH_USER" ]; then
    AUTH_PART="${AUTH_USER}:${AUTH_PASS}@"
fi

# Map proxy_type to gost scheme
case "$PROXY_TYPE" in
    http|socks5|socks4|relay)
        SCHEME="$PROXY_TYPE"
        ;;
    ss|shadowsocks)
        SCHEME="ss"
        SS_METHOD=$(jsection_val shadowsocks method)
        [ -z "$SS_METHOD" ] && SS_METHOD="aes-256-cfb"
        SS_PASS=$(jsection_val shadowsocks password)
        # ss://method:password@addr:port
        LISTEN_URL="${SCHEME}://${SS_METHOD}:${SS_PASS}@${LISTEN_ADDR}:${LISTEN_PORT}"
        ;;
    *)
        SCHEME="http"
        ;;
esac

# For non-ss types, build the URL
if [ "$PROXY_TYPE" != "ss" ] && [ "$PROXY_TYPE" != "shadowsocks" ]; then
    # Check for TLS
    TLS_CERT=$(jsection_val tls cert)
    if [ -n "$TLS_CERT" ]; then
        SCHEME="${SCHEME}+tls"
    fi

    # Check for WebSocket
    WS_PATH=$(jsection_val websocket path)
    if [ -n "$WS_PATH" ]; then
        SCHEME="${SCHEME}+ws"
    fi

    LISTEN_URL="${SCHEME}://${AUTH_PART}${LISTEN_ADDR}:${LISTEN_PORT}"

    # Append WebSocket query params
    if [ -n "$WS_PATH" ]; then
        WS_HOST=$(jsection_val websocket host)
        QUERY="?path=${WS_PATH}"
        [ -n "$WS_HOST" ] && QUERY="${QUERY}&host=${WS_HOST}"
        LISTEN_URL="${LISTEN_URL}${QUERY}"
    fi
fi

log_msg "Listen URL: $LISTEN_URL"

# ---- Build the -F (forward/upstream) argument ----
UPSTREAM_ENABLED=$(jsection_val upstream enabled)
log_msg "Debug: upstream.enabled raw = [$UPSTREAM_ENABLED]"
FORWARD_ARG=""

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
            UP_AUTH="${UP_USER}:${UP_PASS}@"
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

        # Append WS query params if ws_path is set
        if [ -n "$UP_WS_PATH" ]; then
            UP_QUERY="?path=${UP_WS_PATH}"
            [ -n "$UP_WS_HOST" ] && UP_QUERY="${UP_QUERY}&host=${UP_WS_HOST}"
            FORWARD_URL="${FORWARD_URL}${UP_QUERY}"
        fi

        FORWARD_ARG="-F $FORWARD_URL"
        log_msg "Forward URL: $FORWARD_URL"
    else
        log_msg "WARNING: upstream enabled but addr or port is empty/zero (addr=$UP_ADDR port=$UP_PORT)"
    fi
else
    log_msg "Debug: upstream not enabled, skipping -F"
fi

# ---- Start gost ----
log_msg "Starting gost proxy..."
log_msg "Command: $GOST_BIN -L $LISTEN_URL $FORWARD_ARG"

cd "$MODDIR/gost"
if [ -n "$FORWARD_ARG" ]; then
    "$GOST_BIN" -L "$LISTEN_URL" $FORWARD_ARG >> "$LOGFILE" 2>&1 &
else
    "$GOST_BIN" -L "$LISTEN_URL" >> "$LOGFILE" 2>&1 &
fi
GOST_PID=$!

sleep 2

if kill -0 "$GOST_PID" 2>/dev/null; then
    echo "$GOST_PID" > "$PIDFILE"
    log_msg "gost started successfully (PID: $GOST_PID)"
    echo "gost started successfully (PID: $GOST_PID)"
else
    log_msg "ERROR: gost failed to start - check config"
    echo "ERROR: gost failed to start"
    exit 1
fi

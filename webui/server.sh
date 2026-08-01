#!/system/bin/sh
#
# server.sh - WebUI server for Gost proxy
# Multi-strategy: tries httpd first, falls back to nc -e, then nc FIFO
#
# Usage:
#   sh server.sh [MODDIR] [PORT]    # Start server
#   sh server.sh --handle MODDIR    # Handle one HTTP request (for nc mode)
#

# ================================================================
# Handler Mode (for nc approach)
# Reads raw HTTP from stdin, writes raw HTTP response to stdout
# ================================================================
if [ "$1" = "--handle" ]; then
    MODDIR="$2"
    CONFIG="$MODDIR/gost/config.json"
    LOG_PATH="$MODDIR/logs/gost.log"
    PIDFILE="/tmp/gost.pid"
    WEBUI_DIR="$MODDIR/webui"

    PORT=$(grep -o '"webui_port"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG" 2>/dev/null | grep -o '[0-9]*')
    [ -z "$PORT" ] && PORT=8080

    # Read HTTP request line
    read -r REQUEST_LINE 2>/dev/null
    METHOD=$(echo "$REQUEST_LINE" | awk '{print $1}')
    URL=$(echo "$REQUEST_LINE" | awk '{print $2}')

    if [ -z "$METHOD" ] || [ -z "$URL" ]; then
        printf 'HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n400 Bad Request'
        exit 0
    fi

    PATH_ONLY=$(echo "$URL" | cut -d'?' -f1)
    QUERY=$(echo "$URL" | cut -d'?' -f2)
    [ "$QUERY" = "$URL" ] && QUERY=""

    # Read headers
    CONTENT_LENGTH=0
    while IFS= read -r hdr 2>/dev/null; do
        hdr=$(echo "$hdr" | tr -d '\r')
        [ -z "$hdr" ] && break
        case "$hdr" in
            [Cc]ontent-[Ll]ength:*)
                CONTENT_LENGTH=$(echo "$hdr" | sed 's/.*: *//')
                ;;
        esac
    done

    # Read POST body
    BODY=""
    if [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
        BODY=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    fi

    # Helpers
    send_json() {
        printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n'
        printf 'Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n'
        printf '%s' "$1"
    }

    send_static() {
        FILE="$1"
        if [ ! -f "$FILE" ]; then
            printf 'HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 Not Found'
            return
        fi
        case "$FILE" in
            *.html)  MIME="text/html; charset=utf-8" ;;
            *.js)    MIME="application/javascript; charset=utf-8" ;;
            *.css)   MIME="text/css; charset=utf-8" ;;
            *.json)  MIME="application/json; charset=utf-8" ;;
            *.png)   MIME="image/png" ;;
            *.svg)   MIME="image/svg+xml" ;;
            *)       MIME="application/octet-stream" ;;
        esac
        SIZE=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
        printf 'HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' "$MIME" "$SIZE"
        cat "$FILE"
    }

    jval() {
        grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"'
    }

    # Determine if this is an API request
    IS_API=0
    case "$PATH_ONLY" in
        /cgi-bin/api)
            IS_API=1
            ;;
        /api/*)
            IS_API=1
            # Route-style API paths are normalized into the CGI query format.
            # Keep the original query encoded; the CGI parser owns decoding.
            EP=${PATH_ONLY#/api/}
            QUERY="endpoint=$EP${QUERY:+&$QUERY}"
            ;;
    esac

    if [ "$IS_API" = "1" ]; then
        # Reuse the same CGI implementation as busybox httpd so node and
        # configuration behavior stays identical in every server strategy.
        CGI_SCRIPT="$WEBUI_DIR/cgi-bin/api"
        if [ ! -f "$CGI_SCRIPT" ]; then
            printf 'HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{"error":"API handler missing"}'
            exit 0
        fi
        printf 'HTTP/1.1 200 OK\r\nConnection: close\r\n'
        printf '%s' "$BODY" | QUERY_STRING="$QUERY" REQUEST_METHOD="$METHOD" CONTENT_LENGTH="$CONTENT_LENGTH" sh "$CGI_SCRIPT"
        exit 0

        # Legacy inline handler kept unreachable for compatibility reference.
        # Parse query params
        LOG_LINES="200"
        echo "$QUERY" | grep -q "lines=" && LOG_LINES=$(echo "$QUERY" | sed 's/.*lines=//' | grep -o '[0-9]*')
        [ -z "$LOG_LINES" ] && LOG_LINES=200

        case "$EP" in
            status)
                GOST_STATUS="stopped"; GOST_PID=""
                if [ -f "$PIDFILE" ]; then
                    GOST_PID=$(cat "$PIDFILE" 2>/dev/null)
                    [ -n "$GOST_PID" ] && kill -0 "$GOST_PID" 2>/dev/null || GOST_PID=""
                    [ -n "$GOST_PID" ] && GOST_STATUS="running"
                fi
                ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "unknown")
                LP=$(jval listen_port); [ -z "$LP" ] && LP="1080"
                PT=$(jval proxy_type);  [ -z "$PT" ] && PT="redirect"
                case "$PT" in socks) PT="socks5" ;; red|redir) PT="redirect" ;; redirect|socks5) ;; *) PT="redirect" ;; esac
                LA=$(jval listen_addr); [ -z "$LA" ] && LA="0.0.0.0"
                send_json "{\"gost\":{\"status\":\"$GOST_STATUS\",\"pid\":\"$GOST_PID\"},\"webui\":{\"status\":\"running\",\"port\":$PORT},\"arch\":\"$ARCH\",\"listen_port\":$LP,\"proxy_type\":\"$PT\",\"listen_addr\":\"$LA\"}"
                ;;
            config)
                if [ "$METHOD" = "GET" ]; then
                    [ -f "$CONFIG" ] && send_static "$CONFIG" || send_json '{"error":"Config not found"}'
                elif [ "$METHOD" = "POST" ]; then
                    if [ -n "$BODY" ]; then
                        printf '%s' "$BODY" > "$CONFIG"
                        send_json '{"success":true,"message":"Config saved"}'
                    else
                        send_json '{"success":false,"message":"Empty body"}'
                    fi
                fi
                ;;
            start)
                sh "$MODDIR/scripts/start.sh" "$MODDIR" >/dev/null 2>&1; sleep 1
                if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                    send_json "{\"success\":true,\"message\":\"gost started (PID: $(cat "$PIDFILE"))\"}"
                else
                    send_json '{"success":false,"message":"gost failed to start"}'
                fi
                ;;
            stop)
                sh "$MODDIR/scripts/stop.sh" "$MODDIR" >/dev/null 2>&1; sleep 1
                if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                    send_json '{"success":false,"message":"gost failed to stop"}'
                else
                    send_json '{"success":true,"message":"gost stopped"}'
                fi
                ;;
            restart)
                sh "$MODDIR/scripts/stop.sh" "$MODDIR" >/dev/null 2>&1; sleep 1
                sh "$MODDIR/scripts/start.sh" "$MODDIR" >/dev/null 2>&1; sleep 1
                if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                    send_json "{\"success\":true,\"message\":\"gost restarted (PID: $(cat "$PIDFILE"))\"}"
                else
                    send_json '{"success":false,"message":"gost failed to restart"}'
                fi
                ;;
            logs)
                if [ -f "$LOG_PATH" ]; then
                    LOGS=$(tail -n "$LOG_LINES" "$LOG_PATH" 2>/dev/null)
                else
                    LOGS="No logs available."
                fi
                LOGS_ESCAPED=$(printf '%s' "$LOGS" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')
                send_json "{\"logs\":\"$LOGS_ESCAPED\"}"
                ;;
            command)
                PT=$(jval proxy_type);  [ -z "$PT" ] && PT="redirect"
                case "$PT" in socks) PT="socks5" ;; red|redir) PT="redirect" ;; redirect|socks5) ;; *) PT="redirect" ;; esac
                LA=$(jval listen_addr); [ -z "$LA" ] && LA="0.0.0.0"
                LP=$(jval listen_port); [ -z "$LP" ] && LP="1080"
                [ "$PT" = "redirect" ] && LISTEN_SCHEME="red" || LISTEN_SCHEME="socks5"
                send_json "{\"command\":\"-L ${LISTEN_SCHEME}://${LA}:${LP}\"}"
                ;;
            config/import)
                if [ -n "$BODY" ]; then
                    printf '%s' "$BODY" > "$CONFIG"
                    send_json '{"success":true,"message":"Config imported"}'
                else
                    send_json '{"success":false,"message":"Empty body"}'
                fi
                ;;
            "")
                send_json '{"error":"No endpoint specified"}'
                ;;
            *)
                send_json "{\"error\":\"Unknown endpoint: $EP\"}"
                ;;
        esac
    else
        # Serve static files
        case "$PATH_ONLY" in
            /|/index.html)
                send_static "$WEBUI_DIR/index.html"
                ;;
            /*)
                case "$PATH_ONLY" in
                    *..*|*\\*|*%2[eE]*|*%5[cC]*)
                        printf 'HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n400 Bad Request'
                        exit 0
                        ;;
                esac
                FP="$WEBUI_DIR$PATH_ONLY"
                if [ -f "$FP" ]; then
                    send_static "$FP"
                else
                    printf 'HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 Not Found'
                fi
                ;;
            *)
                printf 'HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n400 Bad Request'
                ;;
        esac
    fi

    exit 0
fi

# ================================================================
# Server Mode
# ================================================================
MODDIR="${1:-/data/adb/modules/gost_proxy}"
PORT="${2:-8080}"
WEBUI_DIR="$MODDIR/webui"
SCRIPT="$MODDIR/webui/server.sh"
LOGFILE="$MODDIR/logs/webui.log"
PIDFILE="/tmp/gost-webui.pid"

mkdir -p "$MODDIR/logs"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

log_msg "=========================================="
log_msg "Starting WebUI server"
log_msg "MODDIR=$MODDIR  PORT=$PORT"

echo $$ > "$PIDFILE"

# ---- Find busybox ----
BB=""
for path in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox /system/xbin/busybox; do
    [ -x "$path" ] && BB="$path" && break
done
[ -z "$BB" ] && BB=$(command -v busybox 2>/dev/null)
if [ -z "$BB" ]; then
    log_msg "ERROR: busybox not found"
    exit 1
fi
log_msg "busybox=$BB"

# List available applets for debugging
APPLETS=$("$BB" --list 2>/dev/null || "$BB" 2>&1 | head -5)
log_msg "applets: $(echo "$APPLETS" | tr '\n' ' ' | head -c 500)"

# ================================================================
# Strategy 1: busybox httpd + CGI
# ================================================================
if "$BB" --list 2>/dev/null | grep -qx "httpd"; then
    CGI_SCRIPT="$WEBUI_DIR/cgi-bin/api"
    if [ -f "$CGI_SCRIPT" ]; then
        chmod 755 "$CGI_SCRIPT" 2>/dev/null
        log_msg "Strategy: httpd + CGI"
        log_msg "Starting: $BB httpd -f -p 127.0.0.1:$PORT -h $WEBUI_DIR"
        exec "$BB" httpd -f -p "127.0.0.1:$PORT" -h "$WEBUI_DIR"
    fi
    log_msg "httpd available but CGI script missing, trying nc..."
else
    log_msg "httpd applet not available, trying nc..."
fi

# ================================================================
# Strategy 2: nc -e with wrapper script
# The wrapper has no spaces in path, avoiding the nc -e bug
# ================================================================

# Create wrapper script at path with NO spaces
WRAPPER="/tmp/gost_handler.sh"
cat > "$WRAPPER" << EOF
#!/system/bin/sh
exec sh "$SCRIPT" --handle "$MODDIR"
EOF
chmod 755 "$WRAPPER"

# Check if nc supports -e
if "$BB" --list 2>/dev/null | grep -qx "nc"; then
    NC_HELP=$("$BB" nc --help 2>&1)
    if echo "$NC_HELP" | grep -qi '^\s*-e\b\| -e '; then
        log_msg "Strategy: nc -e with wrapper"
        log_msg "Wrapper: $WRAPPER"

        # Try nc -l -p PORT -e WRAPPER in a loop
        FAIL=0
        while true; do
            "$BB" nc -l -s 127.0.0.1 -p "$PORT" -e "$WRAPPER" 2>>"$LOGFILE"
            RC=$?
            if [ $RC -ne 0 ]; then
                FAIL=$((FAIL + 1))
                log_msg "nc -e exited code=$RC (fails=$FAIL)"
                if [ $FAIL -ge 3 ]; then
                    # Try alternative nc syntax: nc -l PORT -e WRAPPER
                    log_msg "Trying nc -l $PORT -e ..."
                    "$BB" nc -l -s 127.0.0.1 "$PORT" -e "$WRAPPER" 2>>"$LOGFILE"
                    RC2=$?
                    if [ $RC2 -ne 0 ]; then
                        log_msg "nc -l -e also failed (code=$RC2), falling back to FIFO"
                        break
                    fi
                    FAIL=0
                fi
            else
                FAIL=0
            fi
            sleep 1
        done

        # If we broke out due to failure, fall through to FIFO
        log_msg "Falling back to FIFO strategy"
    else
        log_msg "nc -e not supported, using FIFO"
    fi
else
    log_msg "nc applet not available!"
fi

# ================================================================
# Strategy 3: nc with FIFO pipe
# nc -l -p PORT < FIFO | handler > FIFO
# ================================================================
log_msg "Strategy: nc FIFO"

FIFO="/tmp/gost_webui_fifo"
FAIL_COUNT=0

while true; do
    rm -f "$FIFO"
    mkfifo "$FIFO" 2>/dev/null

    if [ ! -p "$FIFO" ]; then
        log_msg "ERROR: mkfifo failed"
        sleep 2
        continue
    fi

    # Open FIFO in background to prevent deadlock
    sleep 0.1 2>/dev/null || true

    "$BB" nc -l -s 127.0.0.1 -p "$PORT" < "$FIFO" 2>>"$LOGFILE" | sh "$SCRIPT" --handle "$MODDIR" > "$FIFO" 2>>"$LOGFILE"

    NC_EXIT=$?
    if [ $NC_EXIT -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_msg "nc FIFO exited code=$NC_EXIT (fails=$FAIL_COUNT)"
        if [ $FAIL_COUNT -ge 5 ]; then
            # Try alternative syntax
            log_msg "Trying nc -l $PORT (no -p)..."
            rm -f "$FIFO"
            mkfifo "$FIFO" 2>/dev/null
            "$BB" nc -l -s 127.0.0.1 "$PORT" < "$FIFO" 2>>"$LOGFILE" | sh "$SCRIPT" --handle "$MODDIR" > "$FIFO" 2>>"$LOGFILE"
            if [ $? -ne 0 ]; then
                log_msg "All nc strategies failed. Waiting 10s before retry..."
                sleep 10
            fi
            FAIL_COUNT=0
        fi
    else
        FAIL_COUNT=0
    fi
    sleep 1
done

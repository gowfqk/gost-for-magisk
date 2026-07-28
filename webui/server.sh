#!/system/bin/sh
#
# server.sh - Pure shell HTTP server for Gost WebUI
# No Python dependency, works with Magisk busybox only
#
# Usage:
#   sh server.sh [MODDIR] [PORT]    # Start server
#   sh server.sh --handle MODDIR    # Handle one request (internal)
#

# ============ Handler Mode ============
# Read HTTP request from stdin, write HTTP response to stdout.
if [ "$1" = "--handle" ]; then
    MODDIR="$2"
    CONFIG="$MODDIR/gost/config.json"
    LOG_PATH="$MODDIR/logs/gost.log"
    PIDFILE="/tmp/gost.pid"
    WEBUI_DIR="$MODDIR/webui"

    # Get WebUI port from config
    PORT=$(grep -o '"webui_port"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG" 2>/dev/null | grep -o '[0-9]*')
    [ -z "$PORT" ] && PORT=8080

    # ---- Read HTTP request line ----
    read -r REQUEST_LINE 2>/dev/null
    METHOD=$(echo "$REQUEST_LINE" | awk '{print $1}')
    URL=$(echo "$REQUEST_LINE" | awk '{print $2}')

    # Fallback for empty request
    if [ -z "$METHOD" ] || [ -z "$URL" ]; then
        printf 'HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n400 Bad Request'
        exit 0
    fi

    # Strip query string
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

    # ---- Helpers ----
    send_json() {
        printf 'HTTP/1.1 200 OK\r\n'
        printf 'Content-Type: application/json; charset=utf-8\r\n'
        printf 'Access-Control-Allow-Origin: *\r\n'
        printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n'
        printf 'Access-Control-Allow-Headers: Content-Type\r\n'
        printf 'Connection: close\r\n'
        printf '\r\n'
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
        printf 'HTTP/1.1 200 OK\r\n'
        printf 'Content-Type: %s\r\n' "$MIME"
        printf 'Content-Length: %s\r\n' "$SIZE"
        printf 'Connection: close\r\n'
        printf '\r\n'
        cat "$FILE"
    }

    jval() {
        grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"'
    }

    # ---- Route request ----
    case "$PATH_ONLY" in
        /api/status)
            GOST_STATUS="stopped"
            GOST_PID=""
            if [ -f "$PIDFILE" ]; then
                GOST_PID=$(cat "$PIDFILE" 2>/dev/null)
                if [ -n "$GOST_PID" ] && kill -0 "$GOST_PID" 2>/dev/null; then
                    GOST_STATUS="running"
                else
                    GOST_PID=""
                fi
            fi
            ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "unknown")
            LISTEN_PORT=$(jval listen_port)
            PROXY_TYPE=$(jval proxy_type)
            LISTEN_ADDR=$(jval listen_addr)
            [ -z "$LISTEN_PORT" ] && LISTEN_PORT="1080"
            [ -z "$PROXY_TYPE" ] && PROXY_TYPE="http"
            [ -z "$LISTEN_ADDR" ] && LISTEN_ADDR="0.0.0.0"
            send_json "{\"gost\":{\"status\":\"$GOST_STATUS\",\"pid\":\"$GOST_PID\"},\"webui\":{\"status\":\"running\",\"port\":$PORT},\"arch\":\"$ARCH\",\"listen_port\":$LISTEN_PORT,\"proxy_type\":\"$PROXY_TYPE\",\"listen_addr\":\"$LISTEN_ADDR\"}"
            ;;

        /api/config)
            if [ "$METHOD" = "GET" ]; then
                if [ -f "$CONFIG" ]; then
                    send_static "$CONFIG"
                else
                    send_json '{"error":"Config not found"}'
                fi
            elif [ "$METHOD" = "POST" ]; then
                if [ -n "$BODY" ]; then
                    printf '%s' "$BODY" > "$CONFIG"
                    send_json '{"success":true,"message":"Config saved"}'
                else
                    send_json '{"success":false,"message":"Empty body"}'
                fi
            fi
            ;;

        /api/start)
            sh "$MODDIR/scripts/start.sh" "$MODDIR" >/dev/null 2>&1
            sleep 1
            if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                send_json "{\"success\":true,\"message\":\"gost started (PID: $(cat "$PIDFILE"))\"}"
            else
                send_json '{"success":false,"message":"gost failed to start"}'
            fi
            ;;

        /api/stop)
            sh "$MODDIR/scripts/stop.sh" "$MODDIR" >/dev/null 2>&1
            sleep 1
            if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                send_json '{"success":false,"message":"gost failed to stop"}'
            else
                send_json '{"success":true,"message":"gost stopped"}'
            fi
            ;;

        /api/restart)
            sh "$MODDIR/scripts/stop.sh" "$MODDIR" >/dev/null 2>&1
            sleep 1
            sh "$MODDIR/scripts/start.sh" "$MODDIR" >/dev/null 2>&1
            sleep 1
            if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                send_json "{\"success\":true,\"message\":\"gost restarted (PID: $(cat "$PIDFILE"))\"}"
            else
                send_json '{"success":false,"message":"gost failed to restart"}'
            fi
            ;;

        /api/logs)
            LINES=200
            if echo "$QUERY" | grep -q "lines="; then
                LINES=$(echo "$QUERY" | sed 's/.*lines=//' | grep -o '[0-9]*')
                [ -z "$LINES" ] && LINES=200
            fi
            if [ -f "$LOG_PATH" ]; then
                LOGS=$(tail -n "$LINES" "$LOG_PATH" 2>/dev/null)
            else
                LOGS="No logs available."
            fi
            LOGS_ESCAPED=$(printf '%s' "$LOGS" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '\f' | sed 's/\f/\\n/g')
            send_json "{\"logs\":\"$LOGS_ESCAPED\"}"
            ;;

        /api/command)
            PT=$(jval proxy_type)
            LA=$(jval listen_addr)
            LP=$(jval listen_port)
            [ -z "$PT" ] && PT="http"
            [ -z "$LA" ] && LA="0.0.0.0"
            [ -z "$LP" ] && LP="1080"
            CMD="-L ${PT}://${LA}:${LP}"
            send_json "{\"command\":\"$CMD\"}"
            ;;

        /api/parse-link)
            send_json '{"success":false,"message":"Not supported in shell mode"}'
            ;;

        /api/config/import)
            if [ -n "$BODY" ]; then
                printf '%s' "$BODY" > "$CONFIG"
                send_json '{"success":true,"message":"Config imported"}'
            else
                send_json '{"success":false,"message":"Empty body"}'
            fi
            ;;

        OPTIONS*)
            printf 'HTTP/1.1 204 No Content\r\n'
            printf 'Access-Control-Allow-Origin: *\r\n'
            printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n'
            printf 'Access-Control-Allow-Headers: Content-Type\r\n'
            printf '\r\n'
            ;;

        /|/index.html)
            send_static "$WEBUI_DIR/index.html"
            ;;

        /*)
            FILE_PATH="$WEBUI_DIR$PATH_ONLY"
            if [ -f "$FILE_PATH" ]; then
                send_static "$FILE_PATH"
            else
                printf 'HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 Not Found'
            fi
            ;;
    esac

    exit 0
fi

# ============ Server Mode ============
MODDIR="${1:-/data/adb/modules/gost_proxy}"
PORT="${2:-8080}"
SCRIPT="$MODDIR/webui/server.sh"
LOGFILE="$MODDIR/logs/webui.log"
PIDFILE="/tmp/gost-webui.pid"

mkdir -p "$MODDIR/logs"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

log_msg "=========================================="
log_msg "Starting WebUI server (pure shell mode)"
log_msg "MODDIR=$MODDIR  PORT=$PORT"
log_msg "SCRIPT=$SCRIPT"

# Write PID
echo $$ > "$PIDFILE"

# ---- Find busybox ----
BB=""
for path in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /system/bin/busybox /system/xbin/busybox; do
    if [ -x "$path" ]; then
        BB="$path"
        break
    fi
done
if [ -z "$BB" ]; then
    BB=$(command -v busybox 2>/dev/null)
fi
if [ -z "$BB" ]; then
    log_msg "ERROR: busybox not found anywhere"
    exit 1
fi
log_msg "busybox=$BB"

# ---- Find nc ----
NC_BIN=""
# Try busybox nc
if "$BB" nc --help 2>&1 | head -1 | grep -qi "nc\|netcat"; then
    NC_BIN="$BB nc"
fi
# Fallback to system nc
if [ -z "$NC_BIN" ]; then
    for path in /system/bin/nc /system/xbin/nc; do
        if [ -x "$path" ]; then
            NC_BIN="$path"
            break
        fi
    done
fi
if [ -z "$NC_BIN" ]; then
    NC_BIN="nc"
fi
log_msg "nc=$NC_BIN"

# ---- Main server loop (FIFO approach) ----
# Uses: nc -l -p PORT < FIFO | handler > FIFO
# nc reads client request -> pipe -> handler stdin
# handler writes response -> FIFO -> nc -> client
log_msg "Entering server loop (FIFO mode)..."
FIFO="/tmp/gost_webui_fifo"
FAIL_COUNT=0

while true; do
    # Recreate FIFO each iteration
    rm -f "$FIFO"
    mkfifo "$FIFO" 2>/dev/null

    if [ ! -p "$FIFO" ]; then
        log_msg "ERROR: mkfifo $FIFO failed"
        sleep 2
        continue
    fi

    # Run nc with FIFO piping to handler
    # busybox nc -l -p PORT: listen on PORT
    "$BB" nc -l -p "$PORT" < "$FIFO" 2>>"$LOGFILE" | sh "$SCRIPT" --handle "$MODDIR" > "$FIFO" 2>>"$LOGFILE"

    NC_EXIT=$?
    if [ $NC_EXIT -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_msg "WARNING: nc exited with code $NC_EXIT (fail count: $FAIL_COUNT)"
        if [ $FAIL_COUNT -ge 5 ]; then
            log_msg "ERROR: Too many failures, trying nc -l syntax..."
            # Fallback: some nc versions use -l without -p
            rm -f "$FIFO"
            mkfifo "$FIFO" 2>/dev/null
            "$BB" nc -l "$PORT" < "$FIFO" 2>>"$LOGFILE" | sh "$SCRIPT" --handle "$MODDIR" > "$FIFO" 2>>"$LOGFILE"
            NC_EXIT=$?
            if [ $NC_EXIT -ne 0 ]; then
                log_msg "ERROR: nc -l also failed (code $NC_EXIT). Resetting fail count."
                FAIL_COUNT=0
            else
                log_msg "nc -l syntax works! Continuing with this syntax."
                FAIL_COUNT=0
                # Switch to -l syntax for subsequent iterations
                while true; do
                    rm -f "$FIFO"
                    mkfifo "$FIFO" 2>/dev/null
                    [ ! -p "$FIFO" ] && { sleep 2; continue; }
                    "$BB" nc -l "$PORT" < "$FIFO" 2>>"$LOGFILE" | sh "$SCRIPT" --handle "$MODDIR" > "$FIFO" 2>>"$LOGFILE"
                    sleep 1
                done
            fi
        fi
    else
        FAIL_COUNT=0
    fi

    # Brief pause between connections
    sleep 1
done

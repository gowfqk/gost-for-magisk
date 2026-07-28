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
# When called with --handle, read HTTP request from stdin,
# process it, and write HTTP response to stdout.
if [ "$1" = "--handle" ]; then
    MODDIR="$2"
    CONFIG="$MODDIR/gost/config.json"
    LOG_PATH="$MODDIR/logs/gost.log"
    PIDFILE="/tmp/gost.pid"
    WEBUI_DIR="$MODDIR/webui"

    # Get WebUI port from config
    PORT=$(grep -o '"webui_port"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG" 2>/dev/null | grep -o '[0-9]*')
    [ -z "$PORT" ] && PORT=8080

    # ---- Read HTTP request ----
    read -r REQUEST_LINE
    METHOD=$(echo "$REQUEST_LINE" | awk '{print $1}')
    URL=$(echo "$REQUEST_LINE" | awk '{print $2}')

    # Strip query string from URL
    PATH_ONLY=$(echo "$URL" | cut -d'?' -f1)
    QUERY=$(echo "$URL" | cut -d'?' -f2)
    [ "$QUERY" = "$URL" ] && QUERY=""

    # Read headers
    CONTENT_LENGTH=0
    while IFS= read -r hdr; do
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
        # Determine MIME type
        case "$FILE" in
            *.html)  MIME="text/html; charset=utf-8" ;;
            *.js)    MIME="application/javascript; charset=utf-8" ;;
            *.css)   MIME="text/css; charset=utf-8" ;;
            *.json)  MIME="application/json; charset=utf-8" ;;
            *.png)   MIME="image/png" ;;
            *.svg)   MIME="image/svg+xml" ;;
            *)       MIME="application/octet-stream" ;;
        esac
        SIZE=$(wc -c < "$FILE" 2>/dev/null)
        printf 'HTTP/1.1 200 OK\r\n'
        printf 'Content-Type: %s\r\n' "$MIME"
        printf 'Content-Length: %s\r\n' "$SIZE"
        printf 'Connection: close\r\n'
        printf '\r\n'
        cat "$FILE"
    }

    # Simple JSON value extractor
    jval() {
        grep -o "\"$1\"[[:space:]]*:[[:space:]]*[^,}]*" "$CONFIG" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"'
    }

    # ---- Route request ----
    case "$PATH_ONLY" in
        /api/status)
            # Check gost status
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
            # Get arch
            ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "unknown")
            # Get config values
            LISTEN_PORT=$(jval listen_port)
            PROXY_TYPE=$(jval proxy_type)
            LISTEN_ADDR=$(jval listen_addr)
            [ -z "$LISTEN_PORT" ] && LISTEN_PORT="1080"
            [ -z "$PROXY_TYPE" ] && PROXY_TYPE="http"
            [ -z "$LISTEN_ADDR" ] && LISTEN_ADDR="0.0.0.0"
            # Build JSON response
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
                    echo "$BODY" > "$CONFIG"
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
            # Escape for JSON
            LOGS_ESCAPED=$(printf '%s' "$LOGS" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '\f' | sed 's/\f/\\n/g')
            send_json "{\"logs\":\"$LOGS_ESCAPED\"}"
            ;;

        /api/command)
            # Build a simplified gost command preview
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
                echo "$BODY" > "$CONFIG"
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

        /*)
            # Serve static files
            FILE_PATH="$WEBUI_DIR$PATH_ONLY"
            if [ -f "$FILE_PATH" ]; then
                send_static "$FILE_PATH"
            elif [ -d "$FILE_PATH" ] && [ -f "$FILE_PATH/index.html" ]; then
                send_static "$FILE_PATH/index.html"
            else
                printf 'HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 Not Found'
            fi
            ;;

        *)
            printf 'HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 Not Found'
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

log_msg "Starting shell-based WebUI server on port $PORT"
log_msg "Module dir: $MODDIR"

# Write PID
echo $$ > "$PIDFILE"

# Find nc binary
NC=""
for cmd in nc busybox; do
    if command -v "$cmd" >/dev/null 2>&1; then
        NC="$cmd"
        break
    fi
done
if [ -z "$NC" ]; then
    log_msg "ERROR: nc not found"
    exit 1
fi

# Check if nc supports -e option (for executing handler directly)
NC_MODE="fifo"
if "$NC" --help 2>&1 | grep -q -- '-e'; then
    NC_MODE="e"
fi
log_msg "nc mode: $NC_MODE"

# Main server loop
while true; do
    if [ "$NC_MODE" = "e" ]; then
        # nc -l -p PORT -e handler (preferred - one connection per iteration)
        "$NC" -l -p "$PORT" -e "sh $SCRIPT --handle $MODDIR" 2>>"$LOGFILE"
    else
        # FIFO fallback for nc without -e
        FIFO="/tmp/gost_webui_fifo_$$"
        rm -f "$FIFO"
        mkfifo "$FIFO" 2>/dev/null
        "$NC" -l -p "$PORT" < "$FIFO" | sh "$SCRIPT" --handle "$MODDIR" > "$FIFO" 2>>"$LOGFILE"
        rm -f "$FIFO"
    fi
done

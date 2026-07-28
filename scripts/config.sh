#!/system/bin/sh

MODDIR=${1:-/data/adb/modules/gost_proxy}
CONFIG="$MODDIR/gost/config.json"

config_read() {
    if [ -f "$CONFIG" ]; then
        cat "$CONFIG"
    else
        echo "{}"
    fi
}

config_write() {
    local json_data="$1"
    if [ -z "$json_data" ]; then
        echo "ERROR: empty config data"
        return 1
    fi
    echo "$json_data" > "$CONFIG"
    if [ $? -eq 0 ]; then
        echo "Config saved successfully"
    else
        echo "ERROR: failed to save config"
        return 1
    fi
}

config_get_field() {
    local field="$1"
    if [ -f "$CONFIG" ]; then
        grep -o "\"$field\":[[:space:]]*[^,}]*" "$CONFIG" | sed "s/\"$field\":[[:space:]]*//" | tr -d '"'
    fi
}

config_set_field() {
    local field="$1"
    local value="$2"
    if [ -f "$CONFIG" ]; then
        sed -i "s/\"$field\":[[:space:]]*[^,}]*/\"$field\": $value/" "$CONFIG"
    fi
}

case "$1" in
    read)
        config_read
        ;;
    write)
        config_write "$2"
        ;;
    get)
        config_get_field "$2"
        ;;
    set)
        config_set_field "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {read|write|get|set} [args...]"
        echo "  read              - Read entire config"
        echo "  write <json>      - Write entire config"
        echo "  get <field>       - Get a config field"
        echo "  set <field> <val> - Set a config field"
        ;;
esac

#!/system/bin/sh

# config.sh - Configuration and node management for gost proxy
# Usage:
#   config.sh <moddir> read                    - Read entire config
#   config.sh <moddir> write <json>            - Write entire config
#   config.sh <moddir> get <field>             - Get a config field
#   config.sh <moddir> set <field> <val>       - Set a config field
#   config.sh <moddir> node list               - List all saved nodes
#   config.sh <moddir> node save <name>        - Save current config as node
#   config.sh <moddir> node switch <name>      - Switch to a saved node
#   config.sh <moddir> node delete <name>      - Delete a saved node
#   config.sh <moddir> node active             - Show active node

MODDIR="${1:-/data/adb/modules/gost_proxy}"
COMMAND="${2:-read}"

CONFIG="$MODDIR/gost/config.json"
NODES_DIR="$MODDIR/gost/nodes"
ACTIVE_FILE="$MODDIR/gost/active"

mkdir -p "$NODES_DIR"

# ---- Config read/write helpers ----
config_read() {
    if [ -f "$CONFIG" ]; then
        cat "$CONFIG"
    else
        echo "{}"
    fi
}

config_write() {
    _json="$1"
    if [ -z "$_json" ]; then
        echo "ERROR: empty config data"
        return 1
    fi
    echo "$_json" > "$CONFIG"
    if [ $? -eq 0 ]; then
        echo "Config saved successfully"
    else
        echo "ERROR: failed to save config"
        return 1
    fi
}

config_get_field() {
    _field="$1"
    if [ -f "$CONFIG" ]; then
        grep -o "\"$_field\":[[:space:]]*[^,}]*" "$CONFIG" | sed "s/.*:[[:space:]]*//" | tr -d '"'
    fi
}

config_set_field() {
    _field="$1"
    _value="$2"
    if [ -f "$CONFIG" ]; then
        sed -i "s/\"$_field\":[[:space:]]*[^,}]*/\"$_field\": $_value/" "$CONFIG"
    fi
}

# ---- Node management ----
node_active_name() {
    if [ -f "$ACTIVE_FILE" ]; then
        cat "$ACTIVE_FILE"
    else
        echo "default"
    fi
}

node_list() {
    _active=$(node_active_name)
    echo "Saved nodes:"
    echo "--------------------------------"
    if [ -d "$NODES_DIR" ] && [ -n "$(ls "$NODES_DIR" 2>/dev/null)" ]; then
        for _f in "$NODES_DIR"/*.json; do
            [ -f "$_f" ] || continue
            _name=$(basename "$_f" .json)
            # Extract proxy type and upstream addr for display
            _ptype=$(grep -o '"proxy_type"[[:space:]]*:[[:space:]]*[^,}]*' "$_f" 2>/dev/null | sed 's/.*:[[:space:]]*//' | tr -d '"')
            _uaddr=$(sed -n '/"upstream"/,/}/p' "$_f" 2>/dev/null | grep -o '"addr"[[:space:]]*:[[:space:]]*[^,}]*' | sed 's/.*:[[:space:]]*//' | tr -d '"')
            _lport=$(grep -o '"listen_port"[[:space:]]*:[[:space:]]*[^,}]*' "$_f" 2>/dev/null | sed 's/.*:[[:space:]]*//' | tr -d '"')
            _marker="  "
            if [ "$_name" = "$_active" ]; then
                _marker="* "
            fi
            printf "%s%-15s  %s://:%s  ->  %s\n" "$_marker" "$_name" "${_ptype:-http}" "${_lport:-1080}" "${_uaddr:-direct}"
        done
        echo "--------------------------------"
        echo "(* = active)"
    else
        echo "  (no saved nodes)"
    fi
}

node_save() {
    _name="$1"
    if [ -z "$_name" ]; then
        echo "ERROR: node name required"
        echo "Usage: config.sh <moddir> node save <name>"
        return 1
    fi
    if [ ! -f "$CONFIG" ]; then
        echo "ERROR: no active config to save"
        return 1
    fi
    cp "$CONFIG" "$NODES_DIR/${_name}.json"
    echo "Node '$_name' saved successfully"
}

node_switch() {
    _name="$1"
    if [ -z "$_name" ]; then
        echo "ERROR: node name required"
        echo "Usage: config.sh <moddir> node switch <name>"
        return 1
    fi
    if [ ! -f "$NODES_DIR/${_name}.json" ]; then
        echo "ERROR: node '$_name' not found"
        node_list
        return 1
    fi
    cp "$NODES_DIR/${_name}.json" "$CONFIG"
    echo "$_name" > "$ACTIVE_FILE"
    echo "Switched to node '$_name'"
    echo "Restart gost to apply changes."
}

node_delete() {
    _name="$1"
    if [ -z "$_name" ]; then
        echo "ERROR: node name required"
        echo "Usage: config.sh <moddir> node delete <name>"
        return 1
    fi
    _active=$(node_active_name)
    if [ "$_name" = "$_active" ]; then
        echo "ERROR: cannot delete active node '$_name'"
        echo "Switch to another node first."
        return 1
    fi
    if [ ! -f "$NODES_DIR/${_name}.json" ]; then
        echo "ERROR: node '$_name' not found"
        return 1
    fi
    rm -f "$NODES_DIR/${_name}.json"
    echo "Node '$_name' deleted"
}

node_active() {
    node_active_name
}

# ---- Route commands ----
case "$COMMAND" in
    read)
        config_read
        ;;
    write)
        config_write "$3"
        ;;
    get)
        config_get_field "$3"
        ;;
    set)
        config_set_field "$3" "$4"
        ;;
    node)
        _subcmd="${3:-list}"
        case "$_subcmd" in
            list)
                node_list
                ;;
            save)
                node_save "$4"
                ;;
            switch)
                node_switch "$4"
                ;;
            delete)
                node_delete "$4"
                ;;
            active)
                node_active
                ;;
            *)
                echo "Usage: config.sh <moddir> node {list|save|switch|delete|active} [name]"
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 <moddir> {read|write|get|set|node} [args...]"
        echo "  read                    - Read entire config"
        echo "  write <json>            - Write entire config"
        echo "  get <field>             - Get a config field"
        echo "  set <field> <val>       - Set a config field"
        echo "  node list               - List all saved nodes"
        echo "  node save <name>        - Save current config as node"
        echo "  node switch <name>      - Switch to a saved node"
        echo "  node delete <name>      - Delete a saved node"
        echo "  node active             - Show active node"
        ;;
esac

#!/usr/bin/env bash
# config.sh — INI config parser → associative array

declare -gA CONFIG

# Parse INI file into CONFIG associative array.
# Keys are section_key (e.g., CONFIG[claude_model]).
parse_config() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local section=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue

        # Section header
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key = value
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip inline comments (space + #)
            val="${val%%[[:space:]]#*}"
            # Strip trailing whitespace
            val="${val%"${val##*[![:space:]]}"}"
            if [[ -n "$section" ]]; then
                CONFIG["${section}_${key}"]="$val"
            else
                CONFIG["$key"]="$val"
            fi
        fi
    done < "$file"
}

# Load config: user config > repo default > built-in defaults
load_config() {
    local custom_config="$1"
    local repo_config="${ORCH_DIR}/config/orch.conf"
    local user_config="${XDG_CONFIG_HOME:-$HOME/.config}/orch/orch.conf"

    # Load repo defaults first
    [[ -f "$repo_config" ]] && parse_config "$repo_config"

    # Override with user config
    [[ -f "$user_config" ]] && parse_config "$user_config"

    # Override with custom config if specified
    if [[ -n "$custom_config" ]]; then
        [[ -f "$custom_config" ]] || die "config file not found: $custom_config"
        parse_config "$custom_config"
    fi

    # Apply built-in defaults for missing keys
    : "${CONFIG[general_default_agent]:=claude}"
    : "${CONFIG[general_log_level]:=info}"
    : "${CONFIG[general_output_format]:=text}"
    : "${CONFIG[general_history_file]:=$HOME/.local/share/orch/history.jsonl}"
    : "${CONFIG[fallback_order]:=claude codex gemini}"
    : "${CONFIG[routing_general]:=claude}"
    : "${CONFIG[fanout_agents]:=claude codex gemini}"
    : "${CONFIG[fanout_timeout]:=120}"
    : "${CONFIG[cost_enabled]:=true}"
    : "${CONFIG[cost_budget_warn]:=5.00}"

    log_debug "config loaded, ${#CONFIG[@]} keys"
}

# Get config value with optional default
config_get() {
    local key="$1" default="${2:-}"
    echo "${CONFIG[$key]:-$default}"
}

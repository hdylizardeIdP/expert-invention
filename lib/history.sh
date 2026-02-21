#!/usr/bin/env bash
# history.sh — session history logging and replay

history_init() {
    local hfile="${CONFIG[general_history_file]:-$HOME/.local/share/orch/history.jsonl}"
    # Expand tilde
    hfile="${hfile/#\~/$HOME}"
    HISTORY_FILE="$hfile"
    local dir
    dir=$(dirname "$HISTORY_FILE")
    [[ -d "$dir" ]] || mkdir -p "$dir"
}

# Log an invocation
history_record() {
    local id="$1" prompt="$2" task_type="$3" agent="$4" duration_ms="$5" cost_usd="$6" success="$7"
    history_init

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local entry
    entry=$(json_build \
        ts "$ts" \
        id "$id" \
        prompt "$prompt" \
        task_type "$task_type" \
        agent "$agent" \
        duration_ms "$duration_ms" \
        cost_usd "$cost_usd" \
        success "$success")

    echo "$entry" >> "$HISTORY_FILE"
}

# Show recent invocations
history_show() {
    history_init

    if [[ ! -f "$HISTORY_FILE" ]] || [[ ! -s "$HISTORY_FILE" ]]; then
        echo "No history recorded yet."
        return 0
    fi

    printf '%s━━━ Recent Invocations ━━━%s\n\n' "$BOLD" "$RESET"
    printf '%-14s %-8s %-10s %-8s %8s  %s\n' "ID" "Agent" "Task" "Status" "Cost" "Prompt"
    printf '%-14s %-8s %-10s %-8s %8s  %s\n' "──" "─────" "────" "──────" "────" "──────"

    # Show last 20 entries
    tail -n 20 "$HISTORY_FILE" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local id agent task_type success cost_usd prompt
        id=$(echo "$line" | json_get '.id')
        agent=$(echo "$line" | json_get '.agent')
        task_type=$(echo "$line" | json_get '.task_type')
        success=$(echo "$line" | json_get '.success')
        cost_usd=$(echo "$line" | json_get '.cost_usd')
        prompt=$(echo "$line" | json_get '.prompt')

        # Truncate prompt
        (( ${#prompt} > 40 )) && prompt="${prompt:0:37}..."

        local status_str
        if [[ "$success" == "true" ]]; then
            status_str="${GREEN}ok${RESET}"
        else
            status_str="${RED}fail${RESET}"
        fi

        printf '%-14s %-8s %-10s %-8b %7s$  %s\n' \
            "$id" "$agent" "$task_type" "$status_str" "${cost_usd:-0}" "$prompt"
    done
}

# Replay a previous invocation
history_replay() {
    local target_id="$1"
    history_init

    if [[ ! -f "$HISTORY_FILE" ]]; then
        die "no history file found"
    fi

    local found=""
    while IFS= read -r line; do
        local id
        id=$(echo "$line" | json_get '.id')
        if [[ "$id" == "$target_id" ]]; then
            found="$line"
            break
        fi
    done < "$HISTORY_FILE"

    if [[ -z "$found" ]]; then
        die "invocation '$target_id' not found in history"
    fi

    local prompt agent task_type
    prompt=$(echo "$found" | json_get '.prompt')
    agent=$(echo "$found" | json_get '.agent')
    task_type=$(echo "$found" | json_get '.task_type')

    log_info "replaying $target_id: agent=$agent task=$task_type"

    # Set options as if user specified them
    OPT_AGENT="$agent"
    OPT_TASK="$task_type"
    PROMPT="$prompt"
}

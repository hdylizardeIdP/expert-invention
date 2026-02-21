#!/usr/bin/env bash
# agents/codex.sh — Codex CLI agent module

invoke_codex() {
    local prompt="$1"
    local model="${OPT_MODEL:-${CONFIG[codex_model]:-}}"
    local sandbox="${CONFIG[codex_sandbox]:-read-only}"
    local extra_flags="${CONFIG[codex_extra_flags]:-}"

    local cmd=(codex exec --json)
    [[ -n "$model" ]] && cmd+=(--model "$model")
    [[ -n "$sandbox" ]] && cmd+=(--sandbox "$sandbox")
    # Add extra flags
    if [[ -n "$extra_flags" ]]; then
        read -ra ef <<< "$extra_flags"
        cmd+=("${ef[@]}")
    fi
    # Prompt as positional arg (codex also accepts stdin via "-")
    cmd+=("$prompt")

    local timeout_secs="${OPT_TIMEOUT:-${CONFIG[fanout_timeout]:-120}}"
    local start_ms
    start_ms=$(now_ms)

    log_debug "codex cmd: ${cmd[*]}"
    local raw_output exit_code
    raw_output=$(timeout "$timeout_secs" "${cmd[@]}" 2>/dev/null)
    exit_code=$?

    local end_ms
    end_ms=$(now_ms)
    local duration_ms=$(( end_ms - start_ms ))

    echo "$raw_output" > "${ORCH_TMPDIR:-/tmp}/orch-codex-raw.json"

    normalize_codex "$raw_output" "$exit_code" "$duration_ms"
}

normalize_codex() {
    local raw="$1" exit_code="$2" duration_ms="$3"

    if (( exit_code != 0 )); then
        local err_msg="codex exited with code $exit_code"
        (( exit_code == 124 )) && err_msg="codex timed out"
        build_normalized "codex" "$err_msg" "true" "$duration_ms" "0" "null"
        return 1
    fi

    # Codex outputs JSONL — filter for message lines, extract text content
    local text=""
    local line_count
    line_count=$(echo "$raw" | wc -l)

    if (( line_count > 1 )); then
        # JSONL mode: extract text from message items
        local collected=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local msg_type
            msg_type=$(echo "$line" | json_get '.type')
            if [[ "$msg_type" == "agent_message" || "$msg_type" == "message" ]]; then
                local item_text
                item_text=$(echo "$line" | json_get '.item.text')
                [[ -z "$item_text" ]] && item_text=$(echo "$line" | json_get '.text')
                [[ -z "$item_text" ]] && item_text=$(echo "$line" | json_get '.content')
                [[ -n "$item_text" ]] && collected+="$item_text"
            fi
        done <<< "$raw"
        text="$collected"
    else
        # Single JSON: try common fields
        text=$(echo "$raw" | json_get '.result')
        [[ -z "$text" ]] && text=$(echo "$raw" | json_get '.text')
        [[ -z "$text" ]] && text=$(echo "$raw" | json_get '.output')
    fi

    if [[ -z "$text" ]]; then
        # Last resort: use raw output as text
        text="$raw"
    fi

    build_normalized "codex" "$text" "false" "$duration_ms" "0" "null"
}

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
    if [[ -n "$extra_flags" ]]; then
        read -ra ef <<< "$extra_flags"
        cmd+=("${ef[@]}")
    fi
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

    # Codex outputs JSONL. Structure per line:
    #   {"type":"item.completed","item":{"type":"agent_message","text":"..."}}
    #   {"type":"item.completed","item":{"type":"reasoning","text":"..."}}
    #   {"type":"turn.completed","usage":{...}}
    # We want lines where .item.type == "agent_message"
    local text=""
    local collected=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local line_type
        line_type=$(echo "$line" | json_get '.type')

        if [[ "$line_type" == "item.completed" ]]; then
            local item_type
            item_type=$(echo "$line" | json_get '.item.type')
            if [[ "$item_type" == "agent_message" ]]; then
                local item_text
                item_text=$(echo "$line" | json_get '.item.text')
                [[ -n "$item_text" ]] && collected+="$item_text"
            fi
        fi
    done <<< "$raw"
    text="$collected"

    if [[ -z "$text" ]]; then
        text="$raw"
    fi

    build_normalized "codex" "$text" "false" "$duration_ms" "0" "null"
}

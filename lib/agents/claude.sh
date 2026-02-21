#!/usr/bin/env bash
# agents/claude.sh — Claude CLI agent module

invoke_claude() {
    local prompt="$1"
    local model="${OPT_MODEL:-${CONFIG[claude_model]:-}}"
    local permission="${CONFIG[claude_permission_mode]:-default}"

    local cmd=(claude -p)

    # Write prompt to temp file for large prompts
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/orch-claude.XXXXXX")
    printf '%s' "$prompt" > "$tmpfile"

    cmd+=(--output-format json)
    [[ -n "$model" ]] && cmd+=(--model "$model")
    [[ "$permission" != "default" ]] && cmd+=(--permission-mode "$permission")

    local timeout_secs="${OPT_TIMEOUT:-${CONFIG[fanout_timeout]:-120}}"
    local start_ms
    start_ms=$(now_ms)

    log_debug "claude cmd: ${cmd[*]} < $tmpfile"
    local raw_output exit_code
    raw_output=$(timeout "$timeout_secs" "${cmd[@]}" < "$tmpfile" 2>/dev/null)
    exit_code=$?
    rm -f "$tmpfile"

    local end_ms
    end_ms=$(now_ms)
    local duration_ms=$(( end_ms - start_ms ))

    echo "$raw_output" > "${ORCH_TMPDIR:-/tmp}/orch-claude-raw.json"

    normalize_claude "$raw_output" "$exit_code" "$duration_ms"
}

normalize_claude() {
    local raw="$1" exit_code="$2" duration_ms="$3"

    if (( exit_code != 0 )); then
        local err_msg="claude exited with code $exit_code"
        (( exit_code == 124 )) && err_msg="claude timed out"
        build_normalized "claude" "$err_msg" "true" "$duration_ms" "0" "null"
        return 1
    fi

    # Extract text from Claude JSON output (.result)
    local text cost_usd
    text=$(echo "$raw" | json_get '.result')
    cost_usd=$(echo "$raw" | json_get '.total_cost_usd')

    if [[ -z "$text" ]]; then
        # Try .content or .text as alternate fields
        text=$(echo "$raw" | json_get '.content')
        [[ -z "$text" ]] && text=$(echo "$raw" | json_get '.text')
    fi

    if [[ -z "$text" ]]; then
        build_normalized "claude" "failed to parse claude output" "true" "$duration_ms" "0" "null"
        return 1
    fi

    [[ -z "$cost_usd" ]] && cost_usd="0"

    # Escape the raw JSON for embedding
    local raw_escaped
    if echo "$raw" | json_valid; then
        raw_escaped="$raw"
    else
        raw_escaped="null"
    fi

    build_normalized "claude" "$text" "false" "$duration_ms" "$cost_usd" "$raw_escaped"
}

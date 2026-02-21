#!/usr/bin/env bash
# agents/gemini.sh — Gemini CLI agent module

invoke_gemini() {
    local prompt="$1"
    local model="${OPT_MODEL:-${CONFIG[gemini_model]:-}}"
    local approval="${CONFIG[gemini_approval_mode]:-default}"

    # gemini -p takes the prompt as its argument value, not stdin
    local cmd=(gemini -p "$prompt" -o json)
    [[ -n "$model" ]] && cmd+=(--model "$model")
    [[ "$approval" != "default" ]] && cmd+=(--approval-mode "$approval")

    local timeout_secs="${OPT_TIMEOUT:-${CONFIG[fanout_timeout]:-120}}"
    local start_ms
    start_ms=$(now_ms)

    log_debug "gemini cmd: ${cmd[*]}"
    local raw_output exit_code
    raw_output=$(timeout "$timeout_secs" "${cmd[@]}" 2>/dev/null)
    exit_code=$?

    local end_ms
    end_ms=$(now_ms)
    local duration_ms=$(( end_ms - start_ms ))

    echo "$raw_output" > "${ORCH_TMPDIR:-/tmp}/orch-gemini-raw.json"

    normalize_gemini "$raw_output" "$exit_code" "$duration_ms"
}

normalize_gemini() {
    local raw="$1" exit_code="$2" duration_ms="$3"

    if (( exit_code != 0 )); then
        local err_msg="gemini exited with code $exit_code"
        (( exit_code == 124 )) && err_msg="gemini timed out"
        build_normalized "gemini" "$err_msg" "true" "$duration_ms" "0" "null"
        return 1
    fi

    # Gemini JSON: .response has the text
    local text
    text=$(echo "$raw" | json_get '.response')

    if [[ -z "$text" ]]; then
        build_normalized "gemini" "failed to parse gemini output" "true" "$duration_ms" "0" "null"
        return 1
    fi

    # Estimate cost from token counts if available
    # Gemini doesn't directly report cost, but we can try to extract tokens
    local cost_usd="0"

    build_normalized "gemini" "$text" "false" "$duration_ms" "$cost_usd" "null"
}

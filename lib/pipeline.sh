#!/usr/bin/env bash
# pipeline.sh — sequential agent chaining (A→B→C)

pipeline_execute() {
    local prompt="$1" chain="$2"

    # Parse comma-separated agent chain
    IFS=',' read -ra stages <<< "$chain"

    if (( ${#stages[@]} < 2 )); then
        die "pipeline requires at least 2 agents (got: $chain)"
    fi

    # Validate all agents
    for a in "${stages[@]}"; do
        a="${a// /}" # trim whitespace
        validate_agent "$a"
        has_cmd "$a" || die "pipeline agent not found: $a"
    done

    local current_text="$prompt"
    local last_good_text=""
    local total_cost=0
    local total_duration=0
    local all_results="[]"

    for (( i=0; i < ${#stages[@]}; i++ )); do
        local agent="${stages[$i]// /}"
        local stage_num=$(( i + 1 ))
        local stage_total=${#stages[@]}

        log_info "pipeline stage $stage_num/$stage_total: $agent"

        # Build augmented prompt for stages after the first
        local stage_prompt
        if (( i == 0 )); then
            stage_prompt="$current_text"
        else
            stage_prompt="Previous agent output:
---
$current_text
---

Original prompt: $prompt

Please build upon, refine, or improve the above output."
        fi

        # Invoke agent
        local result
        result=$(invoke_"$agent" "$stage_prompt")
        local exit_code=$?

        local is_error
        is_error=$(echo "$result" | json_get '.is_error')

        local text duration cost
        text=$(echo "$result" | json_get '.text')
        duration=$(echo "$result" | json_get '.duration_ms')
        cost=$(echo "$result" | json_get '.cost_usd')

        total_duration=$(( total_duration + ${duration:-0} ))
        # Add cost (bash can't do float math, use awk)
        total_cost=$(awk "BEGIN{printf \"%.4f\", $total_cost + ${cost:-0}}")

        if [[ "$is_error" == "true" ]] || (( exit_code != 0 )); then
            log_warn "pipeline stage $stage_num ($agent) failed: $text"
            # Return last good output if we have one
            if [[ -n "$last_good_text" ]]; then
                log_info "returning last good output from stage $((stage_num - 1))"
                build_normalized "${stages[$((i-1))]}" "$last_good_text" "false" "$total_duration" "$total_cost" "null"
                return 0
            else
                build_normalized "$agent" "pipeline failed at stage $stage_num ($agent): $text" "true" "$total_duration" "$total_cost" "null"
                return 1
            fi
        fi

        current_text="$text"
        last_good_text="$text"
        log_debug "pipeline stage $stage_num complete (${duration}ms)"
    done

    # Final result from last agent
    local final_agent="${stages[-1]// /}"
    build_normalized "$final_agent" "$current_text" "false" "$total_duration" "$total_cost" "null"
}

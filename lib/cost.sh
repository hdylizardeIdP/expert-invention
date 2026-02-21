#!/usr/bin/env bash
# cost.sh — cost tracking and reporting

COST_FILE="${HOME}/.local/share/orch/costs.jsonl"

cost_init() {
    local dir
    dir=$(dirname "$COST_FILE")
    [[ -d "$dir" ]] || mkdir -p "$dir"
}

# Record cost from a normalized result
cost_record() {
    local normalized="$1"
    [[ "${CONFIG[cost_enabled]:-true}" == "true" ]] || return 0

    cost_init

    local agent cost_usd duration_ms
    agent=$(echo "$normalized" | json_get '.agent')
    cost_usd=$(echo "$normalized" | json_get '.cost_usd')
    duration_ms=$(echo "$normalized" | json_get '.duration_ms')

    [[ "$cost_usd" == "0" || -z "$cost_usd" ]] && cost_usd="0"

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local entry
    entry=$(json_build \
        ts "$ts" \
        agent "$agent" \
        cost_usd "$cost_usd" \
        duration_ms "$duration_ms")

    echo "$entry" >> "$COST_FILE"

    # Budget warning
    _cost_check_budget "$cost_usd"
}

_cost_check_budget() {
    local new_cost="$1"
    local budget="${CONFIG[cost_budget_warn]:-5.00}"

    # Sum today's costs
    local today
    today=$(date -u +"%Y-%m-%d")

    local total=0
    if [[ -f "$COST_FILE" ]]; then
        while IFS= read -r line; do
            local line_ts line_cost
            line_ts=$(echo "$line" | json_get '.ts')
            line_cost=$(echo "$line" | json_get '.cost_usd')
            if [[ "$line_ts" == "$today"* ]]; then
                total=$(awk "BEGIN{printf \"%.4f\", $total + ${line_cost:-0}}")
            fi
        done < "$COST_FILE"
    fi

    local exceeded
    exceeded=$(awk "BEGIN{print ($total > $budget) ? 1 : 0}")
    if (( exceeded )); then
        log_warn "daily cost \$$total exceeds budget warning \$$budget"
    fi
}

# Show cumulative cost summary
cost_report() {
    cost_init

    if [[ ! -f "$COST_FILE" ]] || [[ ! -s "$COST_FILE" ]]; then
        echo "No cost data recorded yet."
        return 0
    fi

    local today today_epoch week_ago_epoch month_ago_epoch
    today=$(date -u +"%Y-%m-%d")
    today_epoch=$(date -u +%s)
    week_ago_epoch=$(( today_epoch - 7 * 86400 ))
    month_ago_epoch=$(( today_epoch - 30 * 86400 ))

    # Accumulate costs per agent and time period
    declare -A agent_total agent_today agent_week agent_month
    local grand_total=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local agent cost ts
        agent=$(echo "$line" | json_get '.agent')
        cost=$(echo "$line" | json_get '.cost_usd')
        ts=$(echo "$line" | json_get '.ts')

        [[ -z "$agent" || -z "$cost" || "$cost" == "0" ]] && continue

        # Total
        agent_total[$agent]=$(awk "BEGIN{printf \"%.4f\", ${agent_total[$agent]:-0} + $cost}")
        grand_total=$(awk "BEGIN{printf \"%.4f\", $grand_total + $cost}")

        # Today
        if [[ "$ts" == "$today"* ]]; then
            agent_today[$agent]=$(awk "BEGIN{printf \"%.4f\", ${agent_today[$agent]:-0} + $cost}")
        fi

        # This week (approximate via date comparison)
        local ts_date="${ts%%T*}"
        local ts_epoch
        ts_epoch=$(date -u -d "$ts_date" +%s 2>/dev/null || echo 0)
        if (( ts_epoch >= week_ago_epoch )); then
            agent_week[$agent]=$(awk "BEGIN{printf \"%.4f\", ${agent_week[$agent]:-0} + $cost}")
        fi
        if (( ts_epoch >= month_ago_epoch )); then
            agent_month[$agent]=$(awk "BEGIN{printf \"%.4f\", ${agent_month[$agent]:-0} + $cost}")
        fi
    done < "$COST_FILE"

    printf '%s━━━ Cost Summary ━━━%s\n\n' "$BOLD" "$RESET"
    printf '%-10s %10s %10s %10s %10s\n' "Agent" "Today" "Week" "Month" "Total"
    printf '%-10s %10s %10s %10s %10s\n' "─────" "─────" "────" "─────" "─────"

    for agent in claude codex gemini; do
        [[ -z "${agent_total[$agent]:-}" ]] && continue
        printf '%-10s %9s$ %9s$ %9s$ %9s$\n' \
            "$agent" \
            "${agent_today[$agent]:-0}" \
            "${agent_week[$agent]:-0}" \
            "${agent_month[$agent]:-0}" \
            "${agent_total[$agent]:-0}"
    done

    printf '\n%sGrand total: $%s%s\n' "$BOLD" "$grand_total" "$RESET"
}

#!/usr/bin/env bash
# normalize.sh — unified output schema helpers

# Build normalized output object.
# Usage: build_normalized agent text is_error duration_ms cost_usd [raw_json]
build_normalized() {
    local agent="$1" text="$2" is_error="$3" duration_ms="$4" cost_usd="$5" raw="${6:-null}"

    json_build \
        agent "$agent" \
        text "$text" \
        is_error "$is_error" \
        duration_ms "$duration_ms" \
        cost_usd "$cost_usd" \
        raw "$raw"
}

# Output result based on configured format.
# Reads normalized JSON from stdin or $1.
emit_result() {
    local normalized="${1:-$(cat)}"
    local format="${OPT_OUTPUT_FORMAT:-${CONFIG[general_output_format]:-text}}"

    case "$format" in
        json)
            echo "$normalized" | json_pretty
            ;;
        raw)
            local raw
            raw=$(echo "$normalized" | json_get '.raw')
            if [[ -n "$raw" && "$raw" != "null" ]]; then
                echo "$raw"
            else
                echo "$normalized" | json_get '.text'
            fi
            ;;
        text|*)
            local is_error
            is_error=$(echo "$normalized" | json_get '.is_error')
            local text
            text=$(echo "$normalized" | json_get '.text')
            if [[ "$is_error" == "true" ]]; then
                printf '%s%s%s\n' "$RED" "$text" "$RESET" >&2
                return 1
            else
                printf '%s\n' "$text"
            fi
            ;;
    esac
}

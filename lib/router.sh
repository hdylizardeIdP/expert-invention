#!/usr/bin/env bash
# router.sh — task classification + agent selection

# Classify prompt into task type. Sets TASK_TYPE and TASK_CONFIDENCE.
classify_task() {
    local prompt="${1,,}" # lowercase

    TASK_CONFIDENCE="high"

    case "$prompt" in
        *review*|*"pull request"*|*"pr "*|*" pr"*|*"code review"*)
            TASK_TYPE="review" ;;
        *explain*|*"what does"*|*"what is"*|*"how does"*|*"why does"*)
            TASK_TYPE="explain" ;;
        *refactor*|*"clean up"*|*"simplify"*|*"restructure"*)
            TASK_TYPE="refactor" ;;
        *test*|*"unit test"*|*"write test"*|*"add test"*|*"spec"*)
            TASK_TYPE="test" ;;
        *debug*|*"fix bug"*|*"fix error"*|*"not working"*|*"broken"*|*"stacktrace"*|*"traceback"*)
            TASK_TYPE="debug" ;;
        *generate*|*create*|*write*|*implement*|*build*|*"add a"*|*"make a"*)
            TASK_TYPE="generate" ;;
        *error*|*bug*|*fix*)
            TASK_TYPE="debug"
            TASK_CONFIDENCE="medium" ;;
        *)
            TASK_TYPE="general"
            TASK_CONFIDENCE="low" ;;
    esac
}

# Select agent based on classification. Returns agent name.
select_agent() {
    local prompt="$1"

    # Stage 1: explicit --agent flag
    if [[ -n "${OPT_AGENT:-}" ]]; then
        SELECTED_AGENT="$OPT_AGENT"
        log_info "${TASK_TYPE:-explicit} -> $SELECTED_AGENT (explicit)"
        return 0
    fi

    # Stage 2: explicit --task flag
    if [[ -n "${OPT_TASK:-}" ]]; then
        TASK_TYPE="$OPT_TASK"
        TASK_CONFIDENCE="high"
    else
        # Stage 3: keyword heuristic
        classify_task "$prompt"
    fi

    # Lookup agent from routing config
    SELECTED_AGENT="${CONFIG[routing_${TASK_TYPE}]:-${CONFIG[general_default_agent]:-claude}}"

    # Low confidence: ask user interactively (if tty)
    if [[ "$TASK_CONFIDENCE" == "low" ]] && is_tty; then
        log_warn "no clear task type detected"
        local agents_str="${CONFIG[fallback_order]:-claude codex gemini}"
        read -ra agents <<< "$agents_str"

        printf '\nPick agent: ' >&2
        local i=1
        for a in "${agents[@]}"; do
            printf '[%d] %s ' "$i" "$a" >&2
            (( i++ ))
        done
        printf '\n> ' >&2

        local choice
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#agents[@]} )); then
            SELECTED_AGENT="${agents[$((choice - 1))]}"
        fi
        printf '\n' >&2
    fi

    log_info "$TASK_TYPE -> $SELECTED_AGENT"
}

# Validate agent name
validate_agent() {
    local agent="$1"
    case "$agent" in
        claude|codex|gemini) return 0 ;;
        *) die "unknown agent: $agent (expected claude|codex|gemini)" ;;
    esac
}

# Invoke the selected agent with fallback chain
invoke_with_fallback() {
    local prompt="$1" agent="$2"
    local fallback_order="${CONFIG[fallback_order]:-claude codex gemini}"
    read -ra fallbacks <<< "$fallback_order"

    # Move selected agent to front
    local ordered=("$agent")
    for a in "${fallbacks[@]}"; do
        [[ "$a" != "$agent" ]] && ordered+=("$a")
    done

    local result=""
    for a in "${ordered[@]}"; do
        has_cmd "$a" || { log_warn "$a not found, skipping"; continue; }

        log_debug "trying agent: $a"
        result=$(invoke_"$a" "$prompt")
        local exit_code=$?

        # Check if result is an error
        local is_error
        is_error=$(echo "$result" | json_get '.is_error')
        if [[ "$is_error" != "true" ]] && (( exit_code == 0 )); then
            echo "$result"
            return 0
        fi

        # Detect known error patterns
        local err_text
        err_text=$(echo "$result" | json_get '.text')
        case "$err_text" in
            *"429"*|*"rate limit"*) log_warn "$a rate limited, trying next" ;;
            *"auth"*|*"unauthorized"*|*"401"*) log_warn "$a auth error, trying next" ;;
            *"timed out"*) log_warn "$a timed out, trying next" ;;
            *) log_warn "$a failed: $err_text" ;;
        esac
    done

    # All agents failed — return last error
    if [[ -n "$result" ]]; then
        echo "$result"
    else
        build_normalized "none" "all agents failed" "true" "0" "0" "null"
    fi
    return 1
}

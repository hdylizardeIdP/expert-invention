#!/usr/bin/env bash
# log.sh — leveled logging (debug/info/warn/error)

# Log levels: debug=0, info=1, warn=2, error=3
declare -gA LOG_LEVELS=([debug]=0 [info]=1 [warn]=2 [error]=3)
declare -g CURRENT_LOG_LEVEL=1

set_log_level() {
    local level="${1,,}"
    if [[ -n "${LOG_LEVELS[$level]+x}" ]]; then
        CURRENT_LOG_LEVEL="${LOG_LEVELS[$level]}"
    fi
}

_log() {
    local level="$1" msg="$2"
    local level_num="${LOG_LEVELS[$level]:-1}"
    (( level_num < CURRENT_LOG_LEVEL )) && return

    local color=""
    case "$level" in
        debug) color="$DIM" ;;
        info)  color="$CYAN" ;;
        warn)  color="$YELLOW" ;;
        error) color="$RED" ;;
    esac

    printf '%s[orch:%s]%s %s\n' "$color" "$level" "$RESET" "$msg" >&2
}

log_debug() { _log debug "$*"; }
log_info()  { _log info "$*"; }
log_warn()  { _log warn "$*"; }
log_error() { _log error "$*"; }

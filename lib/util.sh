#!/usr/bin/env bash
# util.sh — colors, die(), warn(), is_tty()

# Color codes (empty if not a tty)
if [[ -t 2 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

die() {
    printf '%s[orch] FATAL: %s%s\n' "$RED" "$*" "$RESET" >&2
    exit 1
}

warn() {
    printf '%s[orch] WARN: %s%s\n' "$YELLOW" "$*" "$RESET" >&2
}

info() {
    printf '%s[orch]%s %s\n' "$CYAN" "$RESET" "$*" >&2
}

is_tty() {
    [[ -t 0 ]]
}

is_stderr_tty() {
    [[ -t 2 ]]
}

# Timestamp in milliseconds
now_ms() {
    if command -v date >/dev/null && date +%s%N >/dev/null 2>&1; then
        echo $(( $(date +%s%N) / 1000000 ))
    else
        echo $(( $(date +%s) * 1000 ))
    fi
}

# Generate short random ID
gen_id() {
    head -c 6 /dev/urandom | xxd -p 2>/dev/null || printf '%06x' $RANDOM$RANDOM
}

# Check if a command exists
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure a required command exists
require_cmd() {
    has_cmd "$1" || die "required command not found: $1"
}

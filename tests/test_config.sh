#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/util.sh"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/json.sh"
source "${SCRIPT_DIR}/lib/config.sh"

ORCH_DIR="$SCRIPT_DIR"
_detect_json_tool
set_log_level error

PASS=0 FAIL=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$label"
        (( PASS++ )) || true
    else
        printf '  %s✗%s %s: expected "%s", got "%s"\n' "$RED" "$RESET" "$label" "$expected" "$actual"
        (( FAIL++ )) || true
    fi
}

echo "=== Config: parse_config ==="

# Parse the default config
parse_config "${SCRIPT_DIR}/config/orch.conf"

assert_eq "general_default_agent" "claude" "${CONFIG[general_default_agent]}"
assert_eq "general_log_level" "info" "${CONFIG[general_log_level]}"
assert_eq "general_output_format" "text" "${CONFIG[general_output_format]}"
assert_eq "fallback_order" "claude codex gemini" "${CONFIG[fallback_order]}"
assert_eq "routing_generate" "claude" "${CONFIG[routing_generate]}"
assert_eq "routing_review" "codex" "${CONFIG[routing_review]}"
assert_eq "routing_explain" "gemini" "${CONFIG[routing_explain]}"
assert_eq "claude_model" "claude-sonnet-4-20250514" "${CONFIG[claude_model]}"
assert_eq "codex_model" "" "${CONFIG[codex_model]}"
assert_eq "codex_sandbox" "read-only" "${CONFIG[codex_sandbox]}"
assert_eq "codex_extra_flags" "--skip-git-repo-check" "${CONFIG[codex_extra_flags]}"
assert_eq "gemini_model" "gemini-2.5-flash" "${CONFIG[gemini_model]}"
assert_eq "fanout_timeout" "120" "${CONFIG[fanout_timeout]}"
assert_eq "cost_enabled" "true" "${CONFIG[cost_enabled]}"
assert_eq "cost_budget_warn" "5.00" "${CONFIG[cost_budget_warn]}"

echo ""
echo "=== Config: parse inline comments ==="

# Create temp config with inline comments
TMPCONF=$(mktemp)
cat > "$TMPCONF" <<'EOF'
[test]
key1 = value1 # this is a comment
key2 = value2
# full line comment
key3 = value with spaces
EOF

declare -gA CONFIG=()
parse_config "$TMPCONF"
rm -f "$TMPCONF"

assert_eq "inline comment stripped" "value1" "${CONFIG[test_key1]}"
assert_eq "normal value" "value2" "${CONFIG[test_key2]}"
assert_eq "value with spaces" "value with spaces" "${CONFIG[test_key3]}"

echo ""
echo "=== Config: load_config defaults ==="

declare -gA CONFIG=()
load_config "" 2>/dev/null

assert_eq "default_agent fallback" "claude" "${CONFIG[general_default_agent]}"
assert_eq "log_level fallback" "info" "${CONFIG[general_log_level]}"

echo ""
echo "=== Config: config_get ==="

CONFIG[test_key]="hello"
assert_eq "config_get existing" "hello" "$(config_get test_key)"
assert_eq "config_get missing with default" "fallback" "$(config_get nonexistent fallback)"
assert_eq "config_get missing no default" "" "$(config_get nonexistent)"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
(( FAIL == 0 )) && exit 0 || exit 1

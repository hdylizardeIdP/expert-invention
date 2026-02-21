#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/util.sh"
source "${SCRIPT_DIR}/lib/log.sh"
source "${SCRIPT_DIR}/lib/json.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/normalize.sh"
source "${SCRIPT_DIR}/lib/router.sh"

ORCH_DIR="$SCRIPT_DIR"
_detect_json_tool
set_log_level error  # quiet during tests
load_config ""

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

echo "=== Router: classify_task ==="

classify_task "review this pull request"
assert_eq "review PR" "review" "$TASK_TYPE"

classify_task "explain what a goroutine is"
assert_eq "explain goroutine" "explain" "$TASK_TYPE"

classify_task "refactor this function"
assert_eq "refactor" "refactor" "$TASK_TYPE"

classify_task "write unit tests for the parser"
assert_eq "unit tests" "test" "$TASK_TYPE"

classify_task "debug this error in the login flow"
assert_eq "debug error" "debug" "$TASK_TYPE"

classify_task "generate a fibonacci function"
assert_eq "generate" "generate" "$TASK_TYPE"

classify_task "create a REST API endpoint"
assert_eq "create -> generate" "generate" "$TASK_TYPE"

classify_task "what does this code do"
assert_eq "what does -> explain" "explain" "$TASK_TYPE"

classify_task "fix bug in authentication"
assert_eq "fix bug -> debug" "debug" "$TASK_TYPE"

classify_task "hello world"
assert_eq "general fallback" "general" "$TASK_TYPE"
assert_eq "low confidence" "low" "$TASK_CONFIDENCE"

echo ""
echo "=== Router: select_agent ==="

OPT_AGENT="" OPT_TASK=""
select_agent "review this code" 2>/dev/null
assert_eq "review -> codex" "codex" "$SELECTED_AGENT"

OPT_AGENT="" OPT_TASK=""
select_agent "explain what a goroutine is" 2>/dev/null
assert_eq "explain -> gemini" "gemini" "$SELECTED_AGENT"

OPT_AGENT="" OPT_TASK=""
select_agent "generate a function" 2>/dev/null
assert_eq "generate -> claude" "claude" "$SELECTED_AGENT"

OPT_AGENT="codex" OPT_TASK=""
select_agent "anything at all" 2>/dev/null
assert_eq "explicit agent override" "codex" "$SELECTED_AGENT"

OPT_AGENT="" OPT_TASK="review"
select_agent "anything at all" 2>/dev/null
assert_eq "explicit task override" "codex" "$SELECTED_AGENT"

echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL"
(( FAIL == 0 )) && exit 0 || exit 1

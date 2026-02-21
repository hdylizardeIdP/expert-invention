#!/usr/bin/env bash
# fanout.sh — parallel multi-agent execution (tmux panes with bg-job fallback)

fanout_execute() {
    local prompt="$1"
    local agents_str="${CONFIG[fanout_agents]:-claude codex gemini}"
    local timeout_secs="${OPT_TIMEOUT:-${CONFIG[fanout_timeout]:-120}}"
    read -ra agents <<< "$agents_str"

    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/orch-fanout.XXXXXX")

    # Filter to only available agents
    local available=()
    for a in "${agents[@]}"; do
        if has_cmd "$a"; then
            available+=("$a")
        else
            log_warn "fanout: $a not found, skipping"
        fi
    done

    if (( ${#available[@]} == 0 )); then
        die "no agents available for fanout"
    fi

    # Try tmux pane mode, fall back to background jobs
    if has_cmd tmux && is_stderr_tty; then
        _fanout_tmux "$prompt" "$tmpdir" "$timeout_secs" "${available[@]}"
    else
        _fanout_jobs "$prompt" "$tmpdir" "$timeout_secs" "${available[@]}"
    fi

    # Collect results
    local results="["
    local first=true
    for a in "${available[@]}"; do
        local outfile="$tmpdir/${a}.out"
        if [[ -f "$outfile" ]]; then
            local content
            content=$(cat "$outfile")
            if [[ -n "$content" ]]; then
                $first || results+=","
                results+="$content"
                first=false
            fi
        fi
    done
    results+="]"

    rm -rf "$tmpdir"

    # Output results
    local format="${OPT_OUTPUT_FORMAT:-${CONFIG[general_output_format]:-text}}"
    if [[ "$format" == "json" ]]; then
        echo "$results" | json_pretty
    else
        # Text mode: print each agent's response with header
        for a in "${available[@]}"; do
            local text
            text=$(echo "$results" | json_get ".${a}.text" 2>/dev/null)
            # Parse from array
            local idx=0
            for aa in "${available[@]}"; do
                if [[ "$aa" == "$a" ]]; then
                    break
                fi
                (( idx++ ))
            done
            text=$(echo "$results" | _json_array_get "$idx" "text")
            printf '\n%s━━━ %s ━━━%s\n' "$BOLD" "$a" "$RESET"
            if [[ -n "$text" ]]; then
                printf '%s\n' "$text"
            else
                printf '%s(no output)%s\n' "$DIM" "$RESET"
            fi
        done
    fi
}

_json_array_get() {
    local idx="$1" field="$2"
    case "$_json_tool" in
        jq)
            jq -r ".[$idx].$field // empty" 2>/dev/null
            ;;
        node)
            node -e "
                let d='';
                process.stdin.on('data',c=>d+=c);
                process.stdin.on('end',()=>{
                    try{let a=JSON.parse(d);let v=a[$idx]&&a[$idx]['$field'];if(v)process.stdout.write(String(v))}catch(e){}
                });
            " 2>/dev/null
            ;;
        python3)
            python3 -c "
import sys,json
try:
    a=json.load(sys.stdin);v=a[$idx].get('$field','')
    if v:print(v,end='')
except:pass
" 2>/dev/null
            ;;
    esac
}

_fanout_tmux() {
    local prompt="$1" tmpdir="$2" timeout_secs="$3"
    shift 3
    local agents=("$@")

    local session="orch-fanout-$$"

    # Detect if already inside tmux
    local tmux_cmd="new-session"
    [[ -n "${TMUX:-}" ]] && tmux_cmd="new-window"

    # Create script files for each agent
    for a in "${agents[@]}"; do
        cat > "$tmpdir/${a}.sh" <<SCRIPT
#!/usr/bin/env bash
source "${ORCH_DIR}/lib/util.sh"
source "${ORCH_DIR}/lib/log.sh"
source "${ORCH_DIR}/lib/json.sh"
source "${ORCH_DIR}/lib/config.sh"
source "${ORCH_DIR}/lib/normalize.sh"
source "${ORCH_DIR}/lib/agents/${a}.sh"
_detect_json_tool
load_config ""
echo "Running $a..."
result=\$(invoke_${a} $(printf '%q' "$prompt"))
echo "\$result" > "$tmpdir/${a}.out"
echo "\$result" | json_get '.text'
echo ""
echo "[done — press any key]"
read -r -n1
SCRIPT
        chmod +x "$tmpdir/${a}.sh"
    done

    # Create tmux session with first agent
    tmux "$tmux_cmd" -d -s "$session" "bash $tmpdir/${agents[0]}.sh" 2>/dev/null

    # Split panes for remaining agents
    local i=1
    while (( i < ${#agents[@]} )); do
        tmux split-window -t "$session" -h "bash $tmpdir/${agents[$i]}.sh" 2>/dev/null
        tmux select-layout -t "$session" tiled 2>/dev/null
        (( i++ ))
    done

    tmux select-layout -t "$session" tiled 2>/dev/null

    # Attach to session
    if [[ -n "${TMUX:-}" ]]; then
        # Already in tmux, switch to the window
        tmux select-window -t "$session" 2>/dev/null
    else
        tmux attach -t "$session" 2>/dev/null
    fi

    # Wait for output files
    local deadline=$(( $(date +%s) + timeout_secs ))
    while (( $(date +%s) < deadline )); do
        local all_done=true
        for a in "${agents[@]}"; do
            [[ -f "$tmpdir/${a}.out" ]] || { all_done=false; break; }
        done
        $all_done && break
        sleep 1
    done

    # Cleanup tmux session
    tmux kill-session -t "$session" 2>/dev/null
}

_fanout_jobs() {
    local prompt="$1" tmpdir="$2" timeout_secs="$3"
    shift 3
    local agents=("$@")
    local pids=()

    log_info "fanout: running ${#agents[@]} agents in parallel (background jobs)"

    for a in "${agents[@]}"; do
        (
            local result
            result=$(invoke_"$a" "$prompt" 2>/dev/null)
            echo "$result" > "$tmpdir/${a}.out"
        ) &
        pids+=($!)
    done

    # Wait for all jobs with timeout
    local deadline=$(( $(date +%s) + timeout_secs ))
    for pid in "${pids[@]}"; do
        local remaining=$(( deadline - $(date +%s) ))
        if (( remaining > 0 )); then
            timeout "$remaining" tail --pid="$pid" -f /dev/null 2>/dev/null || true
        fi
    done

    # Kill any remaining
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null
}

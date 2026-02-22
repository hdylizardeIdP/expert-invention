#!/usr/bin/env bash
# json.sh — JSON parsing abstraction (jq > node > python3 fallback)

# Detect best available JSON tool
_json_tool=""
_detect_json_tool() {
    if has_cmd jq; then
        _json_tool=jq
    elif has_cmd node; then
        _json_tool=node
    elif has_cmd python3; then
        _json_tool=python3
    else
        die "no JSON parser found (need jq, node, or python3)"
    fi
    log_debug "json tool: $_json_tool"
}

# Extract a field from JSON on stdin. Usage: json_get '.field.path'
# Supports simple dot-notation paths.
json_get() {
    local path="$1"
    case "$_json_tool" in
        jq)
            jq -r "$path // empty" 2>/dev/null
            ;;
        node)
            node -e "
                let d='';
                process.stdin.on('data',c=>d+=c);
                process.stdin.on('end',()=>{
                    try{
                        let o=JSON.parse(d);
                        let p='${path}'.replace(/^\./,'').split('.');
                        for(let k of p){if(o==null)break;o=o[k];}
                        if(o!==undefined&&o!==null)process.stdout.write(String(o));
                    }catch(e){}
                });
            " 2>/dev/null
            ;;
        python3)
            python3 -c "
import sys,json
try:
    o=json.load(sys.stdin)
    for k in '${path}'.lstrip('.').split('.'):
        if o is None: break
        o=o[k] if isinstance(o,dict) else o[int(k)]
    if o is not None: print(o,end='')
except: pass
" 2>/dev/null
            ;;
    esac
}

# Check if a value should be treated as raw JSON (not quoted).
# Matches: objects {}, arrays [], booleans, null, and pure numbers.
_is_json_raw() {
    local v="$1"
    [[ "$v" =~ ^\{.*\}$ ]] && return 0   # JSON object
    [[ "$v" =~ ^\[.*\]$ ]] && return 0   # JSON array
    [[ "$v" == "true" || "$v" == "false" || "$v" == "null" ]] && return 0
    [[ "$v" =~ ^-?[0-9]+\.?[0-9]*$ ]] && return 0  # number
    return 1
}

# Build a JSON object from key=value pairs.
# Usage: json_build key1 val1 key2 val2 ...
# Values that are objects, arrays, booleans, null, or pure numbers are raw JSON.
json_build() {
    local args=("$@")
    case "$_json_tool" in
        jq)
            local jq_args=() filter="{"
            local i=0
            while (( i < ${#args[@]} )); do
                local k="${args[$i]}" v="${args[$((i+1))]}"
                if (( i > 0 )); then filter+=","; fi
                # Check if value looks like raw JSON
                if _is_json_raw "$v"; then
                    filter+="\"$k\":$v"
                else
                    filter+="\"$k\":\$v${i}"
                    jq_args+=(--arg "v${i}" "$v")
                fi
                (( i += 2 ))
            done
            filter+="}"
            jq -n "${jq_args[@]}" "$filter" 2>/dev/null
            ;;
        node)
            local pairs=""
            local i=0
            while (( i < ${#args[@]} )); do
                local k="${args[$i]}" v="${args[$((i+1))]}"
                if (( i > 0 )); then pairs+=","; fi
                if _is_json_raw "$v"; then
                    pairs+="\"$k\":$v"
                else
                    pairs+="\"$k\":$(node -e "process.stdout.write(JSON.stringify(process.argv[1]))" "$v" 2>/dev/null)"
                fi
                (( i += 2 ))
            done
            echo "{$pairs}"
            ;;
        python3)
            local py_pairs=""
            local i=0
            while (( i < ${#args[@]} )); do
                local k="${args[$i]}" v="${args[$((i+1))]}"
                if (( i > 0 )); then py_pairs+=","; fi
                if _is_json_raw "$v"; then
                    py_pairs+="\"$k\":$v"
                else
                    py_pairs+="\"$k\":$(python3 -c "import json;print(json.dumps('$v'),end='')" 2>/dev/null)"
                fi
                (( i += 2 ))
            done
            echo "{$py_pairs}"
            ;;
    esac
}

# Pretty-print JSON from stdin
json_pretty() {
    case "$_json_tool" in
        jq)      jq . 2>/dev/null ;;
        node)    node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.stringify(JSON.parse(d),null,2)+'\n')}catch(e){process.stdout.write(d)}})" 2>/dev/null ;;
        python3) python3 -c "import sys,json;print(json.dumps(json.load(sys.stdin),indent=2))" 2>/dev/null ;;
    esac
}

# Validate JSON on stdin, returns 0 if valid
json_valid() {
    case "$_json_tool" in
        jq)      jq empty 2>/dev/null ;;
        node)    node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{JSON.parse(d)}catch(e){process.exit(1)}})" 2>/dev/null ;;
        python3) python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null ;;
    esac
}

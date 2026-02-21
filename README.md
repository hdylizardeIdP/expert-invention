# orch

Multi-agent CLI orchestrator. Routes prompts to **Claude**, **Codex**, and **Gemini** CLIs based on task type, with automatic fallback, parallel fan-out, and sequential pipeline chaining.

## Install

```bash
./install.sh
```

Symlinks `orch` to `~/.local/bin` and copies default config to `~/.config/orch/orch.conf`.

**Prerequisites**: `claude`, `codex`, and/or `gemini` CLIs installed and authenticated.

## Usage

```
orch [OPTIONS] [PROMPT...]
```

Prompt can also be piped via stdin.

### Options

| Flag | Description |
|------|-------------|
| `-a, --agent AGENT` | Force agent (`claude\|codex\|gemini`) |
| `-t, --task TYPE` | Declare task type (`generate\|review\|explain\|refactor\|test\|debug`) |
| `--model MODEL` | Override model for selected agent |
| `-f, --fanout` | Run on all agents in parallel (tmux panes) |
| `--pipeline CHAIN` | Chain agents sequentially: `"claude,codex"` |
| `-n, --dry-run` | Show routing decision without executing |
| `-j, --json` | JSON normalized output |
| `--raw` | Pass-through raw agent output |
| `--config FILE` | Alternate config file |
| `-v, --verbose` | Debug logging to stderr |
| `--timeout SECS` | Per-agent timeout |
| `--cost` | Show cumulative cost summary |
| `--history` | Show recent invocations |
| `--replay ID` | Replay a previous invocation |

### Examples

```bash
# Auto-routes to gemini (explain task detected)
orch "explain what a goroutine is"

# Force a specific agent
orch -a claude "write a fibonacci function"

# See routing decision without running
orch --dry-run "review this code"

# Fan-out: all agents answer in parallel (tmux panes)
orch --fanout "what is 2+2"

# Pipeline: claude generates, codex refines
orch --pipeline "claude,codex" "implement a stack in python"

# JSON output with cost info
orch -j "hello"

# Pipe from stdin
echo "explain bash" | orch
```

## Routing

Three-stage classification, first match wins:

1. **Explicit** — `--agent claude` bypasses classification
2. **Task flag** — `--task review` uses config mapping directly
3. **Keyword heuristic** — scans prompt for patterns (`*review*` → review, `*explain*` → explain, etc.)

Default routing (configurable in `orch.conf`):

| Task Type | Agent |
|-----------|-------|
| generate | claude |
| review | codex |
| explain | gemini |
| refactor | claude |
| test | codex |
| debug | claude |

When no task type is detected and stdin is a terminal, prompts interactively for agent selection. Otherwise falls back to `default_agent`.

## Fallback

If the selected agent fails (non-zero exit, timeout, rate limit, auth error), the next agent in `fallback.order` is tried automatically.

## Config

INI format at `~/.config/orch/orch.conf`. See [`config/orch.conf`](config/orch.conf) for all options.

## Architecture

```
orch (main)
├── lib/util.sh        — colors, die(), is_tty()
├── lib/log.sh         — leveled logging
├── lib/json.sh        — JSON parsing (jq > node > python3)
├── lib/config.sh      — INI parser → associative array
├── lib/router.sh      — task classification + agent selection
├── lib/normalize.sh   — unified output schema
├── lib/fanout.sh      — parallel execution (tmux / bg jobs)
├── lib/pipeline.sh    — sequential agent chaining
├── lib/cost.sh        — cost tracking + budget warnings
├── lib/history.sh     — invocation history + replay
└── lib/agents/
    ├── claude.sh      — claude -p --output-format json
    ├── codex.sh       — codex exec --json
    └── gemini.sh      — gemini -p -o json
```

---
description: "Start a ralph loop driven by beads (bd) — runs until every bead is closed"
argument-hint: "[optional guidance] [--max-iterations N] [--parallel N] [--parent ID[,ID...]]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-beads.sh:*)"]
hide-from-slash-command-tool: "true"
---

# ralph-beads

Initialize the loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-beads.sh" $ARGUMENTS
```

You are now inside a ralph-beads loop. Work one bead per iteration by default: query `bd ready` (or `bd ready --parent <id>` when scoped), pick the highest-priority claimable bead, mark it in_progress, do the work, verify it, and close it with `bd close`. If `--parallel N` was passed with N > 1, act as coordinator for up to N safe independent beads: claim them, delegate where available, integrate/review centrally, verify, and close only completed beads yourself. When you try to exit, the stop hook will re-send this prompt for the next iteration.

The loop terminates automatically once no open/in_progress/blocked beads remain (scoped to `--parent` descendants when the flag was passed) — no completion phrase is needed. Do not close beads you haven't actually completed just to end the loop.

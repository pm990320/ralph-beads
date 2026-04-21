---
description: "Start a ralph loop driven by beads (bd) — runs until every bead is closed"
argument-hint: "[optional guidance] [--max-iterations N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-beads.sh:*)"]
hide-from-slash-command-tool: "true"
---

# ralph-beads

Initialize the loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-beads.sh" $ARGUMENTS
```

You are now inside a ralph-beads loop. Work ONE bead per iteration: query `bd ready`, pick the highest-priority claimable bead, mark it in_progress, do the work, verify it, and close it with `bd close`. When you try to exit, the stop hook will re-send this prompt for the next iteration.

The loop terminates automatically once `bd count --status open`, `--status in_progress`, and `--status blocked` are all zero — no completion phrase is needed. Do not close beads you haven't actually completed just to end the loop.

---
description: "Explain the ralph-beads plugin and its commands"
---

# ralph-beads Help

Please explain the following to the user:

## What is ralph-beads?

ralph-beads is a Claude Code plugin that runs a Ralph-Wiggum-style self-referential loop driven by the [beads](https://github.com/steveyegge/beads) issue tracker (`bd` CLI). Unlike the generic `ralph-wiggum` plugin, you do **not** provide a prompt — the prompt is baked in and tells Claude to drain the beads queue one bead at a time.

## Loop mechanics

1. `/ralph-beads` creates `.claude/ralph-beads.local.md` with a fixed prompt.
2. The session works through **one bead per iteration**:
   - `bd ready` → pick highest-priority claimable bead
   - `bd update <id> --status in_progress`
   - Do the work, verify acceptance criteria
   - `bd close <id> -r "summary"`
3. When Claude tries to exit, the Stop hook checks:
   - `bd count --status open`
   - `bd count --status in_progress`
   - `bd count --status blocked`
   If all three are 0 the loop ends. Otherwise the same prompt is fed back for the next iteration.
4. `--max-iterations` (default 100) is a safety cap.

No `<promise>` tag, no custom completion phrase — **completion is measured directly from beads state**.

## Commands

### /ralph-beads [GUIDANCE...] [--max-iterations N] [--parent ID[,ID...]]

Start the loop. All positional args are optional and get appended as extra operator guidance (e.g. "prefer P0 first, run make test after each bead"). `--max-iterations 0` means unlimited.

`--parent <id>` (repeatable, comma-separated also accepted) scopes the loop to transitive descendants of the given bead(s). Both the picker (via `bd ready --parent <id>`) and the completion check use the scoped set — the loop ends when no descendants of the listed parents are open/in_progress/blocked. The parent beads themselves are never counted, so epics aren't required to be "closed" for the loop to finish.

### /cancel-ralph-beads

Delete `.claude/ralph-beads.local.md` so the next Stop exits cleanly.

### /help (namespaced as `/ralph-beads:help`)

This message.

## Requirements

- `bd` CLI on `PATH` (the plugin refuses to start without it).
- A `.beads` directory in the current working directory (i.e. `bd init` has been run).
- Beads to work on — the loop exits immediately if there's nothing open/in_progress/blocked.

## When to use it

**Good fit:**
- A backlog of well-scoped beads with clear acceptance criteria.
- Long-running autonomous work where you want Claude to just keep grinding.
- Workflows that already use beads as the source of truth.

**Bad fit:**
- Ambiguous tasks that need design decisions — those should be human-driven beads before you start.
- Repos where beads aren't set up.

## Learn more

- Ralph technique: https://ghuntley.com/ralph/
- Beads: https://github.com/steveyegge/beads
- Original ralph plugin: https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum

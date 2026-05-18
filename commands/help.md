---
description: "Explain the ralph-beads plugin and its commands"
---

# ralph-beads Help

Please explain the following to the user:

## What is ralph-beads?

ralph-beads is a Claude Code plugin that runs a Ralph-Wiggum-style self-referential loop driven by the [beads](https://github.com/steveyegge/beads) issue tracker (`bd` CLI). Unlike the generic `ralph-wiggum` plugin, you do **not** provide a prompt — the prompt is baked in and tells Claude to drain the beads queue one bead at a time by default, or coordinate safe independent batches with `--parallel N`.

## Loop mechanics

1. `/ralph-beads` creates `.claude/ralph-beads.local.md` with a fixed prompt.
2. The session works through **one bead per iteration by default**:
   - `bd ready` → pick highest-priority claimable bead
   - `bd update <id> --status in_progress`
   - Do the work, verify acceptance criteria
   - `bd close <id> -r "summary"`
3. When Claude tries to exit, the Stop hook checks:
   - `bd count --status open`
   - `bd count --status in_progress`
   - `bd count --status blocked`
   If all three are 0 the loop ends. Otherwise the same prompt is fed back for the next iteration.
4. `--max-iterations` (default 100) is a safety cap. `--parallel` defaults to 1, preserving serial behavior.

No `<promise>` tag, no custom completion phrase — **completion is measured directly from beads state**.

## Commands

### /ralph-beads [GUIDANCE...] [--max-iterations N] [--parallel N] [--parent ID[,ID...]] [--allow-main-worktree]

Start the loop. All positional args are optional and get appended as extra operator guidance (e.g. "prefer P0 first, run make test after each bead"). `--max-iterations 0` means unlimited. `--parallel N` allows up to N safe independent beads per iteration; default `1` is non-parallel.

`--parallel N` makes the main session a coordinator: it can claim a safe batch, delegate independent beads to sub-agents when available, integrate/review centrally, verify, and close completed beads itself. Workers should not close beads, commit final changes, or revert others. Risky/conflicting work stays serial.

`--parent <id>` (repeatable, comma-separated also accepted) scopes the loop to transitive descendants of the given bead(s). Both the picker (via `bd ready --parent <id>`) and the completion check use the scoped set — the loop ends when no descendants of the listed parents are open/in_progress/blocked. The parent beads themselves are never counted, so epics aren't required to be "closed" for the loop to finish.

### Multi-instance safety: worktrees

The Stop hook fires for **every** Claude Code / Codex session whose cwd is the loop's directory, and the loop state file (`.claude/ralph-beads.local.md`) is shared by path. If two agents are working in the same checkout, one session's Stop hook will re-prompt the other — they will fight each other and corrupt the loop.

To prevent this, `/ralph-beads` refuses to start in the **main git worktree** by default. Run each agent in its own linked worktree instead:

```
git worktree add ../<repo>-<task> -b <branch>
cd ../<repo>-<task>
/ralph-beads ...
```

Linked worktrees have distinct paths, so each gets its own state file and the Stop hooks don't cross-talk. Pass `--allow-main-worktree` to bypass the check when you know you're the only agent in this checkout.

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

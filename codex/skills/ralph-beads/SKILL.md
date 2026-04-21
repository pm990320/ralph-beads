---
name: ralph-beads
description: >
  Start a ralph-wiggum-style self-referential loop that drains the beads (bd) issue
  tracker one bead per iteration until every bead is closed. Use when the user says
  "ralph-beads", "start ralph", "drain beads queue", "run the beads loop", or
  similar. Works in tandem with a Stop hook that re-injects the loop prompt until
  bd reports zero open + zero in_progress + zero blocked beads (optionally scoped
  to a parent/epic via --parent). The user may pass free-form guidance (e.g.
  "prefer P0 first"), `--max-iterations N`, and/or `--parent <id[,id...]>` — parse
  those from their message.
tags: [automation, loop, beads, ralph]
---

# ralph-beads

You are being invoked to start a Ralph-Wiggum-style loop that drains the [beads](https://github.com/steveyegge/beads) queue one bead per iteration. A companion **Stop hook** will re-inject this same prompt every time you try to end your turn, until `bd count --status open`, `--status in_progress`, and `--status blocked` are all zero. You do **not** need to emit any completion phrase — the loop terminates automatically from beads state.

## Step 0 — Initialize the loop (run exactly once, on your very first turn)

If `.claude/ralph-beads.local.md` does not already exist in the current working directory, initialize it by running this shell command (substitute `<ARGS>` with the operator arguments parsed below):

```bash
{{PLUGIN_ROOT}}/scripts/setup-ralph-beads.sh <ARGS>
```

**Parsing operator arguments** from the user's message:
- Extract `--max-iterations N` if present (non-negative integer; 0 = unlimited; default 100).
- Extract `--parent <id>` (repeatable; also accept comma-separated like `--parent bd-42,bd-43`) if present. Scopes the loop to transitive descendants of those beads.
- Everything else becomes free-form **guidance** — pass it through as positional args, preserving the user's exact words.
- Example: user says *"ralph-beads prefer P0 first and run make test after each bead --max-iterations 50"* → run `setup-ralph-beads.sh prefer P0 first and run make test after each bead --max-iterations 50`.
- Example: user says *"ralph-beads under bd-42"* → run `setup-ralph-beads.sh --parent bd-42`.
- Example: user says just *"ralph-beads"* → run `setup-ralph-beads.sh` with no args.

If the setup script fails (missing `bd` on PATH, no `.beads/` directory, bad args), **stop** and surface the error to the user. Do not try to proceed without the state file.

If `.claude/ralph-beads.local.md` already exists (e.g. the Stop hook re-injected this skill mid-loop), skip Step 0 entirely and go straight to Step 1.

## Step 1 — Work one bead per iteration

Each iteration of the loop:

1. See what's claimable.
   - **Unscoped** (no `--parent` in the state frontmatter): `bd ready --limit 20` or `bd ready --json`.
   - **Scoped**: read the `parents:` line from `.claude/ralph-beads.local.md` frontmatter; run `bd ready --parent <id>` for each listed parent, merge the results, and pick from that union. Do NOT use plain `bd ready` in scoped mode — it would surface out-of-scope beads. Never open/update/close beads whose parent chain doesn't reach a listed parent.
   - If nothing is ready but `bd count --status blocked` > 0, investigate the blockers — resolve them, close stale dependencies, or document why the blocked beads cannot proceed and close them with a reason.
2. Pick **ONE** bead. Prefer the highest-priority ready bead (P0 > P1 > P2 > P3). Break ties by oldest `created_at`.
3. Run `bd show <id>` to read the full description and acceptance criteria.
4. Mark it in progress: `bd update <id> --status in_progress` (or `bd set-state <id> in_progress`) so the loop snapshot stays accurate.
5. Do the actual work: read/edit/write code, run tests, etc. Follow any repo-level `CLAUDE.md` / `AGENTS.md` instructions.
6. Verify the acceptance criteria are met. Run tests / lint if the repo has them.
7. Close the bead: `bd close <id> -r "<one-line summary>"`. **Only** close when the work is genuinely done — do not close to escape the loop.
8. Commit your changes if the repo is a git repo and the user has not said otherwise. Keep commits scoped to the bead you just closed.

## Rules

- Work exactly **one** bead per iteration. The Stop hook feeds you back for the next.
- **Never close a bead you did not actually complete.** If a bead is impossible or wrong, `bd update` it with an explanation and leave it for a human, or create a follow-up bead (`bd create`) capturing what's missing.
- If you discover work that belongs in its own bead, create it with `bd create` and link dependencies (`bd dep add`) rather than scope-creeping.
- The loop terminates automatically once open + in_progress + blocked all reach 0 across the active scope (all beads if unscoped; transitive descendants of listed parents if scoped). You do **not** need to emit any completion phrase. The parent beads themselves are never counted — close them yourself if desired or run `bd epic close-eligible`.
- If you're confused about state, run `bd status` and `bd ready --explain`.

## Cancelling

The user can cancel the loop at any time by invoking the **cancel-ralph-beads** skill, or by deleting `.claude/ralph-beads.local.md` manually. The next Stop hook firing will see no state file and exit cleanly.

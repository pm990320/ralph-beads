---
name: ralph-beads
description: >
  Start a ralph-wiggum-style self-referential loop that drains the beads (bd) issue
  tracker one bead at a time by default (or coordinated parallel batches with --parallel) until every bead is closed. Use when the user says
  "ralph-beads", "start ralph", "drain beads queue", "run the beads loop", or
  similar. Works in tandem with a Stop hook that re-injects the loop prompt until
  bd reports zero open + zero in_progress + zero blocked beads (optionally scoped
  to a parent/epic via --parent). The user may pass free-form guidance (e.g.
  "prefer P0 first"), `--max-iterations N`, `--parallel N`, and/or `--parent <id[,id...]>` — parse
  those from their message.
tags: [automation, loop, beads, ralph]
---

# ralph-beads

You are being invoked to start a Ralph-Wiggum-style loop that drains the [beads](https://github.com/steveyegge/beads) queue one bead per iteration by default, or up to a safe parallel batch when `--parallel N` is passed. A companion **Stop hook** will re-inject this same prompt every time you try to end your turn, until `bd count --status open`, `--status in_progress`, and `--status blocked` are all zero. You do **not** need to emit any completion phrase — the loop terminates automatically from beads state.

## Step 0 — Initialize the loop (run exactly once, on your very first turn)

If `.claude/ralph-beads.local.md` does not already exist in the current working directory, initialize it by running this shell command (substitute `<ARGS>` with the operator arguments parsed below):

```bash
{{PLUGIN_ROOT}}/scripts/setup-ralph-beads.sh <ARGS>
```

**Parsing operator arguments** from the user's message:
- Extract `--max-iterations N` if present (non-negative integer; 0 = unlimited; default 100).
- Extract `--parent <id>` (repeatable; also accept comma-separated like `--parent bd-42,bd-43`) if present. Scopes the loop to transitive descendants of those beads.
- Extract `--parallel N` if present (positive integer; default 1). `1` preserves serial behavior. Values greater than 1 let the coordinator use sub-agents for safe independent beads.
- Everything else becomes free-form **guidance** — pass it through as positional args, preserving the user's exact words.
- Example: user says *"ralph-beads prefer P0 first and run make test after each bead --max-iterations 50"* → run `setup-ralph-beads.sh prefer P0 first and run make test after each bead --max-iterations 50`.
- Example: user says *"ralph-beads under bd-42"* → run `setup-ralph-beads.sh --parent bd-42`.
- Example: user says *"ralph-beads --parallel 4 docs and tests first"* → run `setup-ralph-beads.sh --parallel 4 docs and tests first`.
- Example: user says just *"ralph-beads"* → run `setup-ralph-beads.sh` with no args.

If the setup script fails (missing `bd` on PATH, no `.beads/` directory, bad args), **stop** and surface the error to the user. Do not try to proceed without the state file.

If `.claude/ralph-beads.local.md` already exists (e.g. the Stop hook re-injected this skill mid-loop), skip Step 0 entirely and go straight to Step 1.

## Step 1 — Work one bead per iteration by default, or a safe batch in parallel mode

Each iteration of the loop:

1. See what's claimable.
   - **Unscoped** (no `--parent` in the state frontmatter): `bd ready --limit 20` or `bd ready --json`.
   - **Scoped**: read the `parents:` line from `.claude/ralph-beads.local.md` frontmatter; run `bd ready --parent <id>` for each listed parent, merge the results, and pick from that union. Do NOT use plain `bd ready` in scoped mode — it would surface out-of-scope beads. Never open/update/close beads whose parent chain doesn't reach a listed parent.
   - If nothing is ready but `bd count --status blocked` > 0, investigate the blockers — resolve them, close stale dependencies, or document why the blocked beads cannot proceed and close them with a reason.
2. Choose work for this iteration. Read `parallel:` from `.claude/ralph-beads.local.md` frontmatter.
   - If `parallel: 1`, pick exactly **ONE** bead. Prefer the highest-priority ready bead (P0 > P1 > P2 > P3). Break ties by oldest `created_at`.
   - If `parallel` is greater than 1, act as a coordinator. Build a batch of up to `parallel` ready beads that are safe to work in parallel. Prefer independent beads with disjoint likely write sets, packages, components, labels, and dependency trees. Leave high-conflict, architectural, migration, shared-config, broad-refactor, or ambiguous beads for serial work.
3. For each chosen bead, run `bd show <id>` to read the full description and acceptance criteria, then mark it in progress: `bd update <id> --status in_progress` (or `bd set-state <id> in_progress`) so the loop snapshot stays accurate.
4. Do the actual work. Follow repo-level `CLAUDE.md` / `AGENTS.md` instructions.
   - In serial mode, work the one bead yourself.
   - In parallel mode, use available sub-agent/delegation tools for independent beads when your harness supports them. Give each worker one bead, explicit file/module ownership, and this rule: workers may edit and verify, but must **NOT** close beads, make final commits, or revert others' changes. While workers run, do useful non-overlapping coordinator work yourself.
5. Integrate/review each result centrally. Verify acceptance criteria are met. Run targeted tests/lint for worker changes plus broader tests when appropriate.
6. Close only completed, verified beads with `bd close <id> -r "<one-line summary>"`. Do not close beads merely because a worker attempted them. For failed or unclear work, leave the bead in_progress/open with notes or create/link a follow-up bead capturing what's missing.
7. Commit your changes if the repo is a git repo and the user has not said otherwise. Keep commits scoped and understandable; in parallel mode, prefer one commit per completed bead or a clearly related batch commit.

## Rules

- Default/serial mode is `parallel: 1`, which means exactly **one** bead per iteration. The Stop hook feeds you back for the next.
- Parallel mode may complete up to `parallel` safe, independent beads per iteration, but correctness beats throughput. When in doubt, reduce the batch size or handle risky beads serially.
- **Never close a bead you did not actually complete.** If a bead is impossible or wrong, `bd update` it with an explanation and leave it for a human, or create a follow-up bead (`bd create`) capturing what's missing.
- If you discover work that belongs in its own bead, create it with `bd create` and link dependencies (`bd dep add`) rather than scope-creeping.
- The loop terminates automatically once open + in_progress + blocked all reach 0 across the active scope (all beads if unscoped; transitive descendants of listed parents if scoped). You do **not** need to emit any completion phrase. The parent beads themselves are never counted — close them yourself if desired or run `bd epic close-eligible`.
- If you're confused about state, run `bd status` and `bd ready --explain`.

## Cancelling

The user can cancel the loop at any time by invoking the **cancel-ralph-beads** skill, or by deleting `.claude/ralph-beads.local.md` manually. The next Stop hook firing will see no state file and exit cleanly.

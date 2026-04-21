# ralph-beads

A plugin that runs a [Ralph Wiggum](https://ghuntley.com/ralph/)–style self-referential loop driven by the [beads](https://github.com/steveyegge/beads) issue tracker (`bd` CLI). It iterates until every bead is closed. You do **not** supply a prompt — the prompt is built in and tells the agent to drain the beads queue one bead per iteration.

Ships for **Claude Code** (native plugin) and **Codex CLI** (install script that wires up custom prompts + Stop hook).

## How it works

```
/ralph-beads
   │
   ▼
┌──────────────────────────────────────────────────────┐
│ each iteration                                        │
│   1. bd ready --limit 20                              │
│   2. pick highest-priority claimable bead             │
│   3. bd update <id> --status in_progress              │
│   4. do the work, verify acceptance criteria          │
│   5. bd close <id> -r "<summary>"                     │
└──────────────────────────────────────────────────────┘
   │
   ▼
Claude tries to exit → Stop hook checks:
  bd count --status open
  bd count --status in_progress
  bd count --status blocked
   ├── all 0      → loop ends
   └── otherwise  → re-inject the same prompt for the next iteration
```

There is no `<promise>` tag. Completion is measured directly from beads state, so Claude can't short-circuit by claiming done.

## Install

### Claude Code

This repo is a Claude Code plugin at its root. Point a marketplace or a local plugin directory at it and enable it in Claude Code. See the [Claude Code plugin docs](https://docs.anthropic.com/en/docs/claude-code/plugins) for the current install flow.

### Codex CLI (0.122+)

Codex replaced custom prompts with **Skills** and doesn't auto-wire plugin-bundled hooks, so there's a one-shot install script:

```bash
git clone <this repo> /path/to/ralph-beads
/path/to/ralph-beads/codex/install.sh
```

The installer:
- Copies rendered Skills into `~/.agents/skills/ralph-beads/` and `~/.agents/skills/cancel-ralph-beads/`.
- Registers the Stop hook in `~/.codex/hooks.json` (merges with existing hooks).
- Sets `[features] codex_hooks = true` in `~/.codex/config.toml`.

Restart any active Codex sessions after installing. Uninstall with `codex/install.sh uninstall`. Re-run install after moving the plugin directory (absolute paths are baked in).

Requires `jq` on `PATH` (used by both the installer and the Stop hook).

## Commands

| Harness | Invocation | Description |
|---|---|---|
| Claude Code | `/ralph-beads [GUIDANCE...] [--max-iterations N] [--parent ID[,ID...]]` | Start the loop. Extra args become operator guidance appended to the built-in prompt. `--max-iterations` defaults to 100 (`0` = unlimited). `--parent` scopes the loop to transitive descendants of one or more parent beads/epics. |
| Claude Code | `/cancel-ralph-beads` | Delete the state file so the next Stop exits cleanly. |
| Claude Code | `/ralph-beads:help` | In-session help. |
| Codex | `$ralph-beads [GUIDANCE...] [--max-iterations N] [--parent ID[,ID...]]` (or `/skills` picker, or just ask "run ralph-beads under bd-42") | Same behavior as the Claude Code version. |
| Codex | `$cancel-ralph-beads` | Cancel the active loop. |

Under Codex, Skills are selected by the model — there's no direct slash-command-with-args primitive. The skill's instructions tell the model to parse `--max-iterations N`, `--parent <id>`, and free-form guidance out of your message and forward them to `setup-ralph-beads.sh`.

### Scoping to an epic (or several)

Pass `--parent <id>` (repeatable, or comma-separated) to restrict the loop to transitive descendants of one or more parent beads. Both the picker (via `bd ready --parent <id>`) and the completion check are scoped — the loop terminates when no descendant is open/in_progress/blocked. The parent beads themselves are never counted, so you can close them manually at the end (or run `bd epic close-eligible`).

```
/ralph-beads --parent bd-42
/ralph-beads --parent bd-42,bd-43
/ralph-beads --parent bd-42 --max-iterations 25 prefer P0 first
```

## Requirements

- `bd` CLI on `PATH`.
- The working directory must be a beads-initialized repo (`.beads/` exists).
- At least one open / in_progress / blocked bead — otherwise the loop exits on the first Stop.

## Examples

```
# Just drain the queue
/ralph-beads

# Cap iterations
/ralph-beads --max-iterations 25

# Scope to an epic (transitive descendants)
/ralph-beads --parent bd-42

# Scope to multiple epics
/ralph-beads --parent bd-42,bd-43 --max-iterations 25

# Extra operator guidance
/ralph-beads prefer P0 first, run `make test` after each bead, never touch infra/
```

## Files

```
.claude-plugin/plugin.json   # Claude Code plugin manifest
commands/                    # Claude Code slash commands
  ralph-beads.md             #   /ralph-beads
  cancel-ralph-beads.md      #   /cancel-ralph-beads
  help.md                    #   /ralph-beads:help
hooks/
  hooks.json                 # Claude Code Stop hook registration
  stop-hook.sh               # Stop-hook logic (shared by both harnesses)
scripts/
  setup-ralph-beads.sh       # Writes .claude/ralph-beads.local.md (shared)
codex/                       # Codex CLI build (0.122+)
  skills/
    ralph-beads/SKILL.md     #   $ralph-beads    (template)
    cancel-ralph-beads/SKILL.md  # $cancel-ralph-beads
  hooks.json                 # Stop hook template (rendered at install time)
  install.sh                 # Installer (copies skills into ~/.agents/skills/,
                             #            merges hook into ~/.codex/hooks.json)
```

The Codex build reuses `hooks/stop-hook.sh` and `scripts/setup-ralph-beads.sh` — the JSON contract (`{"decision":"block","reason":...}`) is the same between Claude Code and Codex Stop hooks, and the state file lives at `.claude/ralph-beads.local.md` in both (historical name; shared by design so you can switch harnesses mid-loop).

## Safety notes

- The built-in prompt tells Claude to **not** close beads it didn't actually complete. There is no machine-enforceable check for that — trust the prompt + your review of the commits.
- `--max-iterations` is the hard circuit breaker. Default is 100.
- If `bd` disappears mid-loop (e.g. uninstalled) the hook self-disables and removes the state file.

## Credit

Built on the structure of Anthropic's [ralph-wiggum](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) plugin, retargeted at beads-driven task queues.

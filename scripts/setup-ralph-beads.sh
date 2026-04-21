#!/bin/bash

# Ralph-Beads setup script
# Creates the state file for an in-session ralph loop driven by beads (bd).

set -euo pipefail

MAX_ITERATIONS=100
EXTRA_GUIDANCE_PARTS=()
PARENT_IDS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat <<'HELP_EOF'
ralph-beads — loop until every bead is closed

USAGE:
  /ralph-beads [GUIDANCE...] [OPTIONS]

ARGUMENTS:
  GUIDANCE...   Optional free-form guidance appended to the built-in prompt
                (e.g. "prefer P0 issues", "run tests after each bead").

OPTIONS:
  --max-iterations <n>   Safety cap on loop iterations (default: 100, 0 = unlimited)
  --parent <id[,id..]>   Scope the loop to one or more parent beads/epics.
                         Only transitive descendants are worked and counted.
                         Repeatable; comma-separated also accepted.
  -h, --help             Show this help

DESCRIPTION:
  Starts a Ralph-Wiggum-style loop in the current session. Each iteration tells
  Claude to query `bd ready`, claim one ready bead, work it to completion, and
  close it with `bd close`. The stop hook reruns the same prompt until no
  descendant beads remain open/in_progress/blocked (or until --max-iterations).

  When --parent is passed, both the picker and the completion check are scoped
  to transitive descendants of the given bead(s). No `<promise>` tag is required
  — completion is measured from beads state.

EXAMPLES:
  /ralph-beads
  /ralph-beads --max-iterations 50
  /ralph-beads --parent bd-42
  /ralph-beads --parent bd-42,bd-43 prefer P0 first
  /ralph-beads prefer P0 and P1 first, run make test after each bead

CANCEL:
  /cancel-ralph-beads
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "❌ --max-iterations requires a non-negative integer (got: '${2:-}')" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --parent)
      if [[ -z "${2:-}" ]]; then
        echo "❌ --parent requires a bead id (e.g. --parent bd-42 or --parent bd-42,bd-43)" >&2
        exit 1
      fi
      IFS=',' read -r -a _split <<< "$2"
      for _id in "${_split[@]}"; do
        _id="${_id// /}"
        [[ -n "$_id" ]] && PARENT_IDS+=("$_id")
      done
      shift 2
      ;;
    *)
      EXTRA_GUIDANCE_PARTS+=("$1")
      shift
      ;;
  esac
done

if ! command -v bd >/dev/null 2>&1; then
  echo "❌ ralph-beads: 'bd' CLI not found on PATH." >&2
  echo "   Install beads (https://github.com/steveyegge/beads) before using this plugin." >&2
  exit 1
fi

if [[ ! -d .beads ]]; then
  echo "❌ ralph-beads: no .beads directory in $(pwd)." >&2
  echo "   Run 'bd init' first, or cd into a beads-enabled repo." >&2
  exit 1
fi

# Validate any --parent IDs exist before we write state. Fail fast rather than
# letting the loop spin on an empty descendant set.
for pid in "${PARENT_IDS[@]}"; do
  if ! bd show "$pid" >/dev/null 2>&1; then
    echo "❌ ralph-beads: --parent '$pid' does not resolve to a bead." >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-bd-descendants.sh
source "$SCRIPT_DIR/lib-bd-descendants.sh"

EXTRA_GUIDANCE="${EXTRA_GUIDANCE_PARTS[*]:-}"
PARENTS_CSV=""
if [[ ${#PARENT_IDS[@]} -gt 0 ]]; then
  PARENTS_CSV=$(IFS=,; echo "${PARENT_IDS[*]}")
fi

mkdir -p .claude

STATE_FILE=".claude/ralph-beads.local.md"

BASE_PROMPT=$(cat <<'PROMPT_EOF'
You are running inside a ralph-beads loop. Your job is to drain the beads queue.

Each iteration of this loop:

1. Run `bd ready --limit 20` (or `bd ready --json`) to see what's claimable.
   - If nothing is ready but `bd count --status blocked` > 0, investigate the
     blockers — resolve them, close stale dependencies, or document why the
     blocked beads cannot proceed and close them with a reason.
2. Pick ONE bead to work on. Prefer the highest-priority ready bead
   (P0 > P1 > P2 > P3). Break ties by oldest created_at.
3. Run `bd show <id>` to read the full description and acceptance criteria.
4. Mark it in progress with `bd update <id> --status in_progress` (or
   `bd set-state <id> in_progress`) so the loop's snapshot stays accurate.
5. Do the actual work: read/edit/write code, run tests, etc. Follow any
   repo-level CLAUDE.md / AGENTS.md instructions.
6. Verify the acceptance criteria are met. Run tests/lint if the repo has them.
7. Close the bead with `bd close <id> -r "<one-line summary>"`. Only close
   when the work is genuinely done — do not close to escape the loop.
8. Commit your changes if the repo is a git repo and the user has not said
   otherwise. Keep commits scoped to the bead you just closed.

Rules:
- Work exactly ONE bead per iteration. The loop will feed you back for the next.
- Never close a bead you did not actually complete. If a bead is impossible
  or wrong, `bd update` it with an explanation and leave it for a human, or
  create a follow-up bead capturing what's missing.
- If you discover work that belongs in its own bead, create it with
  `bd create` and link dependencies (`bd dep add`) rather than scope-creeping.
- The loop terminates automatically once open + in_progress + blocked all
  reach 0. You do NOT need to emit any completion phrase.
- If you're confused about state, run `bd status` and `bd ready --explain`.
PROMPT_EOF
)

PROMPT="$BASE_PROMPT"
if [[ -n "$PARENTS_CSV" ]]; then
  PROMPT="$PROMPT

Scope constraint:
This loop is scoped to transitive descendants of the following parent bead(s): ${PARENTS_CSV}.
- Pick work with \`bd ready --parent <id>\` — iterate over each listed parent if
  there are multiple and merge results. Do NOT use plain \`bd ready\` — it would
  surface out-of-scope beads.
- Do not open, update, or close beads that are not descendants of the listed
  parents (you may still read them with \`bd show\` for context).
- If a scoped bead needs a new child bead, create it with \`bd create\` and link
  it under the same parent via \`bd dep add <parent> parent-of <new-id>\` so it
  stays in scope.
- The loop terminates when no descendants of the listed parents are
  open/in_progress/blocked. The parent beads themselves are NOT counted — close
  them yourself if you want, or run \`bd epic close-eligible\` at the end."
fi

if [[ -n "$EXTRA_GUIDANCE" ]]; then
  PROMPT="$PROMPT

Additional guidance from the operator:
$EXTRA_GUIDANCE"
fi

cat > "$STATE_FILE" <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
parents: "$PARENTS_CSV"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF

if [[ -n "$PARENTS_CSV" ]]; then
  ALL_SNAPSHOT=$(bd_snapshot_all)
  DESC_IDS=$(bd_descendants "$ALL_SNAPSHOT" "${PARENT_IDS[@]}")
  OPEN=$(bd_count_among "$ALL_SNAPSHOT" open "$DESC_IDS")
  IN_PROGRESS=$(bd_count_among "$ALL_SNAPSHOT" in_progress "$DESC_IDS")
  BLOCKED=$(bd_count_among "$ALL_SNAPSHOT" blocked "$DESC_IDS")
else
  OPEN=$(bd count --status open 2>/dev/null | tail -1)
  IN_PROGRESS=$(bd count --status in_progress 2>/dev/null | tail -1)
  BLOCKED=$(bd count --status blocked 2>/dev/null | tail -1)
fi
[[ "$OPEN" =~ ^[0-9]+$ ]] || OPEN=0
[[ "$IN_PROGRESS" =~ ^[0-9]+$ ]] || IN_PROGRESS=0
[[ "$BLOCKED" =~ ^[0-9]+$ ]] || BLOCKED=0
TOTAL=$((OPEN + IN_PROGRESS + BLOCKED))

SCOPE_LINE="Beads remaining: open=$OPEN in_progress=$IN_PROGRESS blocked=$BLOCKED (total=$TOTAL)"
if [[ -n "$PARENTS_CSV" ]]; then
  SCOPE_LINE="$SCOPE_LINE  [scoped to: $PARENTS_CSV]"
fi

cat <<EOF
🔄 ralph-beads loop activated.

State file:      $STATE_FILE
Iteration:       1
Max iterations:  $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
$SCOPE_LINE

The stop hook will keep feeding this prompt back until every scoped bead is
closed or --max-iterations is hit. Cancel with /cancel-ralph-beads.
EOF

if [[ $TOTAL -eq 0 ]]; then
  cat <<'EOF'

⚠️  There are no open/in_progress/blocked beads right now. The loop will end
    on the first stop. Create beads with `bd create` before starting, or pass
    guidance telling Claude to populate them first.
EOF
fi

echo ""
echo "$PROMPT"

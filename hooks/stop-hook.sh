#!/bin/bash

# Ralph-Beads Stop Hook
# Keeps the session looping until every bead is closed.
# Completion condition: bd reports 0 open + 0 in_progress + 0 blocked issues.

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/ralph-beads.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

if ! command -v bd >/dev/null 2>&1; then
  echo "⚠️  ralph-beads: 'bd' CLI not found on PATH — stopping loop" >&2
  rm -f "$STATE_FILE"
  exit 0
fi

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
PARENTS_CSV=$(echo "$FRONTMATTER" | grep '^parents:' | sed -E 's/^parents:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  ralph-beads: state file $STATE_FILE is corrupted — stopping" >&2
  rm -f "$STATE_FILE"
  exit 0
fi

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DESC="$HOOK_DIR/../scripts/lib-bd-descendants.sh"
if [[ -n "$PARENTS_CSV" && ! -f "$LIB_DESC" ]]; then
  echo "⚠️  ralph-beads: descendant helper not found at $LIB_DESC — stopping" >&2
  rm -f "$STATE_FILE"
  exit 0
fi

count_status() {
  local want="$1"
  local out
  out=$(bd count --status "$want" 2>/dev/null | tail -1)
  if [[ "$out" =~ ^[0-9]+$ ]]; then
    echo "$out"
  else
    echo "0"
  fi
}

if [[ -n "$PARENTS_CSV" ]]; then
  # shellcheck disable=SC1090
  source "$LIB_DESC"
  IFS=',' read -r -a _parent_ids <<< "$PARENTS_CSV"
  ALL_SNAPSHOT=$(bd_snapshot_all)
  DESC_IDS=$(bd_descendants "$ALL_SNAPSHOT" "${_parent_ids[@]}")
  OPEN=$(bd_count_among "$ALL_SNAPSHOT" open "$DESC_IDS")
  IN_PROGRESS=$(bd_count_among "$ALL_SNAPSHOT" in_progress "$DESC_IDS")
  BLOCKED=$(bd_count_among "$ALL_SNAPSHOT" blocked "$DESC_IDS")
else
  OPEN=$(count_status open)
  IN_PROGRESS=$(count_status in_progress)
  BLOCKED=$(count_status blocked)
fi
REMAINING=$((OPEN + IN_PROGRESS + BLOCKED))

emit_allow_stop() {
  # Emit a valid "allow the stop to proceed" JSON payload. No `decision` field,
  # so neither Claude Code nor Codex blocks termination. `systemMessage` is shown
  # as a UI notice in both harnesses.
  jq -n --arg msg "$1" '{ "systemMessage": $msg }'
}

if [[ $REMAINING -eq 0 ]]; then
  emit_allow_stop "✅ ralph-beads: no remaining beads (open=0 in_progress=0 blocked=0). Loop complete after $ITERATION iteration(s)."
  rm -f "$STATE_FILE"
  exit 0
fi

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  emit_allow_stop "🛑 ralph-beads: max iterations ($MAX_ITERATIONS) reached with $REMAINING bead(s) still open. Stopping."
  rm -f "$STATE_FILE"
  exit 0
fi

NEXT_ITERATION=$((ITERATION + 1))

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  ralph-beads: prompt body missing from $STATE_FILE — stopping" >&2
  rm -f "$STATE_FILE"
  exit 0
fi

TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

SNAPSHOT="Beads remaining: open=$OPEN in_progress=$IN_PROGRESS blocked=$BLOCKED (total=$REMAINING)"
if [[ -n "$PARENTS_CSV" ]]; then
  SNAPSHOT="$SNAPSHOT [scoped to: $PARENTS_CSV]"
fi

if [[ $MAX_ITERATIONS -gt 0 ]]; then
  SYSTEM_MSG="🔄 ralph-beads iteration $NEXT_ITERATION/$MAX_ITERATIONS | $SNAPSHOT"
else
  SYSTEM_MSG="🔄 ralph-beads iteration $NEXT_ITERATION | $SNAPSHOT"
fi

FULL_PROMPT="${PROMPT_TEXT}

---

Current bead snapshot: ${SNAPSHOT}
Loop iteration: ${NEXT_ITERATION}$(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo " of ${MAX_ITERATIONS}"; fi)"

jq -n \
  --arg prompt "$FULL_PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0

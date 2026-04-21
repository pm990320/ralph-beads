#!/bin/bash
# ralph-beads — shared descendant helpers (sourced by setup-ralph-beads.sh and stop-hook.sh)
#
# bd's `list --json` includes a `parent` field on each bead that has one. We take
# ONE snapshot of the repo via `bd list --all --limit 0 --json` and walk it in
# bash + jq — O(nodes) jq invocations, no per-bead shell calls.
#
# Intentionally avoids bash-4 features (associative arrays) so it runs on the
# Bash 3.2 that ships with macOS.

# bd_snapshot_all
#   Emit a JSON array containing every bead in the repo. Caller should capture
#   to a variable. We strip ASCII control chars (<= 0x1f) from bd's output — bd
#   can emit bare newlines/tabs inside description strings, which breaks jq's
#   strict JSON parser. Whitespace between tokens is OK; stripping it flattens
#   bd's pretty-print output into single-line JSON, which jq parses fine.
bd_snapshot_all() {
  bd list --all --limit 0 --json 2>/dev/null | LC_ALL=C tr -d '\000-\037'
}

# bd_descendants <all_json> <root_id> [root_id...]
#   Prints each descendant bead id (EXCLUDING the roots themselves), one per line,
#   deduplicated. Transitive over the `parent` field.
bd_descendants() {
  local all_json="$1"
  shift
  if [[ $# -eq 0 ]]; then return 0; fi
  if [[ -z "$all_json" ]]; then return 0; fi

  # Space-delimited "visited" set (tokens wrapped in spaces for safe `case` matching).
  # Tracks roots with leading 'R:' and descendants with 'D:' so we can filter at emit time.
  local visited_roots=" "
  local visited_descs=" "
  local queue=("$@")
  local r
  for r in "$@"; do
    visited_roots="$visited_roots$r "
  done

  while [[ ${#queue[@]} -gt 0 ]]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    local kid
    while IFS= read -r kid; do
      if [[ -z "$kid" ]]; then continue; fi
      case "$visited_roots$visited_descs" in
        *" $kid "*) : ;;  # already seen (as root or descendant)
        *)
          visited_descs="$visited_descs$kid "
          queue+=("$kid")
          ;;
      esac
    done < <(jq -r --arg p "$current" '.[] | select(.parent == $p) | .id' <<< "$all_json")
  done

  # Emit descendants only (trim surrounding spaces, split on whitespace).
  local trimmed="${visited_descs# }"
  trimmed="${trimmed% }"
  if [[ -n "$trimmed" ]]; then
    printf '%s\n' $trimmed
  fi
}

# bd_count_among <all_json> <wanted_status> <ids_newline_separated>
#   Count beads in the given ID list whose status matches.
#   Returns 0 on empty input.
bd_count_among() {
  local all_json="$1"
  local wanted_status="$2"
  local ids="$3"
  [[ -z "$ids" || -z "$all_json" ]] && { echo 0; return; }

  local ids_json
  ids_json=$(printf '%s\n' "$ids" | jq -R . | jq -cs 'map(select(length > 0))')

  jq -r --argjson all "$all_json" --argjson ids "$ids_json" --arg wanted "$wanted_status" '
    ($ids | map({(.): true}) | add // {}) as $set
    | [$all[] | select($set[.id] == true and .status == $wanted)] | length
  ' <<<'null'
}

#!/bin/bash

# ralph-beads — Codex installer
#
# Installs the Codex build of ralph-beads:
#   - Copies rendered Skills into ~/.agents/skills/
#     (Codex 0.122+ reads user-level skills from $HOME/.agents/skills/<name>/SKILL.md.
#      Custom prompts under ~/.codex/prompts/ are deprecated and ignored.)
#   - Registers the Stop hook in ~/.codex/hooks.json
#   - Ensures [features] codex_hooks = true in ~/.codex/config.toml
#
# Usage:
#   codex/install.sh              # install (default)
#   codex/install.sh uninstall    # remove skills + hook entry
#
# Re-run install after moving the plugin directory — absolute paths are baked in.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
HOOKS_FILE="$CODEX_DIR/hooks.json"
CONFIG_FILE="$CODEX_DIR/config.toml"

AGENTS_SKILLS_DIR="${AGENTS_SKILLS_HOME:-$HOME/.agents/skills}"

SKILL_NAMES=("ralph-beads" "cancel-ralph-beads")

MODE="${1:-install}"

render() {
  sed "s|{{PLUGIN_ROOT}}|${PLUGIN_ROOT}|g" "$1"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ ralph-beads: 'jq' is required (used by the Stop hook and this installer). Install jq and re-run." >&2
    exit 1
  fi
}

case "$MODE" in
  install|--install|-i)
    require_jq

    mkdir -p "$AGENTS_SKILLS_DIR"

    for name in "${SKILL_NAMES[@]}"; do
      src_dir="$PLUGIN_ROOT/codex/skills/$name"
      dest_dir="$AGENTS_SKILLS_DIR/$name"
      if [[ ! -d "$src_dir" ]]; then
        echo "❌ ralph-beads: missing source skill at $src_dir" >&2
        exit 1
      fi
      mkdir -p "$dest_dir"
      # Render SKILL.md with plugin-root substitution; copy any other files verbatim.
      for f in "$src_dir"/*; do
        fname="$(basename "$f")"
        if [[ "$fname" == "SKILL.md" ]]; then
          render "$f" > "$dest_dir/$fname"
        else
          cp -R "$f" "$dest_dir/"
        fi
      done
      echo "✓ installed skill: $dest_dir"
    done

    RENDERED_HOOK="$(render "$PLUGIN_ROOT/codex/hooks.json")"
    mkdir -p "$CODEX_DIR"

    if [[ -f "$HOOKS_FILE" ]]; then
      TMP="$(mktemp)"
      jq --argjson new "$RENDERED_HOOK" --arg root "$PLUGIN_ROOT" '
        .hooks = (.hooks // {})
        | .hooks.Stop = (.hooks.Stop // [])
        | .hooks.Stop |= map(
            select(
              ((.hooks // []) | all(
                (.command // "") | (contains("ralph-beads") or contains($root)) | not
              ))
            )
          )
        | .hooks.Stop = (.hooks.Stop + ($new.hooks.Stop // []))
      ' "$HOOKS_FILE" > "$TMP"
      mv "$TMP" "$HOOKS_FILE"
      echo "✓ merged Stop hook into $HOOKS_FILE"
    else
      printf '%s\n' "$RENDERED_HOOK" | jq '.' > "$HOOKS_FILE"
      echo "✓ wrote new $HOOKS_FILE"
    fi

    touch "$CONFIG_FILE"
    if grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*true' "$CONFIG_FILE"; then
      echo "✓ codex_hooks already enabled in $CONFIG_FILE"
    elif grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=' "$CONFIG_FILE"; then
      echo "⚠️  $CONFIG_FILE has codex_hooks set to a non-true value — leaving it alone. Set codex_hooks = true manually." >&2
    elif grep -Eq '^\[features\]' "$CONFIG_FILE"; then
      TMP="$(mktemp)"
      awk '
        BEGIN { injected = 0 }
        {
          print
          if (!injected && $0 ~ /^\[features\]/) {
            print "codex_hooks = true"
            injected = 1
          }
        }
      ' "$CONFIG_FILE" > "$TMP"
      mv "$TMP" "$CONFIG_FILE"
      echo "✓ added codex_hooks = true under existing [features] in $CONFIG_FILE"
    else
      printf '\n[features]\ncodex_hooks = true\n' >> "$CONFIG_FILE"
      echo "✓ appended [features] codex_hooks = true to $CONFIG_FILE"
    fi

    cat <<EOF

ralph-beads installed for Codex.

Plugin root:  $PLUGIN_ROOT
Skills dir:   $AGENTS_SKILLS_DIR

Next steps:
  1. Restart any active Codex sessions so skills and hooks pick up.
  2. cd into a beads-initialized repo (.beads/ must exist) with at least one
     open / in_progress / blocked bead.
  3. Start the loop by either:
        - typing \$ralph-beads in Codex and letting the model invoke the skill, or
        - using the /skills picker and selecting "ralph-beads", or
        - simply asking "run ralph-beads" (the skill description will trigger).
     Pass guidance, --max-iterations N, and optional --parallel N inline, e.g.
        "\$ralph-beads prefer P0 first --max-iterations 25"
        "\$ralph-beads --parallel 4 prefer independent docs/tests first"
  4. Cancel mid-loop with \$cancel-ralph-beads, or rm .claude/ralph-beads.local.md.

To uninstall: $0 uninstall
EOF
    ;;

  uninstall|--uninstall|-u)
    for name in "${SKILL_NAMES[@]}"; do
      dest_dir="$AGENTS_SKILLS_DIR/$name"
      if [[ -d "$dest_dir" ]]; then
        rm -rf "$dest_dir"
        echo "✓ removed skill: $dest_dir"
      fi
    done

    if [[ -f "$HOOKS_FILE" ]]; then
      require_jq
      TMP="$(mktemp)"
      jq --arg root "$PLUGIN_ROOT" '
        if .hooks.Stop then
          .hooks.Stop |= map(
            select(
              ((.hooks // []) | all(
                (.command // "") | (contains("ralph-beads") or contains($root)) | not
              ))
            )
          )
        else . end
      ' "$HOOKS_FILE" > "$TMP"
      mv "$TMP" "$HOOKS_FILE"
      echo "✓ stripped ralph-beads Stop hook from $HOOKS_FILE"
    fi

    echo ""
    echo "Uninstalled ralph-beads from Codex. [features] codex_hooks left as-is (other hooks may need it)."
    ;;

  *)
    echo "Usage: $0 [install|uninstall]" >&2
    exit 1
    ;;
esac

---
description: "Cancel the active ralph-beads loop"
allowed-tools: ["Bash(test -f .claude/ralph-beads.local.md:*)", "Bash(rm .claude/ralph-beads.local.md)", "Read(.claude/ralph-beads.local.md)"]
hide-from-slash-command-tool: "true"
---

# Cancel ralph-beads

1. Check if the state file exists with Bash: `test -f .claude/ralph-beads.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: reply "No active ralph-beads loop found."

3. **If EXISTS**:
   - Read `.claude/ralph-beads.local.md` and grab the `iteration:` value from the frontmatter.
   - Remove the file with Bash: `rm .claude/ralph-beads.local.md`
   - Report: `Cancelled ralph-beads loop (was at iteration N)` where N is the iteration value.

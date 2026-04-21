---
name: cancel-ralph-beads
description: >
  Cancel an active ralph-beads loop by deleting its state file. Use when the user
  says "cancel ralph-beads", "stop the beads loop", "end ralph", or similar while
  a ralph-beads loop is running. After cancellation, the next Stop hook firing
  sees no state file and exits cleanly, ending the loop.
tags: [automation, loop, beads, ralph]
---

# Cancel ralph-beads

1. Check whether the state file exists via the shell:
   ```bash
   test -f .claude/ralph-beads.local.md && echo EXISTS || echo NOT_FOUND
   ```
2. If `NOT_FOUND`: reply `No active ralph-beads loop found.` and stop.
3. If `EXISTS`:
   - Read `.claude/ralph-beads.local.md` and extract the `iteration:` value from the frontmatter (first `iteration: N` line).
   - Delete the file: `rm .claude/ralph-beads.local.md`.
   - Report: `Cancelled ralph-beads loop (was at iteration N).`

---
name: ghostbuster
description: >
  Detect and clean ghost teams, orphaned tasks, and numbered agent duplicates
  from ~/.claude/teams/ and ~/.claude/tasks/. Use when the user asks about
  cleaning up teams, finding ghosts, checking for stale agents, or maintaining
  their Agent Teams setup.
---

# ghostbuster

Detect and clean ghost teams from Claude Code Agent Teams.

## Commands

### scan (default)

Run the scanner and display a formatted report:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/ghost-scan.sh"
```

Parse the JSON output and display a human-readable report:

- Show ghost teams with reasons and members
- Show orphan task directories
- Show active teams (untouched)
- Show summary counts

Format example:
```
👻 ghostbuster scan

🔍 Scanning ~/.claude/teams/ and ~/.claude/tasks/...

⚠️  N ghosts found:

  🪦 Team: old-project
     Reason: backup remnant, no active session
     Members: researcher, builder, worker-2

  🗂️  Orphan tasks: N directories with no matching team

✅ Active teams (untouched):
  my-team — researcher (1 member, clean)

Run /ghostbuster clean to remove ghosts.
```

If no ghosts found:
```
👻 ghostbuster scan

✅ All clean! No ghosts found.
  Active teams: my-team, my-other-team
```

### clean

1. Run scan first
2. If ghosts found, show the report and ask the user for confirmation using AskUserQuestion
3. On confirmation, delete ghost team directories and orphan task directories:
   - Use `/usr/bin/find <path> -type f -delete` then `/usr/bin/find <path> -type d -empty -delete` for each path
   - Report each deletion
4. Run scan again to confirm cleanup

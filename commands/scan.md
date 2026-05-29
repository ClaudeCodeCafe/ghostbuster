---
description: Scan for ghost teams and orphaned tasks
allowed-tools: Bash, Read, AskUserQuestion
---

# /ghostbuster:scan

Run the ghost scanner and display results.

## Steps

1. Run the scanner:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/ghost-scan.sh"
```

2. Parse the JSON output and display a formatted report showing ghost teams, orphan tasks, and active teams.

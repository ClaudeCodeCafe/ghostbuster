---
description: Scan and clean ghost teams and orphaned tasks
allowed-tools: Bash, Read, AskUserQuestion
---

# /ghostbuster:clean

Scan for ghosts and clean them up after user confirmation.

## Steps

1. Run the scanner:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/ghost-scan.sh"
```

2. Parse the JSON output. If no ghosts found, report "All clean!" and stop.

3. Display the ghost report (same format as scan).

4. Ask the user for confirmation using AskUserQuestion:
   - "Delete N ghost teams and M orphan task directories?"
   - Options: "Yes, clean them up" / "No, keep them"

5. If confirmed, for each ghost team and orphan task directory:
```bash
/usr/bin/find <path> -type f -delete && /usr/bin/find <path> -type d -empty -delete
```
   Report each deletion.

6. Run the scanner again to verify cleanup. Display the clean report.

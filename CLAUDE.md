# ghostbuster

Claude Code plugin to detect and clean ghost teams from Agent Teams.

## Development

- `bin/ghost-scan.sh` — scanner script (JSON output)
- `skills/ghostbuster/SKILL.md` — skill definition
- `commands/` — slash commands (scan, clean)

## Testing

```bash
# Run scanner directly
./bin/ghost-scan.sh | python3 -m json.tool

# Install as plugin
claude plugin add /path/to/ghostbuster
```

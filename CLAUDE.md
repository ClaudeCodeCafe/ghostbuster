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

# Install as plugin (from the ClaudeCodeCafe marketplace)
/plugin marketplace add ClaudeCodeCafe/ghostbuster
/plugin install ghostbuster@ghostbuster
```

## Version sync

Keep `version` consistent across `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (`metadata.version` + `plugins[0].version`).
The release workflow bumps both automatically on `v*` tag push.

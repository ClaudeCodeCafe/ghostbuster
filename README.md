# ghostbuster

Detect and clean ghost teams, orphaned tasks, and numbered agent duplicates from Claude Code Agent Teams.

## What it detects

- **Ghost teams** — team configs with no active Claude session
- **Numbered ghosts** — duplicated agents like `researcher-2`, `worker-3`
- **Dead tmux panes** — tmux-backed agents whose panes no longer exist
- **Orphan tasks** — task directories with no matching team
- **Backup remnants** — `.backup.*` directories

## Install

```bash
claude plugin add /path/to/ghostbuster
```

## Usage

```
/ghostbuster scan    # detect ghosts (read-only)
/ghostbuster clean   # detect + delete after confirmation
```

## License

MIT

#!/usr/bin/env bash
# ghost-scan.sh — Scan ~/.claude/teams/ and ~/.claude/tasks/ for ghost teams and orphan tasks.
# Outputs a JSON report to stdout. Uses python3 for all JSON operations (no jq dependency).
# Uses /usr/bin/find to avoid RTK hook interception.

set -euo pipefail

TEAMS_DIR="${HOME}/.claude/teams"
TASKS_DIR="${HOME}/.claude/tasks"
SESSIONS_DIR="${HOME}/.claude/sessions"

# Check if tmux is available and running
tmux_running="false"
tmux_panes=""
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux_running="true"
  tmux_panes="$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true)"
fi

export TMUX_PANES="$tmux_panes"

# Pass everything to python3 for analysis and JSON output
python3 - "$TEAMS_DIR" "$TASKS_DIR" "$tmux_running" "$SESSIONS_DIR" <<'PYEOF'
import sys
import os
import json
import re
teams_dir = sys.argv[1]
tasks_dir = sys.argv[2]
tmux_running = sys.argv[3] == "true"
sessions_dir = sys.argv[4]

tmux_panes_raw = os.environ.get("TMUX_PANES", "")
tmux_panes = set(tmux_panes_raw.strip().split("\n")) if tmux_panes_raw.strip() else set()

# Build session registry from ~/.claude/sessions/<PID>.json
# Each file: { pid, sessionId, cwd, startedAt, ... }
live_sessions = []  # list of dicts with pid, sessionId, cwd, startedAt

if os.path.isdir(sessions_dir):
    for fname in os.listdir(sessions_dir):
        if not fname.endswith(".json"):
            continue
        fpath = os.path.join(sessions_dir, fname)
        try:
            with open(fpath, "r") as f:
                sess = json.load(f)
        except (json.JSONDecodeError, IOError):
            continue

        pid = sess.get("pid")
        if pid is None:
            continue

        # Check if PID is alive
        try:
            os.kill(pid, 0)
        except (ProcessLookupError, PermissionError):
            # ProcessLookupError = dead, PermissionError = alive but no permission (still alive)
            if isinstance(sys.exc_info()[1], ProcessLookupError):
                continue
        except OSError:
            continue

        live_sessions.append({
            "pid": pid,
            "sessionId": sess.get("sessionId", ""),
            "cwd": sess.get("cwd", ""),
            "startedAt": sess.get("startedAt", 0),
        })


def find_matching_session(team_config):
    """Check if a team has a live session by matching cwd + createdAt≈startedAt (within 5s)."""
    created_at = team_config.get("createdAt", 0)
    members = team_config.get("members", [])
    if isinstance(members, dict):
        members = list(members.values())

    team_cwds = set()
    for m in members:
        if isinstance(m, dict) and m.get("cwd"):
            team_cwds.add(m["cwd"])

    for sess in live_sessions:
        if sess["cwd"] not in team_cwds:
            continue
        time_diff = abs(sess["startedAt"] - created_at)
        if time_diff <= 5000:  # 5 seconds in ms
            return sess
    return None


def extract_repo(cwd):
    """Extract repo name from cwd path (last path component)."""
    if not cwd:
        return ""
    return os.path.basename(cwd.rstrip("/"))


def get_team_cwd(config):
    """Get the primary cwd from team config (first member's cwd)."""
    members = config.get("members", [])
    if isinstance(members, dict):
        members = list(members.values())
    for m in members:
        if isinstance(m, dict) and m.get("cwd"):
            return m["cwd"]
    return ""


ghost_teams = []
active_teams = []

# Scan teams
if os.path.isdir(teams_dir):
    for entry in sorted(os.listdir(teams_dir)):
        team_path = os.path.join(teams_dir, entry)
        if not os.path.isdir(team_path):
            continue
        if entry in (".DS_Store", ".backup"):
            continue

        config_path = os.path.join(team_path, "config.json")
        if not os.path.isfile(config_path):
            ghost_teams.append({
                "name": entry,
                "path": team_path,
                "repo": "",
                "cwd": "",
                "reasons": ["no config.json"],
                "numbered_ghosts": [],
                "members": []
            })
            continue

        try:
            with open(config_path, "r") as f:
                config = json.load(f)
        except (json.JSONDecodeError, IOError):
            ghost_teams.append({
                "name": entry,
                "path": team_path,
                "repo": "",
                "cwd": "",
                "reasons": ["corrupt config.json"],
                "numbered_ghosts": [],
                "members": []
            })
            continue

        reasons = []
        numbered_ghosts = []
        member_names = []

        team_cwd = get_team_cwd(config)
        team_repo = extract_repo(team_cwd)

        # Check for backup remnant
        if ".backup." in entry:
            reasons.append("backup remnant")

        # Check session liveness via session registry
        matched_session = find_matching_session(config)
        if matched_session is None:
            reasons.append("no active session")

        # Check members
        members = config.get("members", [])
        if isinstance(members, dict):
            members = list(members.values())

        dead_tmux_count = 0
        for member in members:
            name = ""
            if isinstance(member, dict):
                name = member.get("name", member.get("agentName", ""))
            elif isinstance(member, str):
                name = member

            if name:
                member_names.append(name)

                if re.match(r'^.+-\d+$', name):
                    numbered_ghosts.append(name)

                if isinstance(member, dict):
                    backend = member.get("backendType", "")
                    pane_id = member.get("paneId", member.get("tmuxPaneId", ""))
                    if backend == "tmux":
                        if not tmux_running:
                            dead_tmux_count += 1
                        elif pane_id and pane_id not in tmux_panes:
                            dead_tmux_count += 1

        if dead_tmux_count > 0:
            reasons.append(f"dead tmux panes ({dead_tmux_count})")

        if numbered_ghosts and "numbered ghost agents" not in reasons:
            reasons.append("numbered ghost agents")

        if reasons:
            ghost_teams.append({
                "name": entry,
                "path": team_path,
                "repo": team_repo,
                "cwd": team_cwd,
                "reasons": reasons,
                "numbered_ghosts": numbered_ghosts,
                "members": member_names
            })
        else:
            active_teams.append({
                "name": entry,
                "repo": team_repo,
                "cwd": team_cwd,
                "members": member_names,
                "member_count": len(member_names)
            })

# Scan tasks for orphans
orphan_tasks = []

if os.path.isdir(tasks_dir):
    for entry in sorted(os.listdir(tasks_dir)):
        task_path = os.path.join(tasks_dir, entry)
        if not os.path.isdir(task_path):
            continue
        if entry in (".DS_Store",):
            continue

        is_orphan = True
        if os.path.isdir(teams_dir):
            for team_entry in os.listdir(teams_dir):
                team_config = os.path.join(teams_dir, team_entry, "config.json")
                if os.path.isfile(team_config):
                    try:
                        with open(team_config, "r") as f:
                            content = f.read()
                            if entry in content:
                                is_orphan = False
                                break
                    except IOError:
                        pass

        if is_orphan:
            orphan_tasks.append({
                "name": entry,
                "path": task_path
            })

report = {
    "ghost_teams": ghost_teams,
    "orphan_tasks": orphan_tasks,
    "active_teams": active_teams,
    "summary": {
        "ghost_teams": len(ghost_teams),
        "orphan_tasks": len(orphan_tasks),
        "active_teams": len(active_teams)
    }
}

print(json.dumps(report, indent=2, ensure_ascii=False))
PYEOF

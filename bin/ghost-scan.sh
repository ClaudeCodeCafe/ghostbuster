#!/usr/bin/env bash
# ghost-scan.sh — Scan ~/.claude/teams/ and ~/.claude/tasks/ for ghost teams and orphan tasks.
# Outputs a JSON report to stdout. Uses python3 for all JSON operations (no jq dependency).
#
# Session liveness detection:
#   Uses ~/.claude/sessions/<PID>.json as the source of truth.
#   Matches teams to sessions by cwd + createdAt≈startedAt (within 5s).
#   This correctly handles in-process backends where UUIDs don't appear in ps.

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

# ---------------------------------------------------------------------------
# Build the list of alive sessions from ~/.claude/sessions/*.json
# Each file is named <PID>.json: { pid, sessionId, cwd, startedAt, ... }
# A session is alive if its PID is still running (kill -0).
# ---------------------------------------------------------------------------
alive_sessions = []  # list of { cwd, startedAt }

if os.path.isdir(sessions_dir):
    for fname in os.listdir(sessions_dir):
        if not fname.endswith(".json"):
            continue
        fpath = os.path.join(sessions_dir, fname)
        try:
            with open(fpath, "r") as f:
                sess = json.load(f)
            pid = sess.get("pid")
            cwd = sess.get("cwd", "")
            started_at = sess.get("startedAt", 0)
            if pid and cwd:
                try:
                    os.kill(pid, 0)
                    alive_sessions.append({"cwd": cwd, "startedAt": started_at})
                except (OSError, ProcessLookupError):
                    pass
        except (json.JSONDecodeError, IOError, KeyError):
            pass

# Max allowed gap between team createdAt and session startedAt (ms)
TIMESTAMP_TOLERANCE = 5000

def team_has_alive_session(team_config):
    """Check if a team matches any alive session by cwd + createdAt≈startedAt."""
    members = team_config.get("members", [])
    if isinstance(members, dict):
        members = list(members.values())

    team_cwds = set()
    for member in members:
        if isinstance(member, dict):
            cwd = member.get("cwd", "")
            if cwd:
                team_cwds.add(cwd)

    created_at = team_config.get("createdAt", 0)

    for sess in alive_sessions:
        if sess["cwd"] in team_cwds:
            diff = abs(sess["startedAt"] - created_at)
            if diff <= TIMESTAMP_TOLERANCE:
                return True
    return False

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
                "reasons": ["corrupt config.json"],
                "numbered_ghosts": [],
                "members": []
            })
            continue

        reasons = []
        numbered_ghosts = []
        member_names = []

        # Check for backup remnant
        if ".backup." in entry:
            reasons.append("backup remnant")

        # Session liveness: cwd + createdAt≈startedAt
        if not team_has_alive_session(config):
            lead_session = config.get("leadSessionId", "")
            if lead_session:
                reasons.append("no active session")
            else:
                reasons.append("no leadSessionId")

        # Check members for ghosts and dead tmux panes
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

                # Check for numbered ghost pattern (name-N where N is a number)
                if re.match(r'^.+-\d+$', name):
                    numbered_ghosts.append(name)

                # Check tmux backend with dead pane
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

        # Extract repo name from member cwds
        team_cwd = ""
        for member in members:
            if isinstance(member, dict) and member.get("cwd"):
                team_cwd = member["cwd"]
                break
        repo_name = os.path.basename(team_cwd) if team_cwd else ""

        if reasons:
            ghost_teams.append({
                "name": entry,
                "path": team_path,
                "repo": repo_name,
                "cwd": team_cwd,
                "reasons": reasons,
                "numbered_ghosts": numbered_ghosts,
                "members": member_names
            })
        else:
            active_teams.append({
                "name": entry,
                "repo": repo_name,
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

        # A task is orphaned if no team config references it
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

#!/usr/bin/env python3
import os
import subprocess
from pathlib import Path

# Configuration
BASE_DIR = "/Users/devanshwalia/Desktop/work/hli"
GROUP_SIZE = 4  # number of panes per tab
APP_NAMES = ["iTerm2", "iTerm"]  # Try iTerm2 first, then fallback to iTerm


def find_git_repos(base_dir: str):
    base = Path(base_dir)
    if not base.exists():
        return []
    repos = []
    for child in sorted(base.iterdir()):
        git_path = str(child / ".git")
        git_exists = os.path.exists(git_path) and os.path.isdir(git_path)
        is_helm_charts = "helm-charts" in child.name
        if child.is_dir() and git_exists and not is_helm_charts:
            repos.append(str(child))
    return repos


def chunk(lst, size):
    for i in range(0, len(lst), size):
        yield lst[i:i + size]


def applescript_for_group(group, first_tab_in_new_window: bool):
    # Build AppleScript that creates a new tab (first group makes a new window)
    # and splits into up to 4 panes, each cd'ing into the repo directory.
    lines = []
    lines.append("tell application \"iTerm2\"")
    lines.append("  activate")
    if first_tab_in_new_window:
        lines.append("  if (count of windows) is 0 then")
        lines.append("    create window with default profile")
        lines.append("  else")
        lines.append("    create window with default profile")
        lines.append("  end if")
    else:
        lines.append("  if (count of windows) is 0 then")
        lines.append("    create window with default profile")
        lines.append("  else")
        lines.append("    tell current window to create tab with default profile")
        lines.append("  end if")
    lines.append("  set currentWindow to current window")
    lines.append("  set currentTab to current tab of currentWindow")
    lines.append("  set currentSession to current session of currentTab")

    # Write first command
    if len(group) >= 1:
        repo = group[0]
        lines.append(f'  tell currentSession to write text "cd {repo} && clear"')

    # Create additional panes depending on group size
    if len(group) >= 2:
        repo = group[1]
        lines.append("  tell currentSession to split horizontally with default profile")
        lines.append("  set session2 to last session of currentTab")
        lines.append(f'  tell session2 to write text "cd {repo} && clear"')
    if len(group) >= 3:
        repo = group[2]
        lines.append("  tell currentSession to split vertically with default profile")
        lines.append("  set session3 to last session of currentTab")
        lines.append(f'  tell session3 to write text "cd {repo} && clear"')
    if len(group) >= 4:
        repo = group[3]
        lines.append("  tell session2 to split vertically with default profile")
        lines.append("  set session4 to last session of currentTab")
        lines.append(f'  tell session4 to write text "cd {repo} && clear"')

    lines.append("end tell")

    return "\n".join(lines)


def open_repos_in_iterm(repos):
    first = True
    for grp in chunk(repos, GROUP_SIZE):
        script = applescript_for_group(grp, first_tab_in_new_window=first)
        first = False
        subprocess.run(["osascript", "-e", script], check=True)


def main():
    repos = find_git_repos(BASE_DIR)
    print(f"Found {len(repos)} repositories")
    if repos:
        print("Repositories:", [os.path.basename(repo) for repo in repos])
    if not repos:
        print(f"No Git repositories found in {BASE_DIR}")
        return
    open_repos_in_iterm(repos)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
PreToolUse hook — GDPR pre-commit guard.

Fires before any Bash tool call. If the command is a git commit, checks
whether any staged files are from data/raw/ or data/processed/ and blocks
the commit if so.
"""

import json
import sys
import subprocess

data = json.load(sys.stdin)
command = data.get("tool_input", {}).get("command", "")

# Only care about git commit commands
if "git" not in command or "commit" not in command:
    sys.exit(0)

cwd = data.get("cwd", ".")

result = subprocess.run(
    ["git", "diff", "--cached", "--name-only"],
    capture_output=True,
    text=True,
    cwd=cwd,
)

staged = [f for f in result.stdout.strip().split("\n") if f]
protected_files = {"data/analysis_ready.csv", "data/segment_summary.csv", "data/validity_summary.csv"}
forbidden = [
    f for f in staged
    if "data/raw/" in f or "data/processed/" in f or f in protected_files
]

if forbidden:
    print("", file=sys.stderr)
    print("GDPR GUARD — commit blocked.", file=sys.stderr)
    print("The following files contain participant data and must not be committed:", file=sys.stderr)
    for f in forbidden:
        print(f"  {f}", file=sys.stderr)
    print("", file=sys.stderr)
    print("To unstage:  git restore --staged <file>", file=sys.stderr)
    print("To verify:   git diff --cached --name-only", file=sys.stderr)
    sys.exit(2)

sys.exit(0)

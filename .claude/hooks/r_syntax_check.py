#!/usr/bin/env python3
"""
PostToolUse hook — R syntax check.

Fires after any Write or Edit tool call. If the edited file ends in .R,
runs Rscript to parse it and reports any syntax errors so Claude can fix
them immediately rather than discovering them mid-pipeline-run.
"""

import json
import sys
import subprocess

data = json.load(sys.stdin)
file_path = data.get("tool_input", {}).get("file_path", "")

if not file_path.endswith(".R"):
    sys.exit(0)

result = subprocess.run(
    ["Rscript", "--vanilla", "-e", f"parse(file = '{file_path}')"],
    capture_output=True,
    text=True,
)

if result.returncode != 0:
    print(f"\nR syntax error in {file_path}:", file=sys.stderr)
    # R parse errors go to stderr
    print(result.stderr.strip(), file=sys.stderr)
    sys.exit(2)
else:
    print(f"\nR syntax OK: {file_path}", file=sys.stderr)

sys.exit(0)

#!/usr/bin/env python3
"""
PostToolUse hook — config.yaml guard.

Fires after any Write or Edit tool call. If the edited file is config.yaml,
validates YAML syntax and checks for common issues: missing sections, fallback
schedules, unset cut-points.

Uses Rscript + yaml package for parsing (guaranteed installed for this project).
Falls back to a basic check if R is not available.
"""

import json
import sys
import subprocess

data = json.load(sys.stdin)
file_path = data.get("tool_input", {}).get("file_path", "")

if not file_path.endswith("config.yaml"):
    sys.exit(0)

# ── Step 1: YAML syntax via R (yaml package is in renv) ───────────────────────
r_check = subprocess.run(
    [
        "Rscript", "--vanilla", "-e",
        f"tryCatch("
        f"  yaml::read_yaml('{file_path}'),"
        f"  error = function(e) {{ cat('YAML ERROR:', conditionMessage(e), '\\n'); quit(status = 1) }}"
        f")",
    ],
    capture_output=True,
    text=True,
)

if r_check.returncode != 0:
    print(f"\nconfig.yaml — YAML syntax error:", file=sys.stderr)
    print(r_check.stdout.strip(), file=sys.stderr)
    sys.exit(2)

# ── Step 2: Extended validation via Python (optional, best-effort) ─────────────
try:
    import yaml

    with open(file_path) as f:
        cfg = yaml.safe_load(f)

    warnings = []

    required = ["paths", "ggir", "validity", "measurements", "schedules", "output"]
    missing = [k for k in required if k not in cfg]
    if missing:
        warnings.append(f"Missing required sections: {', '.join(missing)}")

    schedules = cfg.get("schedules", {})
    fallbacks = [s for s, v in schedules.items() if isinstance(v, dict) and v.get("fallback")]
    if fallbacks:
        warnings.append(f"Fallback (unconfirmed) schedules: {', '.join(fallbacks)}")

    if not cfg.get("ggir", {}).get("cut_points_mg"):
        warnings.append("Cut-points not yet set — activity classification will be incomplete")

    if warnings:
        print("\nconfig.yaml — saved with warnings:", file=sys.stderr)
        for w in warnings:
            print(f"  ⚠  {w}", file=sys.stderr)
    else:
        print("\nconfig.yaml — OK", file=sys.stderr)

except ImportError:
    # PyYAML not installed — syntax already confirmed by R above
    print("\nconfig.yaml — syntax OK", file=sys.stderr)

sys.exit(0)

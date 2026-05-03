#!/usr/bin/env python3
"""
PostToolUse hook — config.yaml guard.

Fires after any Write or Edit tool call. If the edited file is config.yaml,
validates YAML syntax and checks for common issues: missing sections, fallback
schedules, unset cut-points.

Uses PyYAML for syntax checking. Falls back silently if PyYAML is not available.
"""

import json
import sys

data = json.load(sys.stdin)
file_path = data.get("tool_input", {}).get("file_path", "")

if not file_path.endswith("config.yaml"):
    sys.exit(0)

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

except yaml.YAMLError as e:
    print(f"\nconfig.yaml — YAML syntax error:\n  {e}", file=sys.stderr)
    sys.exit(2)

except ImportError:
    # PyYAML not installed — skip validation
    print("\nconfig.yaml — saved (PyYAML not available, skipping validation)", file=sys.stderr)

sys.exit(0)

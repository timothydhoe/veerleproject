"""
SchoolMoves Pipeline — Single Entry-Point
==========================================
Adjust the parameters below, then run:
    python run_pipeline.py

Or from an IDE: just press "Run All".

This script:
  1. Loads configuration from YAML files
  2. Runs the R pipeline via subprocess (convert -> process -> classify -> label -> validate -> export)
  3. Runs the Python attendance prediction on the processed output
  4. Writes a final summary to logs/pipeline_summary.txt
"""

# ============================================================
# PARAMETERS — Edit these before running
# ============================================================
INPUT_DIR   = "../data/example/"                    # Path to raw .bin or .csv files
OUTPUT_DIR  = "data/processed/"                     # Where to write results
CONFIG_DIR  = "config/"                             # Contains pipeline_params.yaml and school_schedules.yaml
R_PIPELINE  = "R/pipeline/run_pipeline.R"           # Path to the R master script

# Override specific parameters (leave None to use YAML defaults)
OVERRIDES = {
    # "threshold_lig": 50.0,      # Uncomment to override ENMO cut-points
    # "threshold_mod": 200.0,
    # "min_valid_days_waking": 3,
}
# ============================================================

import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import yaml


def main():
    print("=" * 60)
    print("SchoolMoves Pipeline")
    print("=" * 60)

    # Resolve paths relative to this script's location
    script_dir = Path(__file__).parent
    os.chdir(script_dir)

    config_path = Path(CONFIG_DIR) / "pipeline_params.yaml"
    schedule_path = Path(CONFIG_DIR) / "school_schedules.yaml"

    # --- 1. Load and optionally override config ---
    print(f"\n[1/7] Loading config from {config_path}")
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path.resolve()}")
        print("  Make sure CONFIG_DIR points to the directory with pipeline_params.yaml")
        sys.exit(1)

    with open(config_path) as f:
        params = yaml.safe_load(f)

    # --- 2. Apply overrides ---
    active_overrides = {k: v for k, v in OVERRIDES.items() if v is not None}
    if active_overrides:
        print(f"[2/7] Applying {len(active_overrides)} parameter overrides:")
        for k, v in active_overrides.items():
            print(f"  {k}: {params.get(k, '(new)')} -> {v}")
            params[k] = v

        # Write a temporary config with overrides
        tmp_config = tempfile.NamedTemporaryFile(
            mode="w", suffix=".yaml", delete=False, dir=str(script_dir)
        )
        yaml.dump(params, tmp_config, default_flow_style=False)
        tmp_config.close()
        config_for_r = tmp_config.name
        print(f"  Temporary config: {tmp_config.name}")
    else:
        print("[2/7] No overrides — using YAML defaults")
        config_for_r = str(config_path)

    # --- 3. Run the R pipeline ---
    print(f"\n[3/7] Running R pipeline: {R_PIPELINE}")
    print(f"  Input:  {INPUT_DIR}")
    print(f"  Output: {OUTPUT_DIR}")

    r_cmd = [
        "Rscript", R_PIPELINE,
        "--input", INPUT_DIR,
        "--output", OUTPUT_DIR,
        "--config", config_for_r,
        "--schedule", str(schedule_path),
    ]

    try:
        result = subprocess.run(
            r_cmd,
            capture_output=True,
            text=True,
            timeout=3600,  # 1 hour timeout
        )
    except FileNotFoundError:
        print("\nERROR: 'Rscript' not found on your system.")
        print("  Make sure R is installed and Rscript is on your PATH.")
        print("  On Windows: check that R\\bin is in your system PATH.")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("\nERROR: R pipeline timed out after 1 hour.")
        print("  This may indicate the input data is too large or there's an infinite loop.")
        sys.exit(1)

    # Print R output (messages go to stderr in R)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)

    # --- 4. Check R exit code ---
    if result.returncode != 0:
        print("\n" + "=" * 60)
        print("ERROR: R pipeline failed!")
        print("=" * 60)
        print("\nWhat went wrong:")
        if "cannot open the connection" in (result.stderr or ""):
            print("  A file could not be found or opened.")
            print(f"  Check that INPUT_DIR exists: {Path(INPUT_DIR).resolve()}")
        elif "there is no package called" in (result.stderr or ""):
            pkg = (result.stderr or "").split("there is no package called")[1].split("'")[1]
            print(f"  Missing R package: {pkg}")
            print(f"  Install it with: install.packages('{pkg}')")
        else:
            print("  See the error output above for details.")
        print(f"\nFull R stderr saved to: logs/r_pipeline_error.log")
        log_dir = Path("logs")
        log_dir.mkdir(exist_ok=True)
        (log_dir / "r_pipeline_error.log").write_text(result.stderr or "")
        sys.exit(1)

    print("\n[4/7] R pipeline completed successfully")

    # Clean up temporary config
    if active_overrides and os.path.exists(config_for_r):
        os.unlink(config_for_r)

    # --- 5. Load processed output ---
    print(f"\n[5/7] Loading processed data from {OUTPUT_DIR}")
    output_path = Path(OUTPUT_DIR)
    data_files = list(output_path.glob("*.csv")) + list(output_path.glob("*.parquet"))

    if not data_files:
        print(f"  WARNING: No processed files found in {output_path.resolve()}")
        print("  The R pipeline may not have exported any data.")
        _write_summary(params, 0, 0, [])
        return

    # Import here to avoid errors if pandas is not installed
    import pandas as pd

    all_data = []
    for f in data_files:
        if f.name.startswith("validity_report"):
            continue
        try:
            if f.suffix == ".parquet":
                df = pd.read_parquet(f)
            else:
                df = pd.read_csv(f)
            all_data.append(df)
        except Exception as e:
            print(f"  WARNING: Could not read {f.name}: {e}")

    if not all_data:
        print("  No pupil data files could be loaded.")
        _write_summary(params, 0, 0, [])
        return

    combined = pd.concat(all_data, ignore_index=True)
    n_pupils = combined["pupil_id"].nunique() if "pupil_id" in combined.columns else 0
    print(f"  Loaded {len(combined)} epochs for {n_pupils} pupils")

    # --- 6. Run Python attendance analysis ---
    print("\n[6/7] Running attendance prediction")
    attendance_results = _run_attendance(combined, params, schedule_path)

    # --- 7. Write final summary ---
    print("\n[7/7] Writing pipeline summary")
    _write_summary(params, n_pupils, len(combined), attendance_results)

    print("\n" + "=" * 60)
    print("Pipeline complete!")
    print("=" * 60)
    print(f"  Processed data: {output_path.resolve()}")
    print(f"  Summary:        {Path('logs/pipeline_summary.txt').resolve()}")
    if attendance_results:
        print(f"  Attendance:     {Path(OUTPUT_DIR, 'attendance_predictions.csv').resolve()}")


def _run_attendance(combined, params, schedule_path):
    """Run attendance prediction on all pupils."""
    try:
        from python.analysis.attendance_prediction import predict_attendance
        from python.analysis.utils import load_schedule_config
    except ImportError:
        # Try relative import if running from project_1/
        sys.path.insert(0, str(Path(__file__).parent))
        from python.analysis.attendance_prediction import predict_attendance
        from python.analysis.utils import load_schedule_config

    schedule_config = load_schedule_config(str(schedule_path))

    if "pupil_id" not in combined.columns or "enmo_mg" not in combined.columns:
        print("  Skipping attendance prediction: required columns not found")
        return []

    if "timestamp" in combined.columns:
        import pandas as pd
        combined["timestamp"] = pd.to_datetime(combined["timestamp"])

    all_attendance = []
    for pid in combined["pupil_id"].unique():
        pupil_df = combined[combined["pupil_id"] == pid].copy()
        # Derive school_id from first digit of pupil_id
        try:
            school_id = int(str(pid)[0])
        except (ValueError, IndexError):
            continue

        try:
            result = predict_attendance(pupil_df, school_id, schedule_config, params)
            if not result.empty:
                all_attendance.append(result)
        except Exception as e:
            print(f"  WARNING: Attendance prediction failed for pupil {pid}: {e}")

    if all_attendance:
        import pandas as pd
        attendance_df = pd.concat(all_attendance, ignore_index=True)
        out_path = Path(OUTPUT_DIR) / "attendance_predictions.csv"
        attendance_df.to_csv(out_path, index=False)
        print(f"  Attendance predictions: {len(attendance_df)} school-days assessed")
        return all_attendance

    print("  No attendance predictions generated")
    return []


def _write_summary(params, n_pupils, n_epochs, attendance_results):
    """Write pipeline summary to logs/pipeline_summary.txt."""
    log_dir = Path("logs")
    log_dir.mkdir(exist_ok=True)
    summary_path = log_dir / "pipeline_summary.txt"

    n_attendance = sum(len(r) for r in attendance_results) if attendance_results else 0

    lines = [
        "SchoolMoves Pipeline — Run Summary",
        "=" * 50,
        f"Timestamp:     {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"Input:         {INPUT_DIR}",
        f"Output:        {OUTPUT_DIR}",
        f"Pupils:        {n_pupils}",
        f"Total epochs:  {n_epochs}",
        f"Attendance predictions: {n_attendance} school-days",
        "",
        "Parameters used:",
    ]

    for key in ["threshold_lig", "threshold_mod", "threshold_vig",
                "min_valid_days_waking", "min_valid_hours_per_day",
                "output_format"]:
        val = params.get(key, "N/A")
        lines.append(f"  {key}: {val}")

    overrides = {k: v for k, v in OVERRIDES.items() if v is not None}
    if overrides:
        lines.append("")
        lines.append("Overrides applied:")
        for k, v in overrides.items():
            lines.append(f"  {k}: {v}")

    summary_path.write_text("\n".join(lines))
    print(f"  Summary written to {summary_path}")


if __name__ == "__main__":
    main()

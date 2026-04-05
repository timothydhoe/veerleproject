"""
SchoolMoves — Python Analysis Utilities
========================================
Shared functions for loading processed data and config files.
"""

from pathlib import Path

import pandas as pd
import yaml


def load_pupil_data(path: str) -> pd.DataFrame:
    """Load a single pupil's processed file (CSV or parquet).

    Parameters
    ----------
    path : str
        Path to the pupil's data file (.csv or .parquet).

    Returns
    -------
    pd.DataFrame
        Epoch-level data for one pupil.
    """
    path = Path(path)
    if path.suffix == ".parquet":
        return pd.read_parquet(path)
    return pd.read_csv(path, parse_dates=["timestamp"])


def load_all_pupils(processed_dir: str, school_id: int | None = None) -> pd.DataFrame:
    """Load all processed pupil files from a directory.

    Parameters
    ----------
    processed_dir : str
        Path to directory containing per-pupil CSV/parquet files.
    school_id : int, optional
        If given, only load pupils from this school (first digit of pupil_id).

    Returns
    -------
    pd.DataFrame
        Combined epoch data for all (filtered) pupils.
    """
    proc_path = Path(processed_dir)
    files = list(proc_path.glob("*.csv")) + list(proc_path.glob("*.parquet"))

    if not files:
        raise FileNotFoundError(f"No data files found in: {processed_dir}")

    frames = []
    for f in files:
        # Filter by school_id if requested
        if school_id is not None:
            pid = f.stem
            if not pid[:1].isdigit() or int(pid[0]) != school_id:
                continue
        frames.append(load_pupil_data(str(f)))

    if not frames:
        raise FileNotFoundError(
            f"No data files found for school_id={school_id} in: {processed_dir}"
        )

    return pd.concat(frames, ignore_index=True)


def load_schedule_config(config_path: str = "config/school_schedules.yaml") -> dict:
    """Load and return the school schedule configuration.

    Parameters
    ----------
    config_path : str
        Path to school_schedules.yaml.

    Returns
    -------
    dict
        Parsed YAML config with school schedule definitions.
    """
    config_path = Path(config_path)
    if not config_path.exists():
        raise FileNotFoundError(f"Schedule config not found: {config_path}")

    with open(config_path) as f:
        return yaml.safe_load(f)


def load_pipeline_params(config_path: str = "config/pipeline_params.yaml") -> dict:
    """Load pipeline parameters from YAML config.

    Parameters
    ----------
    config_path : str
        Path to pipeline_params.yaml.

    Returns
    -------
    dict
        All pipeline parameters.
    """
    config_path = Path(config_path)
    if not config_path.exists():
        raise FileNotFoundError(f"Pipeline config not found: {config_path}")

    with open(config_path) as f:
        return yaml.safe_load(f)


def epoch_to_minutes(df: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    """Convert 1-second epoch counts to minutes for a grouped summary.

    Groups the dataframe by the given columns (plus 'intensity'),
    counts rows (= seconds), and divides by 60 to get minutes.

    Parameters
    ----------
    df : pd.DataFrame
        Epoch-level data with an 'intensity' column.
    group_cols : list[str]
        Columns to group by (e.g. ['pupil_id', 'date', 'context']).

    Returns
    -------
    pd.DataFrame
        One row per group per intensity, with a 'minutes' column.
    """
    return (
        df.groupby(group_cols + ["intensity"])
        .size()
        .reset_index(name="n_epochs")
        .assign(minutes=lambda x: x["n_epochs"] / 60)
    )

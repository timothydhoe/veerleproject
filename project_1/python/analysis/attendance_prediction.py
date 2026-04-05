"""
SchoolMoves — Attendance Prediction (RQ5)
==========================================
Predicts whether a pupil was present at school on each school day,
based on morning activity patterns detected by the accelerometer.

Algorithm:
  For each school day in the pupil's measurement window:
    1. Extract epochs in [school_start - arrival_window, school_start + 30min]
    2. Look for a sustained activity burst (>=3 consecutive epochs with ENMO > threshold)
    3. Classify:
       - Burst found          -> present,  confidence = "high"
       - Only single peaks    -> present,  confidence = "low"
       - No activity above    -> absent,   confidence = "high"
       - Full non-wear        -> absent,   confidence = "certain"
"""

from datetime import datetime, timedelta

import pandas as pd


def predict_attendance(
    pupil_df: pd.DataFrame,
    school_id: int,
    schedule_config: dict,
    params: dict,
) -> pd.DataFrame:
    """Predict attendance for each school day based on morning activity.

    Parameters
    ----------
    pupil_df : pd.DataFrame
        Processed epoch data for one pupil. Must have columns:
        pupil_id, timestamp, enmo_mg, wear.
    school_id : int
        School ID (1-6), used to look up school start time.
    schedule_config : dict
        Loaded school schedule config (from school_schedules.yaml).
    params : dict
        Pipeline parameters (from pipeline_params.yaml).

    Returns
    -------
    pd.DataFrame
        Columns: pupil_id, date, predicted_present, confidence,
                 arrival_time_detected, researcher_override, final_status
    """
    arrival_window = params.get("attendance_arrival_window_min", 60)
    enmo_threshold = params.get("attendance_enmo_threshold_mg", 50)
    pupil_id = pupil_df["pupil_id"].iloc[0]

    # Find school start time from config
    school_start_str = _get_school_start(school_id, schedule_config)
    school_start_time = datetime.strptime(school_start_str, "%H:%M").time()

    # Ensure timestamp is datetime
    if not pd.api.types.is_datetime64_any_dtype(pupil_df["timestamp"]):
        pupil_df = pupil_df.copy()
        pupil_df["timestamp"] = pd.to_datetime(pupil_df["timestamp"])

    # Get unique school days (weekdays only)
    pupil_df = pupil_df.copy()
    pupil_df["date"] = pupil_df["timestamp"].dt.date
    all_dates = pupil_df["date"].unique()
    school_days = [d for d in all_dates if pd.Timestamp(d).dayofweek < 5]

    results = []
    for day in school_days:
        result = _assess_single_day(
            pupil_df, pupil_id, day, school_start_time,
            arrival_window, enmo_threshold
        )
        results.append(result)

    if not results:
        return _empty_result()

    return pd.DataFrame(results)


def _assess_single_day(
    pupil_df, pupil_id, day, school_start_time,
    arrival_window_min, enmo_threshold
):
    """Assess attendance for a single school day."""
    # Define the arrival window
    school_start_dt = datetime.combine(day, school_start_time)
    window_start = school_start_dt - timedelta(minutes=arrival_window_min)
    window_end = school_start_dt + timedelta(minutes=30)

    # Filter to the arrival window
    mask = (
        (pupil_df["date"] == day)
        & (pupil_df["timestamp"] >= pd.Timestamp(window_start))
        & (pupil_df["timestamp"] <= pd.Timestamp(window_end))
    )
    window_data = pupil_df.loc[mask].sort_values("timestamp")

    result = {
        "pupil_id": pupil_id,
        "date": day,
        "predicted_present": False,
        "confidence": "high",
        "arrival_time_detected": pd.NaT,
        "researcher_override": None,
        "final_status": "absent",
    }

    if window_data.empty:
        result["confidence"] = "high"
        result["final_status"] = "absent"
        return result

    # Check for full non-wear in the window
    if "wear" in window_data.columns and not window_data["wear"].any():
        result["confidence"] = "certain"
        result["final_status"] = "absent"
        return result

    # Check for activity bursts
    above_threshold = (window_data["enmo_mg"] > enmo_threshold).values
    burst_start = _find_burst(above_threshold, min_consecutive=3)

    if burst_start is not None:
        # Sustained burst found -> present, high confidence
        result["predicted_present"] = True
        result["confidence"] = "high"
        result["arrival_time_detected"] = window_data.iloc[burst_start]["timestamp"]
        result["final_status"] = "present"

    elif above_threshold.any():
        # Some peaks but no sustained burst -> present, low confidence
        first_peak_idx = above_threshold.argmax()
        result["predicted_present"] = True
        result["confidence"] = "low"
        result["arrival_time_detected"] = window_data.iloc[first_peak_idx]["timestamp"]
        result["final_status"] = "present"

    else:
        # No activity above threshold -> absent, high confidence
        result["predicted_present"] = False
        result["confidence"] = "high"
        result["final_status"] = "absent"

    return result


def _find_burst(above_threshold, min_consecutive=3):
    """Find the start index of the first burst of >=min_consecutive True values."""
    count = 0
    for i, val in enumerate(above_threshold):
        if val:
            count += 1
            if count >= min_consecutive:
                return i - min_consecutive + 1
        else:
            count = 0
    return None


def _get_school_start(school_id, schedule_config):
    """Look up school start time from config."""
    for school in schedule_config.get("schools", []):
        if school["school_id"] == school_id:
            return school["school_start"]
    raise ValueError(
        f"School ID {school_id} not found in schedule config. "
        f"Available: {[s['school_id'] for s in schedule_config.get('schools', [])]}"
    )


def _empty_result():
    """Return an empty result DataFrame with the correct schema."""
    return pd.DataFrame({
        "pupil_id": pd.Series(dtype="str"),
        "date": pd.Series(dtype="object"),
        "predicted_present": pd.Series(dtype="bool"),
        "confidence": pd.Series(dtype="str"),
        "arrival_time_detected": pd.Series(dtype="datetime64[ns]"),
        "researcher_override": pd.Series(dtype="object"),
        "final_status": pd.Series(dtype="str"),
    })

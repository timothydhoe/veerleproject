"""
generate_dummy_data.py
======================
Generates realistic dummy GENEActiv accelerometer CSV files for the SchoolMoves study.

Output structure:
  <output_dir>/
    meting_1/  <-- one CSV per pupil, measurement period 1
    meting_2/  <-- one CSV per pupil, measurement period 2
    validity_summary.csv

Usage:
  python generate_dummy_data.py                          # 20 pupils, 7 days, 1 Hz
  python generate_dummy_data.py --n-pupils 400 --days 7  # full study dataset
  python generate_dummy_data.py --n-pupils 5 --days 2    # quick test run

Dependencies: numpy, pandas (standard scientific Python only)
"""

import argparse
import os
import time
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

# ===========================================================================
# 1. ARGUMENT PARSING
# ===========================================================================

def parse_args():
    parser = argparse.ArgumentParser(description="Generate dummy GENEActiv accelerometer data")
    parser.add_argument("--n-pupils", type=int, default=20,
                        help="Number of pupils to generate (default 20; set to 400 for full study)")
    parser.add_argument("--days", type=int, default=7,
                        help="Number of days per measurement period (default 7)")
    parser.add_argument("--hz", type=int, default=1,
                        help="Sampling frequency in Hz (default 1; raw device = 100)")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for reproducibility (default 42)")
    parser.add_argument("--output-dir", type=str,
                        default=os.path.join(os.path.dirname(__file__)),
                        help="Root output directory (default: same folder as this script)")
    return parser.parse_args()


# ===========================================================================
# 2. SCHOOL CONFIGURATION
# ===========================================================================
# Each school entry:
#   total_pupils   : target for the full 400-pupil study
#   id_start       : first 4-digit pupil code  (school_digit * 1000 + 1)
#   meting_1_start : first day device is worn, period 1  (date string YYYY-MM-DD)
#   meting_2_start : first day device is worn, period 2
#   max_until_1/2  : time (HH:MM) on the LAST day until which device is still worn
#   school_hours   : dict  weekday_int (0=Mon … 6=Sun) -> (start_HH, start_MM, end_HH, end_MM)
#                    weekdays not present -> no school (weekend / holiday)
#   breaks         : dict  weekday_int -> list of (start_HH, start_MM, end_HH, end_MM)

SCHOOL_CONFIG = {
    1: {
        "total_pupils": 70,
        "id_start": 1001,
        "meting_1_start": "2026-02-23",
        "meting_2_start": "2026-06-01",
        "max_until_1": "13:00",
        "max_until_2": "13:00",
        # Mon=0, Tue=1, Wed=2, Thu=3, Fri=4
        "school_hours": {
            0: (8, 25, 15, 40),   # Monday
            1: (8, 25, 16, 30),   # Tuesday
            2: (8, 25, 11, 55),   # Wednesday
            3: (8, 25, 15, 40),   # Thursday
            4: (8, 25, 15, 40),   # Friday
        },
        "breaks": {
            0: [(10, 5, 10, 20), (12, 0, 13, 0), (14, 40, 14, 50)],
            1: [(10, 5, 10, 20), (12, 0, 13, 0), (14, 40, 14, 50)],
            2: [(10, 5, 10, 15)],
            3: [(10, 5, 10, 20), (12, 0, 13, 0), (14, 40, 14, 50)],
            4: [(10, 5, 10, 20), (12, 0, 13, 0), (14, 40, 14, 50)],
        },
    },
    2: {
        "total_pupils": 80,
        "id_start": 2001,
        "meting_1_start": "2026-03-03",
        "meting_2_start": "2026-05-26",
        "max_until_1": "15:35",
        "max_until_2": "15:35",
        "school_hours": {
            0: (8, 25, 15, 35),
            1: (8, 25, 15, 35),
            2: (8, 25, 12, 0),
            3: (8, 25, 15, 35),
            4: (8, 25, 15, 35),
        },
        "breaks": {
            0: [(10, 5, 10, 20), (12, 0, 12, 50), (14, 30, 14, 45)],
            1: [(10, 5, 10, 20), (12, 0, 12, 50), (14, 30, 14, 45)],
            2: [(10, 5, 10, 20)],
            3: [(10, 5, 10, 20), (12, 0, 12, 50), (14, 30, 14, 45)],
            4: [(10, 5, 10, 20), (12, 0, 12, 50), (14, 30, 14, 45)],
        },
    },
    3: {
        "total_pupils": 60,
        "id_start": 3001,
        "meting_1_start": "2026-01-19",
        "meting_2_start": "2026-04-20",
        "max_until_1": "10:05",
        "max_until_2": "10:05",
        # Generic Belgian primary schedule (school hours unknown)
        "school_hours": {
            0: (8, 30, 15, 30),
            1: (8, 30, 15, 30),
            2: (8, 30, 15, 30),
            3: (8, 30, 15, 30),
            4: (8, 30, 15, 30),
        },
        "breaks": {
            0: [(10, 15, 10, 30), (12, 0, 13, 0)],
            1: [(10, 15, 10, 30), (12, 0, 13, 0)],
            2: [(10, 15, 10, 30), (12, 0, 13, 0)],
            3: [(10, 15, 10, 30), (12, 0, 13, 0)],
            4: [(10, 15, 10, 30), (12, 0, 13, 0)],
        },
    },
    4: {
        "total_pupils": 65,
        "id_start": 4001,
        "meting_1_start": "2026-02-05",
        "meting_2_start": "2026-05-21",
        "max_until_1": "16:35",
        "max_until_2": "16:35",
        "school_hours": {
            0: (8, 30, 16, 30),
            1: (8, 30, 16, 30),
            2: (8, 30, 16, 30),
            3: (8, 30, 16, 30),
            4: (8, 30, 16, 30),
        },
        "breaks": {
            0: [(10, 15, 10, 30), (12, 0, 13, 30)],
            1: [(10, 15, 10, 30), (12, 0, 13, 30)],
            2: [(10, 15, 10, 30), (12, 0, 13, 30)],
            3: [(10, 15, 10, 30), (12, 0, 13, 30)],
            4: [(10, 15, 10, 30), (12, 0, 13, 30)],
        },
    },
    5: {
        "total_pupils": 55,
        "id_start": 5001,
        "meting_1_start": "2026-01-09",
        "meting_2_start": "2026-03-11",
        "max_until_1": "10:25",
        "max_until_2": "09:20",
        "school_hours": {
            0: (8, 30, 15, 55),
            1: (8, 30, 15, 55),
            2: (8, 30, 15, 55),
            3: (8, 30, 15, 55),
            4: (8, 30, 15, 55),
        },
        "breaks": {
            0: [(10, 10, 10, 25), (12, 5, 13, 10), (14, 50, 15, 5)],
            1: [(10, 10, 10, 25), (12, 5, 13, 10), (14, 50, 15, 5)],
            2: [(10, 10, 10, 25), (12, 5, 13, 10), (14, 50, 15, 5)],
            3: [(10, 10, 10, 25), (12, 5, 13, 10), (14, 50, 15, 5)],
            4: [(10, 10, 10, 25), (12, 5, 13, 10), (14, 50, 15, 5)],
        },
    },
    6: {
        "total_pupils": 70,
        "id_start": 6001,
        "meting_1_start": "2026-03-02",
        "meting_2_start": "2026-05-04",
        "max_until_1": "10:10",
        "max_until_2": "10:10",
        "school_hours": {
            0: (8, 30, 15, 25),
            1: (8, 30, 15, 25),
            2: (8, 30, 12, 0),
            3: (8, 30, 15, 25),
            4: (8, 30, 15, 25),
        },
        "breaks": {
            0: [(11, 0, 11, 15), (12, 55, 13, 45)],
            1: [(11, 0, 11, 15), (12, 55, 13, 45)],
            2: [(10, 10, 10, 20)],
            3: [(11, 0, 11, 15), (12, 55, 13, 45)],
            4: [(11, 0, 11, 15), (12, 55, 13, 45)],
        },
    },
}

# Total study pupils per school (used when --n-pupils < 400 for proportional scaling)
TOTAL_STUDY_PUPILS = sum(s["total_pupils"] for s in SCHOOL_CONFIG.values())  # 400


# ===========================================================================
# 3. PUPIL ALLOCATION
# ===========================================================================

def allocate_pupils(n_pupils: int) -> list[dict]:
    """
    Returns a list of pupil dicts, each with keys:
      school_id, pupil_code (4-digit str), school_cfg
    Proportionally distributed across the 6 schools.
    """
    pupils = []
    for school_id, cfg in SCHOOL_CONFIG.items():
        # How many pupils to generate for this school
        count = max(1, round(n_pupils * cfg["total_pupils"] / TOTAL_STUDY_PUPILS))
        for i in range(count):
            pupil_num = cfg["id_start"] + i
            pupils.append({
                "school_id": school_id,
                "pupil_code": str(pupil_num),
                "school_cfg": cfg,
            })
        if len(pupils) >= n_pupils:
            break

    return pupils[:n_pupils]


# ===========================================================================
# 4. HEADER WRITER
# ===========================================================================

def make_header(pupil_code: str, serial: str, start_time: datetime,
                config_time: datetime, extract_time: datetime) -> str:
    """
    Builds the exact 100-line GENEActiv header string (no trailing data).
    Matches the structure of data/fvb_data.csv exactly.
    """
    st = start_time.strftime("%Y-%m-%d %H:%M:%S:000")
    ct = config_time.strftime("%Y-%m-%d %H:%M:%S:000")
    et = extract_time.strftime("%Y-%m-%d %H:%M:%S:000")
    cal = config_time.strftime("%Y-%m-%d %H:%M:%S:000")

    lines = [
        # Lines 1–6: device metadata
        f"Device Type,GENEActiv",
        f"Device Model,1.1",
        f"Device Unique Serial Code,{serial}",
        f"Device Firmware Version,Ver4.08a date14Jul14",
        f"Calibration Date,{cal}",
        f"Application name & version,GeneaLibrary",
        # Lines 7–10: blank
        "", "", "", "",
        # Lines 11–15: measurement config
        f"Measurement Frequency,100 Hz",
        f"Start Time,{st}",
        f"Last measurement,",
        f"Device Location Code,left wrist",
        f"Time Zone,GMT +01:00",
        # Lines 16–20: blank
        "", "", "", "", "",
        # Lines 21–27: subject info
        f"Subject Code,{pupil_code}",
        f"Date of Birth,1900-01-01",
        f"Sex,",
        f"Height,",
        f"Weight,",
        f"Handedness Code,",
        f"Subject Notes,",
        # Lines 28–30: blank
        "", "", "",
        # Lines 31–40: study/config
        f"Study Centre,",
        f"Study Code,",
        f"Investigator ID,",
        f"Exercise Type,",
        f"Config Operator ID,",
        f"Config Time,{ct}",
        f"Config Notes,",
        f"Extract Operator ID,",
        f"Extract Time,{et}",
        f"Extract Notes,",
        # Lines 41–50: blank
        "", "", "", "", "", "", "", "", "", "",
        # Lines 51–80: 6 × 5-line sensor blocks
        # x-axis (51–55)
        f"Sensor type,MEMS accelerometer x-axis",
        f"Range,-8 to 8",
        f"Resolution,0.0039",
        f"Units,g",
        f"Additional information,",
        # y-axis (56–60)
        f"Sensor type,MEMS accelerometer y-axis",
        f"Range,-8 to 8",
        f"Resolution,0.0039",
        f"Units,g",
        f"Additional information,",
        # z-axis (61–65)
        f"Sensor type,MEMS accelerometer z-axis",
        f"Range,-8 to 8",
        f"Resolution,0.0039",
        f"Units,g",
        f"Additional information,",
        # Lux (66–70)
        f"Sensor type,Lux Photodiode 400nm - 1100nm",
        f"Range,0 to 5000",
        f"Resolution,5",
        f"Units,lux",
        f"Additional information,",
        # Button (71–75)
        f"Sensor type,User button event marker",
        f"Range,1 or 0",
        f"Resolution,",
        f"Units,",
        f"Additional information,1=pressed",
        # Thermistor (76–80)
        f"Sensor type,Linear active thermistor",
        f"Range,0 to 70",
        f"Resolution,0.1",
        f"Units,deg. C",
        f"Additional information,",
        # Lines 81–100: blank
        "", "", "", "", "", "", "", "", "", "",
        "", "", "", "", "", "", "", "", "", "",
    ]

    # Verify we have exactly 100 lines before the data section
    assert len(lines) == 100, f"Header has {len(lines)} lines, expected 100"
    return "\n".join(lines) + "\n"


# ===========================================================================
# 5. ACTIVITY STATE CLASSIFICATION (VECTORISED)
# ===========================================================================

def _hm_to_minutes(h: int, m: int) -> int:
    return h * 60 + m


def classify_activity_states(timestamps: pd.DatetimeIndex,
                              school_cfg: dict,
                              is_low_wear: bool,
                              rng: np.random.Generator,
                              n_days: int) -> np.ndarray:
    """
    Returns an integer state array (same length as timestamps):
      0 = sleep
      1 = morning_routine
      2 = school_lesson
      3 = school_break
      4 = lunch
      5 = after_school
      6 = sedentary_evening
      7 = wind_down
      8 = non_wear
    Uses vectorised numpy operations — no Python loops over individual rows.
    """
    STATE_SLEEP     = 0
    STATE_MORNING   = 1
    STATE_LESSON    = 2
    STATE_BREAK     = 3
    STATE_LUNCH     = 4
    STATE_AFTER     = 5
    STATE_EVENING   = 6
    STATE_WINDDOWN  = 7
    STATE_NONWEAR   = 8

    n = len(timestamps)
    states = np.full(n, STATE_SLEEP, dtype=np.int8)

    # Convert timestamps to minutes-since-midnight (vectorised)
    mins = timestamps.hour * 60 + timestamps.minute   # numpy int array via .hour / .minute
    weekdays = timestamps.weekday                      # 0=Mon … 6=Sun

    # ---- Default time-of-day states (applied to all rows, then overwritten) ----
    # sleep:       00:00 – 06:30
    # morning:     06:30 – 08:00  (before school or weekend)
    # after_school/leisure: after school end
    # evening:     19:00 – 21:00
    # wind_down:   21:00 – 23:00
    # sleep again: 23:00 – 24:00

    states[mins >= _hm_to_minutes(6, 30)]  = STATE_MORNING
    states[mins >= _hm_to_minutes(15, 30)] = STATE_AFTER      # default, overwritten by school
    states[mins >= _hm_to_minutes(19, 0)]  = STATE_EVENING
    states[mins >= _hm_to_minutes(21, 0)]  = STATE_WINDDOWN
    states[mins >= _hm_to_minutes(23, 0)]  = STATE_SLEEP

    # ---- School-day states ----
    # Apply per-weekday school schedule (overwrite states for school hours)
    for wd, hours in school_cfg["school_hours"].items():
        sh, sm, eh, em = hours
        school_start = _hm_to_minutes(sh, sm)
        school_end   = _hm_to_minutes(eh, em)

        is_school_day = (weekdays == wd)
        in_school = is_school_day & (mins >= school_start) & (mins < school_end)
        states[in_school] = STATE_LESSON

        # After school on school days
        after_school = is_school_day & (mins >= school_end) & (mins < _hm_to_minutes(19, 0))
        states[after_school] = STATE_AFTER

        # Breaks within school hours
        for bh_s, bm_s, bh_e, bm_e in school_cfg["breaks"].get(wd, []):
            bs = _hm_to_minutes(bh_s, bm_s)
            be = _hm_to_minutes(bh_e, bm_e)

            # Distinguish lunch break from short recess
            duration = be - bs
            is_break = is_school_day & (mins >= bs) & (mins < be)
            if duration >= 30:
                states[is_break] = STATE_LUNCH
            else:
                states[is_break] = STATE_BREAK

    # ---- Non-wear injection ----
    # Place 1–3 non-wear windows per week, randomly during waking hours (08:00–22:00),
    # but more for the "low wear" cohort (~10% of pupils)
    wear_slots_per_day = n // max(n_days, 1)   # approx rows per day
    n_windows = rng.integers(2, 5) if is_low_wear else rng.integers(1, 4)
    n_windows = min(n_windows, n_days * 2)

    for _ in range(n_windows):
        # Pick a random minute window during waking hours 08:00–20:00
        # Duration: 60–180 min for normal, 180–360 min for low-wear
        dur_min = rng.integers(180, 361) if is_low_wear else rng.integers(60, 181)
        # Pick random day and start time
        day_offset = rng.integers(0, n_days)
        start_of_day_idx = day_offset * wear_slots_per_day
        # Start somewhere between 08:00 and 20:00 on that day
        start_min_in_day = rng.integers(_hm_to_minutes(8, 0), _hm_to_minutes(20, 0))
        end_min_in_day   = min(start_min_in_day + dur_min, _hm_to_minutes(22, 0))

        # Find indices within that day's range matching the minute window
        day_mask = (
            (timestamps >= timestamps[0] + pd.Timedelta(days=day_offset)) &
            (timestamps <  timestamps[0] + pd.Timedelta(days=day_offset + 1))
        )
        time_mask = (mins >= start_min_in_day) & (mins < end_min_in_day)
        states[day_mask & time_mask] = STATE_NONWEAR

    return states


# ===========================================================================
# 6. SIGNAL GENERATION (VECTORISED)
# ===========================================================================

# ENMO target ranges (mg) per state: (low, high)
ENMO_RANGES = {
    0: (2,   8),     # sleep
    1: (40,  120),   # morning
    2: (5,   40),    # lesson
    3: (80,  350),   # break/recess
    4: (20,  200),   # lunch
    5: (40,  180),   # after school
    6: (10,  50),    # evening sedentary
    7: (5,   20),    # wind down
    8: (0,   3),     # non-wear
}

# Wrist rest orientation at each state (base x, y, z before perturbation)
REST_XYZ = {
    0: (0.00,  0.05, -0.99),   # sleep: flat on back, z dominant
    1: (0.10,  0.30, -0.95),   # morning: upright
    2: (0.10,  0.30, -0.95),   # lesson: sitting
    3: (0.15,  0.25, -0.97),   # break: active
    4: (0.10,  0.30, -0.95),   # lunch
    5: (0.10,  0.30, -0.95),   # after school
    6: (0.05,  0.15, -0.98),   # evening: relaxed
    7: (0.02,  0.08, -0.99),   # wind down
    8: (0.00,  0.00, -1.00),   # non-wear: on table
}


def generate_signals(states: np.ndarray,
                     activity_scalar: float,
                     rng: np.random.Generator) -> tuple[np.ndarray, ...]:
    """
    Generates x, y, z, lux, button, temp, ENMO, std_x, std_y, std_z, peak_lux
    arrays from state labels. Fully vectorised.

    ENMO = max(0, sqrt(x²+y²+z²) − 1) × 1000  [in mg]
    The function back-calculates x/y/z to hit a per-second ENMO target drawn
    from the state's range, scaled by the pupil's activity_scalar.
    """
    n = len(states)

    # --- Build per-row ENMO target (mg) ---
    enmo_target_mg = np.empty(n)
    for state, (lo, hi) in ENMO_RANGES.items():
        mask = states == state
        lo_s = lo * activity_scalar
        hi_s = hi * activity_scalar
        enmo_target_mg[mask] = rng.uniform(lo_s, hi_s, mask.sum())

    # Convert mg → g  (ENMO target in g units)
    enmo_target_g = enmo_target_mg / 1000.0

    # --- Base orientation per state ---
    bx = np.empty(n)
    by = np.empty(n)
    bz = np.empty(n)
    for state, (rx, ry, rz) in REST_XYZ.items():
        mask = states == state
        bx[mask] = rx
        by[mask] = ry
        bz[mask] = rz

    # Add small orientation noise
    bx += rng.normal(0, 0.02, n)
    by += rng.normal(0, 0.02, n)
    bz += rng.normal(0, 0.02, n)

    # Normalise base to unit vector (on the unit sphere)
    norm_base = np.sqrt(bx**2 + by**2 + bz**2)
    bx /= norm_base
    by /= norm_base
    bz /= norm_base

    # Target vector magnitude = 1 + enmo_target_g  (since ENMO = |vec| − 1)
    target_magnitude = 1.0 + enmo_target_g

    # Scale base unit vector to target magnitude
    x = bx * target_magnitude
    y = by * target_magnitude
    z = bz * target_magnitude

    # Add fine-grained sensor noise (σ = 0.005 g)
    x += rng.normal(0, 0.005, n)
    y += rng.normal(0, 0.005, n)
    z += rng.normal(0, 0.005, n)

    # Clip to device range ±8 g
    x = np.clip(x, -8.0, 8.0)
    y = np.clip(y, -8.0, 8.0)
    z = np.clip(z, -8.0, 8.0)

    # --- Recompute ENMO from final x/y/z ---
    svm = np.sqrt(x**2 + y**2 + z**2)
    enmo = np.maximum(0.0, svm - 1.0) * 1000.0  # in mg

    # --- Per-second standard deviations (approximated for 1 Hz output) ---
    # At 100 Hz, std over a 1-second window reflects intra-second variability.
    # We approximate: std ≈ enmo_target_g * noise_factor + small baseline
    noise_factor = 0.15
    std_base = 0.005
    std_x = np.abs(rng.normal(enmo_target_g * noise_factor + std_base, 0.003, n))
    std_y = np.abs(rng.normal(enmo_target_g * noise_factor + std_base, 0.003, n))
    std_z = np.abs(rng.normal(enmo_target_g * noise_factor + std_base, 0.003, n))

    # Non-wear: force tiny std
    nonwear = states == 8
    std_x[nonwear] = rng.uniform(0.0005, 0.013, nonwear.sum())
    std_y[nonwear] = rng.uniform(0.0005, 0.013, nonwear.sum())
    std_z[nonwear] = rng.uniform(0.0005, 0.013, nonwear.sum())

    # --- Lux ---
    # States: sleep/wind_down=low, indoor lesson=medium, outdoor break=high, non-wear=variable
    lux = np.zeros(n)

    # Night hours: 0–5 lux
    sleep_mask  = (states == 0) | (states == 7)
    lux[sleep_mask] = rng.uniform(0, 5, sleep_mask.sum())

    # Morning routine
    morning_mask = states == 1
    lux[morning_mask] = rng.uniform(50, 400, morning_mask.sum())

    # Indoor school lessons
    lesson_mask = states == 2
    lux[lesson_mask] = rng.uniform(200, 800, lesson_mask.sum())

    # Outdoor breaks/recess  (mix outdoor bright + some indoor)
    break_mask = states == 3
    outdoor = rng.random(break_mask.sum()) > 0.3   # 70% chance outdoor
    lux_break = np.where(outdoor,
                         rng.uniform(1000, 5000, break_mask.sum()),
                         rng.uniform(200, 800,  break_mask.sum()))
    lux[break_mask] = lux_break

    # Lunch
    lunch_mask = states == 4
    lux[lunch_mask] = rng.uniform(100, 2000, lunch_mask.sum())

    # After school / evening
    after_mask  = states == 5
    lux[after_mask]  = rng.uniform(50, 1500, after_mask.sum())
    evening_mask = states == 6
    lux[evening_mask] = rng.uniform(10, 200, evening_mask.sum())

    # Non-wear (device on table) — variable
    lux[nonwear] = rng.uniform(0, 500, nonwear.sum())

    lux = np.clip(lux, 0, 5000).astype(int)

    # Peak lux (max in a simulated 100-sample window ≈ lux * 1.5–6 for outdoor)
    peak_multiplier = rng.uniform(1.0, 4.0, n)
    peak_lux = np.clip(lux * peak_multiplier, 0, 5000).astype(int)

    # --- Button press (extremely rare: ~0.01% of seconds) ---
    button = (rng.random(n) < 0.0001).astype(int)

    # --- Temperature (°C) ---
    # Device warms up during wear (22–34°C), cools during non-wear
    base_temp = 28.0 + rng.normal(0, 1.0)   # pupil-level variation
    # Smooth sinusoidal drift over the day
    hour_of_day = np.arange(n) / 3600.0  # rough hour counter
    temp = base_temp + 2.0 * np.sin(2 * np.pi * hour_of_day / 24.0)
    temp += rng.normal(0, 0.2, n)         # fine noise
    temp[nonwear] -= rng.uniform(2.0, 6.0, nonwear.sum())  # cooler off wrist
    temp = np.clip(temp, 0, 70).round(1)

    # --- Round final values ---
    x    = x.round(4)
    y    = y.round(4)
    z    = z.round(4)
    enmo = enmo.round(2)
    std_x = std_x.round(4)
    std_y = std_y.round(4)
    std_z = std_z.round(4)

    return x, y, z, lux, button, temp, enmo, std_x, std_y, std_z, peak_lux


# ===========================================================================
# 7. TIMESTAMP GENERATION
# ===========================================================================

def build_timestamps(meting_start_str: str,
                     n_days: int,
                     max_until_str: str,
                     hz: int) -> pd.DatetimeIndex:
    """
    Returns a DatetimeIndex covering the full measurement window (24h/day).
    The device is put on the evening before meting_start (at ~17:00) and
    removed on the last day at max_until time.  This ensures sleep epochs
    (00:00–06:30) are present in every intermediate night.

    Sampling at `hz` samples/second.
    """
    start_date = datetime.strptime(meting_start_str, "%Y-%m-%d")
    freq_ns = 1_000_000_000 // hz          # nanoseconds between samples
    freq = f"{freq_ns}ns"

    # Device put on the day before the measurement week starts (at ~17:00)
    # so the first night of sleep is captured.
    recording_start = (start_date - timedelta(days=1)).replace(
        hour=17, minute=0, second=0, microsecond=0
    )

    # Last day: device returned at school at max_until time
    h, m = map(int, max_until_str.split(":"))
    last_day = start_date + timedelta(days=n_days - 1)
    recording_end = last_day.replace(hour=h, minute=m, second=0, microsecond=0)

    # If max_until is before noon it is an early-morning return;
    # if somehow end <= start, fall back to end of last day
    if recording_end <= recording_start:
        recording_end = last_day.replace(hour=22, minute=0, second=0, microsecond=0)

    ts = pd.date_range(
        start=recording_start,
        end=recording_end - pd.Timedelta(nanoseconds=freq_ns),
        freq=freq,
    )
    return ts


# ===========================================================================
# 8. VALIDITY CHECKER
# ===========================================================================

def check_validity(states: np.ndarray, timestamps: pd.DatetimeIndex) -> dict:
    """
    Returns validity flags for waking wear (sedentary analysis) and sleep.
    Criteria:
      - Waking:  >= 4 days with >= 9 valid waking wear hours
      - Sleep:   >= 5 nights with >= 50% of sleep window covered
    """
    WAKING_STATES = {1, 2, 3, 4, 5, 6, 7}   # anything except sleep(0) and non-wear(8)
    SLEEP_STATES  = {0, 7}                    # sleep + wind_down

    dates = timestamps.normalize()
    unique_days = dates.unique()

    valid_waking_days = 0
    valid_sleep_nights = 0

    for day in unique_days:
        day_mask = dates == day

        # Waking validity: non-wear hours ≥ 9h
        waking_secs = np.sum(np.isin(states[day_mask], list(WAKING_STATES)))
        if waking_secs / 3600 >= 9:
            valid_waking_days += 1

        # Sleep validity: sleep-state seconds / expected sleep window (6.5h)
        sleep_secs = np.sum(np.isin(states[day_mask], list(SLEEP_STATES)))
        sleep_expected = 6.5 * 3600
        if sleep_secs / sleep_expected >= 0.5:
            valid_sleep_nights += 1

    meets_waking_criteria = valid_waking_days >= 4
    meets_sleep_criteria  = valid_sleep_nights >= 5

    return {
        "valid_waking_days": valid_waking_days,
        "valid_sleep_nights": valid_sleep_nights,
        "meets_waking_criteria": meets_waking_criteria,
        "meets_sleep_criteria":  meets_sleep_criteria,
        "meets_all_criteria": meets_waking_criteria and meets_sleep_criteria,
    }


# ===========================================================================
# 9. FILE WRITER
# ===========================================================================

def write_pupil_file(filepath: str,
                     pupil_code: str,
                     serial: str,
                     meting_start_str: str,
                     school_cfg: dict,
                     is_low_wear: bool,
                     rng: np.random.Generator,
                     n_days: int,
                     hz: int) -> dict:
    """
    Generates and writes one pupil CSV file. Returns validity info dict.
    """
    # Build timestamps (24h/day; max_until_1 key holds the correct value for this period,
    # the caller patches it for meting_2 via school_cfg["max_until_1"])
    timestamps = build_timestamps(meting_start_str, n_days, school_cfg["max_until_1"], hz)

    if len(timestamps) == 0:
        return {"pupil_code": pupil_code, "meets_all_criteria": False,
                "valid_waking_days": 0, "valid_sleep_nights": 0,
                "meets_waking_criteria": False, "meets_sleep_criteria": False}

    # Activity state classification
    states = classify_activity_states(timestamps, school_cfg, is_low_wear, rng, n_days)

    # Signal generation (per-pupil activity scalar 0.5–1.5)
    activity_scalar = rng.uniform(0.5, 1.5)
    x, y, z, lux, button, temp, enmo, std_x, std_y, std_z, peak_lux = \
        generate_signals(states, activity_scalar, rng)

    # Validity check
    validity = check_validity(states, timestamps)
    validity["pupil_code"] = pupil_code

    # Format timestamps as YYYY-MM-DD HH:MM:SS:mmm
    ts_strs = timestamps.strftime("%Y-%m-%d %H:%M:%S:000")

    # Build DataFrame
    df = pd.DataFrame({
        "ts":       ts_strs,
        "x":        x,
        "y":        y,
        "z":        z,
        "lux":      lux,
        "button":   button,
        "temp":     temp,
        "enmo":     enmo,
        "std_x":    std_x,
        "std_y":    std_y,
        "std_z":    std_z,
        "peak_lux": peak_lux,
    })

    # Build header metadata times
    start_time    = timestamps[0]
    config_time   = start_time - timedelta(days=1)
    extract_time  = start_time + timedelta(days=n_days + 3)

    header_str = make_header(pupil_code, serial, start_time, config_time, extract_time)

    # Write header + data to file
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "w", encoding="utf-8", newline="\n") as f:
        f.write(header_str)
        df.to_csv(f, index=False, header=False)

    return validity


# ===========================================================================
# 10. SERIAL NUMBER GENERATOR
# ===========================================================================

def make_serial(rng: np.random.Generator) -> str:
    """Returns a random 6-digit device serial number string."""
    return f"{rng.integers(100000, 999999):06d}"


# ===========================================================================
# 11. MAIN
# ===========================================================================

def main():
    args = parse_args()

    # Seed the global random generator (numpy >= 1.17 recommended API)
    rng = np.random.default_rng(args.seed)

    output_dir = args.output_dir
    meting_1_dir = os.path.join(output_dir, "meting_1")
    meting_2_dir = os.path.join(output_dir, "meting_2")
    os.makedirs(meting_1_dir, exist_ok=True)
    os.makedirs(meting_2_dir, exist_ok=True)

    # Allocate pupils across schools
    pupils = allocate_pupils(args.n_pupils)

    # Decide which ~10% of pupils are "low-wear" (likely to fail validity)
    n_low_wear = max(1, round(len(pupils) * 0.10))
    low_wear_indices = set(rng.choice(len(pupils), n_low_wear, replace=False).tolist())

    print(f"\n{'='*60}")
    print(f"SchoolMoves Dummy Data Generator")
    print(f"{'='*60}")
    print(f"Pupils to generate : {len(pupils)}")
    print(f"Days per period    : {args.days}")
    print(f"Sampling rate      : {args.hz} Hz")
    print(f"Random seed        : {args.seed}")
    print(f"Output directory   : {os.path.abspath(output_dir)}")
    print(f"Low-wear pupils    : {n_low_wear} (~10%)")
    print(f"{'='*60}\n")

    validity_records = []
    t0 = time.time()

    for idx, pupil in enumerate(pupils):
        school_id   = pupil["school_id"]
        pupil_code  = pupil["pupil_code"]
        school_cfg  = pupil["school_cfg"]
        is_low_wear = idx in low_wear_indices
        serial      = make_serial(rng)

        # --- Meting 1 ---
        cfg_1 = dict(school_cfg)
        cfg_1["max_until_1"] = school_cfg["max_until_1"]   # keep original key
        filepath_1 = os.path.join(meting_1_dir, f"{pupil_code}.csv")
        validity_1 = write_pupil_file(
            filepath=filepath_1,
            pupil_code=pupil_code,
            serial=serial,
            meting_start_str=school_cfg["meting_1_start"],
            school_cfg=school_cfg,
            is_low_wear=is_low_wear,
            rng=rng,
            n_days=args.days,
            hz=args.hz,
        )
        validity_1["meting"] = 1
        validity_1["school_id"] = school_id
        validity_1["is_low_wear_flag"] = is_low_wear

        # --- Meting 2 ---
        # Patch max_until to use meting_2 value inside write_pupil_file
        school_cfg_2 = dict(school_cfg)
        school_cfg_2["max_until_1"] = school_cfg["max_until_2"]  # reuse key internally

        filepath_2 = os.path.join(meting_2_dir, f"{pupil_code}.csv")
        validity_2 = write_pupil_file(
            filepath=filepath_2,
            pupil_code=pupil_code,
            serial=serial,
            meting_start_str=school_cfg["meting_2_start"],
            school_cfg=school_cfg_2,
            is_low_wear=is_low_wear,
            rng=rng,
            n_days=args.days,
            hz=args.hz,
        )
        validity_2["meting"] = 2
        validity_2["school_id"] = school_id
        validity_2["is_low_wear_flag"] = is_low_wear

        validity_records.extend([validity_1, validity_2])

        elapsed = time.time() - t0
        print(f"  [{idx+1:>3}/{len(pupils)}] Pupil {pupil_code} "
              f"(school {school_id}, {'LOW WEAR' if is_low_wear else 'normal':8s}) "
              f"| {elapsed:.1f}s elapsed", end="\r")

    print()   # newline after progress line

    # ===========================================================================
    # 12. SUMMARY
    # ===========================================================================
    validity_df = pd.DataFrame(validity_records)
    summary_path = os.path.join(output_dir, "validity_summary.csv")
    validity_df.to_csv(summary_path, index=False)

    print(f"\n{'='*60}")
    print("VALIDITY SUMMARY")
    print(f"{'='*60}")
    print(f"{'School':<10} {'Pupils':>7} {'Valid(m1)%':>11} {'Valid(m2)%':>11}")
    print(f"{'-'*40}")

    for school_id in sorted(SCHOOL_CONFIG.keys()):
        school_df = validity_df[validity_df["school_id"] == school_id]
        m1 = school_df[school_df["meting"] == 1]
        m2 = school_df[school_df["meting"] == 2]
        n_pupils_school = len(m1)
        if n_pupils_school == 0:
            continue
        pct_m1 = 100 * m1["meets_all_criteria"].sum() / len(m1)
        pct_m2 = 100 * m2["meets_all_criteria"].sum() / len(m2)
        print(f"  School {school_id:<3} {n_pupils_school:>7}   {pct_m1:>8.1f}%   {pct_m2:>8.1f}%")

    total = len(validity_df) // 2
    overall_m1 = validity_df[validity_df["meting"] == 1]["meets_all_criteria"].mean() * 100
    overall_m2 = validity_df[validity_df["meting"] == 2]["meets_all_criteria"].mean() * 100
    print(f"{'-'*40}")
    print(f"  {'TOTAL':<9} {total:>7}   {overall_m1:>8.1f}%   {overall_m2:>8.1f}%")
    print(f"\nTotal files generated : {len(pupils) * 2}")
    print(f"Validity summary CSV  : {summary_path}")
    print(f"Total elapsed time    : {time.time() - t0:.1f}s")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()

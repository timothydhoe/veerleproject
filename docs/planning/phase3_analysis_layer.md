# Phase 3 — Analysis Layer (R + Python)

> Modular analysis modules that answer the study's research questions using the cleaned, labelled pipeline output from Phase 2.

---

## Goal

Produce analysis modules that:
- Answer each research question independently and reproducibly
- Read from the shared parquet format produced by Phase 2
- Export clean summary tables for the UI and for direct reporting
- Are easy to extend with new questions without touching the pipeline

---

## R–Python boundary

| Task | Language | Reason |
|---|---|---|
| Activity totals by context | R | Straightforward aggregation, ggplot2 for visualisation |
| Sedentary bout detection | R | Run-length encoding is natural in R |
| Sleep analysis | R | Direct use of GGIR sleep output |
| School correlations | R | Statistical testing (lm, mixed models) |
| Attendance prediction | Python | Pattern recognition, scikit-learn |
| Batch preprocessing utilities | Python | pandas is faster for large-scale data wrangling |

**Shared data format:** All intermediate data is stored as parquet in `data/processed/`. R uses the `arrow` package; Python uses `pandas` + `pyarrow`.

---

## R analysis modules

### `activity_totals.R`

**Answers:** RQ1 — Total minutes per day per intensity level, by context.

```r
#' Compute daily activity totals per pupil per context
#'
#' @param epochs data.frame — processed epoch data (one row per second)
#' @param valid_only Logical. If TRUE, exclude non-wear and invalid days. Default TRUE.
#' @return data.frame with columns:
#'   pupil_id | school_id | measurement_period | date | context |
#'   sedentary_min | light_min | moderate_min | vigorous_min | total_wear_min
compute_activity_totals <- function(epochs, valid_only = TRUE)
```

**Implementation notes:**
- Group by `pupil_id`, `date`, `context`
- Count epochs per intensity level; divide by 60 (seconds → minutes)
- Exclude epochs where `wear == FALSE` when `valid_only = TRUE`
- Return one row per pupil × date × context combination

**Example output:**

| pupil_id | date | context | sedentary_min | light_min | moderate_min | vigorous_min |
|---|---|---|---|---|---|---|
| 2063 | 2026-03-04 | in_class | 182 | 14 | 2 | 0 |
| 2063 | 2026-03-04 | recess | 4 | 8 | 18 | 0 |
| 2063 | 2026-03-04 | after_school | 45 | 30 | 22 | 8 |

---

### `sedentary_bouts.R`

**Answers:** RQ2 — Sedentary bouts of ≥30 consecutive minutes.

```r
#' Identify and count sedentary bouts
#'
#' @param epochs data.frame — processed epoch data
#' @param min_bout_min Minimum bout length in minutes. Default 30.
#' @param valid_only Logical. Exclude non-wear. Default TRUE.
#' @return data.frame with columns:
#'   pupil_id | date | context | n_bouts | mean_bout_min | total_bout_min
detect_sedentary_bouts <- function(epochs, min_bout_min = 30, valid_only = TRUE)
```

**Implementation notes:**
- Use run-length encoding (`rle()`) on the `intensity` column per pupil per day
- Identify consecutive runs of `sedentary` lasting ≥ `min_bout_min` minutes
- Assign each bout the context of its majority epoch
- A bout that spans a context boundary (e.g. end of class into start of recess) is split

---

### `sleep_analysis.R`

**Answers:** RQ3 — Sleep duration and quality.

```r
#' Summarise GGIR sleep output per pupil per night
#'
#' @param sleep_output data.frame — GGIR Part 4 output (one row per night)
#' @param validity_data data.frame — validity flags from Phase 2
#' @return data.frame with columns:
#'   pupil_id | date | sleep_onset | sleep_offset |
#'   sleep_duration_h | pct_night_valid | valid_night
summarise_sleep <- function(sleep_output, validity_data)
```

**Notes:**
- GGIR Part 4 produces a row per detected sleep period
- `valid_night` = TRUE when `pct_night_valid >= 50`
- Only nights from valid pupils (`pupil_valid_sleep == TRUE`) are included in group-level summaries

---

### `school_correlations.R`

**Answers:** RQ4 — Correlation between lesson duration and in-class activity.

```r
#' Test correlations between school-day structure and activity outcomes
#'
#' @param activity_totals data.frame — output of compute_activity_totals()
#' @param schedule_config Path to school_schedules.yaml
#' @return List with: correlation_table, model_summary, plot
analyse_school_correlations <- function(activity_totals, schedule_config = "config/school_schedules.yaml")
```

**Analysis approach:**
1. From the school schedule config, compute mean lesson block duration per school (minutes of unbroken in-class time)
2. From the activity totals, compute mean in-class sedentary minutes per school
3. Run a Pearson correlation and a simple linear model: `sedentary_min ~ lesson_duration_min`
4. Note: with only 6 schools this is exploratory, not confirmatory — report cautiously

---

## Python analysis modules

### `attendance_prediction.py`

**Answers:** RQ5 — Which days was each pupil likely absent?

```python
def predict_attendance(
    pupil_df: pd.DataFrame,
    school_id: int,
    schedule_config: dict,
    arrival_window_minutes: int = 60
) -> pd.DataFrame:
    """
    Predict attendance for each school day based on morning activity patterns.

    Parameters
    ----------
    pupil_df : pd.DataFrame
        Processed epoch data for one pupil (columns: timestamp, enmo_mg, context)
    school_id : int
        School ID (1-6), used to look up the school start time
    schedule_config : dict
        Loaded school schedule configuration
    arrival_window_minutes : int
        Minutes around school start time to look for an arrival activity burst

    Returns
    -------
    pd.DataFrame
        Columns: date | predicted_present | confidence | arrival_time_detected
    """
```

**Algorithm:**

```
For each school day in the pupil's measurement window:
  1. Extract epochs in the window [school_start - 60min, school_start + 30min]
  2. Look for a sustained activity burst (≥3 consecutive epochs with ENMO > 50 mg)
  3. If burst found → predicted_present = True, confidence = "high"
  4. If only single-epoch peaks → predicted_present = True, confidence = "low"
  5. If no activity above threshold → predicted_present = False, confidence = "high"
  6. Special case: if the entire day is non-wear → predicted_present = False, confidence = "certain"
```

**Output columns:**

| Column | Type | Description |
|---|---|---|
| pupil_id | string | 4-digit ID |
| date | date | School day |
| predicted_present | bool | Model prediction |
| confidence | string | `high`, `low`, `certain` |
| arrival_time_detected | time or NaT | Time of detected arrival burst |
| researcher_override | bool or None | Set via UI; None until reviewed |
| final_status | string | `present`, `absent`, or `unknown` |

---

### `utils.py`

Shared utilities used by analysis modules:

```python
def load_pupil_data(parquet_path: str) -> pd.DataFrame:
    """Load a single pupil's processed parquet file."""

def load_all_pupils(processed_dir: str, school_id: int = None) -> pd.DataFrame:
    """Load all processed pupil files, optionally filtered by school."""

def load_schedule_config(config_path: str = "config/school_schedules.yaml") -> dict:
    """Load and validate the school schedule config."""

def epoch_to_minutes(df: pd.DataFrame, group_cols: list) -> pd.DataFrame:
    """Convert 1-second epoch counts to minutes for a grouped summary."""
```

---

## Pre/post comparison (RQ6)

This analysis is built on top of the individual modules above:

```r
#' Compare activity, sedentary time, and sleep between meting 1 and meting 2
#'
#' @param processed_dir Path to processed data (must contain both meting_1/ and meting_2/ subfolders)
#' @return List with: paired_summary, effect_sizes, plots
compare_pre_post <- function(processed_dir = "data/processed/")
```

**Notes:**
- Only include pupils with valid data in both measurement periods
- Use paired comparisons (same pupil, two time points)
- Report effect sizes (Cohen's d) alongside p-values
- School 3 and 4 schedule uncertainty should be noted in results

---

## Acceptance criteria

Before moving to Phase 4, verify:

- [ ] `compute_activity_totals()` produces sensible in-class sedentary totals (e.g. ~150–200 min/day for a full school day)
- [ ] `detect_sedentary_bouts()` correctly identifies a manually-traced bout in a test pupil
- [ ] `summarise_sleep()` returns expected sleep durations (7–10 hours for primary school children)
- [ ] `predict_attendance()` correctly identifies the 3–5 manually inserted absent days in dummy data
- [ ] All outputs load correctly in the Shiny app (Phase 4)
- [ ] All outputs are exportable as CSV

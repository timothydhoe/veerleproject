# Full Pipeline Overview — Veerle's Old Thigh-Sensor Programme

This document covers the complete pipeline in `oud_programma/1_general.R` and its helper scripts (from the wetransfer folder). The pipeline was built for **Axivity thigh-worn sensors** recording `.cwa` files.

---

## Schematic Overview

Two tracks run in parallel and then converge into the main analysis block.

```
folder_raw/{part}.cwa
        │
        ├─────────────────────────────────────────────────────┐
        │                                                     │
        ▼  Track A: Activity Classification                   ▼  Track B: GGIR / ENMO
        │                                                     │
[resam_bound_callib()]                              [GGIR::g.part1()]
resample_boundaries_calibration.R                  called in 1_general.R (~line 99)
        │                                                     │
        ▼                                                     ▼
folder_axi/{part}.Rds                       folder_ggi/output_1_raw/meta/basic/
(calibrated accelerometer data)             (GGIR internal .RData files)
        │                                                     │
        ▼                                                     ▼
[generate_activity_features()]              [enmo_nonwear_to_min()]
generate_activity_features.R               enmo_nonwear.R
        │                                                     │
        ▼                                                     ▼
folder_fea/{part}.rds                       row-bound across all participants
(~60 features per 5-sec window)                              │
        │                                                     ▼
        ▼                                   folder_enm/enmo_nonwear_per_minute.Rds
[predict_AT()]                              (ENMO + nonwear score per minute)
predict_AT.R + model.rf.thigh.rds
        │
        ▼
folder_pre/{part}.Rds
(features + predicted activity_type)
        │
        ▼
[rbind_5s()]
rbind_5s.R
        │
        ▼
folder_bout/Activity_type_bout_per_5s.Rds
(all participants, 5-sec resolution)
        │
        └──────────────────────┬──────────────────────────────┘
                               │
                               ▼
                   1_general.R — Main Analysis Block
                   (lines 139–984)
                               │
               ┌───────────────┼───────────────┐
               ▼               ▼               ▼
   folder_agg/          folder_sec_all/   folder_agg_bout/
   activity_per_         PA_per_5sec       PA_per_bout
   schoolday             .Rds/.sav/.csv    .Rds/.sav
   .Rds/.sav
   (day-level)          (5s-level)         (bout-level)
```

---

## Step-by-Step Runthrough

---

### Step 1 — Calibration

**Script:** `resample_boundaries_calibration.R` — function `resam_bound_callib()`  
**Called from:** `1_general.R` lines 60–67 (now commented out — run once)

**Input:** `folder_raw/{part}.cwa`  
Raw binary Axivity sensor file per participant.

**What happens:**
- Reads the `.cwa` file using `GGIRread::readAxivity()`
- Computes calibration parameters (offset and scale per axis) using `GGIR::g.calibrate()`, which fits a sphere to stationary periods to correct for sensor drift. Saves parameters to avoid recomputing.
- Applies the calibration: `x_calibrated = (x - offset) * scale` for each axis

**Output:**
- `folder_cal/{part}.rds` — calibration parameters (cached for reuse)
- `folder_axi/{part}.Rds` — calibrated raw accelerometer data at original sample rate

---

### Step 2 — Feature Extraction

**Script:** `generate_activity_features.R` — function `generate_activity_features()`  
**Called from:** `1_general.R` lines 73–79 (now commented out — run once)

**Input:** `folder_axi/{part}.Rds`  
Calibrated accelerometer data.

**What happens:**
- Resamples to 100 Hz via linear interpolation if the device recorded at a different rate
- Applies three Butterworth filters to the signal:
  - **Noise filter** (0.5 Hz low-pass): removes high-frequency noise
  - **Gravity filter** (0.02 Hz low-pass): isolates the static gravity component
  - **Peak filter** (0.06 Hz low-pass): used for step/peak detection
- Groups data into 5-second windows
- Computes ~60 features per window:

| Feature group | Features |
|---|---|
| Temporal (gravity-filtered) | Mean, SD, 25th/50th/75th percentile, min, max — for X, Y, Z, and vector magnitude |
| Orientation | Roll, pitch, yaw — mean and SD |
| Spectral (FFT) | Dominant frequency and power for X, Y, Z, and vector magnitude |
| Peaks | Minimum peak count across X, Y, Z |
| Distribution | Kurtosis, skewness — per axis |
| Correlations | Pearson correlations between axis pairs (XY, XZ, YZ) |
| Covefficient of variation | SD/mean per axis and vector magnitude |
| Sensor | Mean temperature, battery leel, light |

**Output:** `folder_fea/{part}.rds`  
One row per 5-second window, ~60 feature columns.

---

### Step 3 — Activity Classification

**Script:** `predict_AT.R` — function `predict_AT()`  
**Called from:** `1_general.R` lines 90–92 (now commented out — run once)

**Input:**
- `folder_fea/{part}.Rds` — feature data per participant
- `RF_models_kids_PA_type/model.rf.thigh.rds` — pre-trained Random Forest model

**What happens:**
- Loads the feature data and runs it through the Random Forest model
- Adds a predicted `activity_type` column to the data

**Activity types:** `Sitting`, `Lying`, `Standing`, `Walking`, `Running`, `Cycling`

**Output:** `folder_pre/{part}.Rds`  
Feature data with `activity_type` column added.

---

### Step 4 — Combine All Participants

**Script:** `rbind_5s.R` — function `rbind_5s()`  
**Called from:** `1_general.R` lines 132–134 (now commented out — run once)

**Input:** `folder_pre/{part}.Rds` for every participant

**What happens:**
- Drops incomplete minutes (requires exactly 12 observations per minute = 12 × 5s)
- Defines **observation days** as 3:00 AM to 3:00 AM (avoids midnight split issues and handles daylight saving time)
- Creates `start_obs_day` and `end_obs_day` timestamps per day per participant
- Strips all feature columns — keeps only: `pid`, `timestamp`, `activity_type`, `obs_day`, `start_obs_day`, `end_obs_day`
- Row-binds all participants into a single dataset

**Output:** `folder_bout/Activity_type_bout_per_5s.Rds`  
Single file with 5-second activity data for all participants.

---

### Step 5 — GGIR Part 1 (parallel to Track A)

**Script:** `1_general.R` lines 99–101 (now commented out — run once)

**Input:** `folder_raw/` — all `.cwa` files

**What happens:**
- Runs `GGIR::g.part1()` on all raw files
- Applies autocalibration (same sphere-fitting as Step 1, but GGIR's own implementation)
- Computes ENMO at 1-second epochs (`metashort`)
- Detects non-wear periods at 15-minute resolution (`metalong`) using low SD across axes as the signal

**Output:** `folder_ggi/output_1_raw/meta/basic/{part}.RData`  
GGIR internal format containing:
- `M$metashort` — ENMO per second
- `M$metalong` — non-wear scores per 15-minute window

---

### Step 6 — ENMO and Non-Wear Extraction

**Script:** `enmo_nonwear.R` — function `enmo_nonwear_to_min()`  
**Called from:** `1_general.R` lines 106–121 (now commented out — run once)

**Input:** `folder_ggi/output_1_raw/meta/basic/{part}.RData`

**What happens:**
- Reads `M$metashort`: extracts 1-second ENMO values, averages them to 1-minute resolution
- Reads `M$metalong`: maps each 15-minute non-wear score to all minutes within that window
- Returns a data table with one row per participant-minute

**Output:** Row-bound across all participants, saved to:  
`folder_enm/enmo_nonwear_per_minute.Rds`  
Columns: `pid`, `timestamp_minute`, `ENMO`, `nonwearscore`

---

### Step 7 — Main Analysis (`1_general.R` lines 139–984)

This is the section that actually runs (not commented out). It takes the outputs of both tracks and produces the final research outputs.

---

#### 7a — Load Data

**Input:**
- `folder_bout/Activity_type_bout_per_5s.Rds` — 5s activity predictions
- `folder_adm/Dataset_Scholen.sav` — school schedules (observation windows, lesson timetables)
- `folder_adm/Dataset_Afwezigheden.sav` — student absence records
- `folder_adm/Databestand_Slaap.sav` — sleep detection (bed time / wake time)
- `folder_adm/Dataset_Leerlingen.sav` — student-reported non-wear periods
- `folder_enm/enmo_nonwear_per_minute.Rds` — GGIR ENMO and non-wear scores

---

#### 7b — Context Tagging

For each 5-second row, checks whether the timestamp falls within known time windows and adds boolean flags:

| Column | Meaning |
|---|---|
| `during_observation` | Research team was present at the school |
| `during_school_hours` | Within the school day (start to end bell) |
| `during_class_1` … `during_class_7` | Within a specific lesson period |
| `absent` | Student was recorded as absent |
| `sleep_axivity` | Within detected sleep window → overwrites `activity_type` to `'Sleeping'` |
| `nonwear_reported` | Student reported device was off |

---

#### 7c — Merge ENMO and Non-Wear

- Matches each 5-second row to its minute-level ENMO and non-wear score
- Rows with no GGIR data (start/end of recording, calibration artefacts) get `activity_type = NA`
- Combines detected and reported non-wear into a single flag: `nonwear_unique = 1` if either is true
- Sleep overrides non-wear (if sleeping, non-wear flags are cleared)
- Any row with `nonwear_unique == 1` or `during_observation == 0` gets `activity_type = NA`

---

#### 7d — Location Flags

Four mutually exclusive location labels are assigned to each valid row:

| Column | Condition |
|---|---|
| `at_school_activity` | Wearing device + during observation + during school hours + not absent |
| `in_class_activity` | As above + within at least one lesson period |
| `out_class_activity` | As above + not within any lesson period (recess, lunch, etc.) |
| `out_school_activity` | Wearing device + during observation + outside school hours (or absent) |

---

#### 7e — Sitting Bout Detection

A bout is a continuous unbroken stretch of sitting or lying.

- Identifies transitions into and out of sitting/lying
- Numbers each bout sequentially per participant per measurement wave (`bout_nummer_sitting`)
- Calculates bout duration in **minutes** — using `.N / 12` since there are 12 five-second epochs per minute
- For bouts that span a school boundary (e.g. a sitting bout that starts in class and continues into recess), calculates the time within each location separately:
  - `bout_time_sitting_exclusive_school`, `bout_time_sitting_exclusive_in_class`, `bout_time_sitting_exclusive_out_class`, `bout_time_sitting_exclusive_outside`

---

#### 7f — Bout Categorisation

Sitting bouts are classified into six duration bins:

| Variable suffix | Duration |
|---|---|
| `_0_1` | < 1 minute |
| `_1_4` | 1–4 minutes |
| `_5_9` | 5–9 minutes |
| `_10_19` | 10–19 minutes |
| `_20_29` | 20–29 minutes |
| `_30` | ≥ 30 minutes |

For each bin × location combination (total, at school, in class, out of class, elsewhere):
- **Number of bouts** per participant per day
- **Total time** in those bouts per participant per day

---

#### 7g — Day-Level Aggregation

Sums up time in each activity type per participant per day, separately per location:

- **Total** (all valid wear time during observation)
- **At school** (school hours, present, wearing device)
- **In class** (lesson periods)
- **Out of class** (school hours but between lessons)
- **Elsewhere** (outside school hours)

For each location: total observed time, mean ENMO, and minutes in each activity type (Sitting, Lying, Standing, Walking, Running, Cycling, Sleeping).

All sub-summaries are joined into a single wide table `sum_act_per_day`.

---

#### 7h — Write Outputs

Three datasets are saved:

| File | Location | Content |
|---|---|---|
| `activity_per_schoolday.Rds` / `.sav` | `folder_agg/` | One row per participant per day — all activity summaries and bout counts |
| `PA_per_5sec.Rds` / `.sav` / `.csv` | `folder_sec_all/` | One row per 5-second epoch — all context flags, activity type, ENMO, nonwear |
| `PA_per_bout.Rds` / `.sav` | `folder_agg_bout/` | One row per sitting bout — duration, location, bout category |

---

## Folder Reference

| Variable | Path (on Veerle's machine) | Contents |
|---|---|---|
| `folder_raw` | `E:/Eigen versie/1_raw/` | Raw `.cwa` Axivity files |
| `folder_cal` | `E:/Eigen versie/0_calibrated/` | Calibration parameter cache |
| `folder_axi` | `E:/Eigen versie/1_axivity_prep/` | Calibrated accelerometer data |
| `folder_ggi` | `E:/Eigen versie/1_gpart_meta/` | GGIR Part 1 output |
| `folder_fea` | `E:/Eigen versie/2_features/` | 5-second feature matrices |
| `folder_pre` | `E:/Eigen versie/3_activity_type_pred/` | RF activity predictions |
| `folder_bout` | `E:/Eigen versie/4_activity_type_5s_bout/` | Combined 5s data (all participants) |
| `folder_enm` | `E:/Eigen versie/4_enmo_nonwear_minute/` | ENMO + non-wear per minute |
| `folder_sec_all` | `E:/Eigen versie/4_all_by_5sec/` | Final 5s data with all tags |
| `folder_agg` | `E:/Eigen versie/5_activity_type_complete/` | Day-level summary output |
| `folder_agg_bout` | `E:/Eigen versie/6_activity_type_complete_by_bout/` | Bout-level output |
| `folder_adm` | `E:/Eigen versie/0_admin/` | SPSS admin files (schedules, absences, sleep) |

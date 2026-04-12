# Phase 2 — GGIR Pipeline (R)

> Core R processing pipeline built on top of the GGIR package. Takes raw GENEActiv files and produces clean, labelled, per-epoch output ready for analysis.

---

## Goal

Produce a modular, reproducible R pipeline that:
- Converts `.bin` files to `.csv` automatically
- Runs GGIR processing (ENMO, calibration, sleep, non-wear)
- Labels every epoch with a school-context tag
- Applies validity filtering
- Exports to a shared format (parquet/CSV) for the analysis layer

---

## GGIR background

GGIR is an open-source R package developed for processing raw accelerometer data. It wraps a series of validated signal-processing algorithms into a single pipeline with 5 parts:

| GGIR Part | What it does |
|---|---|
| Part 1 | Read raw data, auto-calibrate, compute ENMO, export epoch-level summaries |
| Part 2 | Detect and flag non-wear time; compute physical activity metrics per day |
| Part 3 | Identify sustained inactivity bouts (used for sleep window detection) |
| Part 4 | Detect sleep onset and offset; compute sleep duration and efficiency |
| Part 5 | Generate summary reports per person |

The SchoolMoves pipeline uses Parts 1, 2, and 4 directly. Parts 3 and 5 are optional but recommended for the full run.

**Package reference:** van Hees et al., GGIR: Raw Accelerometry Data Analysis. CRAN. https://CRAN.R-project.org/package=GGIR

---

## Pipeline architecture

```
Input: data/raw/meting_1/*.bin  (or .csv)
         │
         ▼
  01_convert.R
  └── .bin → standardised .csv (GGIR Part 1 file reader)
         │
         ▼
  02_ggir_process.R
  └── GGIR Parts 1–4: ENMO, calibration, non-wear, sleep
         │
         ▼
  03_classify_activity.R
  └── Apply ENMO cut-points → intensity label per epoch
         │
         ▼
  04_label_schedule.R
  └── Join school schedule config → context label per epoch
         │
         ▼
  05_filter_validity.R
  └── Apply 4-day / 5-night validity rules → flag per pupil
         │
         ▼
  06_export.R
  └── Write to data/processed/<pupil_id>.parquet
         │
         ▼
Output: data/processed/ (one parquet per pupil)
```

---

## Module specifications

### `01_convert.R`

**Purpose:** Ensure all input files are in the CSV format GGIR expects, regardless of whether the originals are `.bin` or `.csv`.

```r
#' Convert GENEActiv files to standardised CSV
#'
#' @param input_dir Path to folder containing raw .bin or .csv files
#' @param output_dir Path to write converted CSV files
#' @param overwrite Logical. If TRUE, re-convert existing files. Default FALSE.
#' @return Invisible data.frame with conversion log (file, status, message)
convert_to_csv <- function(input_dir, output_dir, overwrite = FALSE)
```

Notes:
- `.csv` files that already match the GENEActiv format are copied directly
- `.bin` files are read with `GENEAread::read.bin()` and exported
- A conversion log is written to `logs/conversion_log.csv`

---

### `02_ggir_process.R`

**Purpose:** Run GGIR Parts 1–4 on all converted CSV files.

```r
#' Run GGIR pipeline on a directory of GENEActiv CSV files
#'
#' @param input_dir Path to standardised CSV files
#' @param output_dir Path for GGIR output (will be created if absent)
#' @param ggir_config List of GGIR configuration parameters (see details)
#' @param n_cores Number of parallel cores. Default 1.
#' @return Invisible path to GGIR output directory
run_ggir <- function(input_dir, output_dir, ggir_config = default_ggir_config(), n_cores = 1)
```

**Key GGIR configuration parameters:**

```r
default_ggir_config <- function() {
  list(
    # Epoch length
    epochvalues2 = c(1, 60),         # 1-second and 1-minute epochs

    # Activity cut-points (mg) — Hildebrand et al. wrist, children
    threshold.lig = 56.3,
    threshold.mod = 191.6,
    threshold.vig = 695.8,

    # Non-wear detection
    nonWearEdge = 60,                 # 60-minute blocks
    nonWearWindow = 15,               # assessed every 15 min
    nonWearStd = 13,                  # mg threshold for std
    nonWearRange = 50,                # mg threshold for range

    # Sleep detection
    anglethreshold = 5,               # degrees arm angle change
    timethreshold = 5,                # minutes sustained
    ignorenonwear = TRUE,

    # Output
    do.report = c(2, 4),
    save_ms2 = TRUE,
    save_ms2summary = TRUE,

    # Wrist-specific
    acc.metric = "ENMO",
    do.cal = TRUE,                    # auto-calibration
    sensor.location = "wrist"
  )
}
```

---

### `03_classify_activity.R`

**Purpose:** Add an `intensity` column to the epoch-level GGIR output.

```r
#' Classify ENMO values into activity intensity levels
#'
#' @param epochs data.frame with at least columns: pupil_id, timestamp, enmo_mg
#' @param thresholds Named numeric vector: c(sedentary=56.3, light=191.6, moderate=695.8)
#' @return Same data.frame with added column `intensity` (factor)
classify_intensity <- function(epochs, thresholds = default_thresholds())
```

Cut-points applied (mg):
- `sedentary`:  ENMO < 56.3
- `light`:     56.3 ≤ ENMO < 191.6
- `moderate`:  191.6 ≤ ENMO < 695.8
- `vigorous`:  ENMO ≥ 695.8

---

### `04_label_schedule.R`

**Purpose:** Add a `context` column by looking up the school schedule for each epoch.

```r
#' Label epochs with school context
#'
#' @param epochs data.frame with columns: pupil_id, timestamp
#' @param schedule_config Path to school_schedules.yaml
#' @return Same data.frame with added columns: context, schedule_source
label_school_context <- function(epochs, schedule_config = "config/school_schedules.yaml")
```

Context values: `in_class`, `recess`, `lunch`, `before_school`, `after_school`, `weekend`, `unknown`

Schools with missing timetable data (Schools 3 and 4) use the fallback schedule and get `schedule_source = "fallback"`.

---

### `05_filter_validity.R`

**Purpose:** Assess and flag each pupil's validity status.

```r
#' Apply validity criteria per pupil
#'
#' @param epochs data.frame with columns: pupil_id, timestamp, wear, sleep, pct_night_valid
#' @param min_valid_days_waking Minimum valid-day count for sedentary analysis. Default 4.
#' @param min_valid_hours_waking Minimum valid waking hours per day. Default 9.
#' @param min_valid_nights_sleep Minimum valid-night count for sleep analysis. Default 5.
#' @param min_pct_night_valid Minimum % of night with valid data. Default 50.
#' @return data.frame with per-pupil validity flags and exclusion reason
assess_validity <- function(epochs,
                            min_valid_days_waking = 4,
                            min_valid_hours_waking = 9,
                            min_valid_nights_sleep = 5,
                            min_pct_night_valid = 50)
```

Output includes:
- `pupil_valid_sedentary`: TRUE/FALSE
- `pupil_valid_sleep`: TRUE/FALSE
- `n_valid_days`: integer
- `n_valid_nights`: integer
- `exclusion_reason`: human-readable string or NA

---

### `06_export.R`

**Purpose:** Write the final processed dataset to the shared format used by the analysis layer.

```r
#' Export processed epoch data to parquet
#'
#' @param epochs data.frame — full processed epoch dataset
#' @param output_dir Path to write parquet files (one per pupil)
#' @param format One of "parquet" or "csv". Default "parquet".
#' @return Invisible vector of output file paths
export_processed <- function(epochs, output_dir = "data/processed/", format = "parquet")
```

---

## Master pipeline script

`R/pipeline/run_pipeline.R`

```r
# Run the full SchoolMoves pipeline
# Usage: Rscript run_pipeline.R --input data/raw/meting_1 --output data/processed/meting_1

source("R/pipeline/01_convert.R")
source("R/pipeline/02_ggir_process.R")
source("R/pipeline/03_classify_activity.R")
source("R/pipeline/04_label_schedule.R")
source("R/pipeline/05_filter_validity.R")
source("R/pipeline/06_export.R")

run_full_pipeline <- function(input_dir, output_dir, config = "config/school_schedules.yaml") {
  log_info("Starting SchoolMoves pipeline")
  log_info("Input:  {input_dir}")
  log_info("Output: {output_dir}")

  csv_dir  <- convert_to_csv(input_dir, file.path(output_dir, "csv"))
  ggir_dir <- run_ggir(csv_dir, file.path(output_dir, "ggir"))
  epochs   <- load_ggir_output(ggir_dir)
  epochs   <- classify_intensity(epochs)
  epochs   <- label_school_context(epochs, config)
  validity <- assess_validity(epochs)
  epochs   <- epochs |> left_join(validity, by = "pupil_id")

  export_processed(epochs, output_dir)
  write_validity_report(validity, output_dir)

  log_info("Pipeline complete. {nrow(validity)} pupils processed.")
  invisible(validity)
}
```

---

## Dependencies

```r
# R packages (pin versions with renv)
library(GGIR)       # >= 3.0
library(GENEAread)  # for .bin reading
library(arrow)      # parquet support
library(dplyr)
library(lubridate)
library(yaml)
library(logger)
library(glue)
```

Initialise `renv` at project start:
```r
renv::init()
renv::snapshot()  # after installing all packages
```

---

## Acceptance criteria

Before moving to Phase 3, verify:

- [ ] Pipeline runs end-to-end on dummy data without errors
- [ ] ENMO values match manual calculation for 3–5 sample epochs
- [ ] Non-wear periods in dummy data are correctly detected
- [ ] Context labels are correct for a sample of epochs from each school
- [ ] Validity filter correctly excludes the ~10% invalid dummy pupils
- [ ] Parquet output loads correctly in both R and Python

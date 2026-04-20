# How `project_1/` Works

A single reference that walks through every pipeline step, shows the data flow, and lists files that are redundant and safe to remove.

Every step has two parts:
- **Plain language** — what happens in this step and why, for a non-technical reader.
- **Technical** — exact file, functions, inputs, outputs. For a developer.

---

## 1. Purpose

`project_1/` takes raw wrist-worn accelerometer files (from GENEActiv devices worn by schoolchildren) and turns them into per-pupil summaries of physical activity, sleep, and school-context time use (in-class, recess, lunch, etc.). The heavy lifting is done by the R package [GGIR](https://cran.r-project.org/package=GGIR); the pipeline wraps GGIR with school-specific labelling, validity checks, and exports.

---

## 2. Data flow at a glance

```
 config/pipeline_params.yaml ──┐
 config/school_schedules.yaml ─┤
                               ▼
 data/raw/*.bin|*.csv ──► [1] 01_prepare_input.R ──► data/processed/ggir_input/
                                                              │
                                                              ▼
                          [2] 02_run_ggir.R ──► data/processed/ggir/output_*/
                                                              │
                                                              ▼
                          [3] 03_read_ggir_output.R ──► in-memory ggir_data list
                                                              │
                                      ┌───────────────────────┼───────────────────────┐
                                      ▼                       ▼                       ▼
                          [4] 04_label_schedule.R   [5] 05_filter_validity.R    R/analysis/*.R
                                      │                       │                       │
                                      └────────────┬──────────┘                       │
                                                   ▼                                  │
                                      [6] 06_export.R ◄─────────────────────────────┘
                                                   │
                          ┌────────────────────────┼───────────────────────┐
                          ▼                        ▼                       ▼
              analysis/activity_totals.csv  sleep_summary.csv        validity_report.csv
                                                   │
                                                   ▼
                          [7] python/analysis/attendance_prediction.py
                                                   │
                                                   ▼
                          logs/pipeline_summary.txt + attendance outputs
```

The two YAML files at the top drive everything. The researcher edits only those two files; the rest is code.

---

## 3. Entry points

There are three ways to start a run. In practice only the first two matter.

| Entry point | File | What it does |
|-------------|------|--------------|
| Python launcher | [project_1/run_pipeline.py](../../project_1/run_pipeline.py) | Primary entry point. Loads YAML, optionally applies overrides, calls the R pipeline via `Rscript`, then runs the Python attendance step, then writes `logs/pipeline_summary.txt`. |
| R launcher (CLI) | [project_1/R/pipeline/run_pipeline.R](../../project_1/R/pipeline/run_pipeline.R) | Orchestrator — sources all step files and calls `run_full_pipeline()`. Can also be run directly: `Rscript R/pipeline/run_pipeline.R --input … --output …`. |
| Legacy test script | [project_1/test_with_example.R](../../project_1/test_with_example.R) | Development artifact. Still sources archived files — see [§6 Redundant files](#6-redundant-files). |

---

## 4. Step-by-step walkthrough

### Orchestrator — `run_full_pipeline()`

**Plain language.** The master function that runs the whole show. It reads the config, prepares the input files, calls GGIR, reads GGIR's output back, labels time-of-day context, checks validity, runs the analysis functions, and writes the outputs. If called with `use_ggir = FALSE` or no GGIR-compatible files are present, it falls back to a "legacy bypass" path that classifies pre-computed ENMO directly (no GGIR). In day-to-day use, the default GGIR path is the one that runs.

**Technical.**
- **File:** [project_1/R/pipeline/run_pipeline.R](../../project_1/R/pipeline/run_pipeline.R)
- **Key function:** `run_full_pipeline(input_dir, output_dir, config_path, schedule_path, use_ggir = TRUE, n_cores = 1)`
- **Reads:** `config/pipeline_params.yaml`, `config/school_schedules.yaml`, files in `input_dir`.
- **Writes:** everything under `output_dir/` (see subsequent steps).
- **CLI flags:** `--input`, `--output`, `--config`, `--schedule`, `--no-ggir`, `--cores`.

---

### Shared utilities — `utils.R`

**Plain language.** Small helper functions used by every step: loading the YAML, loading optional SPSS `.sav` admin files (absences, sleep times), writing the validity report, and logging progress to the console.

**Technical.**
- **File:** [project_1/R/pipeline/utils.R](../../project_1/R/pipeline/utils.R)
- **Key functions:**
  - `read_pipeline_params(config_path)` — returns a named list of all pipeline params.
  - `read_sav_metadata(sav_dir)` — optionally loads `Dataset_Scholen.sav`, `Dataset_Afwezigheden.sav`, `Databestand_Slaap.sav`, `Dataset_Leerlingen.sav`. Requires the `haven` package.
  - `write_validity_report(validity, output_dir)` — writes `validity_report.csv` into `output_dir`.
  - `log_step(msg)` — timestamped console log.

---

### Step 1 — Prepare input

**Plain language.** Looks at the folder of raw files and figures out what kind of file each one is: a GENEActiv `.bin`, a "real" GENEActiv CSV (with the 100-row header), or a pre-processed epoch CSV (e.g. Tim's files). The first two can be processed by GGIR directly; the third cannot, and is routed to a legacy path. The step also copies/links files into a clean `ggir_input/` folder and builds a manifest so later steps know which pupil each file belongs to.

**Technical.**
- **File:** [project_1/R/pipeline/01_prepare_input.R](../../project_1/R/pipeline/01_prepare_input.R)
- **Key functions:**
  - `prepare_input(input_dir, output_dir, overwrite)` — returns a list with `manifest` (data.frame), `ggir_input_dir`, `bypass_files`.
  - `detect_format(filepath)` — returns `"geneactiv_bin"`, `"geneactiv_csv"`, or `"preprocessed_csv"`.
  - `extract_pupil_id_from_file(filepath)` — parses the 4-digit pupil code from the filename (first digit = school ID).
- **Reads:** files under `input_dir`.
- **Writes:** `output_dir/ggir_input/` with GGIR-compatible files.

---

### Step 2 — Run GGIR (Parts 1–5)

**Plain language.** Calls GGIR with the parameters from `pipeline_params.yaml`. GGIR does all of the real accelerometer processing in five parts:
1. Load raw data, autocalibrate (when possible), compute ENMO and angle metrics.
2. Detect non-wear periods and classify each epoch into sedentary / light / moderate / vigorous using the Hildebrand cut-points.
3. Find sustained inactivity bouts (candidate sleep periods).
4. Detect sleep with the HDCZA algorithm.
5. Produce a time-use analysis broken down by day-segments (the `qwindow`, see Step 4).

The `qwindow` is built automatically from all unique start/end times across every school in `school_schedules.yaml`, so GGIR's Part 5 already produces per-segment numbers.

> **Autocalibration caveat.** Autocalibration (sphere-fitting on stationary periods) requires raw samples. When the input is pre-converted epoch CSVs rather than `.bin`, GGIR cannot sphere-fit and ENMO values rely on the values as-provided. This is a known trade-off in the CSV path.

**Technical.**
- **File:** [project_1/R/pipeline/02_run_ggir.R](../../project_1/R/pipeline/02_run_ggir.R)
- **Key function:** `run_ggir(input_dir, output_dir, params, schedule_path = NULL, n_cores = 1)`
- **Config keys consumed:** `ggir_mode`, `do_calibration`, `acc_metric`, `epoch_lengths`, `desiredtz`, `threshold_lig/mod/vig`, `qwindow_strategy`, `sleep_algorithm`, `save_ms5rawlevels`, `save_ms5raw_without_invalid`, `boutdur_mvpa/in/lig`, `do_report`.
- **Writes:** `output_dir/ggir/output_<datadir>/` with the standard GGIR tree: `meta/basic/`, `meta/ms2.out/` … `meta/ms5.out/`, `meta/ms5.outraw/`, `results/*.csv`, `results/QC/`, `config.csv`.

---

### Step 3 — Read GGIR output

**Plain language.** GGIR writes its results to a folder tree of CSVs and RData files. This step parses the important ones back into tidy R data.frames so the rest of the pipeline can use them.

**Technical.**
- **File:** [project_1/R/pipeline/03_read_ggir_output.R](../../project_1/R/pipeline/03_read_ggir_output.R)
- **Key functions:**
  - `find_ggir_output_dir(output_base)` — locates the `output_<datadir>/` subfolder.
  - `read_part2_daysummary(ggir_dir)` — reads `results/part2_daysummary.csv`.
  - `read_part4_sleep(ggir_dir)` — reads `results/part4_nightsummary_sleep_cleaned.csv`.
  - `read_part5_daysummary(ggir_dir)` — reads `results/part5_daysummary_*.csv`.
  - `load_all_ggir_output(ggir_dir)` — convenience wrapper returning `list(part2_daysummary, part4_sleep, part5_daysummary)`.
- **Reads:** the GGIR output directory from Step 2.
- **Writes:** nothing on disk. Returns an in-memory list.

---

### Step 4 — Label school context

**Plain language.** Converts the school timetables in `school_schedules.yaml` into two things: (a) a `qwindow` vector of decimal-hour boundaries for GGIR to use (this is fed into Step 2), and (b) a lookup table mapping each qwindow segment back to a context label (`in_class`, `recess`, `lunch`, `before_school`, `after_school`). When Step 2 runs, GGIR splits every day at those boundaries, so we just attach labels after the fact. Weekends are handled automatically by day-of-week.

**Technical.**
- **File:** [project_1/R/pipeline/04_label_schedule.R](../../project_1/R/pipeline/04_label_schedule.R)
- **Key functions:**
  - `build_qwindow_from_schedules(schedule_path)` → numeric vector of decimal hours (sorted, bounded by `[0, 24]`).
  - `build_qwindow_context_map(schedule_path, qwindow)` → data.frame `(school_id, segment_start, segment_end, context)`.
  - `load_school_schedules(config_path)` → raw list of schools from the YAML.
  - `label_school_context(epochs, schedule_config)` → epoch-level fallback labeller (legacy bypass only).
  - `extract_school_id(pupil_id)` → first digit of the 4-digit pupil code.
- **Reads:** `config/school_schedules.yaml`.
- **Writes:** nothing on disk; returns R objects that Step 2 (qwindow) and Step 6 (context map) consume.

---

### Step 5 — Validity filtering

**Plain language.** Decides which pupils have enough good data to be included. A pupil is "valid for sedentary analysis" if they wore the device at least N hours per day on at least M days. "Valid for sleep analysis" is a separate criterion based on number of nights with sufficient coverage. The thresholds live in the config.

**Technical.**
- **File:** [project_1/R/pipeline/05_filter_validity.R](../../project_1/R/pipeline/05_filter_validity.R)
- **Key functions:**
  - `assess_validity_from_ggir(part2_daysummary, part4_sleep, params)` — primary path; reads GGIR's own validity columns.
  - `assess_validity(epochs, params)` — epoch-level fallback for the legacy bypass.
  - `extract_pupil_from_ggir_col(x)` — strips the pupil ID out of GGIR's filename column.
- **Config keys consumed:** `min_valid_days_waking`, `min_valid_hours_per_day`, `min_valid_nights_sleep`, `min_pct_night_valid`.
- **Returns:** data.frame with `pupil_id`, `n_valid_days`, `n_valid_nights`, `pupil_valid_sedentary`, `pupil_valid_sleep`, `exclusion_reason`.
- **Writes:** `data/processed/validity_report.csv` (via `write_validity_report()` from utils).

---

### Step 6 — Export

**Plain language.** Writes the summary tables to disk, in either CSV or Parquet depending on the config.

**Technical.**
- **File:** [project_1/R/pipeline/06_export.R](../../project_1/R/pipeline/06_export.R)
- **Key functions:**
  - `export_processed(epochs, output_dir, format)` — one file per pupil (legacy bypass).
  - `export_summary(df, filepath, format)` — a single summary file.
  - `export_ggir_summaries(...)` — convenience wrapper for the GGIR path.
- **Config keys consumed:** `output_format` (`csv` or `parquet`).
- **Writes:**
  - `data/processed/analysis/activity_totals.csv`
  - `data/processed/analysis/sleep_summary.csv`
  - `data/processed/validity_report.csv`

---

### Analyses (`R/analysis/`)

These run after Step 3 and feed Step 6. Each corresponds to a research question (RQ) in the study plan.

| File | Plain language | Key function | Inputs | Output |
|------|----------------|--------------|--------|--------|
| [activity_totals.R](../../project_1/R/analysis/activity_totals.R) | Per pupil, per day, per context: how many minutes sedentary / light / moderate / vigorous. | `compute_activity_totals_ggir(part5_daysummary, context_map)` | GGIR Part 5 + context map | data.frame consumed by Step 6 → `activity_totals.csv` |
| [sleep_analysis.R](../../project_1/R/analysis/sleep_analysis.R) | Per pupil, per night: onset, offset, duration. | `summarise_sleep_ggir(part4_sleep)` | GGIR Part 4 | data.frame → `sleep_summary.csv` |
| [sedentary_bouts.R](../../project_1/R/analysis/sedentary_bouts.R) | Detects sustained sedentary (or other-intensity) bouts via run-length encoding; splits at context boundaries. | `detect_activity_bouts(epochs, min_bout_min, target_intensity)` | Epoch-level data | data.frame of bouts |
| [school_correlations.R](../../project_1/R/analysis/school_correlations.R) | Exploratory (N=6): correlates lesson-block duration with in-class sedentary minutes. | `analyse_school_correlations(activity_totals, schedule_config)` | Activity totals + schedule YAML | List `(correlation_table, model_summary, correlation)` |

---

### Step 7 — Attendance prediction (Python)

**Plain language.** Once the R side is done, the Python script looks at each pupil's morning activity in a window around the school start time. If it sees a clear burst of movement (a "commute spike") it flags the pupil as present. Researchers can override the prediction per pupil/day. The output is a presence table per school day.

**Technical.**
- **Files:**
  - [project_1/python/analysis/attendance_prediction.py](../../project_1/python/analysis/attendance_prediction.py)
  - [project_1/python/analysis/utils.py](../../project_1/python/analysis/utils.py)
- **Key function:** `predict_attendance(pupil_df, school_id, schedule_config, params)` — scans ENMO in the ±60 min window around `school_start`.
- **Reads:** per-pupil processed files from Step 6, `config/school_schedules.yaml`, `config/pipeline_params.yaml`.
- **Writes:** attendance table + entries in `logs/pipeline_summary.txt`.

> **Note on Python scope.** `CLAUDE.md` states that Python is "deferred". That was accurate for the earlier plan, but `run_pipeline.py` and `python/analysis/` are live in `project_1/` and actively called. Treat this note in `CLAUDE.md` as out of date; the Python attendance step is a real part of the current pipeline.

---

## 5. Configuration

Two YAML files, both researcher-editable, both at `project_1/config/`:

### [pipeline_params.yaml](../../project_1/config/pipeline_params.yaml)

All numeric knobs. Grouped into: I/O paths, ENMO cut-points (Hildebrand wrist/children), GGIR settings (epochs, calibration, sleep algorithm, qwindow strategy, bout durations), validity criteria, output format. A researcher should never have to edit an `.R` or `.py` file — every tunable parameter lives here.

### [school_schedules.yaml](../../project_1/config/school_schedules.yaml)

Per-school timetables. For each school: a `school_id`, `schedule_source` (`confirmed` or `fallback`), `school_start`, `school_end`, and a list of `blocks` (each with `context`, `start`, `end`). The qwindow in Step 2 and the context labels in Step 4 are derived entirely from this file. Weekends are implicit (day-of-week).

---

## 6. Redundant files

All paths below are relative to `project_1/`. Each row lists a file/folder that is not part of the live pipeline, why, and what to do. The "safe to delete" label assumes `test_with_example.R` is also removed or rewritten — see the row for it.

| Path | Status | Why | Recommendation |
|------|--------|-----|----------------|
| [R/pipeline/_archive/01_convert.R](../../project_1/R/pipeline/_archive/01_convert.R) | Orphaned (superseded by `01_prepare_input.R`) | Not sourced by `run_pipeline.R`; only referenced by `test_with_example.R`. | **Delete** once `test_with_example.R` is updated or removed. |
| [R/pipeline/_archive/02_ggir_process.R](../../project_1/R/pipeline/_archive/02_ggir_process.R) | Orphaned (superseded by `02_run_ggir.R`) | Same — only referenced by `test_with_example.R`. | **Delete** (same caveat). |
| [R/pipeline/_archive/03_classify_activity.R](../../project_1/R/pipeline/_archive/03_classify_activity.R) | Orphaned (replaced by GGIR Part 2 cut-point classification) | Same. | **Delete** (same caveat). |
| [test_with_example.R](../../project_1/test_with_example.R) | Legacy dev test. Sources the three archived files above. | Not called by `run_pipeline.py` or `run_pipeline.R`; breaks if the archive is removed. | **Delete or rewrite** against the live pipeline. If you keep it, move it under a `tests/` folder and update its `source()` calls. |
| [data/dummy/](../../project_1/data/dummy/) | Empty placeholder. | Referenced nowhere. | **Delete.** |
| [notebooks/01_test_bin_pipeline.Rmd](../../project_1/notebooks/01_test_bin_pipeline.Rmd) | Standalone exploratory notebook. | Not sourced by the pipeline. | **Keep** — useful for QC. Note in the README that notebooks are standalone. |
| [notebooks/02_test_csv_pipeline.Rmd](../../project_1/notebooks/02_test_csv_pipeline.Rmd) | Same. | Same. | **Keep.** |
| [notebooks/03_comparison_old_vs_new.Rmd](../../project_1/notebooks/03_comparison_old_vs_new.Rmd) | Same; compares old vs new pipeline output. | Same. | **Keep** while the rebuild is still being validated. Can be retired once the new pipeline is fully trusted. |
| `python/` at **repo root** (outside `project_1/`) | Vestigial per `CLAUDE.md` note. | Distinct from the live `project_1/python/`. | **Flag for deletion** — confirm contents first. |

"What breaks if you delete this?" — only `test_with_example.R` has a real dependency on the archived files. Everything else in the list is dead weight.

---

## 7. Known gotchas

- **Autocalibration is off for CSV input.** Sphere-fitting needs raw samples. ENMO from pre-converted epoch CSVs is not sphere-fit. Revisit when `.bin` files are available.
- **`CLAUDE.md` vs reality on Python.** `CLAUDE.md` says Python is deferred; in `project_1/` it isn't. Either treat `CLAUDE.md` as outdated on this point, or update it to reflect that Python is live for the attendance step.
- **`test_with_example.R` sources `_archive/`.** If the archive is deleted without updating this file, running it will fail. Prefer deleting both together.
- **qwindow strategy.** If `qwindow_strategy: "auto"` but `school_schedules.yaml` is missing, GGIR falls back to a full-day window `[0, 24]` — Part 5 then produces only one segment per day. Check the log for the `"qwindow from schedules:"` line to confirm the derived boundaries.
- **Pupil ID convention.** First digit of the 4-digit filename = school ID (1–6), remaining three digits = pupil (001–…). Meting 1 and meting 2 files share the same name and are kept in separate folders.

# Developer Guide — SchoolMove

The Developer's Guide for working on this project. Covers the workflow,
what's built, and all the tools available to you.

> **Location note:** This file lives in `r/`. Paths below are relative to `r/` unless
> stated otherwise. `config.yaml` is one level up at the repo root (`../config.yaml`).

---


## Mental model

The project has one job: take accelerometer CSV files → run GGIR → label school context
→ show results in Shiny. Everything else (config, QC) supports that loop.

```
../config.yaml                          ← all parameters live here
        ↓
pipeline/01_run_ggir.R                  ← GGIR Parts 1–5 for each meting
        ↓
../data/processed/
  meting_1/output_meting_1/results/     ← Part 2, 4, 5 CSVs
  meting_2/output_meting_2/results/
        ↓
pipeline/02_label_segments.R            ← map GGIR output to school-day segments
        ↓
../data/segment_summary.csv             ← one level above data/processed/ (see note)
        ↓
pipeline/03_build_summaries.R           ← join all outputs, compute validity flags
        ↓
../data/analysis_ready.csv
../data/validity_summary.csv
        ↓
shiny/                                  ← Dashboard
```

> **Path note:** `config.yaml` sets `data_processed: "../data/processed"`. Steps 02 and 03
> write their output to `file.path(data_processed, "..")` = `../data/` — one directory
> above `data/processed/`, not inside it. The GGIR output itself lands inside
> `data/processed/meting_N/output_meting_N/` (no intermediate `ggir/` subdirectory).
> All scripts and Shiny resolve to the same paths; this is consistent but differs from
> what some older documentation shows.

Orchestrate the full pipeline with `pipeline/run_all.R`.

---

## Workflow

### Starting a session

1. Open `r/SchoolMove.Rproj` in RStudio — working directory is set automatically
2. Open Claude Code in the repo root
3. Run `/blocker-check` to remind yourself where things stand

### Making changes

| What you want to change | Where to do it |
|-------------------------|----------------|
| Pipeline parameters, cut-points, schedules | `../config.yaml` only — never hardcode in `.R` files |
| GGIR pipeline logic | `pipeline/01_run_ggir.R` |
| Segment labeling logic | `pipeline/02_label_segments.R` |
| Summary building / validity flags | `pipeline/03_build_summaries.R` |
| Shared GGIR file readers | `pipeline/utils_ggir.R` |
| Input format detection / manifest | `pipeline/utils_input.R` |
| Sedentary bout detection | `pipeline/utils_bouts.R` |
| Config schema validation | `pipeline/validate_config.R` |
| Dashboard layout / tabs | `shiny/ui.R` |
| Dashboard reactive logic | `shiny/server.R` |
| Shared data loading and helpers | `shiny/global.R` |
| Post-step QC checks | `qc/qc_01_ggir.R`, `qc_02_segments.R`, `qc_03_summaries.R` |
| Package dependencies | Add to `install.R`, then run `renv::snapshot()` in R |

### Testing locally

```r
# 1. Make sure ../config.yaml has dev.example_mode: true  (it does by default)
# 2. Run the full pipeline on dummy data
source("pipeline/run_all.R")

# 3. Run QC checks for each step
source("qc/qc_01_ggir.R")
source("qc/qc_02_segments.R")
source("qc/qc_03_summaries.R")

# 4. Launch the dashboard
shiny::runApp("shiny")
```

Or use the Claude Code `/run-qc` and `/pipeline-status` commands to check state
without opening RStudio.

---

## What's built

| Component | Status | Notes |
|-----------|--------|-------|
| `../config.yaml` | Done | All 6 schools, measurement dates, confirmed schedules, cut-points |
| `pipeline/validate_config.R` | Done | Runtime schema validation; called by run_all.R and global.R |
| `pipeline/utils_input.R` | Done | Format detection, pupil ID extraction, input manifest writer |
| `pipeline/utils_ggir.R` | Done | Version-tolerant GGIR output readers (handles filename variations) |
| `pipeline/utils_bouts.R` | Done | Context-aware sedentary bout detection via RLE on epoch data |
| `pipeline/01_run_ggir.R` | Done | GGIR Parts 1–5 for both metingen; dev overrides wired up |
| `pipeline/02_label_segments.R` | Done | Distributes GGIR output across 5 school-day segments per participant × day |
| `pipeline/03_build_summaries.R` | Done | Joins parts 2/4/5 + segments; computes validity flags; writes analysis-ready tables |
| `pipeline/run_all.R` | Done | Orchestrates 01→02→03 with config validation, manifest, and run log |
| `qc/qc_01_ggir.R` | Done | Verifies GGIR output structure, columns, participant counts, cut-points |
| `qc/qc_02_segments.R` | Done | Verifies segment coverage, fallback schools, data-schedule match |
| `qc/qc_03_summaries.R` | Done | Verifies inclusion counts, MVPA/sleep distributions, cut-points |
| `shiny/global.R` | Done | Loads config, all processed data, profile system, shared helpers and theme |
| `shiny/ui.R` | Done | 7 tabs: Overzicht, Deelnemers, Schooldag, Slaap, Vergelijking, Export, Instellingen |
| `shiny/server.R` | Done | All tabs implemented: reactive filters, plots, downloads, report generation |
| Hooks | Done | GDPR guard, config guard, R syntax check — all active |
| Commands | Done | 6 slash commands available |

---

## Pipeline Architecture

### GGIR Parts 1–5 → script mapping

| GGIR Part | What it does | Script that triggers it | Key output |
|-----------|-------------|------------------------|------------|
| Part 1 | Load CSV data; compute ENMO + anglez from x/y/z; aggregate to epochs | `01_run_ggir.R` | `meta/*.RData` milestone files |
| Part 2 | Non-wear detection; cut-point classification (SB/LPA/MPA/VPA); day summaries; qwindow segment columns | `01_run_ggir.R` | `part2_daysummary.csv` |
| Part 3 | Rest period estimation for sleep detection | `01_run_ggir.R` | `meta/*.RData` |
| Part 4 | Sleep detection (HDCZA algorithm); night summaries | `01_run_ggir.R` | `part4_nightsummary_sleep_cleaned.csv` |
| Part 5 | Full behavioral timeline; waking-window (WW) bout summaries; person summaries | `01_run_ggir.R` | `part5_personsummary_WW_*.csv` |

GGIR manages Part 1–5 sequencing internally. Intermediate milestone `.RData` files in `meta/` allow re-runs to skip already-completed parts when `overwrite: false`.

### Parameter flow: `config.yaml` → `GGIR()`

| `config.yaml` key | R variable | GGIR argument | Notes |
|-------------------|-----------|---------------|-------|
| `ggir.cut_points_mg.sedentary_to_light` | `cp$sedentary_to_light` | `threshold.lig` | 56.3 mg — Hildebrand 2014 |
| `ggir.cut_points_mg.light_to_moderate` | `cp$light_to_moderate` | `threshold.mod` | 191.6 mg |
| `ggir.cut_points_mg.moderate_to_vigorous` | `cp$moderate_to_vigorous` | `threshold.vig` | 695.8 mg |
| `ggir.qwindow` | `qwindow_val` | `qwindow` | manual or auto-derived from schedules |
| `ggir.maxNcores` | `max_cores` | `maxNcores`, `do.parallel` | `do.parallel = max_cores > 1` |
| `ggir.overwrite` | — | `overwrite` | milestone caching control |
| `output.timezone` | — | `desiredtz` | `"Europe/Brussels"` |
| `dev.nonwear_approach` | `nonwear_approach` | `nonwear_approach` | see note below |
| `dev.includedaycrit` | `includedaycrit` | `includedaycrit` | GGIR Part 2 valid-hour threshold |
| `dev.includedaycrit_part5` | `includedaycrit_part5` | `includedaycrit.part5` | GGIR Part 5 valid-fraction threshold |
| *(hardcoded)* | — | `HASPT.algo = "HDCZA"` | wrist-validated for children; van Hees 2015 |
| *(hardcoded)* | — | `anglethreshold = 5` | degrees — HDCZA parameter |
| *(hardcoded)* | — | `timethreshold = 5` | minutes — HDCZA parameter |
| *(hardcoded)* | — | `boutdur.in = c(10,20,30)` | sedentary bout thresholds |
| *(hardcoded)* | — | `rmc.sf = 1` | 1 Hz pre-epoched CSV (not raw 100 Hz) |
| *(hardcoded)* | — | `rmc.firstrow.acc = 101` | 100-row GENEActiv metadata header |
| *(hardcoded)* | — | `rmc.col.acc = 2:4` | x/y/z in g |
| *(hardcoded)* | — | `idloc = 2` | full filename as participant ID |

**`nonwear_approach` note:** The 2023 GGIR non-wear algorithm resamples to 5 Hz
internally. This collapses all variance in 1 Hz dummy CSV data → every epoch flagged
as non-wear. For dummy data (`example_mode: true`), this must be `"2013"`. For real
`.bin`/`.cwa` data (100 Hz), remove the setting entirely.

### Implicit assumptions

| Assumption | Where it matters | Risk if violated |
|-----------|-----------------|-----------------|
| GGIR participant ID column is `ID` (not `id`) and includes `.csv` extension | `extract_school_id()` strips `.csv`; class-override map key lookup strips `.csv` | Different format → silent wrong school assignment or missed override (see P1 in AUDIT.md) |
| Part 2 column `N valid hours` (with spaces) | `setnames()` normalises to `n_valid_hours` | Different name → NA validity flags |
| Part 4 sleep duration column is named `SleepDurationInSpt` or `sleep_dur*` | `dur_col <- grep(...)` in step 03 | Wrong column → incorrect sleep_duration_h |
| Part 5 personsummary has one row per participant (not per qwindow segment) | Step 03 aggregates by `(ID, school, meting)` | Multiple rows → inflated averages |
| GGIR output subdir is named `output_<datadir_basename>` | `find_ggir_output_subdir()` searches for `^output_` | Different prefix → NULL results dir |
| qwindow suffixes in Part 2 column names match `paste0(qw_start, ".", qw_end)` | `02_label_segments.R:200` | Mismatch → silent fallback to proportional approximation (see P9 in AUDIT.md) |

### Known edge cases

**Single-file upload vs batch:** GGIR processes all files in `datadir` as a batch.
Single-file runs work identically. The `n_files` check in step 01 skips empty directories
rather than erroring.

**GGIR fails mid-pipeline:** GGIR throws an R error that propagates up through `source()`
in `run_all.R` and halts the pipeline. Steps 02 and 03 do not run. The partial GGIR
output in `meta/` is preserved, so a re-run with `overwrite: false` resumes from the
last completed milestone.

**Empty or unexpected output CSVs:** Steps 02 and 03 use `tryCatch()` / `NULL` guards
around file reads. Missing files produce NULL; `rbindlist(Filter(Negate(is.null), ...),
fill = TRUE)` tolerates any combination of present/absent metingen. An empty `analysis_ready`
causes Shiny tabs to render empty rather than crashing.

**Class override key mismatch (AUDIT.md P1):** The `pupil_override_map` lookup in
`02_label_segments.R:357` uses `row$ID` directly. GGIR IDs include `.csv`; map keys do
not. Fix: `sub("\\.csv$", "", basename(as.character(row$ID)))` before the lookup.

**MVPA column ambiguity (AUDIT.md P3):** With `boutdur.in = c(10,20,30)`, Part 5 may
contain `dur_day_MVPA_bts_10_min_pla`, `dur_day_MVPA_bts_20_min_pla`, and
`dur_day_total_MVPA_min_pla`. `grep("MVPA", ...)` picks the first alphabetically. Pin
to an explicit column name once actual GGIR output has been inspected.

---

## Pipeline scripts in detail

### `pipeline/validate_config.R`

Runtime schema validation for `config.yaml`. Called at the top of `run_all.R` and
`shiny/global.R`. Checks:

- Required top-level sections present (`paths`, `ggir`, `validity`, `schedules`, `dev`)
- Cut-points are positive and strictly increasing (SB < LPA < MPA)
- Wear time values are in-range (1–24 h, ≥1 valid day)
- Schedule times are valid HH:MM, break boundaries respect school hours

Reports errors (stops execution) and warnings (continues). Safe for non-interactive
batch and Shiny contexts.

---

### `pipeline/01_run_ggir.R`

Runs GGIR Parts 1–5 for `meting_1` and `meting_2` independently. Key decisions:

- **Data source:** `dev.example_mode: true` → `../data/example/dummy_data/`; otherwise `../data/raw/`
- **qwindow strategy:** Auto mode extracts all unique bell-time boundaries from
  `cfg$schedules` (ensures GGIR produces per-window columns for step 02); manual mode
  uses `cfg$ggir$qwindow`
- **CSV reading:** Uses `read.myacc.csv` via the `rmc.*` parameter family — GENEActiv
  native CSV reading was deprecated in GGIR 2.6-4. Header is 100 rows; data columns:
  timestamp (col 1), x/y/z (cols 2–4 in g). Autocalibration disabled (`do.cal=FALSE`)
  because pre-converted CSVs lack the raw signal needed for sphere-fitting.
- **Sleep algorithm:** HDCZA (van Hees 2015), `anglethreshold=5°`, `timethreshold=5min`
- **Bouts:** Sedentary bouts at `boutdur.in=[10,20,30]` min
- **Dev overrides:** `nonwear_approach`, `includedaycrit`, `includedaycrit.part5` active
  only in example mode — remove before running on real data (see config section below)

---

### `pipeline/02_label_segments.R`

Applies school schedule context to GGIR Part 2 day summaries. For each participant × day:

- Identifies the school (first digit of pupil ID) and looks up its schedule from config
- Builds per-segment time intervals: `before_school`, `in_class`, `recess`, `lunch`,
  `after_school` (weekdays); `weekend` (Saturday/Sunday)
- If GGIR produced per-qwindow columns (requires `qwindow` set in step 01), activity is
  distributed proportionally by time overlap. If qwindow columns are absent, falls back
  to proportional day-level approximation.
- Schools with `fallback: true` in config are flagged in output and in QC 02.

Output: `../data/segment_summary.csv` — one row per participant × day × segment.

---

### `pipeline/03_build_summaries.R`

Joins all GGIR parts with segment labels and computes validity flags.

**Validity flags (per participant × meting):**

| Flag | Logic |
|------|-------|
| `n_valid_days` | Days where `N valid hours ≥ min_wear_hours_per_day` |
| `meets_sedentary_criteria` | `n_valid_days ≥ min_valid_days` AND (if `require_weekend_day`) `has_weekend` |
| `meets_sleep_criteria` | `n_valid_nights ≥ min_nights` (Part 4 primary; Part 5 SPT fallback) |
| `exclusion_reason` | First failing criterion, for transparent reporting |

**Activity aggregation:** Maps GGIR Part 5 column names to standardised names
(`mvpa_min_day_avg`, `sb_min_day`, `lpa_min_day`). Handles GGIR column naming variation
across versions via `utils_ggir.R`.

**Context-aware bouts:** Calls `compute_context_bout_summaries()` from `utils_bouts.R`
if `labeled_epochs.csv` exists (epoch-level data). Otherwise uses GGIR-native
day-level bout columns.

Outputs:
- `../data/analysis_ready.csv` — one row per participant × meting
- `../data/validity_summary.csv` — inclusion/exclusion subset

---

### `pipeline/utils_bouts.R`

Context-aware sedentary bout detection using run-length encoding on epoch-level data.

- `detect_activity_bouts()`: RLE on `"intensity|context"` — bouts split at segment
  boundaries so a sitting bout that spans from `in_class` to `recess` is counted separately
- `compute_context_bout_summaries()`: Aggregates to wide format with columns like
  `bouts_30min_in_class_n`, `bouts_30min_in_class_total_min`

Requires one row per 1-second epoch with `ID`, `date`, `context`, `intensity`, `wear`
columns. When epoch data isn't available, step 03 falls back to GGIR-native columns.

---

## QC scripts

Run after each pipeline step. Output `[PASS]` / `[WARN]` / `[FAIL]` per check.

| Script | Checks |
|--------|--------|
| `qc/qc_01_ggir.R` | Results dirs exist, required files present, correct columns, participant counts, cut-points match config |
| `qc/qc_02_segments.R` | segment_summary exists, all segments present for school days, fallback schools flagged, data-schedule mismatches |
| `qc/qc_03_summaries.R` | Inclusion/exclusion counts per meting and school, MVPA/sleep distributions, cut-points match config |

Use the `/run-qc` slash command for a plain-language summary of QC output.

---

## Shiny dashboard

### global.R

Loads everything the dashboard needs at startup:

- Reads `../config.yaml`, validates it, merges the active profile from `profiles/*.yaml`
- Loads `analysis_ready.csv`, `validity_summary.csv`, Part 2 day summaries, Part 4 sleep,
  `segment_summary.csv` (adds Dutch labels and translations)
- Defines shared constants: `MIN_WEAR_H`, `MIN_DAYS`, `NEED_WKND`, `WHO_MVPA_MIN=60`,
  `WHO_SLEEP_MIN_H=8`, `ZONE_COLORS` (SB grey, LPA cyan, MVPA blue)
- Defines `theme_schoolmove()` — Atlassian-inspired minimal aesthetic
- Defines `extract_school_id(id)` (first digit → `school_N`) and version-tolerant
  `load_ggir()` wrappers

### ui.R — 7 tabs

| Tab | Purpose |
|-----|---------|
| **Overzicht** | KPI ribbon, MVPA dumbbell M1→M2 per school, school summary table, auto-generated rapport |
| **Deelnemers** | Participant explorer, MVPA-per-day plot, activity-per-segment chart, wear heatmap, inclusion/exclusion table |
| **Schooldag** | Activity by segment (single zone or full budget), MVPA during recess, weekday profile, sedentary bouts |
| **Slaap** | Sleep KPIs, duration/efficiency violin, Bland-Altman M1 vs M2 agreement |
| **Vergelijking** | Longitudinal slopegraph + Wilcoxon stats; correlation scatter + school/participant comparison tables |
| **Export** | CSV download buttons for all processed outputs |
| **Instellingen** | Profile manager; validity, cut-point, and bout-threshold overrides |

Global navbar filters (school, meting) apply across all tabs; meting filter is hidden
on the Vergelijking tab.

Reusable UI helpers (defined in `ui.R`; also duplicated in `global.R` as a startup bug-fix — see UX debt section):
- `chart_card()` — wraps plots in a card with optional PNG download button
- `kpi_strip_card()` — compact icon + title + value KPI display
- `tip()` — tooltip with info icon
- `fallback_banner()` — yellow warning for unconfirmed school schedules

### server.R

Key helpers:
- `mvpa_col_name()` — reactive: detects correct MVPA column name (GGIR naming varies)
- `apply_global_filters(dt, school_col, meting_col)` — applies navbar selectors to any data.table
- `png_dl(plot_expr, filename_stem, ...)` — standardised PNG download handler
- `safe_meting()` — handles NULL global_meting on Vergelijking tab

Notable reactive patterns:
- KPI cards are clickable and navigate to the relevant detail tab
- Rapport samenvatting (Tab 1) is auto-generated text from the data; copy-to-clipboard via client-side JS
- Deelnemers explorer populates from either a dropdown or clicking a row in the inclusion table
- Vergelijking runs Wilcoxon signed-rank tests per school; reports Δ with 95% CI and rank-biserial effect size

**Why the "Run Pipeline" button does not run GGIR:**
The button (`btn_run_pipeline`) shows a modal with terminal instructions rather than
calling GGIR directly. This is intentional: GGIR Parts 1–5 on the full 400-participant
dataset can run for 30–60 minutes. A synchronous call inside Shiny would block the
entire R process, freezing the UI until completion and preventing any other interaction.
Do not "fix" this by adding a `system()` or `callr::r()` call in the server — the
correct approach for a future async pipeline trigger would be `ExtendedTask` (Shiny
1.8.1+) or `promises` + a separate R background process.

### Module inventory

| Module file | Module ID | Responsibility | Returns |
|-------------|-----------|----------------|---------|
| `modules/mod_overview.R` | `"overview"` | KPI ribbon, MVPA dumbbell per school, school summary table, auto-generated rapport | nothing |
| `modules/mod_participants.R` | `"participants"` | Per-pupil MVPA/segment explorer, wear heatmap, inclusion/exclusion table | nothing |
| `modules/mod_schoolday.R` | `"schoolday"` | Activity by segment, recess MVPA, weekday profile, sedentary bout chart | nothing |
| `modules/mod_sleep.R` | `"sleep"` | Sleep duration/efficiency KPIs, violin plot, Bland-Altman M1 vs M2 | nothing |
| `modules/mod_comparison.R` | `"comparison"` | Meting 1 vs 2 slopegraph, delta plot, Wilcoxon stats, correlation scatter | nothing |
| `modules/mod_export.R` | `"export"` | 11 download handlers: GGIR parts 2 & 5, segment summary, analysis-ready, validity, filtered variants, manifests | nothing |
| `modules/mod_settings.R` | `"settings"` | Profile manager, validity/cut-point/bout overrides, absence registry | `reactiveValues(profile_activated, absence_changed)` |

### Shared list (server.R → modules)

All module server functions receive a `shared` list. Contents:

| Key | Type | Description |
|-----|------|-------------|
| `shared$apply_filters(dt, school_col, meting_col)` | function | Wraps `apply_global_filters_pure()` with session input values |
| `shared$mvpa_col()` | reactive | Detects correct MVPA column name from `analysis_ready` |
| `shared$global_school_val()` | reactive | Current school filter value (`"all"` or a school label) |
| `shared$safe_meting_val()` | reactive | Current meting filter; defaults to `"all"` on Vergelijking tab |
| `shared$cfg` | list | Parsed `config.yaml` (static, loaded at startup) |
| `shared$cfg_path` | character | Resolved path to `config.yaml` (used by mod_settings for profile activation) |
| `shared$segment_summary` | data.table | From `02_label_segments.R` |
| `shared$analysis_ready` | data.table | From `03_build_summaries.R` |
| `shared$validity_summary` | data.table | From `03_build_summaries.R` |
| `shared$part2` | data.table | GGIR Part 2 day summaries |

### Utility functions (`utils/`)

**`utils/util_filters.R`**

| Function | Pure | Description |
|----------|------|-------------|
| `extract_school_id(id)` | ✓ | First digit of participant code → `"school_N"` |
| `apply_global_filters_pure(dt, school_val, meting_val, school_col, meting_col)` | ✓ | Filter a data.table by school and meting values |
| `metric_col_pure(metric, dt, mvpa_col)` | ✓ | Resolve metric selector string to column name |
| `metric_label(metric)` | ✓ | Dutch display label for metric selector |
| `rb_effect_label(r)` | ✓ | Verbal label for rank-biserial effect size |

**`utils/util_plots.R`**

| Function / constant | Pure | Description |
|---------------------|------|-------------|
| `no_data_plot(msg)` | ✓ | Returns a minimal ggplot with a centred message (used when data is absent) |
| `png_dl(plot_expr, filename_stem, width, height, dpi)` | ✓ | Standardised Shiny download handler factory for PNG exports |
| `theme_schoolmove(legend_pos)` | ✓ | Shared ggplot2 theme (Atlassian neutrals, UGent blue accent) |
| `ZONE_COLORS` | — | Named character vector: SB → grey, LPA → cyan, MVPA → UGent blue |

---

## UI Architecture

### Startup loading order

Shiny evaluates files in this order: `global.R` → `ui.R` → `server.R`. Functions must be defined before the file that calls them is evaluated.

```
global.R          ← defines constants, loads data, UI helpers, module functions
    ↓
ui.R              ← calls modOverviewUI(), modParticipantsUI(), etc. + defines page layout
    ↓
server.R          ← calls mod_overview_server(), etc. (modules already defined)
```

**Critical constraint:** Module UI functions (`modOverviewUI`, `modParticipantsUI`, etc.) and the four reusable UI helpers (`chart_card`, `kpi_strip_card`, `tip`, `fallback_banner`) must all be available in the global environment by the time `ui.R` runs. This means they must be sourced in `global.R`, not `server.R`.

Currently, `global.R` sources the modules and re-defines the helpers as a startup bug-fix (added during UX review — see UX_REVIEW.md U0). The permanent fix is to move these to a dedicated `shiny/utils/ui_helpers.R` file and source it in `global.R`.

### CSS and theming

All custom CSS lives in the `app_css` block at the top of `ui.R`. Key conventions:

| Class | Purpose |
|-------|---------|
| `.kpi-strip` | 82px KPI card with icon + label + value |
| `.kpi-nav-card` | Clickable wrapper: hover lift, focus ring |
| `.pipeline-bar` | Top-of-Overzicht pipeline trigger row |
| `.readiness-strip` | Coloured status checks below navbar |
| `.readiness-strip .check-ok/warn/miss` | Green / amber / red check items |
| `#schoolday-seg_view` | Custom segmented button for zone toggle |

Theme: `bs_theme(version=5, bg="#e9f0fa", primary="#1E64C8")`. Heading font: Source Sans 3 (Google). No component library beyond bslib.

### School filter data flow

The global school filter uses `SCHOOL_LABELS`, defined in `global.R` as:
```r
SCHOOL_LABELS <- setNames(paste("School", seq_along(schools)), schools)
# names = "school_1", ...; values = "School 1", ...
```

**Known bug (UX_REVIEW.md U1):** In `selectInput(choices = c("Alle scholen" = "all", SCHOOL_LABELS))`, Shiny displays the **names** ("school_1") and sends the **values** ("School 1") as `input$global_school`. The `school` column in data is "school_1", so the filter never matches. Fix: swap names/values in the `choices` argument:
```r
choices = c("Alle scholen" = "all", setNames(names(SCHOOL_LABELS), SCHOOL_LABELS))
```

---

## UX Debt

All issues identified during the UX review (2026-05-04, full history in `UX_REVIEW.md`)
are resolved as of the 2026-07-11 bundle-readiness pass: U0–U3 and U5 were already fixed
in the code; U4, U6, U7, and U8 were fixed in that pass (misleading pipeline-duration
wording, internal step references leaking into user-facing messages, English DataTables
fallback text, and the redundant chart subtitle, respectively). `UX_REVIEW.md`'s U9
(pupil-ID dropdown showing raw filenames) was also fixed in the same pass. No open UX
debt is currently tracked here — if new issues are found, log them in this section.

---

## GGIR output structure

```
../data/processed/
  meting_1/
    output_meting_1/          ← GGIR names this from the datadir basename
      meta/                   ← intermediate milestone files (.RData)
      results/
        part2_daysummary.csv
        part2_summary.csv
        part4_nightsummary_sleep_cleaned.csv  (or _full.csv, version-dependent)
        part5_daysummary_WW_L56.3M191.6V695.8_T5A5.csv
        part5_personsummary_WW_L56.3M191.6V695.8_T5A5.csv
      config.csv              ← GGIR's own parameter record (archived to logs/)
  meting_2/
    output_meting_2/results/  (same structure)
```

Note: `01_run_ggir.R` now uses `do.report = c(2, 4, 5)` (Part 4 was added — the
sleep night-summary CSV and `visualisation_sleep.pdf` are both now produced;
this doc previously said `c(2, 5)`, which was stale).

Part 5 filenames embed the cut-point values (`L56.3M191.6V695.8`) and HDCZA parameters
(`T5A5` = timethreshold 5, anglethreshold 5). `utils_ggir.R` finds them with regex
patterns so the exact filename doesn't need to be hardcoded anywhere.

### Key Part 2 columns

| Column | Meaning |
|--------|---------|
| `ID` | Filename stem (e.g. `1001.csv`) — first digit = school, last 3 = pupil |
| `N valid hours` | Hours classified as worn that day |
| `N hours` | Total hours in the day window |
| `calendar_date` | Date |
| `weekday` | Day name |

### Key Part 5 columns

| Column | Meaning |
|--------|---------|
| `dur_day_total_IN_min` | Sedentary (SB) minutes — waking day |
| `dur_day_total_LIG_min` | Light PA (LPA) minutes |
| `dur_day_total_MOD_min` | Moderate PA (MPA) minutes |
| `dur_day_total_VIG_min` | Vigorous PA (VPA) minutes |
| `dur_day_MVPA_bts_10_min` | MVPA in bouts ≥10 min |
| `nonwear_perc_day` | % of waking day classified as non-wear |

---

## `config.yaml` — developer reference

Two audiences: sections Veerle edits (`ggir`, `validity`, `schedules`, `measurements`)
and the `dev` section only developers touch.

### `dev` section — when and how to use it

```yaml
dev:
  example_mode: true        # true  → pipeline uses ../data/example/dummy_data/
                            # false → pipeline uses ../data/raw/

  # ⚠ The three settings below exist only for 1 Hz dummy data compatibility.
  # Remove them (or set to null) before running on real 100 Hz participant data.

  nonwear_approach: "2013"  # 2023 default resamples to 5 Hz internally, which
                            # zeros out all variance in 1 Hz signals → everything
                            # flagged as non-wear. "2013" uses the raw signal as-is.

  includedaycrit: 5         # GGIR Part 2: min valid hours/day to count a day.
                            # Production = 16. Dummy data caps out at ~7 h/day.

  includedaycrit_part5: 0.3 # GGIR Part 5: min fraction of waking window that must
                            # be valid. Production = 0.667. Lowered for dummy data.
```

`run_all.R` logs a warning if any override is active. `shiny/global.R` picks up
`includedaycrit` so the dashboard uses the same threshold as GGIR.

**Before switching to real data:**

1. Set `example_mode: false`
2. Remove (or null out) `nonwear_approach`, `includedaycrit`, `includedaycrit_part5`
3. Set `overwrite: false` once the first real run looks good

### Profile system

`profiles/*.yaml` files let you override validity and cut-point parameters without
re-running the pipeline. The active profile is loaded by `shiny/global.R` at startup.
Veerle can switch profiles in the Instellingen tab and save modified versions without
touching `config.yaml` or any `.R` file.

### Activity cut-points

Confirmed by Veerle's protocol (wrist-worn GENEActiv, Hildebrand et al. 2014):

| Intensity | ENMO range |
|-----------|-----------|
| SB (sedentary) | < 56.3 mg |
| LPA (light) | 56.3 – 191.6 mg |
| MPA (moderate) | 191.6 – 695.8 mg |
| VPA (vigorous) | > 695.8 mg |

Set in `../config.yaml` under `ggir.cut_points_mg`, passed to GGIR as
`threshold.lig`, `threshold.mod`, `threshold.vig`.

---

## GENEActiv CSV reading

GENEActiv native CSV reading was deprecated in GGIR 2.6-4. We use `read.myacc.csv`
via the `rmc.*` parameter family. The dummy data (and real data) has a 100-row metadata
header; data starts at row 101. Columns 2–4 are x/y/z (in g), column 1 is the timestamp.

The dummy data was generated at 1 Hz (one row per second). Real device recordings are
100 Hz. Change `rmc.sf` in `01_run_ggir.R` if the real data turns out to be a different
frequency.

The GENEActiv CSV also contains `sdx`, `sdy`, `sdz` columns — within-epoch standard
deviations from the device firmware. These are **not mapped** in the `rmc.*` parameters
and are ignored by GGIR. GGIR computes its own variance metrics from x/y/z directly.

### ENMO vs SVMgs

ENMO is **not computed anywhere in this repo's R code**. Two separate ENMO-like values exist:

| Value | Origin | Used by |
|-------|--------|---------|
| `SVMgs` | Pre-computed by GENEActiv device firmware, stored in the CSV | Not used — GGIR ignores this column |
| GGIR ENMO | Computed internally by GGIR Part 1 from raw x/y/z (√(x²+y²+z²) − 1g) | All downstream pipeline steps (cut-point classification, non-wear, sleep) |

`SVMgs` and GGIR's ENMO are **not identical**: GGIR recomputes from the raw signal and
(when `.bin` files are available) applies autocalibration to correct sensor drift. With
pre-converted CSVs, `do.cal=FALSE` so autocalibration is skipped — ENMO values will have
uncorrected drift. This is an accepted trade-off; revisit if Veerle provides `.bin` files.

---

## Open blockers

| Item | Status | Notes |
|------|--------|-------|
| School 4 timetable | ✅ Resolved | `config.yaml` school_4 is now `fallback: false` (Mon/Tue/Thu/Fri confirmed; Wednesday end time is still a documented estimate — see `docs/data_info/school_info.md`) |
| Real participant data | Pending | Pipeline tested on dummy data and directly against real `.bin`/`.cwa` device files; confirm a full real-scale run has happened before trusting results at 400-participant scale |
| Sleep log availability | Unknown | If children kept a diary, it improves GGIR sleep detection — ask Veerle |

### Pre-production checklist (before switching to real data)

1. `config.yaml` → set `validity.min_wear_hours_per_day: 16`
2. `config.yaml` → set `validity.min_valid_days: 3`
3. `config.yaml` → set `validity.require_weekend_day: true`
4. `config.yaml` → set `validity.min_valid_nights_sleep: 5`
5. `config.yaml` → remove (or null out) `dev.nonwear_approach`, `dev.includedaycrit`, `dev.includedaycrit_part5`
6. Confirm `example_mode: false` (already set)
7. Run `/validate-config` — should report no warnings
8. Run `pipeline/run_all.R`, then all three QC scripts

---

## Claude Code tools

### Slash commands

| Command | What it does |
|---------|-------------|
| `/validate-config` | Checks `../config.yaml` for errors and gaps — run before every pipeline run |
| `/pipeline-status` | Shows what GGIR has processed and what's missing |
| `/run-qc` | Runs QC checks for a pipeline step and summarises output in plain language |
| `/add-schedule` | Converts plain-text timetable info into correct YAML — use when school schedules arrive |
| `/blocker-check` | Produces a meeting-ready summary of open questions for Veerle |
| `/shiny-plan` | Plans a new dashboard feature before any code is written — always run this first |

### Hooks (fire automatically)

| Hook | When | What it does |
|------|------|-------------|
| GDPR guard | Before `git commit` | Blocks commit if `data/raw/` or `data/processed/` files are staged |
| Config guard | After saving `../config.yaml` | Validates YAML syntax + warns about missing values |
| R syntax check | After saving any `.R` file | Catches syntax errors immediately |

Hook scripts are in `../.claude/hooks/` — plain Python, easy to edit.

### MCP server

**context7** is configured and active. Use it to pull up-to-date documentation for any
library without leaving Claude Code:

```
# In a Claude Code message, just ask:
"Check the GGIR docs for the desiredtz parameter"
"Show me how to use bslib's value_box() in Shiny"
```

Key library IDs:
- Shiny → `shiny_posit_co`
- GGIR → `/wadpac/ggir`

---

## Rules

- **Never hardcode a parameter in an `.R` file** — it goes in `../config.yaml`
- **Never commit anything from `data/raw/` or `data/processed/`** — the GDPR hook will stop you, but don't try to bypass it
- **Never introduce Python** unless R/Shiny genuinely can't do it — the architecture decision was deliberate
- **Always run `/shiny-plan` before adding a new Shiny feature** — keeps tabs consistent and avoids rework

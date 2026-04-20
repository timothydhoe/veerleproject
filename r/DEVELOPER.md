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
../data/processed/ggir/
  meting_1/output_meting_1/results/     ← Part 2, 4, 5 CSVs
  meting_2/output_meting_2/results/
        ↓
pipeline/02_label_segments.R            ← map GGIR output to school-day segments
        ↓
../data/processed/segment_summary.csv
        ↓
pipeline/03_build_summaries.R           ← join all outputs, compute validity flags
        ↓
../data/processed/analysis_ready.csv
../data/processed/validity_summary.csv
        ↓
shiny/                                  ← Dashboard
```

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

Output: `../data/processed/segment_summary.csv` — one row per participant × day × segment.

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
- `../data/processed/analysis_ready.csv` — one row per participant × meting
- `../data/processed/validity_summary.csv` — inclusion/exclusion subset

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

Reusable UI helpers in `ui.R`:
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

---

## GGIR output structure

```
../data/processed/ggir/
  meting_1/
    output_meting_1/
      meta/          ← intermediate milestone files (.RData)
      results/
        part2_daysummary.csv
        part2_summary.csv
        part4_nightsummary_*.csv
        part5_daysummary_WW_L56.3M191.6V695.8_T5A5.csv
        part5_personsummary_WW_L56.3M191.6V695.8_T5A5.csv
        visualisation_sleep.pdf
  meting_2/
    output_meting_2/results/  (same structure)
```

Part 5 filenames embed the cut-point values. `utils_ggir.R` finds them with regex
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
| Schools 3 and 4 timetables | ⚠ Fallback | Approximate schedules in config — update when confirmed timetables arrive (use `/add-schedule`) |
| Real participant data | Pending | Pipeline tested on dummy data; ready once `example_mode: false` and dev overrides removed |
| Sleep log availability | Unknown | If children kept a diary, it improves GGIR sleep detection — ask Veerle |

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

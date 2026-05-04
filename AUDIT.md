# SchoolMove — Structural & Code Quality Audit

**Date:** 2026-05-03  
**Reviewer:** External audit (post-refactor review)  
**Scope:** Full `/r` directory — module integrity, reactive hygiene, function quality,
system architecture, data management  
**Codebase state:** 7-module Shiny architecture; pipeline steps 01–03 complete;
dashboard tested on dummy data; real participant data not yet processed

---

## Executive Summary

**No breaking issues found.** All 7 Shiny modules follow the `moduleServer` / `NS()`
pattern correctly. No cross-module `input$` leakage, no GGIR blocking calls inside
the Shiny server, no infinite reactive loops. The architecture is clean and well-suited
to a single-researcher deployment.

Six warnings require attention before the first real-data run. The most consequential
is W1 — the validity thresholds in `config.yaml` are currently at relaxed dummy-data
values that would inflate inclusion rates on real participant data.

---

## 🔴 BREAKING — None

---

## 🟡 WARNINGS

### W1 — `config.yaml` is in relaxed dev-mode; unsafe to run on real data

**File:** `config.yaml` (repo root)

Current values vs. production requirements:

| Setting | Current | Production |
|---------|---------|------------|
| `validity.min_wear_hours_per_day` | 10 | 16 |
| `validity.min_valid_days` | 1 | 3 |
| `validity.require_weekend_day` | false | true |
| `validity.min_valid_nights_sleep` | 1 | 5 |
| `dev.includedaycrit` | 10 | *(remove entirely)* |
| `dev.includedaycrit_part5` | 0.3 | *(remove entirely)* |
| `dev.nonwear_approach` | "2023" | *(remove entirely)* |

**Risk:** Running `01_run_ggir.R` with these values on real 400-participant data would
accept days with as little as 10 waking hours and single-day measurements as valid.
Inclusion rates would be severely inflated, producing scientifically invalid results.

**Note:** `example_mode` is already `false`, which is correct. The dev overrides listed
above are the remaining problem.

**Action required before real data run:**
1. Set `validity.min_wear_hours_per_day: 16`, `min_valid_days: 3`,
   `require_weekend_day: true`, `min_valid_nights_sleep: 5`
2. Remove (or null out) `dev.nonwear_approach`, `dev.includedaycrit`,
   `dev.includedaycrit_part5`

---

### W2 — Hardcoded relative config path in `mod_settings.R`

**File:** `r/shiny/modules/mod_settings.R:325`

```r
cfg_path <- "../../config.yaml"
```

This path is evaluated relative to the R working directory at runtime. When the app is
started correctly with `shiny::runApp("shiny")` from `r/`, the working directory is
`r/shiny/` and the path resolves to `../config.yaml` → correct.

If the app is ever deployed to Shiny Server, `rsconnect`, or launched from a different
directory, this path will silently resolve to the wrong location. The `tryCatch()` on
lines 326 and 331 will catch the failure and show a notification, so there is no silent
data corruption — but the profile activation feature will be non-functional with no
clear diagnostic.

**Recommendation:** Define a resolved `CONFIG_PATH` constant in `global.R` using
`normalizePath()` at startup (where the path is already read correctly) and pass it
via `shared$cfg_path`. Alternatively, document the working-directory assumption
explicitly with a startup assertion.

---

### W3 — `fwrite()` calls for absence CSV have no error handling

**File:** `r/shiny/modules/mod_settings.R:413, 428`

```r
fwrite(dt, absences_path_server)   # line 413 — add absence
fwrite(dt, absences_path_server)   # line 428 — delete absence
```

Both writes use `data.table::fwrite()` directly with no `tryCatch()`. The corresponding
read (`read_absences()` at line 352) does use `tryCatch()`, so only the write path is
unprotected.

**Risk:** A disk-full, permission-denied, or file-locked condition will throw an
unhandled R error inside `observeEvent()`. Shiny will suppress the error silently (the
reactive chain stops), the UI will show the success notification anyway (lines 416–419,
431–432 fire before the crash only if the write succeeds — actually they're after, so
the reactive stops before them). Net effect: the UI shows nothing and the absence
appears to be saved but isn't.

**Recommendation:** Wrap both `fwrite()` calls in `tryCatch()` with an error branch
that sets `output$abs_status_msg` to a visible failure message.

---

### W4 — `rmc.sf = 1` in GGIR call is correct but will mislead future readers

**File:** `r/pipeline/01_run_ggir.R:168`

```r
rmc.sf = 1
```

GGIR defines `rmc.sf` as the sampling frequency (Hz) of the raw input file. The value
`1` is correct here because the input CSVs contain **1-second pre-aggregated epochs**
(the GENEActiv firmware averages 100 raw samples per second before writing to CSV).
However, `CLAUDE.md` describes the device as "100 Hz (raw)" and the script already
has a comment noting that dummy data is 1 Hz. A future developer reading this in
isolation is likely to assume `rmc.sf` should be 100 and "fix" it — breaking GGIR's
internal timeline calculations.

The comment on the nearby `rmc.unit.time` line ("POSIX") already explains the timestamp
format; `rmc.sf` lacks an equivalent note.

**Recommendation:** Add one inline comment:

```r
rmc.sf = 1        # CSVs are pre-aggregated 1-second epochs, not raw 100 Hz samples
```

---

### W5 — School 4 fallback timetable; segment results unreliable until confirmed

**File:** `config.yaml` → `schedules.school_4.fallback: true`

The school 4 timetable was reconstructed from an image and marked `fallback: true`.
QC script `qc_02_segments.R` emits a `[WARN]` for this, and `GEBRUIKERSGIDS.md`
documents the warning. However, the in-dashboard warning mechanism (`fallback_banner()`
defined in `ui.R`) is conditionally rendered.

**Risk:** A researcher who filters to school 4 on the Schooldag or Vergelijking tab
will see segment-level activity breakdowns (`in_class`, `recess`, `lunch`) computed
from approximate time windows — without necessarily seeing the warning if the banner
is not triggered for that specific view.

**Action required:** Confirm the school 4 timetable with Veerle (open blocker).
Until confirmed, verify that `fallback_banner()` is visible on every tab where school
filtering is available when school 4 is selected.

---

### W6 — Context-aware bout metrics silently absent without epoch data

**File:** `r/pipeline/03_build_summaries.R`

`compute_context_bout_summaries()` (from `utils_bouts.R`) requires epoch-level data
in `data/processed/labeled_epochs.csv`. This file is optional — step 02 only produces
it when epoch output is explicitly enabled. When it is absent, step 03 silently skips
the context-aware bout path and falls back to GGIR-native day-level bout columns.

The fallback columns (`bouts_30min_in_class_n`, `bouts_30min_in_class_total_min`, etc.)
will be all NA in `analysis_ready.csv` without any log message to explain why.

**Recommendation:** Add a `message()` at the start of the epoch-fallback branch:

```r
message("[WARN] labeled_epochs.csv not found — context-aware bout columns will be NA.
        To enable these, re-run 02_label_segments.R with epoch output enabled.")
```

---

## 🟢 SUGGESTIONS

### S1 — Four utility functions have description comments but no `@return` / `@param` roxygen

**Files:**
- `r/utils/util_filters.R:62–72` — `metric_label(metric)` — one-line `#'` description,
  no `@param`/`@return`
- `r/utils/util_filters.R:74–81` — `rb_effect_label(r)` — same pattern
- `r/utils/util_plots.R:7` — `no_data_plot(msg)` — one-line `#'` description only
- `r/utils/util_plots.R:31` — `theme_schoolmove(legend_pos)` — one-line `#'` description only

The primary functions (`apply_global_filters_pure`, `metric_col_pure`, `extract_school_id`,
`png_dl`) all have proper roxygen blocks. The four above are the remaining gaps in the
public utility API surface.

---

### S2 — Hardcoded `school_val = "all"` in `mod_schoolday.R:241` lacks a justifying comment

```r
daily <- apply_global_filters_pure(daily, "all", mv)
```

The weekday profile plot intentionally shows all schools regardless of the global school
filter. This is a deliberate design choice (a per-school weekday profile would have too
few data points per cell), but there is no comment explaining it. A future developer
is likely to interpret this as a bug and "fix" it by passing `shared$global_school_val()`.

Add one inline comment on the same line.

---

### S3 — No unit tests for utility functions

`r/tests/` directory exists but is empty. The pure functions in `util_filters.R`
(`apply_global_filters_pure`, `extract_school_id`, `metric_col_pure`) and
`utils_bouts.R` (`detect_activity_bouts`) are directly testable with `testthat` without
any Shiny context. Module behaviour can be covered with `shiny::testServer()`.

Not blocking for the current phase, but adding tests before the first real-data run
would catch regression errors in filtering logic before they affect research outputs.

---

### S4 — Pipeline-not-in-Shiny architectural decision is undocumented

**File:** `r/shiny/server.R:70–96`

The "Run Pipeline" button deliberately shows a modal with terminal instructions
(`Rscript --vanilla r/pipeline/run_all.R`) rather than executing GGIR. This is the
correct design: GGIR can run for 30–60 minutes on the full dataset, and a synchronous
call inside Shiny would block the entire R process, freezing the UI for all connections.

This decision is not documented anywhere. A future contributor is likely to see the
non-functional button and try to "fix" it by calling `system()` or `callr::r()` with a
GGIR call directly in the server. Document the rationale in `DEVELOPER.md`.

---

### S5 — Module files sourced inside `server()` rather than `global.R`

**File:** `r/shiny/server.R:7–14`

All 7 module files are `source()`d inside the `server()` function. This means each new
Shiny session re-parses ~2300 lines of module code. Moving the `source()` calls to
`global.R` would parse module function definitions once at startup, shared across all
sessions.

Low impact for a single-user local deployment (one session at a time). If the app is
ever deployed with multiple concurrent users, this becomes a meaningful inefficiency.

---

## Module Integrity Summary

| Module | NS correct | moduleServer | No input$ leak | Return value |
|--------|-----------|-------------|----------------|--------------|
| `mod_overview.R` | ✓ | ✓ | ✓ | none |
| `mod_participants.R` | ✓ | ✓ | ✓ | none |
| `mod_schoolday.R` | ✓ | ✓ | ✓ | none |
| `mod_sleep.R` | ✓ | ✓ | ✓ | none |
| `mod_comparison.R` | ✓ | ✓ | ✓ | none |
| `mod_export.R` | ✓ | ✓ | ✓ | none |
| `mod_settings.R` | ✓ | ✓ | ✓ | `reactiveValues(profile_activated, absence_changed)` |

---

## Reactive Hygiene Summary

| Pattern | Status |
|---------|--------|
| `req()` guards on nullable inputs | ✓ Present where needed |
| `isolate()` usage | ✓ Not misused |
| Orphaned `observe()` blocks | None found |
| Infinite loop risk | None found |
| GGIR blocking call in server | None — pipeline runs in terminal (intentional) |
| Cross-module `input$` access | None |

---

## Data & Memory Summary

| Concern | Status |
|---------|--------|
| Large files loaded into memory | All data is post-GGIR summaries (not raw epoch CSVs); acceptable for 400 participants |
| Hardcoded absolute paths | None — all paths relative to working directory or config-driven |
| Intermediate file cleanup | No cleanup logic; GGIR output accumulates in `data/processed/`; acceptable for this scale |
| Multi-session path safety | N/A — single-researcher local deployment |
| `fread()` error handling | `analysis_ready` and `validity_summary` wrapped in `tryCatch()`; missing files produce NULL, which causes per-output reactive errors rather than a full app crash |

---

## Pipeline Correctness

**Date:** 2026-05-04  
**Scope:** Parameter passthrough (`01_run_ggir.R` → `GGIR()`), pipeline stage sequencing, output interpretation (`02_label_segments.R`, `03_build_summaries.R`), edge cases  
**Method:** Source-trace of every GGIR argument; cross-check against context7 GGIR docs; path resolution verified against git-status untracked files

---

## 🔴 BREAKING

### P1 — Class-override pupil map key mismatch: school_3 per-pupil end times silently not applied

**File:** `r/pipeline/02_label_segments.R:357`

The `pupil_override_map` is keyed by plain integer strings from config (`"3025"`, `"3026"`, etc.). The lookup at line 357 is:

```r
pupil_info <- pupil_override_map[[as.character(row$ID)]]
```

`row$ID` comes directly from GGIR's `part2_daysummary.csv`. GGIR derives participant IDs from filenames when `idloc = 2`. The `extract_school_id()` function at `02_label_segments.R:32` strips `.csv` with `sub("\\.csv$", "", ...)` — this is defensive code that confirms GGIR's ID column includes the `.csv` extension (e.g. `"3025.csv"`). `as.character("3025.csv")` never matches map key `"3025"`.

**Effect:** All 13 pupils in school_3 classes 2Aa/2Ab/2Ba/2Bb who have a 16:25 school-end override on specific weekdays receive the standard 15:35 end time instead. Their `in_class` and `after_school` segment boundaries are wrong for those days. The failure is completely silent — no warning, no error.

**Action required:**

```r
# 02_label_segments.R:357 — replace:
pupil_info <- pupil_override_map[[as.character(row$ID)]]

# with:
pupil_key  <- sub("\\.csv$", "", basename(as.character(row$ID)))
pupil_info <- pupil_override_map[[pupil_key]]
```

---

## 🟡 WARNINGS

### P2 — `epochvalues2csv = TRUE` is unverified in GGIR 2.x; `labeled_epochs.csv` is never produced by any pipeline step

**Files:** `r/pipeline/01_run_ggir.R:119`, `r/pipeline/03_build_summaries.R:286–320`

`epochvalues2csv = TRUE` appears in the `shared_args` list passed to `GGIR()`. Whether this parameter exists and what it produces in GGIR 2.x could not be confirmed via context7 documentation. Regardless, `02_label_segments.R` is a day-level script only — it reads `part2_daysummary.csv` and writes `segment_summary.csv`. There is no code path in `02_label_segments.R` that produces epoch-level output.

The comment at `03_build_summaries.R:291` is therefore incorrect:

```r
# This is produced when GGIR runs with epochvalues2csv = TRUE and
# 02_label_segments.R assigns school context to each epoch.
```

`02_label_segments.R` never assigns school context to individual epochs. As a result, `labeled_epochs.csv` never exists, the `if (file.exists(labeled_epochs_path))` block in step 03 never fires, and `compute_context_bout_summaries()` in `utils_bouts.R` is dead code. W6 in the existing audit identified the symptom (NA bout columns); this finding identifies the root cause.

**Action required before real-data run:**
1. Verify whether `epochvalues2csv` is a valid GGIR 2.x parameter; if not, remove it from `shared_args`
2. Correct the comment in `03_build_summaries.R:291` — either document that epoch labeling is not yet implemented, or implement the epoch-level labeling pipeline step

---

### P3 — `grep("MVPA", names(part5))` picks first alphabetical match from multiple candidates

**File:** `r/pipeline/03_build_summaries.R:168`

```r
mvpa_col <- grep("MVPA", names(part5), value = TRUE, ignore.case = TRUE)
```

With `boutdur.in = c(10, 20, 30)` passed to GGIR, Part 5 `personsummary` likely contains several MVPA-related columns, for example: `dur_day_MVPA_bts_10_min_pla`, `dur_day_MVPA_bts_20_min_pla`, `dur_day_MVPA_bts_30_min_pla`, and `dur_day_total_MVPA_min_pla`. `grep("MVPA", ...)` returns all of them. `mvpa_col[1]` takes whichever sorts first alphabetically — `bts_10` sorts before `total`, so the dashboard KPI "Gem. MVPA" and the WHO-guideline percentage (`≥60 min/day`) could be showing MVPA-in-bouts-≥10min rather than total MVPA. This is a meaningful scientific distinction and the column selection is GGIR-version-dependent.

**Action required:** After the first real GGIR run, inspect Part 5 column names and replace the broad grep with a ranked preference:

```r
# Prefer total MVPA; fall back to bouts metric
mvpa_candidates <- grep("MVPA", names(part5), value = TRUE, ignore.case = TRUE)
mvpa_col <- c(
  grep("total_MVPA|MVPA_total", mvpa_candidates, value = TRUE),
  mvpa_candidates
)[1]
```

Or pin to the exact column name once it has been observed in practice.

---

### P4 — `dev.nonwear_approach: "2023"` is wrong for 1Hz dummy CSV data; W1 fix recommendation was incomplete

**Files:** `config.yaml:229`, `r/pipeline/01_run_ggir.R:75`

The existing W1 finding recommends removing `dev.nonwear_approach` before a real-data run. However, the config's own inline comment reveals a second problem: the current value `"2023"` is also wrong for example mode. The GGIR 2023 non-wear algorithm resamples internally to 5 Hz; at 1 Hz input this collapses all variance to zero, flagging every epoch as non-wear → zero valid days → all participants excluded. If a developer sets `example_mode: true` for testing, the run produces 0 valid participants with no diagnostic message.

The correct value for 1 Hz CSV dummy data is `"2013"`. For real `.bin`/`.cwa` data (100 Hz), remove the setting entirely.

**Two separate actions required:**
1. *Now (for dummy data):* `config.yaml:229` → `nonwear_approach: "2013"`
2. *Before real-data run:* Remove `dev.nonwear_approach` entirely (as W1 states)

---

### P5 — Output file paths are documented incorrectly in `r/DEVELOPER.md` (and `CLAUDE.md`)

**Source of truth:** `config.yaml:14` (`data_processed: "../data/processed"`), `02_label_segments.R:473`, `03_build_summaries.R:398–401`

`config.yaml` sets `data_processed: "../data/processed"`. Pipeline scripts write:

```r
file.path(base_out, "..", "segment_summary.csv")  # resolves to data/segment_summary.csv
file.path(base_out, "..")                          # resolves to data/
```

Actual output locations (confirmed by `git status` untracked files):

| File | Documented location | Actual location |
|------|---------------------|-----------------|
| `segment_summary.csv` | `data/processed/` | `data/` |
| `analysis_ready.csv` | `data/processed/` | `data/` |
| `validity_summary.csv` | `data/processed/` | `data/` |
| GGIR output | `data/processed/ggir/meting_N/` | `data/processed/meting_N/` |

The code is internally consistent (pipeline and Shiny resolve to the same paths). The documentation is wrong. `DEVELOPER.md` path diagrams require correction.

---

### P6 — Sleep efficiency column grep includes `fraction` — pattern is overly broad

**File:** `r/pipeline/03_build_summaries.R:135`

```r
seff_col <- grep("SleepEfficiencyInSpt|sleep_efficiency|fraction",
                 names(part4), value = TRUE, ignore.case = TRUE)
```

`fraction` matches any column containing that substring. GGIR Part 4 may contain columns like `fraction_night_invalid` or similar. `seff_col[1]` takes the first alphabetical match — which may not be the efficiency column. `SleepEfficiencyInSpt` and `sleep_efficiency` are sufficient for modern GGIR; the `fraction` alternative should be removed.

---

## 🟢 SUGGESTIONS

### P7 — `weekdays()` in `global.R` not locale-protected (fallback path only)

**File:** `r/shiny/global.R:113`

```r
part2[, weekday := weekdays(as.Date(calendar_date))]
```

This line fires only when GGIR's CSV does not include a `weekday` column (possible in older GGIR versions). Without `Sys.setlocale("LC_TIME", "C")`, on a Dutch-locale machine `weekdays()` returns Dutch day names. `mod_schoolday.R:231` filters using `c("Saturday","Sunday")` — Dutch names would return zero rows in the weekend activity plot. Risk is low since modern GGIR produces `weekday` in Part 2 output, but a one-line guard would eliminate the hazard:

```r
part2[, weekday := weekdays(as.Date(calendar_date), abbreviate = FALSE)]
# Becomes locale-safe by calling format() with an explicit day name table, or:
Sys.setlocale("LC_TIME", "C")  # add at top of global.R
```

---

### P8 — `do.report = c(2, 5)` excludes Part 4 visual sleep report

**File:** `r/pipeline/01_run_ggir.R:143`

`DEVELOPER.md` documents `visualisation_sleep.pdf` as expected output under `results/`. GGIR generates this PDF only when Part 4 is included in `do.report`. With `do.report = c(2, 5)`, no sleep visualization PDF is produced. The pipeline doesn't consume the PDF, but researchers may expect it. Consider `do.report = c(2, 4, 5)` or document that the PDF is intentionally not generated.

---

### P9 — qwindow suffix pattern may mismatch actual GGIR column names

**File:** `r/pipeline/02_label_segments.R:200–202`

```r
qw_suffixes <- paste0(qw_starts, ".", qw_ends)
```

For boundaries `[0, 8.5, 10.0, 12.0, 13.0, 15.5, 24]`, R formats `10.0` as `"10"`, producing suffix `"10.12"`. GGIR's actual column names for this window could be `"10.12"` or `"10.0.12.0"` depending on version. If the suffix doesn't match, `use_qwindow` stays `FALSE` and all segment estimates fall back to proportional approximation — silently. Once GGIR is re-run with qwindow set (existing open blocker), inspect the actual Part 2 column names and pin the suffix format explicitly.

---

## Verified ✅ — Parameters correctly passed to `GGIR()`

All parameters below were source-traced from `config.yaml` → `01_run_ggir.R` → `GGIR()` call and cross-checked against context7 GGIR documentation.

| Parameter | Configured value | Verdict |
|-----------|-----------------|---------|
| `mode = 1:5` | all five GGIR parts | ✅ |
| `HASPT.algo = "HDCZA"` | van Hees 2015 wrist-validated sleep algorithm | ✅ |
| `anglethreshold = 5` | degrees — HDCZA default | ✅ |
| `timethreshold = 5` | minutes — HDCZA default | ✅ |
| `threshold.lig = 56.3` | Hildebrand 2014/2017 SB/LPA boundary (mg) | ✅ |
| `threshold.mod = 191.6` | Hildebrand 2014/2017 LPA/MPA boundary (mg) | ✅ |
| `threshold.vig = 695.8` | Hildebrand 2014/2017 MPA/VPA boundary (mg) | ✅ |
| `boutdur.in = c(10,20,30)` | sedentary bout duration thresholds (min) | ✅ |
| `rmc.firstrow.acc = 101` | skips 100-row GENEActiv metadata header | ✅ |
| `rmc.col.acc = 2:4` | x/y/z acceleration columns in g | ✅ |
| `rmc.col.time = 1` | timestamp column | ✅ |
| `rmc.col.temp = 7` | temperature column | ✅ |
| `rmc.unit.acc = "g"` | GENEActiv native unit | ✅ |
| `rmc.unit.time = "POSIX"` | timestamp format | ✅ |
| `rmc.sf = 1` | 1 Hz — CSVs are pre-epoched 1-second data (W4) | ✅ |
| `do.cal = FALSE` (CSV) | autocalibration requires raw signal; CSVs are pre-epoched | ✅ |
| `do.cal = TRUE` (native) | sphere-fitting enabled for raw .bin/.cwa | ✅ |
| `desiredtz = "Europe/Brussels"` | explicit override of machine-timezone default | ✅ |
| `idloc = 2` | full filename as participant ID | ✅ |
| `includedaycrit` | from `dev$includedaycrit` or `validity$min_wear_hours_per_day` | ✅ |
| `includedaycrit.part5` | from `dev$includedaycrit_part5` or `2/3` | ✅ |
| `overwrite = isTRUE(cfg$ggir$overwrite)` | milestone caching controlled via config | ✅ |
| `qwindow` | from config (manual) or derived from schedules (auto) | ✅ |
| Part 1→5 intermediate files | GGIR manages `meta/` milestone `.RData` files internally | ✅ no explicit pass-through needed |
| `outputdir` path resolution | relative paths consistent across pipeline and Shiny | ✅ (P5 is docs error only) |

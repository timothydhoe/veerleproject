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

# to_be_built/

Backlog of research features that were prototyped in the earlier `project_1/` pipeline
(superseded by `r/`) but never had an equivalent built into the current pipeline. This
folder is not wired into `r/` in any way — nothing here is sourced, imported, or run by
the pipeline or Shiny app. It's a holding area for ideas worth revisiting, not an
archive of old code.

Everything else from `project_1/` that duplicated what `r/` already does (or was
already dead code) was deleted rather than kept "just in case" — see git history if you
need to recover it.

## What's here

- **`attendance_prediction.py`** + **`utils.py`** — RQ5: a morning "commute activity
  burst" heuristic that infers whether a pupil was present at school that day, based on
  detecting an ENMO spike near school start time. No equivalent in `r/`.

  Expects two config values that used to live in `project_1/config/pipeline_params.yaml`
  (now deleted) and are **not** present in the root `config.yaml`:
  - `attendance_arrival_window_min` (default in code: **60**)
  - `attendance_enmo_threshold_mg` (default in code: **50**)

  The script already falls back to these defaults if the config values are missing, so
  it still runs standalone — but the originally-tuned values only survive in git history
  (`project_1/config/pipeline_params.yaml` as of the last commit before this cleanup).
  If this feature gets built out, re-derive/re-tune these rather than assuming 60/50 are
  correct for the real dataset.

- **`school_correlations.R`** — RQ4: exploratory correlation between mean lesson-block
  duration and mean in-class sedentary time, across the 6 schools (N=6, so the script's
  own comments already caution against over-interpreting the result). No equivalent in
  `r/`.

## What's deliberately not here

**Bout detection (RQ2)** — `project_1/R/analysis/sedentary_bouts.R` is **not** in this
backlog because it was already ported into `r/pipeline/utils_bouts.R` (same
run-length-encoding-on-intensity-and-context algorithm, same function shapes). One
function from the original, `detect_all_bouts()` (an all-intensities-at-once wrapper),
wasn't carried over — but `r/`'s `detect_activity_bouts(target_intensity = ...)` covers
the same ground per call, so this is a judgment call, not a silent gap. If a genuine
need for the all-intensities-at-once convenience wrapper resurfaces, it's a small
addition to `r/pipeline/utils_bouts.R`, not something to rebuild here.

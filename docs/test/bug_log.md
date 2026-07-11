# SchoolMove — Bug Log

Consolidated from two sources:
- `docs/test/veerleproject_assessment.md` (full repo assessment, run on dummy data)
- Live pipeline test against two real device files (`73044_0000001002.cwa`,
  `1001_left wrist_109488_2026-04-27 11-10-01.bin`), 2026-07-11

Each item is tracked with a status. Fixes happen one at a time, by agreement, in the
order below. This file is updated as each item is resolved.

Status legend: `open` · `fixed` · `wontfix` · `deferred`

---

## 🔴 Critical

### 1. `run_example_pipeline.R` never restores `config.yaml` — status: `fixed`

**Fix applied:** replaced the top-level `on.exit()` with `tryCatch({ ... }, finally =
{ ... })` in `scripts/ci/run_example_pipeline.R` — chosen over "wrap in a function"
because this script is run locally by multiple developers and the restore logic
should be visibly correct at the top level, not hidden inside a function someone has
to remember to call. Confirmed this file is **not** part of the distributed Windows
bundle (`scripts/bundle/build-bundle.ps1` never copies `scripts/ci/`), so this fix
has no path into the production artifact. Verified with a real run: the
`"[ci] config.yaml restored to its original contents"` message now fires, and
`git diff config.yaml` is empty afterward (byte-identical to the committed version).

**Where:** `scripts/ci/run_example_pipeline.R` (top-level `on.exit()`)

The script's `on.exit()` call sits at the top level of the script, not inside a
function. In R, `on.exit()` only attaches to the current function's call frame — at
top level there is no enclosing function, so the handler silently never fires.
Confirmed empirically (reproduced the exact pattern in isolation via `Rscript`: the
exit handler never printed).

**Impact:** running the script exactly as documented (`Rscript
../scripts/ci/run_example_pipeline.R` from `r/`) permanently corrupts the working
`config.yaml` — flips it to `example_mode: true`, `quick_test_n: 2`, and
re-serializes it via `yaml::write_yaml()`, stripping all ~80 Dutch explanatory
comments and reformatting values. This happened for real during the earlier
assessment and had to be restored via `git checkout`.

---

### 2. Stale per-output-directory `config.csv` breaks native `.bin`/`.cwa` runs — status: `fixed`

**Fix applied:** added a guard in `r/pipeline/01_run_ggir.R`, inside the `has_native`
branch, right before `do.call(GGIR, ggir_args)`. Before every native run, it
recursively searches `output_dir` for any `config.csv`, checks whether its
`rmc.firstrow.acc` row is actually set (distinguishing a real leftover value from
GGIR's own `c()` serialization of "unset"), and deletes the file if so — with a
console message identifying exactly what was cleared and why. `file.remove()`'s
return value is checked and a warning is raised if removal fails (e.g. a locked
file), and an unreadable `config.csv` triggers a warning rather than failing
silently. Single file changed; the dummy/CSV/`example_mode` branch is untouched.

Considered and explicitly rejected: (a) redirecting `example_mode` output to a
separate directory — technically sound but touches 9 bundle-shipped files for a
failure mode CI can never trigger (ephemeral runners) and the project owner no longer
triggers locally either (switched local testing to real native files); (b) a broader
"detect any config drift" guard — no known trigger beyond the one confirmed failure
mode, would have been speculative.

**Verified two ways:**
1. **Static review** by an independent agent (fresh context, read the real file,
   traced the logic against the actual `config.csv` format) — confirmed correct, no
   blocking issues.
2. **Live end-to-end reproduction of the exact original failure, then confirmed the
   fix resolves it**: re-ran the dummy CI script to recreate the stale
   `rmc.firstrow.acc: 101` config in the real `data/processed/meting_1/output_meting_1/`
   directory (the exact poisoning mechanism that caused the original crash), then ran
   `01_run_ggir.R` against the same directory with the two real native test files.
   Console output confirmed: `Clearing stale CSV-format config.csv
   (rmc.firstrow.acc=101) before native run: ...` followed by a clean run through all
   of Parts 1-5 with no crash (`Step 01 complete`). Previously, this exact sequence
   crashed with `undefined columns selected`.

**Where:** interaction between `01_run_ggir.R` and GGIR's own `g.inspectfile()`;
manifests at `data/processed/meting_1/output_meting_1/config.csv`

GGIR persists all run parameters to `config.csv` in each output directory. With
`ggir.overwrite: false` (the committed default), a new run reuses that directory's
prior config. Read GGIR 3.3.6's own source (`g.inspectfile()`): if
`rmc.firstrow.acc` is non-empty *for any reason* — including a stale value merged in
from a previous run's persisted `config.csv` — GGIR unconditionally routes **every**
input file through `read.myacc.csv()` (the CSV reader), regardless of actual file
extension, skipping its own `.bin`/`.cwa` extension-based format detection entirely.

**Impact:** confirmed live. `data/processed/meting_1/output_meting_1/config.csv`
**currently contains `rmc.firstrow.acc: 101`** — a leftover from an earlier
CSV-format run, pre-existing before this session, not created by testing today. Any
future real run of Step 01 against native `.bin`/`.cwa` files, with `overwrite:
false`, will crash with `Error in [.data.frame(...) : undefined columns selected`.
Confirmed the fix works: re-running against a clean/never-used output directory
succeeded immediately with the exact same input files and config.

---

## 🟠 High

### 3. Dev overrides applied unconditionally to real GGIR runs — status: `fixed`

**Root cause traced further than originally documented:** `docs/prompt_run_test_data.md`
(an earlier session's own test-prep notes) confirms `nonwear_approach: "2013"` was
only ever meant for dummy-CSV testing, with an explicit rollback step ("remove for
real .bin data") that was never carried out — so the committed value is a forgotten
test-session leftover, not a deliberate real-data choice. Confirmed via GGIR 3.3.6's
own parameter documentation: GGIR's actual default is `"2023"`; `"2013"` is the
original van Hees et al. (2013) algorithm, superseded but kept for backward
compatibility. Nothing in GGIR's own docs ties either version to CSV vs. native
format — that constraint appears to be specific to how this project's CSV path was
originally built, not a GGIR requirement.

**Fix applied:** gated `nonwear_approach`, `includedaycrit`, and `includedaycrit_part5`
behind `isTRUE(dev$example_mode)` in `r/pipeline/01_run_ggir.R` (lines ~76-93) — real
runs (`example_mode: false`) now always get GGIR's own defaults
(`nonwear_approach = "2023"`, `includedaycrit = cfg$validity$min_wear_hours_per_day`)
regardless of whatever is sitting in `config.yaml`'s `dev:` section.

**Explicitly rejected:** removing `dev.nonwear_approach` from `config.yaml` and
hardcoding it per-format in the script (my initial proposal). This would have
violated `CLAUDE.md`'s own stated principle — *"Veerle should never need to edit an
`.R` file to change a parameter... always route new configurable parameters through
`config.yaml`"* — for no added benefit over gating. The chosen fix keeps the config
key alive and editable for dummy/dev testing (matching the `dev:` section's own
documented purpose) while guaranteeing it can never again leak into a real run.

**Verified live:** ran the real native pipeline against the two test files with
`config.yaml`'s stale values still committed as-is (`example_mode: false`,
`nonwear_approach: "2013"`, `includedaycrit: 4`, unchanged). No "Dev overrides
active" message printed (correctly suppressed). Checked GGIR's own freshly-written
`config.csv`: `nonwear_approach,2023,params_cleaning` and
`includedaycrit,16,params_cleaning` — confirming the real run used the correct
defaults regardless of the stale config values. `config.yaml` restored and verified
clean (`git diff` empty) afterward.

**Where:** `r/pipeline/01_run_ggir.R:77-85, 148-150`

`nonwear_approach` and `includedaycrit` are computed from `dev.*` config values and
passed into the real `GGIR()` call unconditionally. Only the console *message*
announcing "dev overrides active" is gated behind `dev.example_mode`; the values
themselves are not. `config.yaml` documents these as "no effect on real data" (line
226), which is false as implemented.

**Impact:** with `config.yaml` as currently committed (`example_mode: false`,
`nonwear_approach: "2013"`, `includedaycrit: 4`), a real-data run today would have
GGIR silently use the 2013 non-wear algorithm (instead of 2023) and a 4-hour
day-inclusion threshold (instead of 16) — affecting Part 2/5 non-wear detection
before any downstream, correctly-gated code ever sees the data.

**Correction from the original assessment:** an earlier draft of this finding
claimed the same bug existed in `03_build_summaries.R`, `shiny/global.R`, and
`qc_01_ggir.R`. On closer reading, those three files correctly gate their own
validity-threshold logic on `example_mode` — only `01_run_ggir.R`'s GGIR-call
arguments are affected.

---

## 🟡 Medium

### 4. QC 01 false-fails on part4 sleep file (non-recursive search) — status: `fixed`

**Investigated before fixing:** confirmed via git history that `qc_01_ggir.R`'s
inline `list.files()`+`fread()` check and `utils_ggir.R`'s `read_part4_sleep()`
weren't a deliberate design split — both were written in the same initial scaffold
commit, and `read_part4_sleep()` was fixed later (commit `f56adcf`, "sleep report
path" fix) to search `results/QC/` too, but `qc_01_ggir.R`'s copy was never updated
to match. Empirically confirmed `fread()` (used by QC) and `read.csv()` (used by
`read_part4_sleep()`, production's only Part 4 reader — confirmed via
`03_build_summaries.R:64-73`) parse the same file with a real type difference
(`calendar_date` as `IDate/Date` vs `character`) — though an independent review
correctly pushed back that this specific difference is inert for what the QC check
actually reports (row/column counts only); the real, load-bearing justification is
the directory/filename-priority mismatch, not the parser choice.

**Fix applied:**
- `qc_01_ggir.R`'s part4 check now calls `read_part4_sleep(results_dir)` (the same
  production helper) instead of its own narrower `list.files()`/`fread()` logic —
  same two-directory search, same cleaned→full→plain filename priority as
  production.
- `utils_ggir.R`'s `read_part4_sleep()` now attaches the resolved file path as a
  `source_path` attribute on its return value (additive, backward-compatible — no
  existing caller is affected) so QC's pass message can still report which specific
  file was found, avoiding the diagnostic-detail regression an independent review
  caught in the first draft of this fix.

**Verified two ways:**
1. **Independent static review** (fresh agent, no prior context) confirmed the fix
   correct and well-justified, caught one real issue (loss of filename detail in the
   pass message, fixed via the `source_path` attribute above), and correctly
   reframed the primary justification from "different parser" to "directory/priority
   search mismatch."
2. **Live before/after comparison**, run on real data:
   - Before: `qc_01_ggir.R` against `meting_2`'s existing output (which only has its
     Part 4 file under `results/QC/`, no `results/`-level file) showed
     `[FAIL] part4 nightsummary CSV not found`.
   - After: same directory shows `[PASS] part4_nightsummary_sleep_full.csv — 3 rows,
     42 columns`, with the resolved path correctly logged.
   - **Confirmed the fix changes nothing else**: ran the full `02_label_segments.R` +
     `03_build_summaries.R` before and after the fix and diffed
     `segment_summary.csv`, `analysis_ready.csv`, `validity_summary.csv` —
     byte-for-byte identical in all three files. The fix only changes QC's own
     diagnostic report, never pipeline output.

**Where:** `r/qc/qc_01_ggir.R:56`

```r
part4_files <- list.files(results_dir, pattern = "^part4.*\\.csv$", full.names = TRUE)
```

Non-recursive — only checks `results_dir` directly. Confirmed the file genuinely
exists one level down at `results/QC/part4_nightsummary_sleep_full.csv` in some
GGIR configurations; `utils_ggir.R`'s `read_part4_sleep()` was already fixed to
search both `results/` and `results/QC/`, but QC 01 wasn't updated to match. Note:
in the most recent test run, the part4 file landed directly in `results/` and QC 01
passed — so this specific false-fail is data/config-dependent, not universal.

---

### 5. QC 01 false-fails on part5 file — hardcoded filename pattern — status: `open`
**Where:** `r/qc/qc_01_ggir.R:69`

```r
part5_files <- list.files(results_dir, pattern = "^part5_daysummary_WW_", full.names = TRUE)
```

Confirmed live against real GGIR 3.3.6 output: Part 5 produced
`part5_daysummary_Segments_L56.3M191.6V695.8_T5A5.csv` — no `WW` anywhere in the
name (naming reflects the qwindow/segment cut-point configuration, not a fixed
`WW` token). QC 01 reported `[FAIL] part5_daysummary_WW_*.csv not found` even
though Part 5 genuinely succeeded and the file was on disk.

Same category as #4 (hardcoded filename assumption vs. GGIR's actual dynamic
naming) — worth deciding together whether these two get one shared, more robust
detection helper or two independent targeted fixes.

---

### 6. Shiny profile "Activeer" button doesn't propagate to the pipeline — status: `open`
**Where:** `r/shiny/modules/mod_settings.R:322-342`

Activating a profile patches the `active:` line in `config.yaml` and shows: *"Profiel
geactiveerd. Herstart de pipeline om de nieuwe instellingen toe te passen."* Confirmed
by grepping `profile|active` across `01_run_ggir.R`, `02_label_segments.R`,
`03_build_summaries.R` — none of them read the profile system. Only
`shiny/global.R:43-69` merges the active profile, and only for dashboard display.
"Restarting the pipeline" as instructed would do nothing; the pipeline would run with
base `config.yaml` values while the dashboard displays profile-derived values.
Currently invisible only because `profiles/default.yaml` mirrors `config.yaml`
exactly.

---

### 7. `qwindow_strategy: auto` would silently break step 02 — status: `open`
**Where:** `r/pipeline/02_label_segments.R:195`

Step 02 always does a literal `qwindow <- as.numeric(cfg$ggir$qwindow)` — no
auto-derivation logic. `01_run_ggir.R` supports `qwindow_strategy: auto` (computing
boundaries from school schedules dynamically) but doesn't persist the resolved
values anywhere for step 02 to reread. Currently latent (default and only-used
strategy is `manual`), but `config.yaml` documents `auto` as supported, so this
would break silently the moment someone switches to it.

---

## ⚪ Low / informational

### 8. Sleep validity can silently resolve to NA — status: `open`
**Where:** `r/pipeline/03_build_summaries.R`

Observed live: `Sleep validity: efficiency column not found in part4 — meets_sleep_criteria
set to NA`. Expected on small test runs (too little data for GGIR to compute sleep
efficiency). Unconfirmed whether this also happens on full-scale real data — needs
checking once the pipeline is re-run on the real dataset (i.e. confirm GGIR's
real-data part4 output includes whatever efficiency column name
`03_build_summaries.R` looks for).

---

### 9. Segment-summary build is an unoptimized row-by-row loop — status: `open`
**Where:** `r/pipeline/02_label_segments.R:~348-445`

Correct but a `for` loop; fine at current scale (2×2 participant-days in testing),
will be slow at full-study scale (hundreds of participants × ~14 days each). Not
urgent — worth knowing before the real-data run so a multi-hour runtime isn't a
surprise.

---

### 10. `labeled_epochs.csv` / context-aware bouts not implemented — status: `open` (acknowledged, not urgent)
**Where:** `r/pipeline/03_build_summaries.R:298-311`

Self-documented in the code and confirmed live
(`[WARN] labeled_epochs.csv not found — context-aware bout columns will be NA`). The
entire `config.yaml bouts:` section and all `bouts_30min_*` columns in
`analysis_ready.csv` currently have zero effect on output. Not silently broken — an
acknowledged, unfinished feature.

---

### 11. Unconventional participant-ID filenames degrade to `school_NA` — status: `open` (informational, decide if action needed)
**Where:** ID parsing via GGIR `idloc=2`, consumed in `02_label_segments.R`

GGIR extracts the participant ID as everything before the first underscore in the
filename (confirmed: `1001_left wrist_...` → `1001`; `73044_0000001002.cwa` →
`73044`). The study's documented convention expects a 4-digit code where the first
digit is a school ID (1–6). `73044`'s first digit (`7`) doesn't match any configured
school. Confirmed this does **not** crash the pipeline — it degrades gracefully to
`school_NA` and a single `outside_school` segment spanning the full day, and QC 02
correctly surfaces a warning (`Participants found with no schedule in config.yaml:
school_NA`). No school-ID validation exists anywhere in the pipeline (e.g. in
`utils_input.R`'s manifest writer) to catch this earlier or more clearly.

---

## 📄 Documentation drift — status: `open`

From the original assessment, grouped as one item (typically fixed together in a
single doc pass):

- `CLAUDE.md`'s "Open Blockers" list is partially stale — blocker #2 (school 3/4
  fallback schedules) is resolved (`config.yaml` shows `fallback: false` for both,
  with sourced schedules); blockers #1 and #3 still appear genuinely open.
- Two documents `CLAUDE.md` references don't exist:
  `docs/planning/plan_of_attack_v2.md` (whole folder absent) and
  `docs/step3_action_plan_and_strategy.md`.
- `docs/data_info/school_info.md` is stale — still describes schools 3 and 4 as
  using a generic fallback schedule, contradicting the now-confirmed schedules in
  `config.yaml`.
- `DEVELOPER.md` has two stale entries: line 624 still lists school 4 as
  `fallback: true`; lines 502-503 say `do.report = c(2, 5)` and claim no sleep PDF,
  but `01_run_ggir.R:155` now has `do.report = c(2, 4, 5)`.
- `CLAUDE.md`'s directory layout and `config.yaml`'s own comment on `data_processed`
  both say summary CSVs (`segment_summary.csv`, `analysis_ready.csv`,
  `validity_summary.csv`) land under `data/processed/`. Confirmed directly (twice,
  in two separate runs) that they actually land one level up, in `data/` — because
  `02_label_segments.R` and `03_build_summaries.R` both write to
  `file.path(base_out, "..", "<file>.csv")`. This inaccuracy is also the direct
  cause of finding #13 below.

---

## ⚠️ Process / design gap — status: `open`

### 13. Summary CSV output path is not redirectable, and got overwritten during testing
**Where:** `r/pipeline/02_label_segments.R`, `r/pipeline/03_build_summaries.R`

These two scripts write `segment_summary.csv`, `analysis_ready.csv`, and
`validity_summary.csv` to a **fixed** path derived from `data_processed/..`
regardless of what `paths.data_processed` is pointed at. During today's isolated
test (redirecting `data_processed` to a scratch folder specifically to avoid
touching real output), these three fixed-path files were still overwritten with
test-run results. They're gitignored, so there's no git history to recover the
previous contents.

**Confirmed impact:** `r/logs/pipeline_runs.csv` and archived `ggir_config_*.csv`
files show two earlier full real-mode (`example_mode: false`) pipeline runs:
2026-04-28 (`datadir: ../data/raw/veerle_testdata/meting_1` — very likely the same
two test files, so low-risk) and **2026-05-03** (`datadir: ../data/raw/meting_1` —
a different, real data source path that no longer exists on disk today). The May 3
run's summary output is the one that can't be vouched for — unknown content, now
overwritten, unrecoverable via git.

This isn't a "bug" in the traditional sense — it's a design gap (no
redirectable/overwrite-safe output path) that turned into a real, one-time data loss
during testing. Worth deciding whether to make the path configurable, add an
overwrite guard/confirmation, or just document the risk clearly.

---

## ℹ️ Minor — status: `open`

### 14. renv version mismatch
`renv::status()` / every script run reports: *"renv 1.2.0 was loaded from project
library, but this project is configured to use renv 1.2.2."* Low priority — likely a
one-line `renv::record()` or `renv::restore(packages = "renv")` fix.

# SchoolMove — Bug Log

Consolidated from two sources:
- `docs/test/veerleproject_assessment.md` (full repo assessment, run on dummy data)
- Live pipeline test against two real device files (`73044_0000001002.cwa`,
  `1001_left wrist_109488_2026-04-27 11-10-01.bin`), 2026-07-11

Each item is tracked with a status. Fixes happen one at a time, by agreement, in the
order below. This file is updated as each item is resolved.

Status legend: `open` · `fixed` · `wontfix` · `deferred`

---

## ⏸ Session checkpoint (2026-07-12)

**Progress: 7 of 16 fixed** (#16 is a new low-priority item logged during #7's fix —
see below).
- ✅ Fixed: #1 (config.yaml corruption), #2 (stale config.csv breaking native runs),
  #3 (dev overrides leaking into real runs), #4 (QC part4 false-fail), #5 (QC part5
  false-fail), #6 (Shiny profile not reaching pipeline), #7 (step 02 trusting a
  possibly-stale config.yaml qwindow instead of GGIR's own recorded value).
- ⬜ Open: #8, #9, #10, #11, #12 (doc drift), #13, #14, #15, #16.

Next open item in severity order: **#15** (Medium — Shiny "download part5" export
hardcodes the `WW` variant), discovered during #5's review but not yet fixed.

### Resume prompt

Paste this to continue in the same style:

> We're working through `docs/test/bug_log.md` in SchoolMove, one bug at a time.
> Check the "Session checkpoint" section at the top for where we left off, then
> pick up exactly there. Keep using this workflow for every remaining bug:
>
> 1. **Explain the problem** in plain terms — what's broken, where, why it matters.
>    Investigate before proposing anything (read the actual current code, check git
>    history/docs for original intent, don't assume the bug log's original wording
>    is the final word — it's a starting point, re-verify against the live repo
>    since line numbers and context shift as earlier fixes land).
> 2. **Ask clarifying questions** if the fix direction depends on something only I
>    know (intent, priorities, risk tolerance) — don't guess.
> 3. **Present 2-3 concrete options** with tradeoffs, mark your recommended one, and
>    say why. Be willing to reverse your own recommendation if I push back with a
>    good reason, or if you find new evidence — say so plainly rather than
>    defending a first take.
> 4. **Leave room for my questions** on that specific bug before doing anything.
> 5. **Wait for explicit approval** before touching any file — no changes on
>    spec alone.
> 6. Once approved, and for anything non-trivial: **get an independent agent review**
>    of the problem + proposed solution before applying (static/read-only review,
>    no code execution) — this has caught real issues on every bug so far
>    (comment-stripping risk, parser-parity concerns, wrong root-cause framing).
>    Use judgement on when this is warranted; ask if unsure.
> 7. **Apply the fix**, then **verify it live**: reproduce the original bug first if
>    possible, confirm the fix resolves it, and — critically — **run the full
>    pipeline (or the affected steps) before and after the change and diff the
>    output CSVs** (`segment_summary.csv`, `analysis_ready.csv`,
>    `validity_summary.csv`) to prove the fix doesn't alter results it shouldn't.
>    Back up and restore `config.yaml` around any test that needs to temporarily
>    change it (verify via `git diff` that it's byte-identical afterward).
> 8. **Update `docs/test/bug_log.md`**: mark the item `fixed`, document what was
>    tried/rejected and why, what was applied, and exactly how it was verified —
>    write it the way the already-fixed items (#1-#6) are written, as the reference
>    format.
> 9. Log any new issues discovered along the way as new tracked items, don't just
>    mention them in passing and drop them.
> 10. Move to the next open item in severity order, and repeat.
>
> Do not batch multiple bugs' approvals together — one at a time, fully verified
> and documented, before starting the next.

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

### 5. QC 01 false-fails on part5 file — hardcoded filename pattern — status: `fixed`

**Investigated before fixing:** traced exactly which part5 variant each production
script depends on, rather than assuming a generic pattern swap would do. Confirmed:
`02_label_segments.R` (line ~206) hard-requires `part5_daysummary_Segments_*.csv`
specifically — no fallback to WW/MM (it degrades to wear-time-only estimates without
it, doesn't crash, but silently loses activity-intensity detail, which is why this
is still a `fail()` not a `warn()`). `03_build_summaries.R` (line 76) is deliberately
variant-agnostic for personsummary — matches any `part5_personsummary_*` file and
adapts its summation logic (`is_segments_file` check) to whichever variant is
present. The original QC check required `_WW_` specifically for both — a variant
`02_label_segments.R` never even reads, and one that a real GGIR run may not produce
at all (confirmed: a 2-day native test recording produced only the `Segments`
variant, no `WW`, even though GGIR's own log announces attempting all three).

**Fix applied:** daysummary check now requires `part5_daysummary_Segments_*.csv`
specifically (matching `02_label_segments.R`'s real dependency); personsummary check
broadened to generic `^part5_personsummary_` (matching `03_build_summaries.R`'s own
generic pattern). No `results/QC/` recursion added (unlike the part4 fix) — confirmed
via a real run log that Part 5 Segments daysummary reliably lands directly in
`results/`, never under `QC/`, so this asymmetry with the Part 4 fix is justified,
not an oversight.

**Verified two ways:**
1. **Independent static review** (fresh agent) confirmed both production-dependency
   claims by reading the actual source, confirmed QC's and production's "first
   match" file picks are guaranteed to agree (same directory, same pattern, same
   default alphabetical sort), and confirmed the no-QC/-recursion decision against a
   real run log rather than taking it on faith.
2. **Live before/after comparison**: `meting_2` went from `[FAIL]
   part5_daysummary_WW_*.csv not found` to `[PASS]
   part5_daysummary_Segments_L56.3M191.6V695.8_T5A5.csv — 3 rows` and `[PASS]
   part5_personsummary_Segments_... — 2 participants`. Re-ran `02_label_segments.R` +
   `03_build_summaries.R` after the fix and diffed all three output files against the
   pre-fix baseline (same baseline used for Bug #4's verification) — byte-for-byte
   identical. Confirms zero impact on pipeline output, only on QC's own diagnostics.

**New issue surfaced by the independent review (not previously tracked) — logged
below as item #15**, out of scope for this fix but worth tracking.

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

### 6. Shiny profile "Activeer" button doesn't propagate to the pipeline — status: `fixed`

**Two candidate designs were investigated and independently reviewed before
implementing.** The initial candidate ("Option 3": have "Activeer" write the
profile's values directly into `config.yaml` via targeted line-patching, so every
consumer needs zero new code) was reviewed by an independent agent and rejected:
it would have needed to solve comment-preservation per-field (the exact failure
class behind Bug #1), partial profiles are already a real, current fact (the
existing "save profile" UI only writes 2 of `bouts:`'s 5 fields, not hypothetical),
multi-line patches have no atomicity, and — most persuasively — `profiles/default.yaml`'s
own header comment already documents the *intended* design: *"It is loaded by the
Shiny app... and merged over the base values in config.yaml. **The pipeline uses
these values when running.**"* That's a direct textual statement of intent that the
pipeline should read profiles — this bug is that intent never being finished, not a
different mechanism being deliberately chosen.

**Fix applied (the reviewed-and-recommended design):** extracted `global.R`'s
existing profile-merge logic (`modifyList()`-based, already correctly handles
partial profiles) into a shared `apply_active_profile(cfg, profiles_dir = NULL)`
function in `validate_config.R` (already sourced by all four consumers). Each of
`01_run_ggir.R`, `02_label_segments.R`, `03_build_summaries.R` now calls
`apply_active_profile(cfg)` right after `read_config_yaml()` (default path
resolution correct since they all run from `r/`); `global.R` calls it with an
explicitly resolved path (it runs one directory deeper, from `r/shiny/`). Never
writes to `config.yaml` — purely an in-memory merge, same as before, just now
shared by the pipeline instead of Shiny-only.

**Verified live, both directions:**
1. Created a temporary test profile (`min_wear_hours_per_day: 8` instead of the
   base config's `16`), activated it, ran `02_label_segments.R` +
   `03_build_summaries.R` against existing GGIR output. Result: participant
   `1001.csv/meting_1` went from `n_valid_days=0, meets_sedentary_criteria=FALSE`
   (16h baseline) to `n_valid_days=4, meets_sedentary_criteria=TRUE` (8h profile) —
   a real, measurable change in pipeline output driven entirely by profile
   activation, not a config.yaml edit.
2. Reverted `profiles.active` back to `"default"`, re-ran the same two scripts, and
   diffed all three output files against the original pre-fix baseline —
   byte-for-byte identical. Confirms the fix is fully reversible and doesn't alter
   default-profile behavior.
3. Deleted the temporary test profile afterward; `config.yaml` confirmed clean via
   `git diff` throughout (only `profiles.active` was ever touched, and only
   temporarily, then restored to the committed value).

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

### 7. `qwindow_strategy: auto` would silently break step 02 — status: `fixed`

**Investigated before fixing:** confirmed step 02's `qwindow <- as.numeric(cfg$ggir$qwindow)`
(then at line 196) always re-reads `config.yaml`'s literal manual list, with no
awareness of `qwindow_strategy`. Traced two distinct failure modes, not one:
(a) the originally-titled case — switching to `qwindow_strategy: auto` means step 01
stops using `config.yaml`'s `qwindow:` list entirely (derives boundaries from
`cfg$schedules` instead, held only in memory, never written back to `config.yaml`),
so step 02 would silently use a stale/irrelevant list; (b) a second, broader case
found during investigation — even in `manual` mode, editing `config.yaml`'s
`qwindow:` list after step 01 has already run (without a step-01 rerun) produces the
exact same class of silent mismatch. Confirmed via GGIR's own docs (`context7`,
`/wadpac/ggir`) that `qwindow` is a single Part 2 argument GGIR uses to segment both
Part 2's daysummary and Part 5's Segments file identically — there was never a
legitimate reason for step 01 and step 02 to have independently-sourced values;
step 02's job is to *remember* what step 01 used, not to have its own opinion.

Also confirmed step 01/02 run in the same R session when invoked via `run_all.R`
(`source()`, not separate processes) — but rejected relying on that in-memory value
because both scripts are also designed to be run standalone (e.g. re-running just
step 02 after a labeling-logic tweak, without re-running slow GGIR — the reason
`ggir.overwrite: false` exists). An in-memory handoff would work by accident via
`run_all.R` and break silently the moment either script is run on its own.

**Fix applied:** added `resolve_ggir_qwindow(meting_output_dir)` to `utils_ggir.R` —
reads GGIR's own persisted per-meting `config.csv` (via the existing but previously
unused `read_ggir_config()` helper), parses its `qwindow` row's `"c(0,8.5,...)"`
string into a numeric vector. This file is GGIR's own audit record of what it
actually ran with for that specific output — already trusted enough that
`run_all.R:60-76` archives a copy of it into `logs/` after every run.

`02_label_segments.R` now resolves `qwindow` by calling this helper for `meting_1`
and `meting_2` independently (confirmed with the project owner: both metingen must
always share the same schedule/qwindow — a study-design invariant, not just an
assumption), and:
- if both resolve and agree → uses that value;
- if both resolve but **disagree** → hard `stop()` naming both resolved values,
  since divergence would itself indicate a real inconsistency (e.g. one meting
  re-run with different schedules) worth surfacing loudly rather than silently
  picking one;
- if only one meting has GGIR output yet → uses that one, with a `message()` noting
  which meting was missing;
- if neither has run yet → falls back to `as.numeric(cfg$ggir$qwindow)` (old
  behavior) with a `warning()` that the value may not reflect an actual GGIR run.

No changes to `01_run_ggir.R` — confirmed via grep that `cfg$ggir$qwindow` /
`qwindow_strategy` are read nowhere else in the repo (not in Shiny, not in QC
scripts, not in `validate_config.R`), so the fix is fully contained to
`utils_ggir.R` (additive) and `02_label_segments.R`.

**Explicitly rejected:**
- *Sharing `build_qwindow_from_schedules()` between both scripts* (the original
  plan going into this session) — would have step 02 **recompute** the auto-derived
  value from `cfg$schedules` rather than read what GGIR actually used. Still
  vulnerable to schedule-drift between a step-01 run and a later step-02 run, and
  does nothing for the manual-mode drift case. Reconsidered once the ground-truth
  `config.csv` route was found to be no more code for a strictly more correct
  result.
- *Building full meting-aware matching into `distribute_qwindow_cols()`* (reading
  each meting's value and keeping them separately keyed all the way through
  window-matching) — unnecessary once the project owner confirmed meting_1/meting_2
  are guaranteed to share one qwindow; a "must-agree-or-stop" check gets the same
  safety without restructuring the downstream matching logic.

**Verified three ways:**
1. **Independent static review** (fresh agent, no prior context) read
   `utils_ggir.R`, `02_label_segments.R`, and three real archived `config.csv`
   samples (`r/logs/ggir_config_meting_*_2026*.csv`), confirmed the parser handles
   real GGIR output correctly (including GGIR's `c()`-empty-value convention),
   confirmed no other file reads the changed variables, and confirmed graceful
   degradation on a fresh clone before step 01 has ever run. Flagged two low-cost
   improvements (both applied): use `tail(row$value, 1)` instead of `row$value[1]`
   defensively in case `config.csv` ever has more than one `qwindow` row, and print
   both resolved values in the disagreement `stop()` message rather than just
   telling the user to reconcile them. Also flagged a pre-existing, out-of-scope
   issue — logged below as item #16.
2. **Live end-to-end run on real data**: backed up the existing
   `segment_summary.csv`/`analysis_ready.csv`/`validity_summary.csv` (produced
   pre-fix from the two real native test files), re-ran `02_label_segments.R` +
   `03_build_summaries.R` post-fix. Console confirmed the new message: `Using
   qwindow resolved from GGIR's own config.csv: 0, 8.5, 10, 12, 13, 15.5, 24` (both
   metingen's real `config.csv` agreed, as expected — no drift in this dataset).
   Diffed all three output files against the pre-fix baseline — byte-for-byte
   identical. Confirms the fix changes nothing when there's no actual drift, only
   the previously-untested drift/mismatch paths.
3. **Isolated unit test of the new logic's edge cases**, using synthetic
   `config.csv` fixtures in a scratch directory (no real pipeline data touched):
   confirmed `resolve_ggir_qwindow()` parses agreeing and disagreeing values
   correctly and returns `NULL` for a missing file; confirmed the "both agree" path
   returns the shared value; confirmed the "disagree" path throws the expected
   `stop()` with both values named; confirmed the "only one meting present" path
   falls back to it with the expected missing-meting note; confirmed the "neither
   present" path correctly falls through to the `config.yaml` fallback.

**Where:** `r/pipeline/utils_ggir.R` (new `resolve_ggir_qwindow()`),
`r/pipeline/02_label_segments.R` (~line 196, `qwindow` resolution block)

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

### 16. `find_ggir_output_subdir()` picks the first `output_*` subdir with no ordering guarantee — status: `open` (informational)
**Where:** `r/pipeline/utils_ggir.R:40-51`

Discovered during Bug #7's independent review, not previously tracked. If a
meting's output directory ever accumulates more than one `output_*` subdirectory
(e.g. a partial re-run under a renamed `datadir`), `find_ggir_output_subdir()` picks
`ggir_subdirs[1]` — order from `list.dirs()`, not guaranteed stable or chronological
across filesystems. This is pre-existing and already affects every consumer of
`find_ggir_results_dir()` / `read_ggir_config()` (step 02's main part2 loading,
`read_part4_sleep()`, and now `resolve_ggir_qwindow()` from Bug #7's fix) —
Bug #7's fix does not make this scenario any more likely to occur, but it does add a
new, more visible symptom if it's ever hit: the new meting_1-vs-meting_2 qwindow
agreement check could throw a confusing "metingen disagree" `stop()` when the real
cause would be a stale/wrong subdirectory pick, not an actual qwindow mismatch.
Previously this would have just silently used the wrong subdirectory's data with no
error at all — arguably worse. Not fixed as part of Bug #7 — flagged as a follow-up;
worth deciding whether `find_ggir_output_subdir()` should sort by modification time
or fail loudly when more than one candidate exists.

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

---

## 🟡 Medium — found during Bug #5's independent review

### 15. Shiny "download part5" export hardcodes the `WW` variant — status: `open`
**Where:** `r/shiny/modules/mod_export.R:193` —
`dl_combined(pattern = "^part5_personsummary_WW_")`

Same category of bug as the original #5, in a different consumer: this dashboard
export handler hardcodes the `WW` personsummary variant specifically, with no
fallback. Confirmed via a real GGIR 3.3.6 run log
(`docs/test/pipeline.md:65,118`) that a real run can produce **only** `MM` and
`Segments` variants, no `WW` at all. In that scenario, this export handler currently
finds nothing and silently writes an empty CSV — no error, no warning, just a
misleadingly empty download for Veerle. Not covered by any QC check (QC 01 only
validates inputs for steps 02/03, not Shiny's own export paths). Not fixed as part
of Bug #5 — flagged as a follow-up.

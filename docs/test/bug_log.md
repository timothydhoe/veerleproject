# SchoolMove — Bug Log

Consolidated from two sources:
- `docs/test/veerleproject_assessment.md` (full repo assessment, run on dummy data)
- Live pipeline test against two real device files (`73044_0000001002.cwa`,
  `1001_left wrist_109488_2026-04-27 11-10-01.bin`), 2026-07-11

Each item is tracked with a status. Fixes happen one at a time, by agreement, in the
order below. This file is updated as each item is resolved.

Status legend: `open` · `fixed` · `wontfix` · `deferred`

---

## ⏸ Session checkpoint (2026-07-14)

**Progress: 17 of 18 fixed/resolved** (note: `#16` is used twice in this document
for two unrelated items — the dummy-ID-collision fix under "Fixed" below, and
`find_ggir_output_subdir()`'s ordering guarantee under the "Low" section — this
duplication predates this session, left as-is rather than renumbering everything
retroactively). `#16b` is a one-time manual data cleanup, not a numbered bug.
- ✅ Fixed: #1 (config.yaml corruption), #2 (stale config.csv breaking native runs),
  #3 (dev overrides leaking into real runs), #4 (QC part4 false-fail), #5 (QC part5
  false-fail), #6 (Shiny profile not reaching pipeline), #7 (step 02 trusting a
  possibly-stale config.yaml qwindow instead of GGIR's own recorded value), #15
  (Shiny part5 export hardcoded WW variant, silently dropping participants), #16
  (dummy participant IDs collided with real ID convention — renamed to a reserved
  range), #8 (sleep validity conflated data-completeness with sleep-efficiency,
  plus an adjacent sleep_duration_h column-mismatch bug found alongside it), #18
  (part5 personsummary variant selection was still arbitrary/alphabetical after
  #15), #11 (unconventional participant IDs now flagged at input-scan time), #13
  (summary CSV overwrite risk — backup-before-write safety net), #14 (renv version
  mismatch — documented, one-line fix), #16/find_ggir_output_subdir (sorts by
  mtime + warns instead of a silent arbitrary pick), doc drift (#12, all 5 points
  verified resolved).
- 🚫 `wontfix`: #9 (segment-summary loop — benchmarked at full study scale:
  4.66 seconds, not a real problem).
- ⏸ `deferred`: #10 (`labeled_epochs.csv` — scoped: needs real epoch-scale design
  work, ~480M rows at full study scale, not a quick fix; doesn't block tomorrow's
  real run).
- ⬜ Open: #17 (Windows MAX_PATH — partially mitigated by proactive warnings, but
  still a genuine GGIR/OS constraint, not structurally fixable from this codebase).

All items from the original assessment are now either fixed, explicitly ruled out
with evidence, or deferred with a documented reason. #17 is the only item still
genuinely open, and it's non-critical.

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

### 8. Sleep validity can silently resolve to NA — status: `fixed`

**Reclassified from Low to Medium/High during investigation** — this gates a real
inclusion/exclusion criterion for the study's sleep analysis, not just a diagnostic
or export path like most other items at this severity level. Left in its original
list position for history, but should be read as more consequential than "Low."

**Investigated before fixing — this was not what the original bug log guessed.**
The original entry assumed this was "too little test data for GGIR to compute
sleep efficiency" and would likely resolve itself on real data. Checked GGIR's
actual real-data output directly instead of assuming: confirmed via header
inspection that **no column matching "efficiency" exists anywhere** in this GGIR
version's Part 4 output, regardless of dataset size — `03_build_summaries.R` was
looking for a column (`SleepEfficiencyInSpt`) that was never going to exist.

**A deeper methodological question surfaced during the fix, and was resolved
against the primary source.** This project's own documentation disagreed with
itself about what the "≥50% valid sleep" criterion actually means:
`docs/data_info/data_dictionary.md` (citing Antczak et al. 2021) defines it as
**data completeness** (% of the night with valid, non-missing accelerometer data);
`r/GEBRUIKERSGIDS.md` and the code's own column search described it as **sleep
efficiency** (time asleep ÷ time in the estimated sleep window) — a different
concept entirely (a night can have complete data but poor sleep, or vice versa).
Resolved by checking Veerle's original protocol email (primary source), which
states verbatim: *"GGIR provides two estimates to determine data validity: the
number of valid hours and the fraction (%) of the night identified as invalid...
we will convert the fraction of the night identified as invalid to percentage of
the night identified as valid... at least 50% valid sleep data for five nights."*
Confirmed: **data completeness is correct**, not sleep efficiency. The
`GEBRUIKERSGIDS.md`/code assumption was a real mix-up (understandable — both are
"a percentage related to the night"), not a deliberate design choice.

**A second, independent bug was found and fixed alongside this one** (same block,
adjacent columns, discovered during review): `sleep_duration_h` used an unanchored
column-name pattern (`grep("duration|SleepDurationInSpt|sleep_dur", ...)`) that,
given GGIR's real column order, matched `SptDuration` (sleep-*window* length)
before `SleepDurationInSpt` (actual time asleep) — confirmed live: participant
`73044` was reporting **8.53h** (window length) instead of the correct **3.04h**
(actual sleep), a 5.5-hour overstatement, not a rounding footnote.

**Fix applied** (`r/pipeline/03_build_summaries.R`):
- The validity gate (`meets_sleep_criteria`, `n_valid_nights`) now derives
  `pct_night_valid = 100 × (1 − fraction_night_invalid)` from GGIR's real
  `fraction_night_invalid` column — confirmed present and populated in real data
  (0.365 for both real test participants) — matching Veerle's protocol exactly.
  This also let the old 0–1-vs-0–100 "scale detection" heuristic be removed
  entirely for this gate: `fraction_night_invalid` is unambiguously a 0–1 fraction
  by GGIR's own naming convention, so no detection is needed. Added a one-line
  sanity check (`message()` if any value falls outside [0,1]) as cheap insurance,
  per review feedback.
- A **separate** derived column, `derived_eff_ratio_pct` (`SleepDurationInSpt ÷
  SptDuration × 100`), is still computed — but now used *only* for the
  `sleep_efficiency_pct` reporting column / dashboard sleep tab (`mod_sleep.R`),
  explicitly not for the validity gate. Named to avoid colliding with the existing
  (now legacy/dead-in-practice, kept for other GGIR versions) `eff_col` grep
  pattern, which an earlier draft's column name accidentally did collide with.
- `sleep_duration_h`'s `dur_col` now matches `SleepDurationInSpt` exactly first,
  only falling back to the old loose pattern for GGIR versions without that exact
  column. The pre-existing unit-sanity heuristic (`raw_val >= 1` else warn+NA) is
  now skipped specifically when the exact match succeeds (known column, known
  units) — needed because two real dummy-set participants have genuine mean sleep
  durations under 1 hour (0.81h, 0.50h) and would otherwise have been wrongly
  nulled out with a false "unexpected value" warning.
- Updated `r/GEBRUIKERSGIDS.md` (3 places) and `config.yaml`'s
  `min_pct_night_valid` comment, which both still described the criterion as
  sleep efficiency — the same mix-up that caused the bug, left uncorrected would
  have misled the next person to touch this code the same way.

**Verified three ways:**
1. **Three rounds of independent static review**, tracking the fix through each
   revision: round 1 (efficiency-only) approved; round 2 (added the `dur_col` fix)
   caught nothing new beyond confirming round 1 held; round 3 (after the
   `fraction_night_invalid` pivot, following Veerle's email) — the only round that
   actually reviewed the final, correct validity-gate logic — found no blocking
   issues, independently re-verified the real header/values, and confirmed the
   `dur_col_is_known_hours` bypass correctly fixes the <1h-participants problem
   without affecting the fallback path. Two of round 3's minor suggestions (doc
   staleness, sanity-check message) were folded into the fix.
2. **Live before/after run on real, clean data** (post item #16b cleanup):
   confirmed `n_valid_nights`/`meets_sleep_criteria` were blank for every
   participant before the fix; after, both are correctly populated (e.g. real
   participants `1001`/`73044`: 1 valid night each — correctly `FALSE` for
   `meets_sleep_criteria`, since 5 nights are required and these tiny test
   recordings only have 1 — expected, not a bug). `sleep_duration_h` for `73044`
   corrected from 8.53h to 3.04h; `5901.csv`'s genuine 0.50h no longer wrongly
   nulled; `sleep_efficiency_pct` now shows real computed percentages (e.g. 92.8%,
   35.7%) instead of blank.
3. **Diffed everything else** before/after: `segment_summary.csv` byte-identical
   (this step never touches it); every non-sleep column in `analysis_ready.csv`
   (validity/MVPA/SB/segment columns) confirmed identical via `all.equal()` —
   proving the fix changed only what it was meant to change.

**Where:** `r/pipeline/03_build_summaries.R` (~lines 134-168 validity block,
~lines 210-260 averages block), `r/GEBRUIKERSGIDS.md`, `config.yaml` (comment only)

---

### 9. Segment-summary build is an unoptimized row-by-row loop — status: `wontfix` (benchmarked, not a real problem)
**Where:** `r/pipeline/02_label_segments.R:~348-445`

**Measured instead of assumed.** The original concern was speculative — "will be
slow at full-study scale" was never actually benchmarked. Built a synthetic harness
using the exact same loop body, `schedule_cache` structure, and `window_lookup`
hash-list lookup as the real code, sized to full study scale (400 participants ×
14 days = 5,600 participant-days, ~5-6 segments/day → 21,600 output rows).
**Result: 4.66 seconds.** Even with generous overhead for parts the synthetic
harness simplified (real `pupil_override_map` lookups, absence overlay, disk I/O),
this is nowhere near a real bottleneck.

**Not touching this code.** Rewriting an already-carefully-verified, correctness-
critical loop (this logic went through extensive review during Bug #7) for a
performance problem that measurably doesn't exist would only add risk for no
benefit. Closing as `wontfix` rather than `open` — the concern was investigated
and specifically ruled out, not just deprioritized.

---

### 10. `labeled_epochs.csv` / context-aware bouts not implemented — status: `deferred` (reviewed, scoped, not a quick fix)
**Where:** `r/pipeline/03_build_summaries.R:298-311`

**Re-confirmed via `docs/test/whats_going_on.md` item #2** (separate session review): independently
re-verified that `split_at_context_boundary`'s design/mechanism is correct (it splits a sedentary
bout whenever the school-context label changes mid-bout, via `bout_key <- paste(is_target,
ddata$context, sep = "|")` RLE logic in `detect_activity_bouts()`) — it's genuinely just inert
because `labeled_epochs.csv` doesn't exist yet, same root cause as this item, not a second bug.

Self-documented in the code and confirmed live
(`[WARN] labeled_epochs.csv not found — context-aware bout columns will be NA`). The
entire `config.yaml bouts:` section and all `bouts_30min_*` columns in
`analysis_ready.csv` currently have zero effect on output. Not silently broken — an
acknowledged, unfinished feature.

**Investigated the actual scope before deciding whether to implement.** The
consuming functions (`detect_activity_bouts()`, `compute_context_bout_summaries()`
in `utils_bouts.R`) are already fully implemented, and `01_run_ggir.R:141` already
sets `epochvalues2csv = TRUE`, so GGIR is already configured to export raw
epoch-level CSVs. The missing piece is a genuinely new pipeline step: read GGIR's
raw 1-second epoch export, join each epoch against the school-schedule boundaries
(the same logic `02_label_segments.R` already has, but at epoch instead of
day-segment resolution) to produce `labeled_epochs.csv`. At full study scale that's
~400 participants × 14 days × 86,400 seconds/day ≈ **480 million epoch-rows** — a
real memory/performance design question (chunking strategy, whether to keep it in
R or push to data.table's disk-backed options), not a quick fix.

**Decision: defer.** This is a new feature, not a bug fix — `bouts_30min_*` being
NA doesn't block validity, MVPA, sleep, or segment-level analysis, all of which are
core to tomorrow's real run. Implementing epoch-scale joining correctly needs real
design work and shouldn't be rushed the night before a real data collection run.
Revisit when there's time to design it properly, not as part of this pass.

---

### 16. `find_ggir_output_subdir()` picks the first `output_*` subdir with no ordering guarantee — status: `fixed`
**Where:** `r/pipeline/utils_ggir.R:40-51`

Discovered during Bug #7's independent review, not previously tracked. If a
meting's output directory ever accumulates more than one `output_*` subdirectory
(e.g. a partial re-run under a renamed `datadir`), `find_ggir_output_subdir()` picked
`ggir_subdirs[1]` — order from `list.dirs()`, not guaranteed stable or chronological
across filesystems. Affects every consumer of `find_ggir_results_dir()` /
`read_ggir_config()` (step 02's main part2 loading, `read_part4_sleep()`,
`resolve_ggir_qwindow()`, and now `pick_ggir_variant_file()` from Bug #18).

**Fix applied:** when more than one `output_*` subdir exists, sort by modification
time (most recently written = most likely the intended run) instead of taking
`list.dirs()`'s first result, and `warning()` (not just `message()`) listing every
candidate found and which one was picked, so it's visibly unusual rather than a
silent guess.

**Verified:** created two synthetic `output_*` dirs with different mtimes;
confirmed the function picks the more recently modified one and the warning fires
with an accurate message listing both candidates.

---

### 11. Unconventional participant-ID filenames degrade to `school_NA` — status: `fixed`
**Where:** ID parsing via GGIR `idloc=2`, consumed in `02_label_segments.R`

GGIR extracts the participant ID as everything before the first underscore in the
filename (confirmed: `1001_left wrist_...` → `1001`; `73044_0000001002.cwa` →
`73044`). The study's documented convention expects a 4-digit code where the first
digit is a school ID (1–6). `73044`'s first digit (`7`) doesn't match any configured
school. Confirmed this does **not** crash the pipeline — it degrades gracefully to
`school_NA` and a single `outside_school` segment spanning the full day, and QC 02
correctly surfaces a warning (`Participants found with no schedule in config.yaml:
school_NA`). No school-ID validation existed anywhere in the pipeline to catch this
earlier or more clearly.

**Fix applied:** `write_input_manifest()` (`utils_input.R`) already computes a
`school_id` per file for the manifest via `get_school_from_pupil()`. Added an
optional `valid_school_ids` parameter — when supplied, any file whose derived
`school_id` isn't in that set now triggers a `warning()` at input-scan time (right
at the start of `run_all.R`, before GGIR even runs), listing the exact
filename/pupil_id/school_id, instead of only surfacing much later as a silent
`school_NA` degradation caught solely by QC 02. `run_all.R` passes
`valid_school_ids` derived from `names(cfg$schedules)`. Optional parameter
(defaults to `NULL` = no check) so no other caller is affected.

**Verified:** ran `write_input_manifest()` against the two real test files
(`1001`, `73044`). Console: `[input] 1 file(s) have a school ID that doesn't match
any configured school (1, 2, 3, 4, 5, 6): 73044_0000001002.cwa -> pupil_id=73044,
school_id=7` — fires exactly on the known case, clearly, at the earliest possible
point in the pipeline.

---

## 📄 Documentation drift — status: `fixed`

From the original assessment, grouped as one item (was fixed together in one doc
pass, landed via a separate WIP that got merged into `main` alongside the bug_fix
branch — verified all five points directly against the current repo state, not
assumed from the commit message):

- ~~`CLAUDE.md`'s "Open Blockers" list is partially stale~~ — resolved: blocker #2
  (school 3/4 fallback schedules) marked resolved with sourcing details; blocker #3
  (real-data re-run confirmation) also now resolved as of this session (see
  `CLAUDE.md`). Blocker #1 (Veerle's original GGIR `config.csv`) remains genuinely
  open — no evidence it's been received.
- ~~Two documents `CLAUDE.md` references don't exist~~ — resolved: `CLAUDE.md` now
  explicitly notes these were removed rather than left as dead links.
- ~~`docs/data_info/school_info.md` is stale~~ — resolved: schools 3 and 4 now show
  their real, sourced schedules (school 3 with per-class overrides, school 4 with
  a documented Wednesday-end-time estimate), not the old generic fallback text.
- ~~`DEVELOPER.md` has two stale entries~~ — resolved: school 4 now shows
  "✅ Resolved... `fallback: false`", and the `do.report` note correctly says
  `c(2, 4, 5)`.
- ~~`CLAUDE.md`'s directory layout and `config.yaml`'s comment~~ — resolved: both
  now correctly state the summary CSVs land in `data/`, not `data/processed/`.

---

## ⚠️ Process / design gap — status: `fixed`

### 13. Summary CSV output path is not redirectable, and got overwritten during testing — status: `fixed`
**Where:** `r/pipeline/02_label_segments.R`, `r/pipeline/03_build_summaries.R`, `r/pipeline/utils_ggir.R`

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

**Fix applied:** added `backup_if_exists(path)` to `utils_ggir.R` — before each of
the three files is written, if a file already exists at that path it's copied to a
timestamped `<file>.bak.<YYYYMMDD_HHMMSS>` alongside it first (keeping the 5 most
recent backups per file, to avoid unbounded growth from routine dev/test
iteration). Chosen over making the output path independently configurable: a
backup-on-write safety net protects against the actual failure mode (silent,
unrecoverable overwrite) regardless of how `paths.data_processed` is set, including
the exact "redirected data_processed still resolves to the same parent" scenario
that caused this in the first place — a new config option would need to be used
*correctly* to help, whereas this fires unconditionally. Wired into all three write
sites: `segment_summary.csv` (`02_label_segments.R`), `analysis_ready.csv` and
`validity_summary.csv` (`03_build_summaries.R`). Also added `data/*.csv.bak.*` to
`.gitignore` so backups never get accidentally tracked.

**Verified:** wrote v1 of a test file, called `backup_if_exists()`, overwrote with
v2, called it again — confirmed two distinct timestamped backups created, each
containing the correct prior content. Separately confirmed the 5-backup cap: 8
sequential write+backup cycles left exactly 5 backup files, oldest pruned first.

---

## ℹ️ Minor — status: `open`

### 16b. Cleanup: `data/processed/` cross-contamination from mixed real/dummy test runs

While verifying item #16's rename, found `meting_1`'s output directory contaminated with
leftover milestones from two earlier test generations (a pre-rename dummy run and, briefly,
a partial post-rename dummy run) mixed in alongside the real-data run — a live instance of the
provenance gap discussed during Bug #15's investigation. Cleaned up: `meting_1` cleared and
regenerated fresh from the two real test files only; `meting_2` (previously 100% stale dummy
data left over from an earlier session, never run for real) replaced entirely with a clean run
on the renamed dummy IDs. `segment_summary.csv`/`analysis_ready.csv`/`validity_summary.csv`
regenerated from this clean state — 12 participants (2 real + 10 dummy), no phantom extras.
`config.yaml` confirmed restored byte-for-byte identical throughout (temporarily redirected
`data_raw`/`data_processed`/`example_mode` for isolated testing, backed up and restored each time).

Does not fix the underlying gap itself (still no automated provenance check — see the
"no provenance check" discussion under Bug #15) — this was a one-time manual cleanup of the
state that had accumulated in this repo, not a code change.

---

### 17. Deep output paths can hit Windows's 260-character MAX_PATH limit — status: `open` (non-critical)
**Where:** GGIR's own Part 5 report-writing (`g.report.part5`, via `data.table::fwrite`), triggered from `r/pipeline/01_run_ggir.R`

Discovered while verifying the dummy-ID rename (item #16's fix — not caused by it). Redirecting
`paths.data_processed` to a deeply-nested path (a session-scoped scratch directory used only for
that verification, ~150 characters before GGIR's own subfolders/filenames were even added) caused
GGIR to fail with `cannot open the connection` / `No such file or directory`, while the exact same
run against a short path (`C:/Users/.../Temp/sm_dummy_verify`) succeeded immediately. Confirmed the
failing path was exactly 260 characters — Windows's classic `MAX_PATH` limit (paths at or above
260 characters fail unless long-path support is explicitly enabled, which is not the default on
most Windows installs). GGIR's own report filenames are already fairly long on their own (e.g.
`part5_daysummary_full_MM_L56.3M191.6V695.8_T5A5.csv`), so this doesn't take an especially deep
project location to trigger — a repo checked out under a moderately nested path (e.g. a redirected
OneDrive/corporate profile folder, which is common on managed Windows machines) plus the default
`data/processed/<meting>/output_<meting>/results/QC/...` nesting could plausibly hit this on a real
researcher's machine, not just in ad-hoc testing.

**Not fixed, not urgent** — no evidence this affects the current repo location or any real run so
far, and it's an OS/filesystem constraint rather than a logic bug. Worth knowing about before
recommending a deployment location to Veerle or a colleague (e.g. avoid deeply nested folders,
or note that Windows long-path support may need enabling), rather than something to code around.

**Partially mitigated separately:** `validate_config.R` now warns proactively if
`paths.data_raw`/`data_processed` resolve past 140 characters (added alongside the
`bug_fix` branch merge), and the Windows bundle `.bat` launchers now check the
extraction path length upfront too. Neither is a structural fix of GGIR's own
report-writing — they're early warnings, not a guarantee GGIR itself won't hit
`MAX_PATH` on a sufficiently long path. Still `open` as a genuine GGIR/OS
constraint, but a researcher now gets warned before running, not after a confusing
mid-run failure.

---

### 14. renv version mismatch — status: `fixed` (documented; not reproducible from repo code)
`renv::status()` / every script run reports: *"renv 1.2.0 was loaded from project
library, but this project is configured to use renv 1.2.2."*

**Investigated:** `renv/activate.R` already correctly pins `version <- "1.2.2"`
(matching `renv.lock`'s own `"renv"` entry), and a fresh bootstrap in a clean
worktree correctly reports `Bootstrapping renv 1.2.2 ... Using renv 1.2.2 from
global package cache` with no mismatch warning. Could not reproduce the mismatch
itself — it depends on what's already sitting in a *specific machine's* project-
local `renv/library/.../renv/` folder (e.g. left over from before this project
pinned 1.2.2), not on anything in the repo's own config. Not a code bug.

**Fix applied:** documented the one-line resolution in `r/DEVELOPER.md` (new
"Troubleshooting" note right after "Starting a session"): run
`renv::restore(packages = "renv")` to sync the project's own renv copy to the
lockfile-pinned version, then restart R.

**Verified:** ran `renv::restore(packages = "renv", prompt = FALSE)` — completed
cleanly (`The library is already synchronized with the lockfile`), confirming the
documented command is valid and won't itself error if run on a machine that does
hit the mismatch.

---

## 🟡 Medium — found during Bug #5's independent review

### 15. Shiny "download part5" export hardcodes the `WW` variant — status: `fixed`

**Investigated before fixing:** re-verified against the live repo rather than trusting
the original wording. Confirmed `mod_export.R:193` still hardcodes
`dl_combined(pattern = "^part5_personsummary_WW_")`, with no fallback and no status
badge/disabled-state on the button at all (unlike `dl_segments`, which correctly shows
"Run stap 02 eerst" when its file is missing — this button gives no signal whatsoever).
Reproduced live, with genuinely clean (non-contaminated) data: right now,
`meting_1`'s real-data output only has a `Segments` file; `meting_2`'s dummy-data
output has both `Segments` and `WW`. Clicking the button as originally written would
silently download **meting_1's real participants dropped entirely**, not just an
empty file — worse than the originally-logged "empty CSV" scenario. Likely cause:
GGIR only produces the `WW` (waking-window) variant when it can reliably detect
sleep/wake periods, which depends on data quality/quantity — plausible to recur with
real study data, not just a testing artifact.

**Key context that shaped the fix:** in the real study, the same participant ID
appears in *both* meting_1 and meting_2 (repeated measures, not independent
participant sets). So a variant mismatch between metingen isn't just "some
participants missing" — it can mean the *same person's* two measurement waves get
computed under silently different day-boundary conventions (GGIR's `WW`/`MM`/
`Segments` variants define "a day" differently) sitting side by side in a raw CSV
handed directly to a researcher, feeding the dashboard's own "Meting 1 vs Meting 2"
comparison — with no downstream code to normalize or flag the difference, unlike the
main pipeline (`03_build_summaries.R`), which already handles mixed variants
internally via its `is_segments_file` check.

**Fix applied** (`r/shiny/modules/mod_export.R`):
- `dl_ggir()`: broadened the hardcoded `WW`-only pattern to the generic
  `^part5_personsummary_` (matching `03_build_summaries.R`'s existing approach), and
  attached the matched file's variant (`WW`/`MM`/`Segments`) as an R attribute on the
  returned data.frame — mirroring the existing `attr(out, "source_path")` pattern
  already used by `read_part4_sleep()` in `utils_ggir.R`.
- `dl_combined()`: captures that attribute into a local variable before any column
  mutation (to avoid depending on the attribute surviving `$<-` operations), adds it
  as an explicit `ggir_variant` column per meting, and — critically — replaced
  `do.call(rbind, ...)` with `rbindlist(..., fill = TRUE)` (the same idiom already
  used in `02_label_segments.R`/`03_build_summaries.R`), since `Segments` has a
  genuinely different column schema than `WW`/`MM` (confirmed by diffing real
  headers: `Segments` adds a `window` column and swaps `Nvaliddays`/`Nvaliddays_WD`/
  `Nvaliddays_WE` for `Nvalidsegments_WD`/`Nvalidsegments`/`Nvalidsegments_WE`).
  `do.call(rbind,...)` errors outright on mismatched columns; `rbindlist(fill=TRUE)`
  fills the gap with `NA` instead. Explicitly preserved the existing
  "return `NULL` when nothing found" contract (checked via `length(rows) == 0` before
  calling `rbindlist`, since an empty-list `rbindlist()` returns a valid 0-row table,
  not `NULL`, which would have silently changed the download handler's existing
  empty-CSV fallback behavior).
- `dl_part5` handler: only the pattern argument changed to match `dl_ggir`'s new
  generic pattern; everything else (filtering, `write.csv`) untouched.

**Explicitly out of scope for this fix** (a real, separate gap, deliberately not
addressed here): this button still has no status badge/disabled-state UI treatment
at all. Worth a follow-up to match `dl_segments`'s existing pattern.

**Verified three ways:**
1. **Two rounds of independent static review.** Round 1 caught a real blocking bug in
   the first draft: combining differently-shaped variant files via `do.call(rbind,
   ...)` would crash (not just silently mis-tag) the instant meting_1 and meting_2
   resolved to genuinely different variants — exactly the scenario this fix exists
   for. Round 2 (after switching to `rbindlist(fill=TRUE)`) confirmed the fix as
   applied is correct, traced the empty-list contract preservation, and confirmed
   `setDT()`/`extract_school_id()` behave correctly on the `data.table` `rbindlist`
   returns instead of the plain `data.frame` `do.call(rbind,...)` used to return.
2. **Live run against real, clean data** (post item #16b cleanup): replicated
   `dl_ggir`/`dl_combined`'s logic standalone against the actual
   `data/processed/` state. Before the fix, meting_1 (real participants `1001`,
   `73044`) would have been silently dropped entirely (no `WW` file). After the fix,
   both metingen's participants appear in the combined result, each correctly
   tagged `ggir_variant = "Segments"` (both metingen happened to resolve to the same
   variant with today's data).
3. **Synthetic fixture test forcing the actual mismatch scenario**: built minimal
   `Segments`- and `WW`-shaped CSVs for the same participant ID (`2011`) in
   meting_1 and meting_2 respectively (mirroring the "same person, two waves"
   real-world case above). Confirmed no crash; the combined table correctly contains
   both rows with `ggir_variant` set to `"Segments"` and `"WW"` respectively, and
   `NA` filled in for each row's non-applicable columns (`Nvaliddays_WD` NA for the
   Segments row, `window`/`Nvalidsegments_WD` NA for the WW row) — exactly the
   intended behavior.

**Where:** `r/shiny/modules/mod_export.R` (`dl_ggir`, `dl_combined`, `dl_part5`
handler, ~lines 157-200)

---

## 🔴 Critical — found after #15 shipped, still live in the core pipeline

### 18. part5 personsummary variant selection was arbitrary/alphabetical — status: `fixed`

**Context: this is why the delivered pipeline was silently excluding activity
data.** #15 treated the WW/MM/Segments mismatch as a Shiny-export-only
crash/mislabeling risk and fixed it there (safe `rbindlist(fill=TRUE)` +
`ggir_variant` tagging). It never asked *why* a meting would resolve to a
different variant in the first place, and it never touched the core pipeline
(`03_build_summaries.R`), which reads part5 personsummary through the exact
same "grab the first pattern match" logic.

**Investigated by actually running the fixed branch, not just re-reading the
log.** Ran the full pipeline against the bundled dummy data (`example_mode:
true`). GGIR produced **three** part5 personsummary files side by side in
`meting_1`'s own results directory — `MM`, `Segments`, `WW` — because
`do.report = c(2,4,5)` with `qwindow` set makes GGIR attempt all three
day-boundary conventions, and more than one can succeed for the same run.
`load_ggir_file()` (`r/pipeline/utils_ggir.R:85-87`, used by
`03_build_summaries.R:77` via `load_ggir(pattern = "^part5_personsummary_")`)
and `mod_export.R`'s `dl_ggir()` both did `list.files(...)[1]` — whichever
sorts first alphabetically, with zero regard for which one actually has data
for most participants.

**Confirmed live, in `analysis_ready.csv`:** `meting_1`'s alphabetically-first
file was `MM` (requires a full midnight-to-midnight day), which GGIR only
produced for **1 of 10** dummy participants. `Segments` (this study's actual
qwindow/school-day variant — the one `02_label_segments.R` already
hard-requires) covered **7 of 10**. The pipeline silently picked `MM`,
leaving `mvpa_min_day_avg`/`sb_min_day`/`lpa_min_day` blank for the other 9
participants in `analysis_ready.csv` — the file the whole study's scientific
output depends on — with no warning anywhere. `meting_2` (no `MM` file that
run) happened to resolve to `Segments` by the same alphabetical accident, so
the same participant's two measurement waves could also end up built from
different day-boundary conventions with nothing to catch it, same risk #15
already flagged for the Shiny export but never checked for in the pipeline.

**Fix applied:** added `pick_ggir_variant_file(files, prefer = c("Segments",
"WW", "MM"))` to `r/pipeline/utils_ggir.R`. When a pattern matches more than
one file it reads each candidate's participant count (`length(unique(ID))`),
picks the first variant present from the preference list (Segments first,
matching this study's design and `02_label_segments.R`'s own requirement),
`message()`s every candidate's coverage so the choice is visible in logs, and
`warning()`s if a non-chosen candidate actually covers *more* participants
than the one picked — so a wrong preference-list assumption on some future
dataset still surfaces instead of failing silently again. Wired into all
three call sites that had the ambiguous pattern:
- `load_ggir_file()` (used by `03_build_summaries.R`'s `load_ggir()`) —
  the core pipeline path that was silently dropping participants.
- `mod_export.R`'s `dl_ggir()` — replaces its own `files[1]`.
- `qc/qc_01_ggir.R`'s part5 personsummary check — was reporting a false
  `[PASS] ... — 1 participants` off whichever file sorted first; now reports
  the actually-chosen variant's real count.

`length(files) == 1` (the common case — most real runs won't have multiple
variants survive) short-circuits before any of this runs, so behavior is
unchanged whenever there's nothing ambiguous to resolve.

**Verified three ways:**
1. **Dummy data (`example_mode: true`), full pipeline re-run.** Console:
   `[ggir] Multiple part5 report variants found (MM=1p, Segments=7p, WW=2p) —
   using 'Segments'` for meting_1, `(Segments=8p, WW=4p) — using 'Segments'`
   for meting_2. `analysis_ready.csv`'s meting_1 activity columns went from
   1/10 participants populated to 7/10 (the remaining 3 genuinely have no
   valid Segments window in this short dummy data — not a selection
   artifact, confirmed by checking their raw Segments-file presence).
2. **Real native data** (`73044_0000001002.cwa`,
   `1001_left wrist_109488_2026-04-27 11-10-01.bin`, `example_mode: false`,
   copied into both metingen for a quick two-participant run): GGIR only
   produced a `Segments` file for either meting this run (no `MM`/`WW`
   survived) — confirms the `length(files) == 1` short-circuit path, no
   spurious warnings, both participants' MVPA/SB/LPA/sleep populated
   correctly in `analysis_ready.csv`.
3. **Shiny export, both datasets:** downloaded "Activiteitsprofiel per
   deelnemer" via the running dashboard in both scenarios above. Dummy-data
   export correctly shows `ggir_variant = "Segments"` for all rows, both
   metingen. Real-data export contains both real participants (`1001`,
   `73044`), both metingen, both tagged `Segments`.

**Where:** `r/pipeline/utils_ggir.R` (new `pick_ggir_variant_file()`,
`load_ggir_file()`), `r/shiny/modules/mod_export.R` (`dl_ggir()`),
`r/qc/qc_01_ggir.R` (part5 personsummary check)

---

## 🆕 Additional issues — from `docs/test/whats_going_on.md` (session 2026-07-22)

Consolidated in from a separate ad-hoc issue log (`docs/test/whats_going_on.md`) so
`bug_log.md` stays the single place all tracked issues live. Cross-checked
`docs/test/veerleproject_assessment.md` against the items above at the same time —
every finding in that document is already reflected here (it's the document
`bug_log.md` was originally consolidated from), so nothing new to add from it.

### 19. `qwindow_strategy: auto` never pooled `class_overrides` boundaries — status: `fixed`

**Where:** `r/pipeline/01_run_ggir.R:35-58` (`build_qwindow_from_schedules()`),
`config.yaml:154-166` (school_3 `class_overrides`), `r/pipeline/02_label_segments.R:312-377`
(per-pupil override schedule construction)

**Investigated before fixing:** traced the full chain end-to-end rather than trusting
the surface description in `docs/test/whats_going_on.md` item #1, which first raised
this. Confirmed: `build_qwindow_from_schedules()` pools `school_start`/`school_end`/
`breaks` from every school into one shared qwindow list used by a single `GGIR()` call
per meting — all schools processed together, GGIR itself has no concept of "school."
Separately, `02_label_segments.R` already builds an exact per-pupil schedule for
school_3's 13 `class_overrides` pupils (classes 2Aa/2Ab/2Ba/2Bb), including their real
16:25 late-dismissal boundary on override days — but `build_qwindow_from_schedules()`
never read `class_overrides` at all, so under `qwindow_strategy: auto` the shared
qwindow list never contained a 16:25 cut. Confirmed the practical consequence:
`distribute_qwindow_cols()` (`02_label_segments.R:276-300`) apportions activity by
time-overlap whenever a real segment boundary doesn't land exactly on a qwindow cut —
so those 13 pupils' after-school segment on override days was being estimated via
overlap-interpolation instead of exact-matched, identical treatment to `manual` mode,
defeating `auto`'s purpose for that subset.

Also confirmed **this bug was dormant in practice**: `config.yaml`'s live
`qwindow_strategy` is `"manual"` today, and the manual `qwindow:` list also lacks a
16:25 cut — so nothing is currently worse because of this bug. It only becomes live
once `qwindow_strategy` is switched to `"auto"`, which the project owner confirmed is
the intended eventual setting for the real run.

**Fix applied:** extended `build_qwindow_from_schedules()` to also pool boundary times
from `class_overrides`, generically — scans for any value shaped like `HH:MM` anywhere
under a school's `class_overrides`, rather than hardcoding the `school_end_override`
key name:
```r
if (!is.null(sch$class_overrides)) {
  override_vals <- unlist(sch$class_overrides, use.names = FALSE)
  is_hm <- grepl("^\\d{1,2}:\\d{2}$", override_vals)
  all_times <- c(all_times, override_vals[is_hm])
}
```
Chosen generically (scan-any-HH:MM-shaped-value) rather than special-casing
`school_end_override` by name, per independent review feedback, so a future override
type (e.g. a hypothetical `school_start_override` or break-time override — neither
exists today) doesn't silently reintroduce the same gap.

**Explicitly considered and not chosen:**
- *Doc-only fix* (reword `config.yaml`'s "auto" comment to disclose the gap without
  closing it) — rejected as insufficient once the project owner confirmed `auto` is
  the intended real-run setting; a known, closeable precision gap shouldn't ship as a
  documented limitation when a small, contained code fix removes it.
- *Per-school GGIR calls* (make GGIR genuinely school-aware by splitting the single
  shared `GGIR()` call into one per school) — rejected as disproportionate: verified
  `02_label_segments.R:213-223` currently hard-asserts meting_1/meting_2 resolve to one
  identical shared qwindow (`stop()` if they diverge), and the window-lookup logic is
  keyed only by `ID date window_idx` with no school dimension anywhere — reworking
  this would be a much larger blast radius. Also confirmed this wouldn't even fully
  solve the class_overrides case on its own, since the overrides apply to a *subset of
  pupils within* school_3, not the whole school — would need to go to per-class or
  per-pupil GGIR calls to fully resolve, an even bigger change.

**Verified two ways:**
1. **Independent static review** (fresh agent, no prior context): confirmed the bug's
   existence and mechanism by reading the actual code and `config.yaml`; separately
   verified the proposed fix's exact R snippet by constructing/running it against the
   real parsed `class_overrides` structure — confirmed pupil-ID integers (`3025`-`3042`)
   are correctly excluded by the regex, all `"16:25"` values are correctly kept,
   `hm_to_h()` is unaffected by duplicates (already deduplicated upstream via
   `unique()`), and no degenerate-coercion risk exists in the current pupil ID range.
2. **Live execution against the real current `config.yaml`** (post-fix, independent
   agent run): confirmed the applied fix's actual output — auto-derived qwindow grew
   from 34 to 35 boundaries, the new value is `16.4167` (16:25), traced specifically to
   school_3's `class_overrides` (the only school with any), and every other school's
   boundaries are unchanged. Confirmed the resulting vector is still valid for GGIR's
   `qwindow` argument (numeric, strictly ascending, 0→24, no NAs, no duplicates).
   Confirmed `config.yaml`'s live `qwindow_strategy` is still `"manual"`, so this fix
   has zero effect on the current production setting — it activates only once/if
   switched to `"auto"`, consistent with the config's own existing note that switching
   strategies requires a full step-01 rerun.

**Impact:** closes the one confirmed concrete precision gap in `qwindow_strategy: auto`
for school_3's 13 `class_overrides` pupils, ahead of the project owner's planned switch
to `auto` for the real study run.

---

### 20. `CLAUDE.md` mischaracterized `min_wear_hours_per_day` as a "waking hours" criterion — status: `fixed`

**Where:** `CLAUDE.md` ("Key Domain Concepts" table)

Documentation-only, already fixed prior to this session. `CLAUDE.md`'s validity-criteria
row now correctly states the 24h-calendar-day valid-wear-hours mechanism (GGIR's
`includedaycrit`), distinct from the non-configurable waking-hours `includedaycrit.part5`
used only internally by Part 5. Full investigation detail (independent agent verification
against GGIR's own decompiled source) preserved in `docs/test/whats_going_on.md` item #3.
Logged here for completeness, since `bug_log.md` is now the single place all tracked
issues live.

---

### 21. Claude Code hooks hardcoded to the original author's Mac path — status: `fixed`

**Where:** `.claude/settings.json` (all three hook `command` entries)

All three hooks (GDPR guard, config guard, R syntax check) were wired to
`python3 /Users/timothydhoe/Code/veerle-project/.claude/hooks/<script>.py` — a
hardcoded absolute Mac path invoked via `python3`. Confirmed on this Windows machine:
the path doesn't exist and `python3` isn't resolvable on PATH (only `python`, via
Anaconda). None of the three hooks fired here, silently — contrary to `CLAUDE.md`'s
"Hooks (automatic) ... Fire without any invocation" framing.

**Fix applied (commit `8835844`):** each hook command now resolves the interpreter at
runtime (`if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi`)
and invokes the script via `"${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>.py"`, with
`"shell": "bash"` set explicitly on each hook entry so the `if`/`command -v` syntax has
a POSIX shell to run under regardless of the platform default.

**Verified 2026-07-22:**
- Interpreter fallback: `command -v python3` fails on this machine as expected, falls
  back to `python` (Anaconda) — confirmed by running the resolution logic directly.
- `${CLAUDE_PROJECT_DIR}` resolves to the correct repo root.
- End-to-end: force-staged a dummy file in `data/raw/`, ran `gdpr_guard.py` with a
  realistic Windows-style `cwd` (`C:/Users/...`) piped in as the hook payload would
  provide, and confirmed it blocks the commit (exit code 2) with the expected message;
  confirmed it passes clean (exit 0) when nothing forbidden is staged.

**Caveat (not a live bug, just a fragile assumption):** `gdpr_guard.py` passes the
JSON payload's `cwd` straight into `subprocess.run(cwd=...)`. This only works because
Claude Code's harness supplies a native Windows-style path on this platform — a
POSIX-style `cwd` (e.g. `/c/Users/...`, as bash's own `$(pwd)` would produce) crashes
that call with `NotADirectoryError: [WinError 267]`. Confirmed this failure mode during
testing when a POSIX-style `cwd` was substituted; not something the fix needs to
handle unless the harness's `cwd` format ever changes on this platform.

---

### 22. `.claude/commands/pipeline-status.md` checks the wrong output path — status: `open`

**Where:** `.claude/commands/pipeline-status.md:15,17`

Checks `data/processed/segment_summary.csv`, `data/processed/analysis_ready.csv`, and
`data/processed/validity_summary.csv` — these three files actually land in `data/`
directly (confirmed via `config.yaml`'s own comment and the write-path code in
`02_label_segments.R`/`03_build_summaries.R`). Same underlying path confusion already
fixed in `CLAUDE.md`'s directory layout and `config.yaml`'s own comment (see the
"Documentation drift" section above) — but this specific command file was missed by
that pass.

**Impact:** running `/pipeline-status` today under-reports progress, showing these
three outputs as missing even when the pipeline has completed through step 03. The
GGIR raw-output path checks in the same command are correct and unaffected.

---

### 23. `.claude/settings.local.json` has the same stale Mac-specific path, in the permissions allowlist — status: `fixed`

**Where:** `.claude/settings.local.json`

Contained `"Bash(/Users/timothydhoe/Syntra/.venv/bin/python3 *)"` — same root cause as
#21, but harmless in practice: it was an unused allowlist pattern, not something
that executed on its own. The #21 fix (commit `8835844`) only touched
`.claude/settings.json`, so this entry was missed by that pass.

**Fix applied 2026-07-22:** removed the stale line from the `permissions.allow` array.
`"Bash(python3 *)"` (a few lines above it, still present) already covers the general
case portably.

---

### 24. Stale `data/processed/` path in pipeline code header comments — status: `open` (comment-only, no functional impact)

**Where:** `r/pipeline/02_label_segments.R:14`, `r/pipeline/03_build_summaries.R:9-10`

Header comments describe output paths as `data/processed/segment_summary.csv` etc. —
the code itself correctly writes to `data/` directly (same actual location #22
confirms). Comment-only drift, no functional impact.

---

### 25. `Makefile`'s `py-*` targets are dead — status: `open`

**Where:** `Makefile:1-11`

`py-install`, `py-lint`, `py-test` all `cd python && ...`, but no `python/` directory
exists anywhere in the repo — predates the Python-deferred architecture decision and
the `to_be_built/` reorganization (which relocated the repo's only Python files, an
unbuilt attendance-prediction backlog feature, to `to_be_built/`, not `python/`).
Running any of these three targets fails immediately with "no such file or directory."
Only `r-install` (`cd r && Rscript install.R`) is real.

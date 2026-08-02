# SchoolMove — Feature Log

Tracks **new/requested functionality** — work that isn't a defect in existing behavior,
but something that doesn't exist yet (or exists in code but isn't actually usable by
Veerle in the delivered Windows bundle). Kept separate from `docs/test/bug_log.md`,
which tracks defects in already-intended behavior. Uses its own number sequence
(unrelated to `bug_log.md`'s numbering) — cross-reference by filename + number, e.g.
"see bug_log.md #17".

If investigation during any item below turns up an actual defect (not a missing
feature), log that as a new item in `bug_log.md` instead — don't let it hide inside a
feature entry here.

Status legend: `proposed` · `in-progress` · `built-unverified` · `verified` ·
`wontfix` · `deferred`

- **proposed** — requested, not yet planned/scoped.
- **in-progress** — plan approved, being implemented.
- **built-unverified** — code written, but not yet confirmed working end-to-end
  through the actual delivery path (the built Windows bundle Veerle runs — see
  workflow step 8 below). Don't linger here; this status exists to make an
  untested-in-the-real-path feature visible, not to be a comfortable resting state.
- **verified** — confirmed working through the built Windows bundle, not just in
  RStudio/dev. This is the bar for "done" in this log.
- **wontfix** — considered, deliberately not building it (document why).
- **deferred** — real, scoped, but intentionally postponed (document why and what
  would trigger picking it back up).

---

## Workflow

Paste this to continue in the same style:

> We're working through `docs/test/feature_log.md` in SchoolMove, one feature at a
> time. Keep using this workflow for every item:
>
> 1. **Describe the request in plain terms** — what's wanted and why it matters to
>    the study/researcher, in your own words back to me, so we can catch
>    misunderstandings early.
> 2. **Ask clarifying questions** to pin down exactly what's wanted/expected —
>    acceptance criteria, edge cases, who uses it and how (Veerle via the dashboard?
>    a script? both?). Don't assume — a feature request is inherently more
>    underspecified than a bug report, since there's no existing broken behavior to
>    anchor on.
> 3. **Investigate the current state of the program against that request** before
>    proposing anything — read the actual current code, don't assume the request
>    describes a blank slate. Check whether it already exists in whole or in part
>    (this has already happened once: the absence feature turned out to be fully
>    built via `data/absences.csv` + the Instellingen tab, just not reachable through
>    the Windows bundle). Check `bug_log.md` too in case this is actually a known,
>    already-tracked defect rather than new work.
> 4. **Write up a plan**: approach, files touched, what "done" looks like, and any
>    tradeoffs worth flagging.
> 5. **Get an independent agent review of the plan itself** (fresh context,
>    static/read-only, no code execution) before presenting it to me — catch flawed
>    assumptions or design issues before I ever see the plan, same discipline
>    `bug_log.md` uses for non-trivial fixes.
> 6. **Present the (possibly revised) plan**, with options/tradeoffs where relevant,
>    and a clear recommendation. Leave room for my questions.
> 7. **Wait for explicit approval before touching any file** — no changes on spec
>    alone.
> 8. **Apply the change**, then **test afterward**: confirm the feature actually
>    works as intended, and confirm nothing else broke — run the affected
>    pipeline/dashboard before and after, diff output CSVs where relevant, same
>    regression discipline as `bug_log.md`. If the feature is anything Veerle would
>    touch standalone (dashboard, pipeline run, config), also confirm it works
>    through an actual built Windows bundle (`scripts/bundle/build-bundle.ps1`
>    output), not only in RStudio/dev — that gap is exactly what's currently blocking
>    the absence feature, and dev-only testing is what let it go unnoticed.
> 9. **Update `docs/test/feature_log.md`**: set the status, and document what was
>    tried/rejected and why, what was applied, and exactly how it was verified —
>    same reference format `bug_log.md` uses for its fixed items.
> 10. **Log any new issues discovered along the way** as their own tracked items —
>     new items here if feature-shaped, or flag for `bug_log.md` if it's actually a
>     defect — don't just mention them in passing and drop them.
> 11. Move to the next item, one at a time. Don't batch multiple items' approvals
>     together.

---

## Open

Collected from the project owner on 2026-07-23, not yet investigated/planned. See
`docs/test/order_of_approach.md` for working order and reasoning across these plus
the parallel `bug_log.md` items (#29–31).

### 1. Pipeline-wide error/log-to-file capture — status: `built-unverified`

Write errors/warnings encountered along the full pipeline run to a `.txt` log file,
overwritten by default on each run, with the option to redirect to a different
(persistent) location when a specific run is worth keeping. Directly closes the
follow-up noted in `bug_log.md` #17 ("if a general error-logging system gets built
for other reasons, route this constraint's warning through it too" — no such system
currently exists in the codebase). Second in working order per
`order_of_approach.md` — pure infrastructure, no dependencies, and helps debug
several later items (bug #29, feature #4 below).

**Clarified scope** (project owner, 2026-07-27): errors/warnings only, not a full
console transcript (keeps the log small/scannable — GGIR's own internal
`suppressWarnings()`/`message()` calls are out of scope regardless, since anything a
package swallows before it reaches R's condition system can't be caught no matter how
the call is wrapped). Covers both the pipeline scripts *and* the Shiny dashboard
(startup + runtime). Persistence is manual copy-after-the-fact — no new config.yaml
key.

**Independent review of the plan** (fresh agent, static/read-only, before
implementation) returned "sound-with-changes" and confirmed: `r/pipeline/` is already
established as shared code sourced by both the pipeline and Shiny (`utils_ggir.R`
precedent), the current error/warning surface is almost entirely un-swallowed so
outer handlers see real signal (`01_run_ggir.R`'s `do.call(GGIR, ...)` is bare, no
local `tryCatch`), the `withCallingHandlers`+`tryCatch` combination is a standard,
correct R idiom, and `options(shiny.error = ...)` is appropriate for the pinned shiny
1.13.0. It also caught two real gaps, both folded into the implementation: (1)
`bug_log.md` #17's MAX_PATH warning (raised via `validate_config()`, called from both
entry points) is captured for free since it now runs inside the wrapped code — closes
that follow-up too; (2) the plan initially didn't route through the `.bat` launchers'
existing failure messaging — added a line to each pointing at the relevant log file.

**Applied:**
- New shared helper `r/pipeline/utils_logging.R`: `init_pipeline_log()` (create/
  truncate + header), `log_warning()`/`log_error()` (append timestamped lines), and
  `with_logged_conditions(expr, log_path, context)` — wraps an expression, logging any
  warning without muffling it (console output unaffected) and logging any error before
  re-throwing it (existing failure behaviour, e.g. the `.bat`'s errorlevel check,
  unaffected).
- `r/pipeline/run_all.R`: initializes `logs/pipeline_errors.txt` at the top; wraps
  config validation and each of the three step `source()` calls (labeled
  "01_run_ggir.R" / "02_label_segments.R" / "03_build_summaries.R" in the log).
- `r/shiny/global.R`: initializes `logs/shiny_errors.txt` (sourced first, before
  `library()` calls — dependency-free base R); wraps config validation and the entire
  startup data-loading block (`analysis_ready`/`validity_summary`/`part2`/`part4`/
  `part4_full`/`add_waking_valid_hours()`/`segment_summary` — a `{ }` block passed as
  a lazy argument still assigns into the calling environment, so nothing about how
  these objects are exposed to the rest of the app changes); adds
  `options(shiny.error = ...)` for errors during reactive/render execution after
  startup.
- `scripts/bundle/templates/1 - Pipeline uitvoeren.bat` and
  `2 - Dashboard starten.bat`: on `errorlevel 1`, now also print the relevant log
  file's path alongside the existing "check the console" message.

**Verified live**, 2026-07-27, once R was found to be installed on the machine after
all (`C:/Program Files/R/R-4.5.3`, just not on PATH). Ran the real pipeline twice
against `data/raw/veerle_testdata` (participants 1001/73044 — same real device data
bug #31 was verified against), with `config.yaml`'s `data_raw` temporarily redirected
and restored each time (`git diff` confirmed byte-identical after both runs).

**First run surfaced two real defects** — exactly why this step exists rather than
trusting static review alone:
1. `write_input_manifest()`'s call in `run_all.R` (before the wrapped Step 01) was
   never wrapped, so a real, useful warning (`"2 file(s) have a school ID that doesn't
   match any configured school"`) reached the console but not the log.
2. GGIR's Part 1 processing emitted ~1197 near-identical `NAs introduced by coercion`
   / `argument is not numeric or logical: returning NA` warnings in under two seconds
   — the opposite of what the independent plan review's warning-propagation check had
   suggested was likely, and it defeated the "small, scannable" goal outright
   (`pipeline_errors.txt` came out to 1198 lines, 1197 of them one of two messages).

**Both fixed and re-verified** in a second live run:
- `write_input_manifest()`'s call is now wrapped the same way as the three pipeline
  steps.
- `utils_logging.R` now collapses consecutive identical `(level, context, message)`
  entries into one line with a `(xN)` suffix, buffered in an internal dedup state and
  flushed on the next distinct message, on `log_error()` (before it stops execution),
  and via `on.exit()` when each `with_logged_conditions()` call finishes. Second run's
  `pipeline_errors.txt` came out to 15 lines total — the school-ID warning, the
  coercion warnings correctly collapsed (e.g. `(x560)`, `(x420)`), and the one real
  part5-variant-coverage warning from `03_build_summaries.R` — genuinely scannable.
- Confirmed no `ERROR` lines in either run (both exited 0), and `config.yaml` restored
  byte-identical both times.

**Shiny side also verified live**, not just statically: sourced `global.R` directly
(`Rscript -e "setwd('shiny'); source('global.R')"`, run from `r/` so `.Rprofile`
activates renv) against the real processed output from the pipeline run above.
Completed without error (`part2`: 20 rows, `analysis_ready`: 4 rows — real data,
correctly loaded), and `logs/shiny_errors.txt` was created with just its header line
(nothing to log — a clean run, correctly reflected). This exercises the wrapped
config-validation and startup-data-load code paths, and implicitly confirms
`options(shiny.error = ...)` is syntactically valid (the file wouldn't have sourced
otherwise) — but not the reactive/runtime error path itself, which needs a live
browser session to trigger, nor a run through the actual `.bat`-launched Windows
bundle.

**Remaining gap, honestly stated:** not yet run through the built Windows bundle
(`scripts/bundle/build-bundle.ps1` output, launched via the real `.bat` files) — this
log's own bar for `verified`. Given how much was actually exercised live here (real
pipeline run twice, real data, real bugs found and fixed, Shiny startup path
confirmed), staying at `built-unverified` is a matter of this log's stated definition
rather than remaining doubt about correctness — recommend closing that specific gap
opportunistically alongside the full bundle audit (item 8 in `order_of_approach.md`)
rather than as a special one-off trip through the bundle just for this.

### 5. Performance / dead-code audit — pipeline & bundle "fluidity" check — status: `proposed`

Requested by the project owner while scoping feature #1 (error/log-to-file capture), out
of concern that the bundle is "already a pretty slow process" — adding more
infrastructure, even cheap infrastructure like #1, shouldn't be layered onto
un-investigated existing slowness without first checking whether some of it is avoidable
(unnecessary code, redundant computation, dead weight) rather than inherent GGIR/IO cost.

Scope to pin down at investigation time: does "the end product" mean the bundle's
pipeline run (`1 - Pipeline uitvoeren.bat`), the dashboard launch
(`2 - Dashboard starten.bat`), or both. Candidate places to look, not yet investigated:
redundant data loads (e.g. `global.R` reading `part2`/`part4`/`part4_full` as three
separate full CSV passes at every dashboard startup — see #1 and `bug_log.md` #31),
any dead/unused code paths, and whether GGIR's own per-participant runtime (already
measured at 42–53+ min for just 2 dummy participants, per `windows-verify.yml`'s own
comment) has any avoidable overhead on this project's side versus being purely
GGIR-internal cost.

Fourth in working order per `order_of_approach.md` — placed right after the logging
feature (#1) and before the bundle-terminal bug (`bug_log.md` #29), so later
performance-sensitive work (dashboard startup performance, #3; the full bundle audit,
#4) targets a lean baseline instead of possibly redoing tuning around code this audit
ends up trimming, and so the heaviest remaining feature (`labeled_epochs.csv`, #2 —
~480M rows at full study scale) isn't built on top of unexamined existing inefficiency.

### 2. Make `split_at_context_boundary` / `labeled_epochs.csv` functional — status: `built-unverified`

Is `split_at_context_boundary()` (in `utils_bouts.R`) actually functional end-to-end?
If not, make it so. Same gap already tracked as `bug_log.md` #10 (`deferred`, now
superseded by this item's build): that item confirmed `split_at_context_boundary()`
and `detect_activity_bouts()` are correctly implemented, but inert because
`labeled_epochs.csv` doesn't exist yet. Sixth in working order per
`order_of_approach.md` — tackled after the validity-criterion bug (bug #31) and the
performance/dead-code audit (#5) settled.

**Investigation before building (workflow step 3) surfaced two scoping corrections
to the original request**, both confirmed live on real device data
(`data/raw/veerle_testdata`), not just dummy data:
1. GGIR's `epochvalues2csv` export is **5-second** resolution, not 1-second as every
   prior doc/comment assumed (`bug_log.md` #10, `optimization_log.md` #3, this repo's
   `config.yaml` `dev.epoch_length_s: 1` comment all said 1s — that key describes a
   different input path, pre-converted CSVs, and doesn't apply to GGIR's own epoch
   export). Real-scale estimate is therefore ~96M rows (400 participants × 14 days),
   not ~480M.
2. `detect_activity_bouts()` hardcoded a 1-second-epoch assumption in its bout-length
   arithmetic (`min_bout_min * 60L` / `runs$lengths / 60`) — fed real 5s-epoch data
   unmodified, this would have required 5× the real elapsed time to reach a nominal
   30-minute threshold. Caught by an independent plan review before any code was
   written (see below).

**Two rounds of independent plan review** (fresh agents, static/read-only, before
implementation) were run, per this log's workflow. Round 1 (verdict:
sound-with-changes) caught the epoch-length bug above, plus: no timestamp `%z`
parsing plan for the epoch CSV's ISO8601+offset format, no `backup_if_exists()` call
planned before the new step's write, no crash-safe write pattern, and an incomplete
wear/non-wear polarity check (see below). Round 2 (verdict: sound-with-changes) found
the epoch-length fix's formula wasn't spelled out precisely enough to implement
safely, the wear-polarity sanity check had no way to receive the `part2` data it
needed, the planned schedule-cache extraction would have silently broken (missing
`hm_to_h`/`%||%` dependencies), the absence-overlay logic wasn't being extracted
alongside the schedule-cache logic (copy-drift risk), and a real operational gap: if
a study's GGIR output already exists with `overwrite: false`, turning on epoch
labeling afterward could hit GGIR's milestone caching and never produce the epoch
export at all. All of these were folded into the plan before implementation.

**Applied:**
- `config.yaml`: new `bouts.enable_epoch_labeling` (default `false` — expensive at
  full study scale). Gates both `01_run_ggir.R`'s `epochvalues2csv` (previously
  unconditional `TRUE`, closing `optimization_log.md` #3 as a side effect) and
  whether `02b_label_epochs.R` runs. `bouts.split_at_context_boundary` is now
  actually read (previously a dead setting, unconditionally always-split regardless
  of its value) — Veerle's confirmed methodology is "always split," so behavior is
  unchanged, but the config flag is no longer a no-op.
- New `r/pipeline/utils_schedule.R`: `build_schedule_cache()`, `build_pupil_override_map()`,
  `get_schedule()`, `extract_school_id()`, `resolve_schedule_key()`, `read_absence_keys()`,
  and `ABSENCE_OVERLAY_SEGMENTS`, extracted out of `02_label_segments.R`'s inline code
  (was previously ~100 lines of script-level logic, not reusable) so the day-level
  (`02`) and new epoch-level (`02b`) labeling steps share one implementation instead
  of two that could drift apart. `02_label_segments.R` refactored to call these —
  verified byte-identical `segment_summary.csv` before/after the refactor.
- `utils_bouts.R`: `detect_activity_bouts()` gained an `epoch_length_s` parameter
  (explicit arg, or read from an `epoch_length_s` column in the epoch data if
  present, defaulting to 1 for legacy callers/tests) replacing the hardcoded 1s
  arithmetic, and a `split_at_context_boundary` parameter that actually controls
  whether bouts split at context changes (previously always did, regardless of any
  setting). `compute_context_bout_summaries()` wires both through from
  `bout_cfg`/the epoch data automatically.
- New `r/pipeline/utils_epoch_labeling.R`: `build_labeled_epochs_for_participant()`
  reads one participant's raw epoch CSV, parses ISO8601+offset timestamps (tested
  across a Europe/Brussels DST transition), derives the real epoch length
  empirically from the data's own timestamp deltas (not hardcoded, not read from the
  unrelated `dev.epoch_length_s` key — sanity-floored/ceilinged to [0.1, 300]s with a
  fallback), pulls wear/non-wear from GGIR's internal `IMP$r5long` (in
  `meta/ms2.out/*.RData` — an undocumented GGIR structure, degrades to `wear = NA`
  on a length mismatch rather than crashing, plus a sanity cross-check against
  `part2`'s trusted `n_valid_hours`), classifies intensity via `cut_points_mg`
  (converting ENMO's g units to the config's mg-based cut-points), and looks up
  school context via the shared `utils_schedule.R` helpers plus the same
  absence-overlay logic `02_label_segments.R` uses (in_class/recess/lunch only).
- New `r/pipeline/02b_label_epochs.R`: the actual pipeline step. Iterates
  participants from `part2`'s own `(ID, filename)` pairs — **not** by scanning
  `meta/csv/` directly, since GGIR's own participant ID can differ from the raw
  device filename (confirmed: real participant `1001`'s file is
  `1001_left wrist_..._.bin`, but GGIR's `idloc=2` truncates the ID to `1001` at the
  first underscore — same behavior `bug_log.md` #11 already documented). Calls
  `backup_if_exists()` before writing, writes to a temp path and renames to
  `data/processed/labeled_epochs.csv` only on success (crash-safe), streams
  per-participant via `fwrite(append=)` rather than accumulating the full ~96M-row
  table in memory. Warns clearly if an expected epoch CSV is missing, suggesting a
  `ggir.overwrite: true` rerun (the milestone-caching gap Round 2's review flagged).
- `03_build_summaries.R`: fixed a pre-existing, previously-undiscovered path bug
  (logged separately as `bug_log.md` #32) where `labeled_epochs_path` resolved
  outside `data/processed/` entirely — the block was unreachable before this feature
  existed, so it was never caught.
- `run_all.R`: sources `02b_label_epochs.R` conditionally on
  `bouts.enable_epoch_labeling`, wrapped in the existing logging infra (feature #1).

**Verified live, four ways:**
1. **Unit-level, manually** (testthat isn't installed in this environment — no
   network access to bootstrap `renv`): every new/changed function
   (`detect_activity_bouts()`'s epoch-length and split-boundary logic,
   `utils_schedule.R`'s cache-building and lookup functions, `derive_epoch_length_s()`,
   `classify_intensity()`, `build_labeled_epochs_for_participant()` including the
   `r5long` mismatch fallback, missing-ms2out fallback, weekend labeling, DST
   handling, and absence overlay) was exercised via hand-written assertions
   replicating the testthat-format tests now in `r/tests/testthat/` — all passed.
   The testthat files themselves are committed for when a real `renv`-backed R
   environment runs the suite.
2. **Real-data mechanical check**: ran `build_labeled_epochs_for_participant()`
   against both a dummy participant (1901) and a real GENEActiv device participant
   (1001, from `data/raw/veerle_testdata`, already processed by the real pipeline).
   For both, summed epoch-derived wear hours (via the new `wear` column ×
   `epoch_length_s`) matched `part2`'s already-trusted `n_valid_hours` **exactly**
   (51.75h and 18.5h respectively) — strong independent confirmation `IMP$r5long`'s
   polarity assumption is correct, not just structurally length-matched.
3. **Functional, end-to-end**: with `enable_epoch_labeling: true`, ran
   `02b_label_epochs.R` against the existing (mixed dummy+real) GGIR output —
   produced `labeled_epochs.csv` with exactly the expected row count (269,640 =
   sum of each participant's epoch count across both metingen). Ran
   `03_build_summaries.R` — `analysis_ready.csv` correctly gained real, non-NA
   `bouts_30min_{after_school,before_school,in_class,weekend}_{n,total_min}` columns.
4. **Regression, byte-for-byte**: captured `segment_summary.csv`/`analysis_ready.csv`/
   `validity_summary.csv` as a baseline *before any code in this item was touched*.
   After the full change-set, with `bouts.enable_epoch_labeling: false` (the shipped
   default) and `labeled_epochs.csv` absent (the true default state, not just the
   flag off), all three files came back **byte-identical** to that original
   baseline — confirms this entire feature is a true no-op until explicitly enabled,
   with zero effect on the existing pipeline. The demo `labeled_epochs.csv` produced
   during step 3's testing was deleted afterward rather than left as a stray
   artifact that could confuse a later run.

**Remaining gap, honestly stated:** not yet run at full study scale (~96M rows, 400
participants) — only dummy-scale and the 2 real `veerle_testdata` participants (both
finished in seconds). Full-scale timing/memory is unmeasured and should be checked
before relying on this in production, per this log's own "stay honest about gaps"
convention. Also not yet run through the built Windows bundle — same gap feature #1
has, recommend closing both opportunistically alongside the full bundle audit (item 8
in `order_of_approach.md`) rather than as separate one-off trips through the bundle.

### 3. Shiny dashboard startup performance / loading indicator — status: `proposed`

`2 - Dashboard starten.bat` takes a long time to open because of the data volume
being read in. Wanted: faster perceived startup, plus a visible progress indicator
(percentage or count) while data loads — and to investigate proper use of Shiny's
`reactive()`/lazy-loading patterns so startup isn't fully blocking. Seventh in working
order per `order_of_approach.md` — do this after feature #2 (labeled_epochs.csv), not
before, since that feature will add more data for the dashboard to load and any
loading-indicator design should reflect the real eventual data volume.

### 4. Full bundle functional audit — status: `proposed`

Does the delivered Windows bundle work as it should, and what's needed to make it
so? Specifically: the dashboard should support rerunning the pipeline with different
configurations (adjustments or a chosen profile), and recording absences should
actually work end-to-end through the bundle Veerle runs (the absence-registry
feature already exists in Shiny/pipeline code — see the earlier conversation in this
log's history — but isn't reachable/functional through the bundle; root cause not
yet confirmed, candidate leads include Shiny's working-directory shift when launched
via `runApp('shiny', ...)` vs. `resolve_cfg_path()`'s relative-path assumptions).
Explicitly deprioritized by the project owner ("the dashboard is a nice to have — I
want to focus on the codebase and correctness of output data first"). Last (eighth)
in working order per `order_of_approach.md` — biggest scope, most cross-cutting, and
benefits from every other item above being settled first. Decide at investigation
time whether the absence-recording gap is folded into this item or split out
separately.

# SchoolMove Project Assessment

Date: 2026-07-11
Scope: full health-check of the repo — does the `r/` pipeline work end-to-end, what
bugs remain, and is `project_1/` obsolete.

Method: three research agents surveyed the codebase in parallel (pipeline code, CI,
docs/config/blockers, and `project_1/`), after which I independently re-verified every
claim that mattered by reading the source myself, and then **actually ran the full
pipeline end-to-end** on the committed dummy data to get first-hand confirmation
rather than relying on secondhand reports. Two of the findings below were corrections
I made to the initial research, and one (the config.yaml corruption bug) was only
found by literally running the tooling and watching it fail.

---

## Executive summary

**Yes, the pipeline works.** I ran `r/pipeline/run_all.R` (via
`scripts/ci/run_example_pipeline.R`) against the committed dummy data on this machine.
All three steps (GGIR Parts 1–5 → segment labeling → summary build) completed
successfully in **253 seconds**, producing `analysis_ready.csv`, `segment_summary.csv`,
and `validity_summary.csv`. Two of the three QC scripts passed cleanly; the third
(QC 01) reported one false failure caused by its own bug (below), not a pipeline
failure.

**`project_1/` is obsolete** and superseded component-for-component by `r/`, which also
adds a QC layer and Shiny dashboard that `project_1/` never had. Two small scripts in
`project_1/` have no equivalent in `r/` — noted below, no action taken per your
request.

**Bugs found:** one critical (silently corrupts your config file if you run the
documented local test command), one high-severity (real-data runs would silently use
wrong GGIR parameters), and several medium/low issues plus meaningful documentation
drift. None of these were fixed — all are documented below with exact locations and
suggested fixes, per your instruction to just report them.

---

## 1. Pipeline run — first-hand verification

I ran the pipeline myself rather than relying only on CI history:

```
═══ SchoolMove Pipeline ══════════════════════════════════════════
[input] Found 20 files: 20 GGIR-compatible (0 .bin), 0 pre-processed
── Step 01: GGIR (Parts 1–5) ──  meting_1 (2 files), meting_2 (2 files)
── Step 02: Segment labels ──  174 rows | 2 participants | 2 metingen
── Step 03: Build summaries ──  analysis_ready.csv, validity_summary.csv written
═══ Pipeline complete ════════════════════════════════════════════
Total time: 253 s
```

QC results against that fresh output:

| QC step | Result |
|---|---|
| QC 01 (GGIR output) | Mostly pass; **1 false FAIL** (part4 sleep file — see Bug #3) |
| QC 02 (segment labels) | **All PASS** |
| QC 03 (analysis-ready summaries) | **All PASS** (with expected WARNs about low inclusion %, explained below) |

Notes on what I saw:
- GGIR version in use: 3.3.6. Format detection worked correctly (`GENEActiv CSV — using rmc.* parameters, autocalibration OFF`).
- The "only 25% of participants meet validity criteria" QC 03 warning is **not a bug** — it's an artifact of how I ran QC (I restored `config.yaml` to real-data thresholds *before* running QC, so it correctly judged the small dummy dataset against the real 16h/day bar). Not a finding, just context so you don't chase it.
- One thing worth watching on real data: the run log printed `Sleep validity: efficiency column not found in part4 — meets_sleep_criteria set to NA`. On this dummy run that's expected (too little data for GGIR to compute sleep efficiency), but if this also happens on real data it would silently leave every participant's sleep-validity flag as NA. Worth double-checking once the pipeline is re-run on real data — see Bug #6.
- CI (`gh` CLI isn't available in this environment to check the latest run status) — the repo's GitHub Actions history is at `https://github.com/timothydhoe/veerleproject/actions`; recommend checking that directly. The commit history (`f56adcf` → `9635e72` → `a3dbebe` → `d191062`) shows a genuine iterative "fix real CI failures" sequence (a Windows argument-quoting bug, a bundle README gap, a timeout raised after observing 42–53 min real runtimes) — good evidence CI reached a working state, and consistent with what I observed running it locally.

**Housekeeping:** running the pipeline modified `r/logs/input_manifest.csv` and
`r/logs/pipeline_runs.csv` (expected — these are the pipeline's own run-history
records) and created two new archived GGIR config snapshots in `r/logs/`. I left these
in place as a legitimate record of this run. I did **not** commit anything.

---

## 2. Bugs found, ranked by severity

### 🔴 Critical — `scripts/ci/run_example_pipeline.R` never actually restores `config.yaml`

**This is not hypothetical — it happened to your `config.yaml` during this assessment,
and I had to restore it myself via `git checkout`.**

The script's header claims it "restores the original config.yaml exactly... regardless
of success or failure," using:

```r
on.exit({
  writeLines(original_lines, cfg_path)
  message("[ci] config.yaml restored to its original contents")
}, add = TRUE)
```

This `on.exit()` call sits at the **top level of the script**, not inside a function.
In R, `on.exit()` only registers a handler for the current function's call frame — at
top level there is no enclosing function to exit from, so the handler **silently never
fires**. I confirmed this by running the script exactly as documented
(`Rscript ../scripts/ci/run_example_pipeline.R` from `r/`): the pipeline completed, but
`config.yaml` was left permanently switched to `example_mode: yes`, `quick_test_n: 2`,
and fully re-serialized by `yaml::write_yaml()` — stripping every one of its
~80 Dutch explanatory comments and reformatting all values (e.g. `false` → `no`,
`"16"` stays but quoting style changes, lists reformatted). The confirmation message
(`"[ci] config.yaml restored..."`) never appeared in the run log, which is the
detectable symptom.

**Why it's harmless in CI but dangerous locally:** GitHub Actions runners are
ephemeral and nothing gets committed back, so `windows-verify.yml` never notices. But
`DEVELOPER.md` and the script's own header document this as the safe way to test
locally. Any researcher or developer who runs it as instructed will silently corrupt
their working `config.yaml` — including flipping it to dummy-data mode — unless they
happen to `git diff` afterward.

**Fix guidance:** wrap the body of the script in a function (or use
`withr::defer()`/a `tryCatch(..., finally = ...)`), so `on.exit()` has a real call
frame to attach to. Simplest fix:
```r
run <- function() {
  on.exit({ writeLines(original_lines, cfg_path); message("[ci] config.yaml restored") }, add = TRUE)
  ...
  source("pipeline/run_all.R")
}
run()
```

---

### 🟠 High — real-data GGIR runs would silently use dummy-data parameters

`config.yaml` documents `dev.nonwear_approach` and `dev.includedaycrit` as
example-mode-only (line 226: *"heeft geen enkel effect op echte data (example_mode:
false negeert dit)"* — "has no effect on real data"). This is **false as implemented**.

In `r/pipeline/01_run_ggir.R:77-85`:
```r
nonwear_approach     <- dev$nonwear_approach     %||% "2023"
includedaycrit       <- dev$includedaycrit       %||% cfg$validity$min_wear_hours_per_day
includedaycrit_part5 <- dev$includedaycrit_part5 %||% (2 / 3)

if (isTRUE(dev$example_mode) && (!is.null(dev$nonwear_approach) || !is.null(dev$includedaycrit))) {
  message("Dev overrides active: ...")   # only the MESSAGE is gated, not the values
}
```
These are then passed unconditionally into the actual `GGIR()` call at lines 148-150.
With `config.yaml` as currently committed (`example_mode: false`,
`dev.includedaycrit: 4`, `dev.nonwear_approach: "2013"`), **a real-data run today would
have GGIR internally use the 2013 non-wear algorithm instead of 2023, and a 4-hour
day-inclusion threshold instead of 16** — silently, with no warning, since the
`example_mode`-gated message never fires to say so.

**Correction to an earlier (overstated) version of this finding:** I initially thought
this same bug existed in three other files. On closer reading, it doesn't — I was
wrong there, and correcting it here.
`03_build_summaries.R:31-35`, `shiny/global.R:77-81`, and `qc_01_ggir.R:126-130` **all
correctly gate** their own validity-threshold logic on
`isTRUE(cfg$dev$example_mode)`. So the actual downstream impact is narrower than it
first looked: `analysis_ready.csv`, `validity_summary.csv`, the Shiny dashboard, and
QC 01's own validity report would all correctly use the real 16-hour threshold even
with this bug present. What's *actually* wrong is that **GGIR itself** would run its
internal Part 2/5 processing — including non-wear detection — with the wrong
algorithm and threshold, before any of that downstream, correctly-gated code ever
sees the data. That's still a real problem (wrong non-wear detection affects
everything downstream), just not a four-file-wide one.

**Fix guidance:** gate the override values themselves, not just the message:
```r
nonwear_approach <- if (isTRUE(dev$example_mode)) dev$nonwear_approach %||% "2023" else "2023"
includedaycrit    <- if (isTRUE(dev$example_mode)) dev$includedaycrit %||% cfg$validity$min_wear_hours_per_day else cfg$validity$min_wear_hours_per_day
```
`DEVELOPER.md`'s "pre-production checklist" already lists removing these dev keys
before a real run as a manual step — this fix would make that step unnecessary and
remove the silent-failure risk of forgetting it.

---

### 🟡 Medium — QC 01 reports a false failure on part4 sleep files

Freshly confirmed by actually running QC 01 against real GGIR 3.3.6 output: it reports

```
[FAIL] part4 nightsummary CSV not found (expected ^part4.*\.csv)
```

but the file genuinely exists at
`results/QC/part4_nightsummary_sleep_full.csv` — one directory level down from where
`qc_01_ggir.R:56` looks:
```r
part4_files <- list.files(results_dir, pattern = "^part4.*\\.csv$", full.names = TRUE)
```
This is non-recursive and only checks `results_dir` directly. Meanwhile,
`utils_ggir.R`'s `read_part4_sleep()` was already fixed (per recent commits) to search
both `results/` and `results/QC/` — step 03 reads the file just fine, as I saw in the
run log (`[utils_ggir] Part 4 sleep: part4_nightsummary_sleep_full.csv (QC/)`). QC 01
just wasn't updated to match.

**Fix guidance:** add `recursive = TRUE` to the `list.files()` call, or mirror
`utils_ggir.R`'s two-directory search.

---

### 🟡 Medium — Shiny profile "Activeer" button doesn't actually change pipeline output

`mod_settings.R:322-342` only patches the `active:` line in `config.yaml` and then
shows the user this message:
> *"Profiel geactiveerd. Herstart de pipeline om de nieuwe instellingen toe te
> passen."* ("Profile activated. Restart the pipeline to apply the new settings.")

I confirmed this message is misleading: I grepped `profile|active` across
`01_run_ggir.R`, `02_label_segments.R`, and `03_build_summaries.R` — **none of them
read the profile system at all.** They all call `read_config_yaml("../config.yaml")`
directly and only ever look at the base config sections. Only
`shiny/global.R:43-69` merges the active profile's values over `cfg`, and only for
**dashboard display**. So activating a non-default profile and "restarting the
pipeline" as instructed would do nothing — the pipeline would still run with base
`config.yaml` values, while the dashboard would display validity/cut-points computed
against the *profile's* values. Currently invisible only because the shipped
`profiles/default.yaml` happens to mirror `config.yaml` exactly.

**Fix guidance:** either have the three pipeline scripts also load-and-merge the
active profile (mirroring `global.R`'s logic), or remove the "restart to apply"
messaging and clarify that profiles currently only affect the dashboard view.

---

### 🟡 Medium — `qwindow_strategy: auto` would silently break step 02

`02_label_segments.R:195` always does a literal `qwindow <- as.numeric(cfg$ggir$qwindow)`
config read, with no auto-derivation logic anywhere in the file. But
`01_run_ggir.R` supports `qwindow_strategy: auto`, dynamically computing boundaries
from school schedules and **not persisting them anywhere** for step 02 to reread.
Currently latent — the default and only-used strategy is `manual` — but `config.yaml`
explicitly documents `auto` as a supported option, so this would break silently the
moment someone switches to it.

**Fix guidance:** either have step 01 persist the resolved qwindow (e.g. to
`logs/`) for step 02 to read back, or have step 02 call the same
`build_qwindow_from_schedules()` logic when `qwindow_strategy == "auto"`.

---

### ⚪ Low / informational

- **`labeled_epochs.csv` is never produced by any pipeline step** — self-documented in
  `03_build_summaries.R:298-311`, and I saw it fire live in my run
  (`[WARN] labeled_epochs.csv not found — context-aware bout columns will be NA`).
  This means the entire `config.yaml bouts:` section and all `bouts_30min_*` columns
  in `analysis_ready.csv` currently have zero effect on output. Not a bug — an
  acknowledged, unfinished feature — but worth remembering it's not silently broken,
  it's just not built yet.
- **Sleep validity can silently resolve to NA.** My run log showed:
  `Sleep validity: efficiency column not found in part4 — meets_sleep_criteria set to NA`.
  Expected on a 2-participant dummy run; worth confirming this doesn't also happen on
  the real dataset once re-run (i.e. confirm GGIR's real-data part4 output includes
  whatever efficiency column name `03_build_summaries.R` is looking for).
- **`02_label_segments.R`'s segment-summary build is a row-by-row `for` loop**
  (lines ~348-445) — correct but will be slow at full-study scale (hundreds of
  participants × ~14 days each vs. today's 2×2). Not urgent, but worth knowing before
  the real-data run so a multi-hour runtime isn't a surprise.

---

## 3. Documentation drift

None of these affect pipeline correctness, but they'll cause confusion for you or
Veerle if left as-is:

- **`CLAUDE.md`'s "Open Blockers" list is partially stale.** Blocker #2 (school 3/4
  fallback schedules) looks resolved — I checked `config.yaml` directly and both
  schools now show `fallback: false` with sourced schedules (school 3 has detailed
  per-class overrides citing an email from Veerle; school 4 cites a schedule image).
  Blockers #1 (Veerle's original GGIR `config.csv`) and #3 (confirming the real-data
  re-run with qwindow actually happened) still appear genuinely open — I found no
  evidence either way in the repo.
- **Two documents `CLAUDE.md` references don't exist in the repo**:
  `docs/planning/plan_of_attack_v2.md` (the whole `docs/planning/` folder is absent),
  and `docs/step3_action_plan_and_strategy.md` (only step1 and step2 exist under
  `docs/`). The step3 reference also appears in `monday_meeting_prep.md`'s own
  file-tree diagram, suggesting it may have existed at some point and been removed.
- **`docs/data_info/school_info.md` is stale** — still describes schools 3 and 4 as
  using a "generic Belgian primary school schedule as fallback," contradicting the
  now-confirmed schedules in `config.yaml`.
- **`DEVELOPER.md` has two stale entries I confirmed directly:**
  - Line 624 still lists school 4 as `fallback: true` — `config.yaml` now has
    `fallback: false`.
  - Lines 502-503 say `do.report = c(2, 5)` and claim the sleep PDF isn't produced —
    but `01_run_ggir.R:155` now has `do.report = c(2, 4, 5)`, so Part 4 is included
    and the sleep PDF is likely produced now.
- **`CLAUDE.md`'s directory layout is inaccurate about where summary CSVs land.** It
  documents `segment_summary.csv`, `analysis_ready.csv`, and `validity_summary.csv` as
  living under `data/processed/`. I confirmed from my own run that they actually land
  one level up, directly in `data/` (`data/segment_summary.csv`, not
  `data/processed/segment_summary.csv`) — because `02_label_segments.R` and
  `03_build_summaries.R` both write to `file.path(base_out, "..", "<file>.csv")`. Only
  the raw GGIR output (`data/processed/<meting>/...`) actually lives where documented.
  `config.yaml`'s own comment on `data_processed` ("Uitvoermap voor GGIR-resultaten
  **en samenvattingsbestanden**") has the same inaccuracy.

---

## 4. `project_1/` — status (flagged only, no action taken)

`project_1/` is an earlier, now-superseded rebuild of the pipeline. Confirmed:
- Last modified **2026-04-28**; `r/` has commits as recent as **2026-07-11** (today).
- Not referenced anywhere in `CLAUDE.md` (confirmed via grep — zero matches).
- Component-for-component superseded: its input-prep, GGIR wrapper, segment-labeling,
  and validity/export scripts were all rebuilt in `r/pipeline/` (one file,
  `utils_ggir.R`, even says in its own header that it was "ported and adapted from
  project_1/R/pipeline/03_read_ggir_output.R"). `r/` additionally has a QC layer and
  Shiny dashboard that `project_1/` never had.
- Its own config (`project_1/config/pipeline_params.yaml`) is out of sync with the
  root `config.yaml` (different validity thresholds), and it has no `renv`/lockfile of
  its own — unlike `r/`.

**Two scripts have no equivalent in `r/` and would be lost if `project_1/` were
deleted without porting them:**
1. `project_1/R/analysis/school_correlations.R` — exploratory lesson-block-duration
   vs. in-class-sedentary-time correlation analysis.
2. `project_1/python/analysis/attendance_prediction.py` — a commute-spike
   attendance-prediction heuristic (morning ENMO burst detection), plus its launcher
   `project_1/run_pipeline.py`.

Everything else in `project_1/` (including its own `_archive/` folder and
`test_with_example.R`, which its own internal doc `how_it_works.md` already flags as
dead code) is safely superseded.

No action was taken on `project_1/` per your instruction — this is presented as facts
for you to decide on.

---

## 5. Open questions worth raising with Veerle

1. Has Veerle's original GGIR `config.csv` (from her prior runs) ever been received?
   No evidence of it in the repo — this is the one blocker I couldn't find any trace
   of being resolved.
2. Has step 01 (`01_run_ggir.R`) actually been re-run on the real dataset since
   `qwindow` was added to `config.yaml`? The code/config side is ready, but I found no
   evidence in the repo of a completed real-data run (local `data/processed/` on this
   machine only had a partial, Part-1-only leftover run, which doesn't count either
   way since it's gitignored/local state).
3. Do you want the two orphaned `project_1/` scripts (school correlations, attendance
   prediction) ported into `r/`, or should `project_1/` just be deleted as-is?

---

## Summary table

| # | Severity | Finding | Location |
|---|---|---|---|
| 1 | 🔴 Critical | `run_example_pipeline.R`'s config restore never fires — corrupts `config.yaml` on local runs | `scripts/ci/run_example_pipeline.R` (top-level `on.exit`) |
| 2 | 🟠 High | Dev overrides (`nonwear_approach`, `includedaycrit`) applied unconditionally to real GGIR runs | `r/pipeline/01_run_ggir.R:77-85, 148-150` |
| 3 | 🟡 Medium | QC 01 false-FAILs on part4 sleep file (non-recursive search) | `r/qc/qc_01_ggir.R:56` |
| 4 | 🟡 Medium | Shiny profile activation doesn't propagate to pipeline; UI message is misleading | `r/shiny/modules/mod_settings.R:322-342` |
| 5 | 🟡 Medium | `qwindow_strategy: auto` would silently break step 02 (latent, not currently used) | `r/pipeline/02_label_segments.R:195` |
| 6 | ⚪ Low | Sleep validity can silently resolve to NA if part4 lacks expected efficiency column | `r/pipeline/03_build_summaries.R` |
| 7 | ⚪ Low | Segment-summary build is an unoptimized row-by-row loop — fine at dummy scale, slow at full-study scale | `r/pipeline/02_label_segments.R:~348-445` |
| 8 | ⚪ Info | `labeled_epochs.csv`/context-aware bouts feature not yet implemented (self-documented, not silently broken) | `r/pipeline/03_build_summaries.R:298-311` |
| — | 📄 Docs | `CLAUDE.md`, `DEVELOPER.md`, `docs/data_info/school_info.md` all contain stale or missing references — see §3 | various |

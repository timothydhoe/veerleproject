# Plan: Absences via `config.yaml`

Status: `proposed` — not yet implemented. Drafted 2026-08-02, reviewed by an
independent agent (same session) that caught three real gaps in the first draft
(now folded in below). Relates to `feature_log.md` item #4 (the dashboard's
existing absence-entry tab is suspected broken in the deployed bundle) and
`bug_log.md`'s note on the same — this plan does not fix that dashboard path,
it routes around it for now.

## Why

Currently, absences are entered via the Shiny dashboard's Instellingen tab
(`r/shiny/modules/mod_settings.R`), writing to `data/absences.csv`, read by
`r/pipeline/02_label_segments.R` to overlay `segment="absent"` on school-time
segments only (in_class/recess/lunch) for that pupil/date — before/after-school
time still counts, and (per bug_log.md #4 context) this dashboard entry path
is suspected non-functional in the deployed Windows bundle. The project owner
wants a simpler, config.yaml-driven mechanism that works today, with full-day
exclusion from all validity/analysis output — not just a school-time overlay.

## Decisions locked in

- **Full-day exclusion, including that night's sleep validity.** One absence
  entry drops everything for that (pupil, date): segments, daytime validity,
  *and* sleep validity. Simplest rule, one exclusion list, no extra fields to
  disambiguate onset/wake-day mapping.
- **config.yaml is the entry point for now.** Dashboard reconciliation is
  deferred to whenever `feature_log.md` #4's bundle audit happens — this plan
  does not attempt to fix or replace that audit.
- **Boolean, full-day only** — no `part_of_day`/`reason` granularity (dropping
  today's morning/afternoon partial-absence support).
- **Sparse CSV** — only absent rows exist; a row's presence means absent. No
  need to materialize every (ID, date) combination — GGIR's own day-level
  output already provides that density; the absence list only marks which of
  those already-dense days to cut.

## 1. `config.yaml` schema

New top-level key:

```yaml
afwezigheden:
  - { pupil_id: "2063", date: "2026-03-01" }
  - { pupil_id: "3041", date: "2026-03-02" }
```

`pupil_id` = bare numeric ID as it appears in filenames (e.g. `"2063"`), **not**
the extension-suffixed form GGIR's own `ID` column uses (`"2063.cwa"`). Confirmed
this matches the existing convention — `extract_school_id()` and
`resolve_schedule_key()` both strip the extension the same way
(`sub("\\.[^.]+$", "", basename(as.character(id)))`) before matching.
`paths.absences` stays, but now describes a *generated* file, not a
hand-edited one.

## 2. Sync step

At the start of the pipeline run, read `cfg$afwezigheden`, normalize, and
**fully regenerate** `data/absences.csv` (overwrite, not merge) with columns
`pupil_id, date, absent` (always `TRUE`). This changes the CSV's schema from
today's `pupil_id, date, part_of_day, reason` to a 3-column file — anything
still reading the old schema needs updating (see §6).

## 3. Where exclusion is actually applied — three places, not two

- **`02_label_segments.R`**: drop the (ID, date) row entirely before/while
  building `segment_summary.csv` — all segments for that day, not just
  school-time ones. Replaces the current partial NA-overlay
  (`ABSENCE_OVERLAY_SEGMENTS`/lunch-split logic) outright.
- **`03_build_summaries.R`**: filter `part2` (has `ID`/`calendar_date`) and
  `part4` — the **cleaned** variant only — before computing
  `participant_validity`, sleep validity, and sleep averages. **Important
  nuance from the independent review: do not filter `part4_full`** (the
  separate unfiltered variant `add_waking_valid_hours()` uses) — it needs the
  excluded day's raw sleep timing intact so a *following*, non-excluded day's
  waking-hours math (which can carry over from the prior night) stays
  correct. Filter only `part2` and the cleaned `part4` after that
  calculation, before the validity aggregation.
- **`02b_label_epochs.R`/`utils_epoch_labeling.R`** (only relevant if
  `bouts.enable_epoch_labeling: true`): this consumer independently uses
  `read_absence_keys()`/`ABSENCE_OVERLAY_SEGMENTS` too, at epoch level —
  missed in the first draft, caught by the independent review. Needs the same
  full-day-drop treatment, or the `bouts_30min_*` columns in
  `analysis_ready.csv` will silently still include excluded days.

## 4. Known, unfixable limitation

`part5_personsummary_*.csv` — source of `mvpa_min_day_avg`, `sb_min_day`,
`lpa_min_day`, `bouts_30min_day`, `bouts_10min_day` — is computed by GGIR
itself, already aggregated across the *entire* recording, before this
pipeline ever sees it. GGIR has no per-date exclusion parameter. **These five
columns will still include an excluded day's contribution.** Fixing this
would mean recomputing them ourselves from `part2`/epoch data — comparable in
scope to the already-deferred `labeled_epochs.csv` bout work (bug_log #10).
Flagged, not solved, by this plan.

## 5. `n_absent_school_days` needs a redesign, not a straight port

Today it's derived by scanning `segment_summary` for `segment == "absent"`
rows (`03_build_summaries.R:330-337`). Once 02 drops rows instead of labeling
them, that check always returns `NULL` and the column silently vanishes —
caught by the independent review as a direct contradiction of keeping that
column. Fix: compute it directly from the config-derived absence-key list
(count of (pupil_id, meting) entries), joined into `participant_validity` in
03 — no longer dependent on segment_summary's contents at all.

## 6. Other consumers that need updating

- **`qc/qc_02_segments.R`**: currently warns *"absences.csv has rows but no
  'absent' segments found — re-run step 02"* — this will misfire on every
  clean run once 02 stops emitting `absent`-labeled rows. Needs rewiring to
  check the opposite: that listed (ID, date) pairs are correctly *absent
  from* `segment_summary.csv`, not labeled within it.
- **`mod_settings.R`** (dashboard): its `read_absences()` hardcodes the old
  4-column schema (`part_of_day`, `reason`) — will break/degrade against the
  new 3-column file. Per project-owner decision, this tab becomes
  **read-only** (add/delete disabled, pointing to config.yaml), but the
  display code itself still needs updating for the new schema, not just
  gating the buttons.

## 7. Shared implementation

Repurpose `utils_schedule.R`'s `read_absence_keys()` to read from
`cfg$afwezigheden` (config) instead of the CSV, with ID-extension stripping
built in. Used identically by 02, 03, and 02b (when enabled) so all three
can't drift apart — matching this file's existing stated purpose (it was
already extracted specifically to keep 02 and 02b from drifting).

## 8. Validation

`validate_config.R`/config-guard hook: warn (not error, since pupil existence
can't be checked before step 01 has run) on malformed dates and duplicate
(pupil_id, date) entries. 02/03/02b themselves warn if a listed pair matches
zero rows in the data being filtered — same typo-detection the current code
already does, just relocated.

## 9. Docs to update

`CLAUDE.md` (`paths.absences` description, Key Domain Concepts), `r/DEVELOPER.md`,
`r/GEBRUIKERSGIDS.md` (Veerle's actual Dutch instructions — the one that
matters most to her), `docs/test/feature_log.md` (new entry referencing #4's
context).

## 10. Tests

Extend `r/tests/testthat/test_utils_schedule.R`: config-parsing (valid pairs,
malformed dates, duplicates, extension-stripping), plus a regression case
matching the `qc_02_segments.R` rewrite — verifying an excluded (ID, date) is
genuinely absent from `segment_summary.csv`, `part2`-derived validity, and
sleep validity, and that a *following* day's waking-hours calc is unaffected
by a preceding excluded day.

## Suggested build order

1. Config schema + `validate_config.R` warnings (no behavior change yet —
   safe to land alone).
2. Shared `utils_schedule.R` helper, repurposed to read config instead of
   CSV.
3. `02_label_segments.R` full-day drop + regenerated `data/absences.csv`.
4. `03_build_summaries.R` filtering (part2, cleaned part4 only,
   `n_absent_school_days` redesign).
5. `qc_02_segments.R` rewrite.
6. `mod_settings.R` read-only conversion + schema update.
7. `02b`/epoch-level filtering (only if `bouts.enable_epoch_labeling` is ever
   turned on for real data).
8. Docs + tests, verified against a live run the way this codebase's other
   bug-log entries are (before/after regression, byte-for-byte where
   unaffected columns are checked).

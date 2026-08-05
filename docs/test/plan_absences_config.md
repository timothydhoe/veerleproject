# Plan: Absences via `config.yaml`

Status: `implemented` — all 8 build-order steps complete and verified live
against real pipeline output; see `docs/test/feature_log.md` #6 for the full
verification record (including two real bugs found and fixed along the way).
Not yet run through the built Windows bundle — see that entry's "Remaining
gap" note. Originally drafted 2026-08-02. This
version (2026-08-04) is a full revision produced through a step-by-step design
conversation with the project owner, then independently reviewed against the
live codebase by a fresh agent with no conversation context (same process the
first draft went through). Two rounds of review changed several decisions
from the first draft — most significantly, absences no longer affect
wear-validity or sleep at all, only daytime activity numbers (see "Decisions
locked in") — and caught factual corrections folded in below (§3, §11) plus
one explicitly out-of-scope item (see note at the end).
Relates to `feature_log.md` item #4 (the dashboard's existing absence-entry
tab is suspected broken in the deployed bundle) and `bug_log.md`'s note on
the same — this plan does not fix that dashboard path, it routes around it.

## Why

Currently, absences are entered via the Shiny dashboard's Instellingen tab
(`r/shiny/modules/mod_settings.R`), writing to `data/absences.csv`, read by
`r/pipeline/02_label_segments.R` to overlay `segment="absent"` on school-time
segments only (in_class/recess/lunch) for that pupil/date — before/after-school
time still counts, and (per bug_log.md #4 context) this dashboard entry path
is suspected non-functional in the deployed Windows bundle. The project owner
wants a simpler, config.yaml-driven mechanism that works today.

## Decisions locked in

- **Two separate questions, two separate answers.** "Was the device worn
  enough that day?" (a data-quality question, drives inclusion/exclusion of
  the *participant*) and "was this a normal day of movement?" (a behavior
  question, drives what counts in the *activity numbers*) are not the same
  question. An absence entry answers only the second one.
- **Daytime activity only, whole day.** An absence entry drops that
  (pupil, date) entirely from the daytime activity output — all school-context
  segments (before_school, in_class, recess, lunch, after_school), not just
  school hours as today. This replaces the current partial NA-overlay
  (`ABSENCE_OVERLAY_SEGMENTS`/lunch-split logic) outright.
- **Wear-validity is untouched.** `n_valid_days`, `mean_wear_h`, `has_weekend`,
  `meets_sedentary_criteria` — none of these change because of an absence. A
  pupil who wore the device on an absent day still gets credit for a valid
  wear-day. This is actually a no-op relative to today's code: `03` currently
  applies no absence filtering to `part2` at all, so "don't add filtering
  here" requires no new code, only *not* doing what the first draft proposed.
- **Sleep is untouched, completely.** No part of sleep — validity
  (`meets_sleep_criteria`, `n_valid_nights`) or the sleep averages
  (`sleep_duration_h`, `sleep_efficiency_pct`) — is affected by a daytime
  absence. `part4` (cleaned or full) is never filtered by absence. This
  reverses the first draft's "drop that night's sleep too" decision.
- **config.yaml is the entry point**, read directly by every pipeline
  consumer (`02`, `03`, `02b`) — no generated file sits between config and
  pipeline behavior. This matches how `class_overrides.pupils` already works
  (pupil rosters live only in config, read directly, no CSV intermediate) and
  avoids a staleness risk: if a generated CSV were the thing consumers read,
  running a step standalone without first regenerating that CSV could
  silently use stale absence data. Reading config directly can't go stale.
- **A read-only mirror CSV is still generated**, purely so the researcher can
  do her own ad-hoc processing (e.g. open it in Excel) outside the app. It is
  refreshed every time `02` runs and is not read by any pipeline logic or by
  the dashboard — a passive byproduct, not a second source of truth.
- **Boolean, full-day only** — no `part_of_day`/`reason` granularity (dropping
  today's morning/afternoon partial-absence support).
- **Sparse config list** — only absent entries exist; an entry's presence
  means absent. No need to materialize every (ID, date) combination.

## 1. `config.yaml` schema

New key, placed directly after `validity` and before `# ── Meetperiodes`
(both are "what counts" decision blocks; `measurements`/`schedules` below are
reference data):

```yaml
# ── Afwezigheden ──────────────────────────────────────────────────────────────
# pupil_id = kale code (bv. "2063"), sluit die dag volledig uit.
# afwezigheden:
#   - { pupil_id: "2063", date: "2026-03-01" }
afwezigheden: []
```

`pupil_id` = bare numeric ID as it appears in filenames (e.g. `"2063"`), **not**
the extension-suffixed form GGIR's own `ID` column uses (`"2063.cwa"`) —
matches the existing convention (`extract_school_id()` and
`resolve_schedule_key()` both strip the extension the same way before
matching). Ships empty (`[]`) with a commented example, since no real absences
are known yet.

`paths.absences` stays, but now describes the generated read-only mirror
(§2), not a hand-edited input file.

**Accepted tradeoff:** this puts pupil IDs + specific dates into a file that
is committed to git (`config.yaml` is tracked; today's `data/absences.csv` is
`.gitignore`d). Precedent already exists — `class_overrides.pupils` puts bare
pupil IDs in committed config — and the project owner has accepted this for
absence dates too. Flagged here for the record, not left as a silent change
in exposure.

## 2. Read-only mirror

At the start of `02_label_segments.R`, after computing the effective absence
list from config, write it out to `data/absences.csv` (columns: `pupil_id,
date`), overwriting each run, backed up via the existing `backup_if_exists()`
mechanism. This file is never read back by any pipeline step or by the
dashboard — it exists solely for the researcher's own use outside the app.

## 3. Shared implementation

Repurpose `utils_schedule.R`'s `read_absence_keys()` to read `cfg$afwezigheden`
directly instead of a CSV path. Rename it (it no longer reads a file) and
remove the now-dead `ABSENCE_OVERLAY_SEGMENTS` constant in the same step,
since its only purpose (marking school-hours-only segments) no longer applies
once exclusion is whole-day.

**Correction from independent review:** `02_label_segments.R` does **not**
currently call `read_absence_keys()` — despite its own header comment
suggesting otherwise, it has its own separate ~75-line inline block that
reads `absences.csv` and does its own part-of-day/lunch-split matching. Only
`02b_label_epochs.R` currently calls the shared helper. So Step 3 of the
build order isn't "repoint an existing call to config" for `02` — it's
"replace that whole inline block" with a call to the (renamed) shared
helper. Same end state (all three consumers sharing one implementation so
they can't drift apart), but a bigger diff in `02` than a first read of this
plan would suggest.

## 4. Where exclusion is actually applied

- **`02_label_segments.R`**: drop the (ID, date) row entirely from
  `segment_summary.csv` — all daytime segments, not just school-time ones.
  Also writes the mirror CSV (§2).
- **`02b_label_epochs.R`/`utils_epoch_labeling.R`** (only relevant if
  `bouts.enable_epoch_labeling: true` — off by default today, pending a
  full-scale performance check, unrelated to this plan): this consumer
  independently duplicates the absence-overlay logic at epoch level, and
  currently has the same school-hours-only limitation. Needs the same
  whole-daytime-context-drop treatment, or the `bouts_30min_*` columns in
  `analysis_ready.csv` would silently still include excluded days' school-hour
  bouts. Still only touches daytime context labels — sleep-related epoch data
  is a separate part of GGIR's output and is never touched.
- **`03_build_summaries.R`**: **no filtering of `part2` or `part4` at all** —
  this is the key reversal from the first draft. `participant_validity` and
  all sleep computations run exactly as they do today, untouched by absences.
  The only two changes here are cleanup, not new filtering logic (§5).

## 5. `03_build_summaries.R` changes (light touch)

1. Remove the now-dead `seg_active <- seg[segment != "absent"]` filter — once
   absent days are dropped entirely from `segment_summary.csv` rather than
   labeled, there's no `"absent"` segment value left to filter out; the
   averaging already excludes those days by their absence from the data.
2. `n_absent_school_days` can no longer be derived by scanning
   `segment_summary` for `segment == "absent"` rows (that check silently
   returns nothing once rows are dropped instead of labeled). Compute it
   directly from `cfg$afwezigheden` instead: count each pupil's absence
   entries, assigning each date to the correct `meting` by matching it
   against that pupil's actually-recorded days in `part2` (which meting a
   date belongs to isn't stored on the absence entry itself). Join the result
   into `participant_validity`/`analysis_ready` as before.

## 6. Known, unfixable limitation

`part5_personsummary_*.csv` — source of `mvpa_min_day_avg`, `sb_min_day`,
`lpa_min_day`, `bouts_30min_day`, `bouts_10min_day` — is computed by GGIR
itself, already aggregated across the *entire* recording, before this
pipeline ever sees it. GGIR has no per-date exclusion parameter. **These five
columns will still include an excluded day's contribution.** Fixing this
would mean recomputing them ourselves from `part2`/epoch data — comparable in
scope to the already-deferred full bout-detection work. Flagged, not solved,
by this plan.

## 7. `qc/qc_02_segments.R`

Currently warns *"absences.csv has rows but no 'absent' segments found —
re-run step 02"* — this will misfire on every clean run once `02` stops
labeling rows and starts dropping them. Rewire to check the opposite: for
every (pupil, date) listed in `config.yaml`, confirm that day is genuinely
*absent from* `segment_summary.csv`. Typo detection (an absence entry that
doesn't match any real recorded day at all — wrong ID, date outside the
recording window) belongs in `02` itself, warned about at drop-time by
comparing the absence list against real recorded days *before* dropping,
since a typo'd entry and a correctly-dropped entry look identical after the
fact.

## 8. `mod_settings.R` (dashboard)

Per project-owner decision, the Instellingen tab's Afwezigheden section
becomes fully read-only:

- The "add absence" form (pupil, date, part-of-day, reason, "Toevoegen"
  button) and the per-row delete button are removed entirely, not just
  disabled — `part_of_day`/`reason` have no meaning under the new full-day
  boolean schema.
- The display table shrinks from 4 columns to 2 (pupil, date) and reads
  directly from `shared$cfg$afwezigheden` (already loaded in memory) rather
  than from any CSV — consistent with §3's direct-from-config approach.

## 9. Validation

`validate_config.R`/config-guard hook: warn (not error, since pupil existence
can't be checked before step 01 has run) on malformed dates and duplicate
(pupil_id, date) entries.

## 10. Docs to update

- **`r/GEBRUIKERSGIDS.md`** (Veerle's actual Dutch instructions — the one
  that matters most) needs a real rewrite of its existing "§7 Afwezigheden
  registreren" section, not a tweak: remove the dashboard-form instructions
  and the "hand-edit `data/absences.csv` in Excel" instructions (that file is
  now an auto-regenerated, read-only mirror — hand-edits would be silently
  overwritten on the next run), replace with "edit `config.yaml`'s
  `afwezigheden` list," and note it's now always whole-day.
- **`CLAUDE.md`** and **`r/DEVELOPER.md`** currently say nothing about
  absences at all — this is new content, not an update.
- **`docs/test/feature_log.md`** — new dated entry, same reference format the
  log already uses.
- **`ARCHITECTURE.md`** — missed in the first pass, caught by independent
  review: its data-flow table (an "Absence registry" row pointing at
  `data/absences.csv`, entered "via Shiny or manually") and a mermaid diagram
  node ("Absence overlay\n(data/absences.csv)") both describe the pre-plan
  architecture and need updating to reflect config.yaml as the source of
  truth.
- **`config.yaml`'s own `paths.absences` inline comment** ("Afwezigheidsregister,
  beheerd via het dashboard") — mentioned in §1's prose but easy to forget as
  an actual task; added explicitly to the build order below.

## 11. Tests

Extend `r/tests/testthat/test_utils_schedule.R`:
- Config parsing: valid entries, malformed dates, duplicate (pupil_id, date)
  entries, extension-suffixed IDs stripped correctly.
- An absence entry removes the *whole* day from `segment_summary.csv` (all
  daytime segments), not just school hours.
- **Regression guard**: an absence entry does *not* change `n_valid_days`,
  `mean_wear_h`, `has_weekend`, or any sleep validity/average — this is the
  most important test given how easy it would be to accidentally reintroduce
  the coupling this plan deliberately removes.
- `n_absent_school_days` lands on the correct `meting` for a pupil with
  entries spanning both measurement waves.
- **Caught by independent review**: `r/tests/testthat/test_utils_schedule.R`
  already has two tests for `read_absence_keys()` using its current
  file-path-argument signature. These will fail once the function is renamed
  and repurposed to take `cfg` (§3) — they need to be rewritten to match the
  new signature, not just left as additional coverage alongside them.

## Build order

1. Config schema (§1) + `validate_config.R` warnings (§9) + updating
   `config.yaml`'s existing `paths.absences` inline comment — no behavior
   change yet, safe to land alone.
2. Shared `utils_schedule.R` helper, repurposed + renamed (§3) — including
   rewriting the two existing tests that depend on its old signature (§11).
3. `02_label_segments.R` full-day drop + mirror CSV (§2, §4) — replacing its
   existing inline absence-handling block (~75 lines), not just repointing a
   call (§3 correction).
4. `03_build_summaries.R` cleanup (§5) — no `part2`/`part4` filtering.
5. `qc_02_segments.R` rewrite (§7).
6. `mod_settings.R` read-only conversion (§8).
7. `02b`/epoch-level fix (§4) — only exercised if
   `bouts.enable_epoch_labeling` is ever turned on for real data.
8. Docs (§10) + tests (§11), verified against a live run.

## Out of scope, tracked separately

The Schooldag dashboard tab's "Afwezig" category (a bar/facet inside the
activity charts, sourced from the `segment_label` factor in
`r/shiny/global.R`) will silently stop appearing once `02` drops absent days
instead of labeling them — confirmed harmless (no crash, no misrender; both
ggplot2's and data.table's defaults simply drop the now-empty category) but
a real, deliberate visual change nonetheless. Explicitly scoped out of this
plan by the project owner (2026-08-04) — tracked as `bug_log.md` #36, with
three redesign options recorded there for whenever it's picked up.

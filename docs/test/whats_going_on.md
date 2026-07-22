# SchoolMove — What's Going On (Session Issue Log)

Issues and open questions raised during ad-hoc conversation review, separate from
`docs/test/bug_log.md` (which tracks the earlier structured bug-fixing pass). Logged
here as they come up so nothing gets mentioned in passing and dropped.

Status legend: `open` · `fixed` · `wontfix` · `deferred`

---

## 🔴 Severe

### 1. `qwindow_strategy: auto` never assigns a participant-specific/school-specific qwindow at the GGIR level — status: `open`

**Where:** `r/pipeline/01_run_ggir.R:35-67` (`build_qwindow_from_schedules()`, `qwindow_val`
branch), `r/pipeline/02_label_segments.R:35, 197-233, 276-296` (`extract_school_id()`,
qwindow resolution, `distribute_qwindow_cols()`), `config.yaml:39-48, 154-166`

**Traced precisely (not just the config-level description) — what happens end to end
if `qwindow_strategy: "auto"` is selected:**

1. `01_run_ggir.R` computes **one** pooled qwindow list (`build_qwindow_from_schedules()`
   — confirmed live: 34 boundaries, pooling `school_start`/`school_end`/`breaks` from
   **all 6 schools at once**) and passes it as a single `qwindow` argument to **one
   `GGIR()` call per meting** (not per school, not per participant). Every participant
   in that meting — whichever school they belong to — is processed against the
   identical 34-block grid. GGIR's raw Part 5 output (`segment1`...`segment34`) has no
   concept of school; it is structurally identical for every ID.
2. The school linkage exists **only** downstream, in `02_label_segments.R`:
   `extract_school_id(ID)` (first digit) looks up that participant's real school
   schedule, then `distribute_qwindow_cols()` overlap-weights the shared 34-block grid
   onto that school's real segment times to estimate per-segment intensity.

**So: does `auto` assign each ID the correct qwindow per its school label? No — not
directly.** GGIR itself is never school-aware under either strategy; `auto` only
changes how fine the *shared* grid is.

**Is the final result still correct? Mostly, but with one confirmed, concrete gap:**
- For every school's **base** schedule (no override), the reconstruction happens to
  come out exact: `build_qwindow_from_schedules()` and `02_label_segments.R`'s
  `get_schedule()` both derive boundaries from the same underlying
  `school_start`/`school_end`/`breaks` values, so a participant's own school's real
  segment edges always land exactly on a pooled boundary — no partial-block
  interpolation for that participant's own segments.
- **Confirmed real gap:** `build_qwindow_from_schedules()` never reads
  `class_overrides` (school_3's per-class late-dismissal override, e.g. `16:25` for
  classes 2Aa/2Ab/2Ba/2Bb, `config.yaml:154-166`), even though `02_label_segments.R`
  *does* apply that override when building those specific pupils' real segments. For
  those pupils, on override days, the "exact match" property above breaks — their
  after-school-override segment is estimated via partial-block overlap approximation
  against whichever pooled block happens to span 16:25, identical exposure to manual
  mode. `auto` gives this subset no benefit despite its name suggesting otherwise.

**Downgraded from the original framing:** this is not a mislabeling/misgrouping bug —
`segment_summary.csv`/`analysis_ready.csv` do correctly carry a `school` column and
group every participant under their own school throughout the pipeline, verified by
tracing `extract_school_id()`'s use in both `02_label_segments.R` and
`03_build_summaries.R` (joins keyed on `ID + school + meting` throughout). The real,
severe issue is narrower: **`auto`'s name/doc comment ("leidt grenspunten automatisch
af uit de schoolroosters", `config.yaml:41`) implies per-school derivation that does
not actually happen at the GGIR level**, and the one concrete subset where this causes
a real accuracy gap is the `class_overrides` pupils described above.

**Not yet decided:** whether to (a) rename/re-document `auto` to accurately describe
"pooled boundaries from all schools' base schedules, excluding class_overrides," (b)
extend `build_qwindow_from_schedules()` to also pool `class_overrides` boundaries
(closes the gap, still keeps the "one shared grid for everyone" architecture), or (c)
a bigger structural change to make GGIR genuinely per-school. Needs a decision before
`auto` is used for a real run.

---

### 4. Hooks likely non-functional on any machine other than the original author's — status: `open`

**Where:** `.claude/settings.json` (all three hook `command` entries)

All three hooks (GDPR guard, config guard, R syntax check) are wired up as:
```
"command": "python3 /Users/timothydhoe/Code/veerle-project/.claude/hooks/gdpr_guard.py"
```
— a hardcoded absolute path to the original author's Mac, invoked via `python3`.

Confirmed on a second machine (Windows, this checkout at
`C:\Users\astri\Desktop\Data_Scientist\Projects\veerleproject`): that path doesn't
exist, and `python3` isn't even resolvable on PATH (only `python`, via Anaconda
3.13.5). Net effect: none of the three hooks fire here — the GDPR guard, config guard,
and R syntax check are all silently inactive on this machine, contrary to `CLAUDE.md`'s
"Hooks (automatic) ... Fire without any invocation" framing.

**Fix direction (researched, not applied):** Claude Code's Hooks Reference documents
`${CLAUDE_PROJECT_DIR}` as the portable project-root variable for hook `command`
entries — this replaces the hardcoded path regardless of machine/OS. The Python
interpreter name still needs runtime selection rather than a hardcoded choice, since
Mac (`python3` typically present) and this Windows setup (`python` present, `python3`
absent) disagree: a single-execution wrapper like
`sh -c 'command -v python3 >/dev/null 2>&1 && python3 "$0" || python "$0"' "${CLAUDE_PROJECT_DIR}/.claude/hooks/<script>.py"`
picks the right one without double-running the hook (a plain `cmd1 || cmd2` fallback
would mask a real non-zero exit from a working interpreter). Not yet confirmed whether
Claude Code's hook runner invokes `command` through a shell that can resolve `sh` on
Windows — needs live testing once applied.

**Impact:** currently no GDPR guard, config-file validation, or R syntax checking on
any machine except the original author's, if even that path is still current there.

---

### 5. `.claude/commands/pipeline-status.md` checks the wrong output path — status: `open`

**Where:** `.claude/commands/pipeline-status.md:15,17`

Checks `data/processed/segment_summary.csv`, `data/processed/analysis_ready.csv`, and
`data/processed/validity_summary.csv` — but these three files actually land in `data/`
directly (confirmed via `config.yaml`'s own comment and the write-path code in
`02_label_segments.R:531` / `03_build_summaries.R:459-460`, both of which write to
`file.path(base_out, "..", "<file>.csv")` where `base_out` is `data/processed`).

**Impact:** running `/pipeline-status` today would report these three outputs as
missing even when the pipeline has completed through step 03 — under-reports real
progress. The GGIR raw-output checks in the same command (under
`data/processed/ggir/...`) are correct and unaffected.

---

## ⚪ Informational

### 2. `bouts.split_at_context_boundary` — confirmed correct in design, but inert — status: `deferred`

**Where:** `config.yaml:52-60` (`bouts.split_at_context_boundary`),
`r/pipeline/utils_bouts.R` (`detect_activity_bouts()`, `bout_key` RLE logic),
`r/pipeline/03_build_summaries.R:340-376` (`labeled_epochs.csv` gate)

**Confirmed understanding is correct:** `split_at_context_boundary: true` splits a
sedentary bout into two whenever the school-context label changes mid-bout — not
specifically recess/lunch, but *any* context-label boundary crossing (before_school,
in_class, recess, lunch, after_school, outside_school, weekend). Mechanism, traced in
`detect_activity_bouts()`: it run-length-encodes on `intensity × context` combined
(`bout_key <- paste(is_target, ddata$context, sep = "|")`), so a context change always
breaks a run — e.g. a 35-minute sit spanning into recess counts as two bouts, not one
(matches the config's own comment at `config.yaml:52-54`).

**Currently a no-op:** the setting is only read inside `03_build_summaries.R`'s
`labeled_epochs.csv` block (lines 353-376), and that file is never produced by any
current pipeline step — `02_label_segments.R` is day-level only, and no epoch-level
school-context labeling step exists yet. This is the same gap as `bug_log.md` item
#10 (deferred there: needs real epoch-scale design work, ~480M rows at full study
scale, not a quick fix). Not a bug — the design is correct and ready to activate once
`labeled_epochs.csv` exists; it's explicitly gated on Veerle's own methodological
decision per the config comment ("wacht op methodologische beslissing").

---

### 3. `CLAUDE.md` mischaracterizes `min_wear_hours_per_day` as a "waking hours" criterion — status: `fixed`

**Fixed** in the CLAUDE.md documentation-sync pass: the "Key Domain Concepts" table's
"Validity criteria" row now states the correct mechanism (24h calendar-day valid-wear
hours via GGIR's `includedaycrit`, distinct from the non-configurable waking-hours
`includedaycrit.part5`), the correct current numbers (≥9h/≥4 days, matching Veerle's
protocol citation and `config.yaml`), and notes that the old ≥16h/≥3-day figure was an
earlier, superseded email figure. See `CLAUDE.md`'s Key Domain Concepts table.

<details>
<summary>Original finding (kept for context)</summary>

**Where:** `CLAUDE.md` ("Key Domain Concepts" table, "Validity criteria" row),
`config.yaml:65` (`validity.min_wear_hours_per_day`), `r/pipeline/01_run_ggir.R:94-95`
(`includedaycrit` vs `includedaycrit.part5`), `r/pipeline/03_build_summaries.R:87-112`
(`n_valid_hours`, `n_valid_days`)

**Independently verified** (fresh agent, read the actual files plus GGIR's own
installed R source/docs directly — not just its rendered documentation):

`config.yaml`'s `min_wear_hours_per_day` is compared against GGIR Part 2's
`"N valid hours"` column (`03_build_summaries.R:112`,
`n_valid_days = sum(n_valid_hours >= min_wear_h, ...)`), which `01_run_ggir.R:94`
feeds via GGIR's `includedaycrit` parameter. GGIR's own docs state `includedaycrit` is
*"minimum required valid hours for a calendar day... applies to the entire day"* —
confirmed further by decompiling GGIR's `g.analyse.perday()` source, which slices
`nvalidhours` on full midnight-to-midnight indices, not a waking-only window. This is
a genuinely **24-hour-day** metric — device-worn-and-recording-correctly hours,
irrespective of sleep/wake state.

GGIR does have a real waking-hours-only criterion, but it's a *different* parameter
(`includedaycrit.part5`) used only for Part 5, and in this codebase it's hardcoded to
a fixed `2/3` (`01_run_ggir.R:95`) — never read from `config.yaml`, not adjustable by
Veerle. So there are genuinely two separate "enough good data" rules in the pipeline
(one 24h-based and config-driven, one waking-hours-based and fixed), and it's easy to
conflate them.

**The problem:** `CLAUDE.md`'s "Key Domain Concepts" table describes the sedentary
validity criterion as *"≥16 valid **waking** hours on ≥3 days (≥1 weekend)"* — but the
criterion the pipeline actually computes and gates on is 24-hour-day valid-wear hours,
not a waking-restricted count. Anyone reading `CLAUDE.md` to understand what
`min_wear_hours_per_day` means would come away with the wrong mental model of what's
being measured.

**Impact:** documentation-only — does not affect pipeline output or correctness, only
understanding. Should be corrected in `CLAUDE.md` to describe the criterion accurately
(24h calendar-day valid-wear hours via GGIR's `includedaycrit`, distinct from the
non-configurable waking-hours `includedaycrit.part5` used internally by Part 5).

</details>

---

### 6. `.claude/settings.local.json` has the same class of stale Mac-specific path — status: `open`

**Where:** `.claude/settings.local.json` (permissions allowlist)

Contains `"Bash(/Users/timothydhoe/Syntra/.venv/bin/python3 *)"` — same root cause as
item #4, but harmless in practice since it's an unused allowlist pattern, not something
that executes on its own.

---

### 7. Stale `data/processed/` path in pipeline code comments (comment-only, no behavior bug) — status: `open`

**Where:** `r/pipeline/02_label_segments.R:14`, `r/pipeline/03_build_summaries.R:9-10`

Header comments describe output paths as `data/processed/segment_summary.csv` etc. —
the code itself correctly writes to `data/` directly (same actual location `#5` and
`whats_going_on.md`'s CLAUDE.md-directory-layout note both confirm). Comment-only
drift, no functional impact.

---

### 8. `Makefile`'s `py-*` targets are dead — status: `open`

**Where:** `Makefile:1-11`

`py-install`, `py-lint`, `py-test` all `cd python && ...`, but no `python/` directory
exists anywhere in the repo — it predates the Python-deferred architecture decision and
the `to_be_built/` reorganization (which relocated the only Python files in the repo,
an unbuilt attendance-prediction backlog feature, to `to_be_built/`, not `python/`).
Running any of these three targets fails immediately with "no such file or directory."
Only `r-install` (`cd r && Rscript install.R`) is real.

---

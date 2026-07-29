# SchoolMove — Optimization Log

Catalog of performance and dead-code candidates from the audit requested by the
project owner (`docs/test/feature_log.md` item #5 / `docs/test/order_of_approach.md`
item 4), sparked by concern that the bundle's pipeline run and/or dashboard launch are
"already a pretty slow process" and shouldn't have more infrastructure layered onto
un-investigated existing slowness.

**Nothing in this log has been applied.** This is a survey pass — investigate, formulate
a candidate change, get it independently reviewed for breakage risk, present it, log it —
ordered by expected impact (greatest first), so a full review can happen before deciding
which changes are actually worth the hassle.

Status legend: `catalogued` (investigated + reviewed, not yet applied) ·
`needs-input` (blocked on a decision only the project owner/Veerle can make) ·
`approved` (signed off, ready to apply) · `applied` · `rejected` (considered, decided
against, with reason) · `no-action` (investigated, found to already be fine)

---

## Workflow

For each candidate:
1. **Investigate** — read the actual current code, don't assume the audit's first
   description is the final word.
2. **Formulate** a concrete candidate change (or conclude "no action needed").
3. **Independent review** (fresh-context agent, static/read-only, no code execution) —
   check the proposed change for breakage risk against currently-working behavior, not
   just the problem it's meant to solve.
4. **Present** the issue and the reviewed candidate change, with tradeoffs, to the
   project owner.
5. **Log** it here, ranked by expected impact, status `catalogued` until a decision is
   made. Nothing gets applied at this stage.

Once the full catalog exists, decide together which items are worth doing, then apply
them one at a time following `bug_log.md`/`feature_log.md`'s own apply-and-verify
discipline (live before/after run, diff output CSVs, update this log's status).

---

## 1. GGIR forced single-core (`maxNcores: 1`) — status: `needs-input`

**Where:** `config.yaml` (`ggir.maxNcores`), `r/pipeline/01_run_ggir.R` (`do.parallel = max_cores > 1`)

**Expected impact: highest, by a wide margin, at full study scale.** GGIR's own docs
(confirmed via context7, `/wadpac/ggir`) state parallelization applies across Parts 1,
2, 3, and 5 — the exact parts that dominate the pipeline's own measured runtime
(`windows-verify.yml`'s own comment: 42–53+ minutes for just 2 dummy participants).
At ~400 real participants, this is the single largest lever available: GGIR's own
default for `do.parallel` is `TRUE`, but this project's committed config forces
`maxNcores: 1`, which computes `do.parallel = FALSE` and overrides GGIR's own default
back to single-core.

**Not dead code or an oversight** — the config comment is explicit and deliberate:
*"1 = één kern (veilig op elke laptop). Op een moderne laptop zijn 2–4 kernen sneller"*
(1 = one core, safe on any laptop; a modern laptop is faster with 2–4 cores). This was
a conscious safety-first choice, not neglect.

**Real constraint, not just a knob to turn:** GGIR's own docs warn that multi-core runs
need real headroom — recommending ≥8GB RAM total and a target of ~2GB available *per
process*, and that raising `maxNcores` on a memory-constrained machine risks memory
errors mid-run (the docs' own suggested mitigation for a memory error is *reducing*
`maxNcores` back down). Blindly bumping the default without knowing the researcher's
actual hardware could turn "safe but slow" into "crashes on a 400-participant run."

**What's needed before this can move to a concrete change:** a decision (or hardware
info) from the project owner / Veerle on what machine(s) will actually run the full
400-participant pipeline, so a `maxNcores` recommendation (or a config comment update
guiding researchers to set it themselves based on their RAM) can be made responsibly
rather than guessed. This is why it's `needs-input`, not `catalogued` — no independent-
review pass has happened yet because there's no concrete change to review.

**Update — real measurement taken, real gap found (2026-07-27):** project owner
confirmed the target deployment hardware is "same specs as this laptop" — Intel
i7-12650H, 10 cores/16 logical processors, ~16GB RAM. Ran the real pipeline (not
dummy data) against the two real device recordings already in the repo
(`data/raw/veerle_testdata/meting_1`/`meting_2`: `1001_left wrist_...bin`,
`73044_0000001002.cwa`), redirecting `paths.data_processed` to an isolated scratch
directory each time (`config.yaml`/`01_run_ggir.R` confirmed byte-identical via
`git diff` after every run):

- `maxNcores: 1` — **171s** wall-clock, single Rscript process.
- `maxNcores: 4` — **97s** wall-clock (**1.76x speedup**, not linear 4x — expected for
  a job this small: only 2 unique participants × 2 metingen, parallel setup overhead,
  Amdahl's law). Both runs completed successfully (exit 0).
- Peak memory during the `maxNcores: 4` run, sampled every 5s via `tasklist`: highest
  single snapshot summed all concurrent `Rscript.exe` processes to **~6.0GB** total
  (individual workers ranged ~150MB–2.1GB depending on which GGIR stage/file each was
  handling at that moment) — comfortable headroom on a 16GB machine in isolation.

**Independent review found a real, confirmed gap, not a hypothetical one:**
`bug_log.md` already documents that these same two test recordings have only **1
valid night each** (~1 day of data) — far short of the ~7-8 day windows in
`config.yaml`'s own `measurements:` section for the real study. GGIR's Part 1 holds
raw per-file signal in memory during processing, so per-worker memory very plausibly
scales with recording *duration* — meaning the measured ~6GB peak likely
**understates** real per-worker memory against full-length 7-8 day recordings. No
longer real or synthetic native-format (`.bin`/`.cwa`) test data is currently
available to verify this directly (GDPR blocks fabricating a substitute from real
data).

**What this update does and doesn't establish:**
- ✅ Confirms the underlying reasoning holds: GGIR parallelizes via a concurrency
  queue (bounded by `maxNcores`), not by loading all N participants at once — so peak
  memory should scale with concurrency, not total study size (400 vs. 4
  participants), per GGIR's own docs (context7, `/wadpac/ggir`) and confirmed no
  evidence of an all-files-at-once step in Parts 1-3. Part 5's aggregation does read
  across all processed files at once, but only already-condensed summary rows —
  trivial memory even at N=400.
- ✅ Confirms a real, non-trivial speedup (1.76x) and no crash at `maxNcores: 4` on
  this exact hardware, for at least short recordings.
- ❌ Does **not** yet establish that `maxNcores: 4`'s ~6GB peak is safe against
  real-length 7-8 day recordings — the one open question that actually matters for a
  committed default.

**Resolution (2026-07-27) — project owner chose to pick a conservative number now
rather than wait for longer test data, reasoning that halving concurrency roughly
halves worst-case combined memory regardless of remaining duration-scaling
uncertainty.** A follow-up review found the uncertainty itself is smaller than
thought: GGIR's `chunksize` parameter (confirmed via context7, `/wadpac/ggir`) caps
how much raw data is loaded per worker at a time — expressed as a fraction of a
12/24h period, **default `1`** (~1 day per chunk) — and is **not set** in
`01_run_ggir.R`'s `shared_args`, so this default is already in effect. This means
GGIR does **not** load a full 7-8 day recording into memory at once regardless of
`maxNcores`; each worker's load size is capped near ~1 day either way. The two short
test recordings (~1 valid night each) are therefore a reasonably valid proxy for
per-chunk memory even against real multi-day recordings — the duration-scaling
concern raised earlier is substantially, though not completely, resolved (fixed
baseline overhead and stage-to-stage variability, per the reviewer, mean "halves
exactly" is a heuristic, not a guarantee).

**Recommended candidate: `maxNcores: 2`** (not the originally-measured `4`) — real
1.76x-vs-1x speedup precedent at `maxNcores: 4` makes a real (if smaller, untested)
speedup very likely at `maxNcores: 2` too, while roughly halving worst-case combined
memory relative to the measured ~6.0GB peak at 4. Independent review verdict: a
reasonable, low-risk default, more so than initially expected given the `chunksize`
finding.

**Status: `approved` — ready to apply**, pending the project owner's go-ahead to
actually make the change (bump `config.yaml`'s `maxNcores: 1` → `2`, and update the
adjacent comment to note the memory tradeoff and instruct researchers to drop back to
`1` if they hit memory errors, per GGIR's own documented mitigation). Not yet applied
— consistent with this log's own rule that nothing gets changed until the full catalog
is reviewed and each item is explicitly signed off.

---

## 2. Redundant GGIR Part 5 "WW" variant computed but never used — status: `catalogued`

**Where:** `r/pipeline/01_run_ggir.R` `shared_args` (no `timewindow` argument currently
set)

**Expected impact: high, every pipeline run, scales with participant count.** GGIR
generates Part 5 output for both `MM` (midnight-to-midnight) and `WW`
(wake-to-wake) time windows by default. Since `qwindow` is also set, this project's
`qwindow`-based "Segments" variant is additionally produced (GGIR's own docs: qwindow
is only used in Part 5 when `timewindow` includes `MM` — Segments is a further
subdivision of MM, not an independent third scheme). `docs/test/bug_log.md` #18
confirmed a real run actually produced all three variants side by side. Only
`Segments` is ever consumed: `02_label_segments.R` hard-requires it specifically, and
`utils_ggir.R`'s `pick_ggir_variant_file()` (used generically by `03_build_summaries.R`,
`qc_01_ggir.R`, and `mod_export.R`'s downloads) prefers `Segments` first, `WW` second,
`MM` third — `WW` is never actually selected in normal operation.

**Candidate change:** add `timewindow = "MM"` to `shared_args`. Confirmed via GGIR's
own tutorial (its canonical qwindow example pairs `qwindow=c(...)` with
`timewindow="MM"` directly) that this suppresses `WW` entirely while `MM` and
`Segments` continue to be produced — cutting Part 5's redundant report/aggregation
work from 3 variants to 2, per participant, every run.

**Independent review — real tradeoff found, not a free win:** `pick_ggir_variant_file()`
also does a genuine, currently-load-bearing cross-check — it compares participant
coverage across whichever variants exist and warns if the chosen variant (`Segments`)
covers fewer participants than an alternate. `feature_log.md` item #1's live
verification run actually triggered this exact warning once (a real Segments/WW
coverage mismatch was caught in practice). Dropping `WW` reduces this check to a
single comparator (`MM`) instead of two — `MM` alone is a meaningfully weaker
day-boundary definition than `WW`, so this is not a fully equivalent safety net, just a
weaker one. Reviewer's verdict: **safe to proceed**, but flag in any changelog that the
coverage cross-check becomes `MM`-only going forward.

**Decision needed:** is losing some of that cross-check's diagnostic strength an
acceptable price for cutting a third of Part 5's redundant work? (A cleaner
alternative worth considering later: replace the incidental WW-vs-Segments coverage
check with a dedicated, explicit "did every input participant end up in the final
Segments output" QC check — decoupling data-completeness verification from which Part
5 variants happen to get computed. Out of scope for this specific candidate, noted for
`qc_01_ggir.R` or `qc_03_summaries.R` consideration if this item is picked up.)

---

## 3. `epochvalues2csv = TRUE` writes an unused raw epoch export — status: `resolved` (implemented as part of `feature_log.md` #2)

**Where:** `r/pipeline/01_run_ggir.R:150` (hardcoded, applies to every run — real and
dummy/example alike)

**Correction:** "1 row/second" below was wrong — confirmed live (dummy data and real
device data alike) that GGIR's `epochvalues2csv` export is actually 5-second resolution
(GGIR's own internal `windowsizes` default), not 1-second. Doesn't change this item's
conclusion, just the units. See `bug_log.md` #10's superseding note for the full context.

**Expected impact: real but disk/IO-bound, not proven as a wall-clock win.** GGIR
writes a full raw per-epoch CSV (1 row per 5s) per participant. Confirmed via
`utils_bouts.R`'s own header comment and `03_build_summaries.R` (lines 364-402) that
this raw export is only ever useful as input to a future `labeled_epochs.csv` step —
tracked as `feature_log.md` item #2, status `proposed`, not built. Nothing in the
current codebase reads it.

**Measured live this session** (safe, isolated benchmark — scratch output directory,
`config.yaml` and `01_run_ggir.R` restored byte-identical afterward, confirmed via
`git diff`): ran the dummy pipeline twice, once as-is and once with
`epochvalues2csv = FALSE`.
- `analysis_ready.csv`/`segment_summary.csv`/`validity_summary.csv`: **byte-identical**
  both ways — confirms this is a pure export toggle with zero effect on real output,
  consistent with GGIR's own docs.
- Output disk size: **26MB → 11MB** (~58% reduction) on a tiny 4-dummy-participant
  test run.
- Wall-clock time: 278s (TRUE) vs. 334s (FALSE) — **no measurable speedup**; if
  anything slightly slower without it, almost certainly ordinary system noise at this
  small scale, not a real causal effect either direction.

**Candidate change:** add a new `ggir.epochvalues2csv` key to `config.yaml`'s `ggir:`
section (default `FALSE`), read by `01_run_ggir.R` instead of the hardcoded `TRUE`.
Flip the default to `TRUE` when feature #2 (`labeled_epochs.csv`) is actually built and
needs this export as its input.

**Independent review:** confirmed no other current consumer exists anywhere in the
repo. **Verdict: safe to proceed.**

**Implemented** (feature #2 build): rather than a separate `ggir.epochvalues2csv` key,
`01_run_ggir.R`'s `epochvalues2csv` now reads `cfg$bouts$enable_epoch_labeling` directly
— the same flag that gates whether `02b_label_epochs.R` runs at all. A single flag
avoids the two settings ever getting out of sync (e.g. epoch export off but the labeling
step on, or vice versa). Default `false`, as recommended here. Verified: with the flag
`false` (the shipped default), `analysis_ready.csv`/`segment_summary.csv`/
`validity_summary.csv` are byte-identical to before this change.

**Honest framing for ranking:** disk savings are real and will scale meaningfully with
400 real participants over full multi-week recordings (plausibly gigabytes), but this
does **not** address "the pipeline feels slow" — that complaint is most likely
GGIR-internal Part 1 processing cost, which items #1 and #2 above actually target.
Ranked below those two for that reason, despite being the most thoroughly measured
item so far.

---

## 4. Dashboard reads GGIR's Part 4 file twice per meting — status: `catalogued`

**Where:** `r/shiny/global.R` (`part4`/`part4_full` blocks), `r/pipeline/utils_ggir.R`'s
`read_part4_sleep()`

**Expected impact: moderate, dashboard-only, but happens on every launch (higher
frequency than the pipeline, which runs only occasionally).** `read_part4_sleep()` is
called twice per meting — once preferring the "cleaned" variant, once preferring
"full" — because `part4` (dashboard's own sleep-validity display) and `part4_full`
(feeds `add_waking_valid_hours()`, which needs every attempted night regardless of
validity — see `bug_log.md` #31) are genuinely different use cases. But in this
project's actual current outputs, only the `_full` variant exists on disk, so both
calls resolve to the *same file* and read it twice with base R's `read.csv()` (slower
than the `fread()` used elsewhere in the same file).

**Candidate change (not yet fully designed — flagging complexity, not a ready diff):**
read once, check the resolved `source_path` attribute already returned by
`read_part4_sleep()`, and only issue the second read if the "cleaned" variant's file
actually exists and differs from what the first read already found. This directly
touches the same code path involved in `bug_log.md` #31's waking-hours validity
criterion — real correctness stakes if done carelessly (wrong file feeding the wrong
downstream computation). Recommend a specific, careful design pass — with its own
independent review — before writing an actual diff, rather than rushing a dedup here.
Not sent for review yet since there's no concrete diff to review.

---

## 5. Shiny loads all 7 tabs' data eagerly at startup — status: `catalogued` (tracks into an existing item, not new work)

**Where:** `r/shiny/global.R`

**Expected impact: real, once-per-dashboard-session cost — but this is already tracked
separately.** All 7 tabs' backing data (part2, part4, part4_full, analysis_ready,
validity_summary, segment_summary) loads unconditionally at startup regardless of
which tab the user opens first; only per-tab *rendering* is Shiny's normal lazy
behavior, not the underlying reads/joins.

**Not a new item** — this is exactly `feature_log.md` item #3 ("dashboard startup
performance / loading indicator"), already `proposed` and deliberately sequenced in
`order_of_approach.md` *after* item #6 (`labeled_epochs.csv`), since that feature will
add real data volume and any reactive/lazy-loading redesign should target the eventual
data size, not today's smaller one. Logged here only so this audit's impact-ranking is
complete; the actual work belongs to feature #3, not this log.

---

## 6. Unused `ggrepel` package loaded at Shiny startup — status: `catalogued`

**Where:** `r/shiny/global.R:30`

**Expected impact: low** — one package's load time, once per dashboard startup.

**Candidate change:** remove `library(ggrepel)`.

**Independent review:** grepped the entire repo (not just `r/shiny/`) for
`geom_text_repel`, `geom_label_repel`, any `ggrepel::`-prefixed call — zero matches
outside the `library()` call itself. **Verdict: safe to proceed.** Essentially a free
win, no tradeoff found.

---

## 7. `plotly` used in only one module vs. `ggplot2`'s broad use — status: `catalogued` (informational only)

**Where:** `r/shiny/global.R:31`, `r/shiny/modules/mod_comparison.R`

**Expected impact: low, speculative.** `plotly` is a heavier dependency than
`ggplot2`, loaded at every startup, but used in only one module (2 calls) for
interactive charts vs. `ggplot2`'s ~18 calls across most other modules. This may be a
deliberate choice for that specific chart's interactivity, not an oversight — no
action recommended without confirming whether that interactivity is actually wanted
before considering swapping it for a static `ggplot2` chart.

---

## 8. GGIR Part 2/4/5 PDF report generation (`do.report = c(2, 4, 5)`) — status: `catalogued` (informational only, needs Veerle's input)

**Where:** `r/pipeline/01_run_ggir.R:174`

**Expected impact: uncertain, real per-participant cost.** Part 5's PDF report
rendering in particular is genuine extra work per participant. No evidence found
anywhere in the codebase (Shiny, docs, `DEVELOPER.md`, `GEBRUIKERSGIDS.md`) that these
PDFs are actually opened or consumed by anything downstream — `AUDIT.md` itself
already notes "the pipeline doesn't consume the PDF, but researchers may expect it."

**No candidate change proposed.** This is a standard GGIR QC deliverable that Veerle
may rely on for manual visual QC — removing an expected researcher-facing output
without asking would be presumptuous. Worth a direct question to Veerle ("do you
actually open/use these PDFs?") before treating this as an optimization target at all.

---

## 9. GGIR autocalibration re-run cost — status: `no-action`

**Where:** `r/pipeline/01_run_ggir.R:187` (`do.cal = TRUE` for native `.bin`/`.cwa`)

**Investigated and found already handled.** GGIR's own `meta/*.RData` milestone files
already let re-runs skip already-completed parts (including Part 1's autocalibration)
whenever `overwrite: false` — the committed default. No separate caching layer is
missing; this is not an optimization opportunity.

---

## 10. Bundle launchers, renv startup, `config.yaml`'s "informatief" keys — status: `no-action`

**Investigated, nothing actionable found.** `scripts/bundle/build-bundle.ps1` and the
`.bat` templates add no avoidable runtime cost (R-portable/renv copying is a one-time
build-time cost, not paid at launch). `.Rprofile`'s renv activation check is an
inherent tradeoff of a portable, no-install bundle. Every `config.yaml` key marked
"informatief, niet actief ingelezen" (informational, not actively read) has a clear
comment explaining why it's intentionally inert — none are orphaned leftovers. No
dead/unreferenced `.R` files found anywhere under `r/` (only `install.R` is
unreferenced, and it's an intentional manual one-time setup script, not dead code).

---

## Summary table

| # | Item | Impact | Status |
|---|------|--------|--------|
| 1 | `maxNcores: 1` forces single-core | Highest (whole-pipeline, scales with cores) | `approved` (→ 2) |
| 2 | Redundant Part 5 `WW` variant | High (per-participant, every run) | `catalogued` |
| 3 | Unused `epochvalues2csv` export | Moderate (disk/IO only, not proven wall-clock) | `resolved` |
| 4 | Duplicate Part 4 file reads | Moderate (dashboard-only, high frequency) | `catalogued` |
| 5 | Eager Shiny startup loading | Moderate | tracked as `feature_log.md` #3 |
| 6 | Unused `ggrepel` package | Low | `catalogued` |
| 7 | `plotly` usage imbalance | Low, speculative | `catalogued` (informational) |
| 8 | `do.report` PDF generation | Uncertain | `catalogued` (needs Veerle's input) |
| 9 | GGIR calibration caching | — | `no-action` |
| 10 | Bundle/renv/config cruft | — | `no-action` |

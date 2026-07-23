# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in
this repository.

## Project Overview

**SchoolMove** is a data pipeline for processing wrist-worn GENEActiv accelerometer data
from ~400 Belgian schoolchildren across 6 schools, analyzing physical activity patterns
in school contexts. Client: Veerle Van Oeckel (UGent).

## Environment Setup

- **R**: Managed by `renv`. Run `renv::restore()` in R to install dependencies. This is
  the **primary language** for this project.
- **Python**: Deferred — only to be introduced if R/Shiny cannot meet a specific need.
  Do not build Python components unless explicitly asked.

`renv.lock` is committed and pins all package versions for reproducibility.

## Architecture

> **R is the primary and (for now) only language.** GGIR handles the entire accelerometer
> processing pipeline. R-Shiny handles all output, QC visualization, and researcher
> interaction. Python is **not** part of the current plan — it may be introduced later if
> a specific need arises, but do not assume or propose it.

### Language roles

| Layer | Tool | Notes |
|-------|------|-------|
| Accelerometer processing | GGIR (R package) | Parts 1–5; canonical pipeline |
| School context labeling | R (data.table) | Custom post-GGIR segment assignment |
| QC & output | R Shiny | Dashboard for Veerle and academic colleagues |
| Config | `config.yaml` (repo root) | Researcher-editable, read by R |
| Python | — | Deferred; do not introduce unless asked |

### Researcher config file

`config.yaml` at the repo root is the **single place researchers tweak the pipeline**
without touching code. Veerle should never need to edit an `.R` file to change a
parameter. The config covers:

- GGIR parameters (epoch length, cut-points, non-wear thresholds, sleep algorithm)
- School schedules and day-segment definitions
- Validity criteria (min wear hours, min valid days, weekend requirement)
- Measurement metadata (school IDs, meting dates)
- Developer/testing overrides (example_mode, relaxed thresholds for dummy data)

R code reads this file at startup via the `yaml` package and passes values into GGIR,
the segment labeler, and Shiny. When adding new configurable parameters, always route
them through `config.yaml`, not as hardcoded values in scripts.

### Directory Layout

```
README.md                 # Non-technical project overview (front door for GitHub visitors)
ARCHITECTURE.md           # Deep state/data-flow reference (mermaid diagrams, file-based state)
AUDIT.md, UX_REVIEW.md    # Historical, point-in-time audit reports — findings now largely
                          # resolved/tracked in r/DEVELOPER.md; not living documentation
scripts/
  bundle/                 # Builds the portable Windows distribution (see r/GEBRUIKERSGIDS.md)
  ci/                     # CI helpers (dummy-data pipeline run, Shiny smoke test)
.github/workflows/        # CI: pipeline + dashboard verification on push/PR, bundle build

r/
  SchoolMove.Rproj        # Open in RStudio to start working
  install.R               # Run once: renv::restore(), then installs packages
  .Rprofile               # renv auto-activation
  renv/ + renv.lock       # Package environment (do not edit)
  DEVELOPER.md            # ← The current, actively-maintained technical reference for r/ —
                          # read this for anything beyond what CLAUDE.md covers
  GEBRUIKERSGIDS.md       # Dutch end-user guide (install, dashboard, troubleshooting)

  pipeline/
    run_all.R             # ← Researcher entry point: sources 01, 02, 03 in sequence
    01_run_ggir.R         # GGIR parts 1–5 for both metingen (reads config.yaml)
    02_label_segments.R   # Apply school schedule context to GGIR output
    03_build_summaries.R  # Build analysis-ready tables + validity flags

  qc/
    qc_01_ggir.R          # Verify GGIR outputs after step 01
    qc_02_segments.R      # Verify segment coverage after step 02
    qc_03_summaries.R     # Verify validity counts + distributions after step 03

  shiny/
    global.R              # Load config + all processed data + shared helpers
    ui.R                  # Dashboard layout (bslib, 7 tabs)
    server.R              # Reactive logic

config.yaml               # Researcher-facing config — all tunable parameters here
data/
  raw/                    # Input .csv files (GDPR — not in repo)
    meting_1/             # Pupil CSV files for wave 1
    meting_2/             # Pupil CSV files for wave 2
  processed/
    ggir/
      meting_1/           # GGIR output for wave 1
      meting_2/           # GGIR output for wave 2
    summaries/
      segment_summary.csv   # Output of 02_label_segments.R
      analysis_ready.csv    # Output of 03_build_summaries.R
      validity_summary.csv  # Output of 03_build_summaries.R
  example/                # Fictional test data (safe to commit)
    dummy_data/
      meting_1/
      meting_2/
docs/                     # Detailed reference documents — read before implementing
to_be_built/              # Backlog of unbuilt research features (RQ4, RQ5) — not wired
                          # into r/. See to_be_built/README.md.
.claude/
  settings.json           # Hooks configuration (see Claude Code Tooling below)
  hooks/                  # Hook scripts (GDPR guard, config guard, R syntax check)
  commands/               # Custom slash commands for Claude Code
```

> **Note on Python**: Python is not part of the active pipeline. `to_be_built/` contains
> two standalone Python files (an unbuilt attendance-prediction feature) that are not
> imported or run by anything in `r/` — see `to_be_built/README.md`. Do not build new
> Python components unless explicitly asked.

### Pipeline Steps

| Step | Script | What happens | Key output |
|------|--------|--------------|------------|
| **01** | `01_run_ggir.R` | GGIR Parts 1–5: load CSVs, ENMO, non-wear, cut-point classification, sleep detection, day summaries | `part2_daysummary.csv`, `part4_nightsummary_sleep_cleaned.csv`, `part5_daysummary_WW_*.csv` |
| **QC 01** | `qc/qc_01_ggir.R` | Verify GGIR outputs: required files present, correct columns, participant counts | Console report |
| **02** | `02_label_segments.R` | Apply school schedule labels to GGIR output: for each participant × day, distribute per-qwindow activity (read from `part5_daysummary_Segments_*.csv`, not `part2_daysummary.csv`) across school context segments (in_class / recess / lunch / before_school / after_school). Falls back to wear-time-only if that Part 5 Segments file is missing. | `segment_summary.csv` |
| **QC 02** | `qc/qc_02_segments.R` | Verify segment coverage: all pupils labeled, no missing school day windows, fallback school warnings | Console report |
| **03** | `03_build_summaries.R` | Join all outputs into analysis-ready wide table; compute validity flags per participant | `analysis_ready.csv`, `validity_summary.csv` |
| **QC 03** | `qc/qc_03_summaries.R` | Verify inclusion/exclusion counts, check MVPA distributions, confirm cut-points match config | Console report |
| **Shiny** | `shiny/` | Dashboard: Overzicht, Deelnemers, Schooldag, Slaap, Meting 1 vs 2, Export, Instellingen (7 tabs) | Interactive app |

Run the full pipeline at once with `r/pipeline/run_all.R` (source in RStudio or
`Rscript --vanilla r/pipeline/run_all.R` in terminal).

### GGIR internals (Parts 1–5)

| GGIR Part | What happens | Key output |
|-----------|--------------|------------|
| Part 1 | Load CSV data, ENMO + anglez derivation, epoch aggregation | `.RData` milestone files |
| Part 2 | Non-wear detection, clipping, cut-point classification, day/segment summaries | `part2_daysummary.csv` |
| Part 3 | Rest period estimation (feeds sleep detection) | `.RData` |
| Part 4 | Sleep detection (HDCZA algorithm) | `part4_nightsummary_sleep_cleaned.csv` (primary; falls back to `_sleep_full.csv`, then bare `part4_nightsummary.csv`) |
| Part 5 | Full behavioral timeline, bouts, fragmentation, day-segment analysis | `part5_daysummary_WW_*.csv`, `part5_personsummary_WW_*.csv` |

GGIR persists all parameters in a `config.csv` per output directory, enabling
reproducible re-runs. Our `config.yaml` feeds into this.

### Input format

**Both CSV and native `.bin`/`.cwa` files are supported.** The original plan assumed
CSV-only input (see the CSV-specific caveats below), but real GGIR runs against
Veerle's data have already processed native `.bin` files directly, with GGIR
autocalibration (Part 1 sphere-fitting) enabled — confirmed by pipeline logs showing
`format: native (.bin/.cwa) — autocalibration ON`. The earlier "CSV only" blocker is
superseded; `.bin` input works in practice. The CSV-only caveats below (no
autocalibration, SVMgs ≠ GGIR ENMO) still apply when a participant's data arrives as
pre-converted CSV rather than raw `.bin`.

## Key Domain Concepts

| Term | Definition |
|------|-----------|
| **ENMO** | Euclidean Norm Minus One — primary acceleration metric (gravity-subtracted). Computed from raw x/y/z samples. |
| **SVMgs** | Pre-computed per-epoch ENMO sum in CSV files — NOT identical to GGIR's ENMO (no autocalibration). |
| **Epoch** | Fixed time window (1 second in this study) for aggregating raw samples. |
| **Cut-points** | ENMO thresholds classifying activity intensity. Hildebrand 2014/2017, wrist, children: SB < 56.3 mg, LPA 56.3–191.6 mg, MPA 191.6–695.8 mg, VPA > 695.8 mg. |
| **Autocalibration** | Corrects sensor drift via sphere-fitting on stationary periods. **Not applicable with pre-converted CSVs.** |
| **Non-wear detection** | SD < 13 mg and range < 50 mg on ≥2 of 3 axes, over 60-min blocks assessed every 15 min. |
| **Validity criteria** | Sedentary analysis: ≥9 valid hours of wear on ≥4 days (≥1 weekend), per Veerle's protocol citation — matches `config.yaml`'s `min_wear_hours_per_day`/`min_valid_days`. The "hours" here are 24h calendar-day valid-wear hours (GGIR's `includedaycrit`), not a waking-only window — a separate, non-configurable waking-hours parameter (`includedaycrit.part5`, hardcoded to 2/3) exists only for Part 5 internals. An earlier ≥16h/≥3-day figure (from an early email from Veerle, later superseded) still lingers in `docs/step2_ggir_pipeline_reference.md`'s historical quote. Sleep: ≥50% valid sleep on ≥5 nights. |
| **GGIR** | R package for the canonical 6-part accelerometer pipeline. Parts 1–5 are in scope. |
| **Meting** | Dutch for "measurement". Meting 1 and meting 2 are the two measurement waves per school. |
| **Segment** | School day context label: `before_school`, `in_class`, `recess`, `lunch`, `after_school`, `weekend`. |

## Data Format

Input files are GENEActiv CSVs. Key characteristics (full spec in
`docs/step1_data_format_reference.md`):

- **File naming**: 4-digit code — first digit = school ID (1–6), remaining 3 digits = pupil
  ID (001–...). Example: `2063` = pupil 063 at school 2. Meting 1 and meting 2 files share
  the same name and are in separate folders.
- **Header**: 100-row metadata block before data rows
- **Data columns**: timestamp, x, y, z, light, button, temperature, SVMgs, x_std, y_std,
  z_std, peak_lux
- **Sampling rate**: 100 Hz (raw), aggregated to 1-second epochs in CSV

## Open Blockers

1. **GGIR config** — Full parameter set from Veerle's original GGIR runs (she may have a
   `config.csv` from a previous run). Needed to ensure new results stay comparable. Still
   open — no evidence in the repo that this has been received.
2. ~~**School schedules — schools 3 and 4**~~ **Resolved.** `config.yaml` now has
   `fallback: false` for both, with sourced schedules (school 3 has per-class overrides
   citing an email from Veerle; school 4 cites a schedule image).
3. ~~**Confirm a real-data re-run has happened since `qwindow` was added**~~ **Resolved.**
   Confirmed 2026-07-13: two real `.bin`/`.cwa` device files ran cleanly end-to-end through
   the qwindow-aware pipeline (`02_label_segments.R` correctly reads
   `part5_daysummary_Segments_*.csv`), verified via `qc_01_ggir.R`/`qc_02_segments.R`/
   `qc_03_summaries.R`. Not yet tested at full study scale (~400 participants across
   6 schools), but the two risks previously flagged here are both now resolved: see
   `docs/test/bug_log.md` #9 (segment-summary loop — benchmarked at full study scale,
   4.66s, not a real problem — `wontfix`) and #13 (summary CSV output paths now
   backed up before every overwrite — `fixed`).

## MCP Servers

- **context7** (`https://mcp.context7.com/mcp`) — Use for library documentation lookups.
  - GGIR docs: library ID `/wadpac/ggir`
  - R Shiny docs: library ID `shiny_posit_co`
    (source: `https://context7.com/websites/shiny_posit_co`)
- **playwright** (`npx @playwright/mcp@latest`) — Browser automation, used to drive the
  Shiny dashboard for UX review (e.g. `UX_REVIEW.md` was produced this way).

## Claude Code Tooling

### Hooks (automatic)

Configured in `.claude/settings.json`. Fire without any invocation.

| Hook | Trigger | What it does |
|------|---------|--------------|
| **GDPR guard** | Before any `git commit` | Aborts the commit if any file from `data/raw/` or `data/processed/` is staged. |
| **Config guard** | After saving `config.yaml` | Validates YAML syntax. Warns about missing sections, fallback schedules, unset cut-points. |
| **R syntax check** | After saving any `.R` file | Runs `Rscript --vanilla -e "parse(file = '...')"` and surfaces errors immediately. |

Hook scripts live in `.claude/hooks/` — edit them there if behaviour needs to change.

### Commands (invoke with `/`)

Defined as markdown prompts in `.claude/commands/`. Each becomes a slash command in Claude Code.

| Command | Use it when... |
|---------|----------------|
| `/validate-config` | Before running the pipeline — plain-language readiness report on `config.yaml` |
| `/pipeline-status` | Checking which pipeline steps have completed and what output exists |
| `/run-qc` | After running a pipeline step — interprets QC script output in plain language |
| `/add-schedule` | A school timetable arrives — describe it in plain text and Claude writes the YAML |
| `/blocker-check` | Before a meeting with Veerle — one-page briefing on open questions |
| `/shiny-plan` | Before adding any new Shiny feature — produces a full plan before any code is written |

---

## Reference Documentation

All files in `docs/` should be read before implementing any pipeline component:

- `step1_data_format_reference.md` — CSV format specification
- `step2_ggir_pipeline_reference.md` — GGIR pipeline internals
- `meeting-notes/monday_meeting_prep.md` — Open questions and context from client meetings
- `data_info/data_dictionary.md` — Field/unit/derived-variable spec for all pipeline outputs
- `data_info/research_questions.md` — The study's research questions the pipeline answers
- `data_info/school_info.md` — Per-school schedules and context-labeling rules
- `info/GENEAread_bin_to_csv.md` — `.bin`→CSV conversion notes
- `info/*.docx` — Veerle's original source documents (schools, study, metingen — cited
  directly by `config.yaml` and `school_info.md`)

(The Dutch end-user guide lives at `r/GEBRUIKERSGIDS.md`, not under `docs/`.)

(A `step3_action_plan_and_strategy.md` and `planning/plan_of_attack_v2.md` were
referenced here previously but don't exist in the repo — removed rather than
left as dead links. If they existed at some point, they'd need to be
recovered or rewritten from scratch, not just re-added as references.)

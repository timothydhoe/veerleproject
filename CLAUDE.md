# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in
this repository.

## Project Overview

**SchoolMove** is a data pipeline for processing wrist-worn GENEActiv accelerometer data
from ~400 Belgian schoolchildren across 6 schools, analyzing physical activity patterns
in school contexts. Client: Veerle Van Oeckel (UGent). Currently in planning/early
implementation phase.

## Environment Setup

- **R**: Managed by `renv`. Run `renv::restore()` in R to install dependencies. This is
  the **primary language** for this project.
- **Python**: Deferred — only to be introduced if R/Shiny cannot meet a specific need.
  Do not build Python components unless explicitly asked.

There is no build/test infrastructure yet. `renv.lock` is planned but not yet created.

## Architecture

> **R is the primary and (for now) only language.** GGIR handles the entire accelerometer
> processing pipeline. R-Shiny handles all output, QC visualization, and researcher
> interaction. Python is **not** part of the current plan — it may be introduced later if
> a specific need arises, but do not assume or propose it.

### Language roles

| Layer | Tool | Notes |
|-------|------|-------|
| Accelerometer processing | GGIR (R package) | Parts 1–6; canonical pipeline |
| QC & output | R Shiny | Dashboard for Veerle and academic colleagues |
| Config | `config.yaml` (see below) | Researcher-editable, read by R |
| Python | — | Deferred; do not introduce unless asked |

### Researcher config file

A central `config.yaml` at the repo root (or `r/config.yaml`) is the **single place
researchers tweak the pipeline** without touching code. Veerle and her colleagues should
never need to edit an `.R` file to change a parameter. The config covers:

- GGIR parameters (epoch length, cut-points, non-wear thresholds, sleep algorithm)
- School schedules and day-segment definitions
- Validity criteria (min wear hours, min valid days, weekend requirement)
- Output preferences (which reports to generate, file formats)
- Measurement metadata (school IDs, meting dates)

R code reads this file at startup (e.g. via the `yaml` package) and passes values into
GGIR and Shiny. When adding new configurable parameters, always route them through
`config.yaml`, not as hardcoded values in scripts.

### Directory Layout

```
r/
  SchoolMove.Rproj        # Open this in RStudio to start working
  install.R               # Run once to install packages
  pipeline/
    01_run_ggir.R         # GGIR pipeline runner (reads config.yaml)
  shiny/
    global.R              # Shared setup for the dashboard
    ui.R                  # Dashboard layout and tabs
    server.R              # Dashboard logic
  validation/
    check_outputs.R       # Sanity checks after running the pipeline
config.yaml               # Researcher-facing config — all tunable parameters here
data/
  raw/                    # Input .csv files (GDPR — not in repo)
  processed/              # GGIR output (milestone .RData + summary CSVs)
  example/                # Fictional test data (safe to commit)
docs/                     # Detailed reference documents — read before implementing
.claude/
  settings.json           # Hooks configuration (see Claude Code Tooling below)
  hooks/                  # Hook scripts (GDPR guard, config guard, R syntax check)
  commands/               # Custom slash commands for Claude Code
```

> **Note on Python directory**: A `python/` directory exists in the repo from an earlier
> plan. It is vestigial — ignore it unless Python work is explicitly requested.

### Pipeline Phases (GGIR-centric)

| Phase | GGIR Part | What happens | Key output |
|-------|-----------|--------------|------------|
| **1** | Part 1 | Load CSV data, ENMO + anglez derivation, epoch aggregation | `.RData` milestone files |
| **2** | Part 2 | Non-wear detection, clipping, cut-point classification, day/segment summaries | `part2_daysummary.csv` |
| **3** | Part 3 | Rest period estimation (feeds sleep detection) | `.RData` |
| **4** | Part 4 | Sleep detection (L5 / HDCZA) | `part4_nightsummary.csv` |
| **5** | Part 5 | Full behavioral timeline, bouts, fragmentation, day-segment analysis | `part5_daysummary.csv` |
| **6** | Part 6 | Cross-record analyses (meting 1 vs meting 2 comparisons, school-level) | Summary CSVs |
| **7** | Shiny | QC dashboard, schedule overlays, export-ready tables for Veerle | Interactive app |

GGIR persists all parameters in a `config.csv` per output directory, enabling
reproducible re-runs. Our `config.yaml` feeds into this.

### Input format

**CSV files only for now.** Raw `.bin` files are not in scope at this stage. Note that
this means GGIR autocalibration (Part 1 sphere-fitting) cannot be applied — ENMO values
will be based on the pre-converted CSV data rather than autocalibrated raw samples. This
is an accepted trade-off for the current phase; revisit if Veerle provides `.bin` files.

## Key Domain Concepts

| Term                   | Definition                                                                                                                                                              |
|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **ENMO**               | Euclidean Norm Minus One — primary acceleration metric (gravity-subtracted). Must be computed from raw x/y/z samples, not from epoch means (Jensen's inequality issue). |
| **SVMgs**              | Pre-computed per-epoch ENMO sum already in the CSV files — NOT identical to GGIR's recalculated ENMO due to autocalibration.                                            |
| **Epoch**              | Fixed time window (1 second in this study) for aggregating raw samples.                                                                                                 |
| **Cut-points**         | ENMO thresholds classifying activity intensity. Confirmed values (Hildebrand 2014/2017, wrist-worn, children): SB < 56.3 mg, LPA 56.3–191.6 mg, MPA 191.6–695.8 mg, VPA > 695.8 mg. |
| **Autocalibration**    | Corrects sensor drift via sphere-fitting on stationary periods. GGIR applies this in Part 1 on raw data. **Not applicable when using pre-converted CSVs.**               |
| **Non-wear detection** | Identifies device-off-wrist periods: SD < 13 mg and range < 50 mg on ≥2 of 3 axes, over 60-min blocks assessed every 15 min. |
| **Validity criteria**  | Sedentary analysis: ≥9 valid waking hours on ≥4 days. Sleep analysis: ≥50% valid sleep data on ≥5 nights. |
| **GGIR**               | R package implementing the canonical 6-part accelerometer pipeline. All 6 parts are in scope for this study.                                                            |
| **Meting**             | Dutch for "measurement". Meting 1 and meting 2 are the two measurement waves per school.                                                                                |

## Data Format

Input files are GENEActiv CSVs. Key characteristics (full spec in
`docs/step1_data_format_reference.md`):

- **File naming**: 4-digit code — first digit = school ID (1–6), remaining 3 digits = pupil
  ID (001–...). Example: `2063` = pupil 063 at school 2. Meting 1 and meting 2 files share
  the same name and are separated into different folders.
- **Header**: 100-row metadata block before data rows
- **Data columns**: timestamp, x, y, z, light, button, temperature, SVMgs, x_std, y_std,
  z_std, peak_lux
- **Sampling rate**: 100 Hz (raw), aggregated to 1-second epochs in CSV

## Open Blockers

Before implementing classification logic, these must be resolved with the research team:

1. **GGIR config** — Full parameter set from Veerle's original GGIR runs (she may have a
   `config.csv` from a previous run)
2. **School schedules** — Schools 3 and 4 timetables still missing
3. **Day-segment definitions** — Final time windows for lessons, recess, lunch, PE, etc.

## MCP Servers

- **context7** (`https://mcp.context7.com/mcp`) — Use for library documentation lookups.
  - GGIR docs: query with library ID `ggir` or similar
  - **R Shiny docs**: query with library ID `shiny_posit_co`
    (source: `https://context7.com/websites/shiny_posit_co`)

  > context7 is a single MCP server that serves docs for many libraries dynamically.
  > There is no separate Shiny MCP server to configure — use the existing context7 server
  > with the library ID above.

## Claude Code Tooling

### Hooks (automatic)

Configured in `.claude/settings.json`. Fire without any invocation.

| Hook | Trigger | What it does |
|------|---------|--------------|
| **GDPR guard** | Before any `git commit` | Aborts the commit if any file from `data/raw/` or `data/processed/` is staged. Prints the offending files and how to unstage them. |
| **Config guard** | After saving `config.yaml` | Validates YAML syntax (via R's `yaml` package). Warns about missing sections, fallback schedules, and unset cut-points. |
| **R syntax check** | After saving any `.R` file | Runs `Rscript --vanilla -e "parse(file = '...')"` and surfaces errors immediately. |

Hook scripts live in `.claude/hooks/` and are plain Python — edit them there if behaviour needs to change.

### Commands (invoke with `/`)

Defined as markdown prompts in `.claude/commands/`. Each becomes a slash command in Claude Code.

| Command | Use it when... |
|---------|----------------|
| `/validate-config` | Before running the pipeline — get a plain-language readiness report on `config.yaml` |
| `/pipeline-status` | Checking what GGIR has already processed and what's still missing |
| `/add-schedule` | A school timetable arrives — describe it in plain text and Claude writes the YAML |
| `/blocker-check` | Before a meeting with Veerle — produces a one-page briefing on open questions |
| `/shiny-plan` | Before adding any new feature to the dashboard — produces a full plan before any code is written |

---

## Reference Documentation

All files in `docs/` are detailed and should be read before implementing any pipeline
component:

- `step1_data_format_reference.md` — CSV format specification
- `step2_ggir_pipeline_reference.md` — GGIR pipeline internals
- `step3_action_plan_and_strategy.md` — Earlier action plan (written when Python was
  primary — **partially outdated**, but useful for domain context and output requirements)
- `meeting-notes/monday_meeting_prep.md` — Open questions and context from client
  meetings

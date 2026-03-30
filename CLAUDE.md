# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SchoolMove** is a data pipeline for processing wrist-worn GENEActiv accelerometer data from ~400 Belgian schoolchildren across 6 schools, analyzing physical activity patterns in school contexts. Client: Veerle Van Oeckel (UGent). Currently in planning/early implementation phase.

## Environment Setup

- **Python**: Managed by `uv` (v0.11.2), Python 3.12. Run `uv sync` to install dependencies.
- **R**: Planned to use `renv`. Run `renv::restore()` in R to install dependencies once set up.

There is no build/test infrastructure yet. `pyproject.toml`, `Makefile`, and `renv.lock` are planned but not yet created.

## Architecture

Dual-language design: **R for the initial GGIR pipeline** (leverages battle-tested accelerometer processing), **Python for downstream analysis, aggregation, and output**. A Shiny dashboard in R is planned for QC visualization.

### Planned Directory Layout

```
r/
  run_ggir.R              # GGIR pipeline runner
  shiny/                  # QC dashboard
  validation/             # Cross-validate R vs Python outputs
python/
  pyproject.toml
  src/accel_pipeline/
    ingest/               # CSV/bin parsing, file naming decoder
    processing/           # ENMO, non-wear, sleep, activity classification
    analysis/             # Day segments, bouts, summaries
    output/               # Reports and visualizations
    config/               # School schedules, cut-point parameters
  tests/
data/
  raw/                    # Input .bin or .csv files (GDPR — not in repo)
  processed/              # Pipeline outputs
  example/                # Fictional test data (safe to use)
docs/                     # Detailed reference documents — read before implementing
```

### Pipeline Phases (from `docs/step3_action_plan_and_strategy.md`)

1. **Phase 0** — Resolve blockers (cut-points, input format, school schedules)
2. **Phase 1** — CSV ingestion, file naming decoder (4-digit: school + pupil ID), school schedule config
3. **Phase 2** — Core processing: ENMO, non-wear detection, data validity checks
4. **Phase 3** — Sleep detection, full SB/LPA/MVPA classification
5. **Phase 4** — Output: dashboards, comparison reports, export tables

## Key Domain Concepts

| Term | Definition |
|------|-----------|
| **ENMO** | Euclidean Norm Minus One — primary acceleration metric (gravity-subtracted). Must be computed from raw x/y/z samples, not from epoch means (Jensen's inequality issue). |
| **SVMgs** | Pre-computed per-epoch ENMO sum already in the CSV files — NOT identical to GGIR's recalculated ENMO due to autocalibration. |
| **Epoch** | Fixed time window (1 second in this study) for aggregating raw samples. |
| **Cut-points** | ENMO thresholds classifying activity as SB (sedentary), LPA (light), or MVPA (moderate-to-vigorous). **Exact values are a current blocker** — await Veerle's protocol. |
| **Autocalibration** | Corrects sensor drift via sphere-fitting on stationary periods. GGIR applies this in Part 1; recalculates ENMO after correction. |
| **Non-wear detection** | Identifies device-off-wrist periods via low std dev across axes. |
| **Validity criteria** | ≥16h wear/day, ≥3 valid days (incl. ≥1 weekend day) per recording period. |
| **GGIR** | R package implementing the canonical 6-part accelerometer pipeline. Parts 1, 2, and 5 are critical for this study; Part 6 is not needed. |

## Data Format

Input files are GENEActiv CSVs. Key characteristics (full spec in `docs/step1_data_format_reference.md`):
- **File naming**: 4-digit code — first 1-2 digits = school ID, remaining digits = pupil ID
- **Header**: 100-row metadata block before data rows
- **Data columns**: timestamp, x, y, z, light, button, temperature, SVMgs, x_std, y_std, z_std, peak_lux
- **Sampling rate**: 100 Hz (raw), aggregated to 1-second epochs in CSV

## Open Blockers

Before implementing classification logic, these must be resolved with the research team:
1. **Cut-point values** — Exact ENMO mg thresholds for SB/LPA/MVPA
2. **Input format** — Whether to use pre-processed CSVs or raw .bin files (impacts whether autocalibration can be applied)
3. **GGIR config** — Full parameter set from Veerle's original GGIR runs
4. **School schedules** — Schools 3 and 4 timetables still missing
5. **Day-segment definitions** — Final time windows for lessons, recess, lunch, PE, etc.

## Reference Documentation

All four files in `docs/` are detailed and should be read before implementing any pipeline component:
- `step1_data_format_reference.md` — CSV format specification
- `step2_ggir_pipeline_reference.md` — GGIR pipeline internals
- `step3_action_plan_and_strategy.md` — Implementation roadmap and architecture decisions
- `meeting-notes/monday_meeting_prep.md` — Open questions and context from client meetings

# Monday meeting prep — Tim Hellemans

**Date**: Monday, March 31, 2026
**With**: Tim Hellemans (Ortec) — technical advisor, math specialist
**Format**: Informal discussion
**Goal**: Align on project understanding, surface open questions, propose a plan that demonstrates proactive thinking

---

## Part 1 — What I've learned so far

### The project in one paragraph

Veerle's team at UGent is studying physical activity in Belgian primary school children across 6 schools. Children wear GENEActiv wrist accelerometers for ~7 days, twice per school (meting 1 and meting 2). The raw acceleration data needs to be processed into per-day summaries of sedentary behavior (SB), light physical activity (LPA), and moderate-to-vigorous physical activity (MVPA), segmented by school schedule (lessons vs recess vs free time). The current tooling is GGIR, an R package. Our job is to build a pipeline — initially in R leveraging GGIR, then ported to Python — with added value through visualization, quality reporting, and accessibility.

### Key technical concepts I've grasped

- **ENMO** (Euclidean Norm Minus One): the standard metric for body acceleration, gravity-subtracted. `max(0, √(x² + y² + z²) − 1)`, averaged per epoch.
- **SVMgs**: pre-computed by the GENEActiv software in the CSV export — essentially the sum of per-sample ENMO across an epoch. Related but not identical to what GGIR computes (GGIR autocalibrates first).
- **Epochs**: fixed time windows (1-second in Veerle's protocol) over which raw 100 Hz samples are aggregated.
- **Cut-points**: ENMO thresholds that classify each epoch as SB, LPA, or MVPA. Population-specific (children, wrist-worn, GENEActiv).
- **GGIR pipeline**: 6-part sequential pipeline — autocalibration → metric extraction → quality checks → sleep detection → time-use analysis → cross-recording analysis.
- **Validity criteria**: ≥16h wear per valid day, ≥3 valid days (incl. ≥1 weekend day) per valid measurement, clipping score <0.150.

### What I have documented

I've created three reference documents:

1. **Step 1 — Data format reference**: Complete CSV column definitions, header structure, file naming convention, ENMO vs SVMgs distinction, Jensen's inequality issue
2. **Step 2 — GGIR pipeline walkthrough**: All 6 parts explained, relevance-mapped to Veerle's study, porting complexity assessed, open questions identified
3. **Step 3 — Action plan and strategy**: Phased implementation plan, MCP server architecture proposal, output strategy with value-adds

---

## Part 2 — Questions for Tim

### About the data and processing

1. **SVMgs vs ENMO**: The CSV files contain a pre-computed SVMgs column (ENMO summed over raw samples per epoch, factory calibration). GGIR ignores this and recomputes ENMO from raw `.bin` files after autocalibration. For our pipeline:
   - Is the accuracy gain from autocalibration significant enough to justify parsing `.bin` files?
   - Or can we work from CSVs with `SVMgs / sample_count` as our ENMO estimate?
   - **My current thinking**: Start from CSV, design interfaces so the ENMO source is swappable. Validate CSV-based results against GGIR's `.bin`-based output to quantify the calibration error.

2. **Cut-point values**: Veerle references "validated cut-points specifically designed for children with data from wrist-worn GENEActiv accelerometers" (citation 7 in her protocol). I don't have the exact thresholds yet.

3. **Autocalibration algorithm**: GGIR fits stationary-period accelerometer readings to a sphere of radius 1g to estimate per-axis offset and gain corrections. This is essentially a least-squares sphere fit. Worth understanding the math — is this something you've encountered? Any pitfalls I should know about?

4. **Sleep detection**: GGIR's HDCZA algorithm is the most complex component. An alternative is the L5 method (find the least-active 5-hour window in each 24h period). Is L5 sufficient for a school-children study, or would the research team expect full HDCZA?

5. **Non-wear detection**: GGIR uses rolling-window standard deviation on each axis. If std dev is below a threshold on ≥2 of 3 axes for an extended period, it's non-wear. Are there better approaches? The temperature column (skin ~30°C vs table ~22°C) could be a useful supplementary signal.

6. **Jensen's inequality issue**: You can't compute ENMO from epoch-averaged x, y, z values — the norm of the mean ≠ the mean of the norms. This means the CSV's `xm`, `ym`, `zm` columns are lossy for ENMO purposes. The `SVMgs` column preserves the correct computation. Worth flagging as it's a potential source of bugs.

### About scope and approach

7. **R-first, then Python**: I'm proposing to build the initial version in R, directly leveraging GGIR and using R Shiny for visualization. Then port the pipeline to Python. This gives us:
   - Ground truth from GGIR to validate the Python implementation
   - A working prototype Veerle can use immediately (R Shiny)
   - Both languages as deliverables (R is critical in academia)
   - Does this approach make sense to you? Any concerns?

8. **Scope**: Is this a one-off pipeline ("process Veerle's data, deliver results") or a reusable tool ("build something for future studies")? This affects architecture decisions — config-driven vs hardcoded, CLI vs library, etc.

9. **Validation strategy**: How do we know our pipeline is correct? My plan is to run GGIR on the same data, then compare our output against GGIR's output per-pupil per-day. What tolerance should we accept for numerical differences?

10. **The Zenodo dataset as a development stand-in**: We can't work with real data yet (GDPR). The Zenodo GENEActiv dataset (231 recordings from New Caledonia, same hardware, public) could serve as development data. Same format, same device, no privacy issues. Good idea, or are there gotchas?

### About timing and data availability

11. **Data collection timeline**: Some measurements have already happened (School 5 meting 1 was Jan 9–16), others are still upcoming (School 1 meting 2 is Jun 1–8). Does Veerle already have `.bin` files from completed measurements? When can we expect real (anonymized) data to work with?

12. **GGIR config.csv**: GGIR stores all parameter values in a `config.csv` after each run. If Veerle has already processed any data with GGIR, that file would give us every parameter setting she used. This is the single most useful artifact she could share. Should I ask for it?

13. **Missing metadata**: School 3's per-class timetable and School 4's schedule are missing from the measurement document. These are needed for day-segment analysis. Should I flag this to Veerle or is it already being handled?

14. **Getting a `.bin` file for development**: The Zenodo dataset has open-access epoch CSVs (immediately downloadable), but the raw `.bin` files are restricted and require author approval. For building the binary parser and testing autocalibration, we need at least one `.bin` file. Two paths:
    - **Request Zenodo access**: Submit a request to the dataset authors (University of New Caledonia) with a justification about pipeline development. Note: their devices are 60 Hz vs Veerle's 100 Hz.
    - **Ask Veerle directly**: Even a single anonymized/scrambled `.bin` file from her own data would be ideal — same hardware version (GENEActiv 1.1, 100 Hz), same export format. This is faster and more representative.
    - Should I pursue both paths in parallel?

---

## Part 3 — Proposed plan

### Dual-language strategy: R → Python

```
         R phase (GGIR + Shiny)              Python phase (custom pipeline)
         ========================            ==============================
Week 1   Set up R env, run GGIR              Set up uv env, project scaffold
         on Zenodo data                      CSV parser, school schedule config
                                            
Week 2   Configure GGIR with                 Core pipeline: ENMO, non-wear,
         Veerle's parameters                 clipping, cut-points, validity
                                            
Week 3   Build R Shiny prototype:            Sleep detection (L5 or HDCZA)
         quality dashboard,                  Full time-series classification
         schedule overlay plots              
                                            
Week 4   Validate: compare GGIR             Day-segment analysis
         output vs Python output             Bout detection
                                            
Week 5+  Iterate based on feedback          Output: dashboards, reports,
         from Veerle                         export tables, MCP server
```

The R and Python tracks can run in parallel. The R phase provides both a working tool for Veerle and a validation oracle for the Python implementation.

### Development environment

| Component | Tool | Notes |
|-----------|------|-------|
| Python environment | `uv` | Fast, reproducible, lockfile-based |
| R environment | `renv` | R equivalent of uv for reproducibility |
| Version control | GitHub | Private repo, structured branching |
| AI-assisted dev | Claude Code | With context7 MCP on GGIR for R source reference |
| R visualization | Shiny | Interactive dashboards for Veerle |
| Python visualization | TBD | Plotly, Streamlit, or HTML reports |

### Environment management: uv is Python-only

`uv` does not manage R environments — it's Astral's replacement for pip/venv/poetry, Python-only. For R, the equivalent is `renv`. The two run side by side without interfering:

| Concern | Python | R |
|---------|--------|---|
| Environment manager | `uv` | `renv` |
| Lockfile | `uv.lock` | `renv.lock` |
| Project config | `pyproject.toml` | `.Rprofile` + `renv/` |
| Package install | `uv add pandas` | `renv::install("GGIR")` |

Both lockfiles get committed to git so anyone can reproduce the exact environment. For a unified developer experience across both languages, a `Makefile` or `just` (modern command runner) can provide shared targets like `make setup-r`, `make setup-python`, `make run-ggir`, `make run-pipeline`.

### Claude Code + context7 setup

- Connect context7 MCP server for GGIR (`https://context7.com/wadpac/ggir`)
- This gives Claude Code searchable access to GGIR's R source code
- Useful during R phase: "How does GGIR implement non-wear detection?" → get the actual R code
- Useful during Python phase: "Port this GGIR function to Python" → with exact source as context

### Project structure (initial)

```
accelerometer-pipeline/
├── README.md
├── docs/
│   ├── step1_data_format_reference.md
│   ├── step2_ggir_pipeline_reference.md
│   └── step3_action_plan_and_strategy.md
├── r/
│   ├── renv.lock
│   ├── run_ggir.R              # GGIR configuration and execution
│   ├── shiny/                  # R Shiny dashboard app
│   └── validation/             # Compare GGIR output vs Python output
├── python/
│   ├── pyproject.toml          # uv project config
│   ├── src/
│   │   └── accel_pipeline/
│   │       ├── ingest/         # CSV/bin parsing, metadata extraction
│   │       ├── processing/     # ENMO, non-wear, sleep, classification
│   │       ├── analysis/       # Day segments, bouts, summaries
│   │       ├── output/         # Reports, tables, visualizations
│   │       └── config/         # School schedules, parameters
│   └── tests/
├── data/
│   ├── raw/                    # .bin or .csv input files (gitignored)
│   ├── processed/              # Pipeline output (gitignored)
│   └── example/                # Fictional example (committed)
└── mcp/                        # MCP server wrappers (later phase)
```

---

## Part 4 — Ideas for added value

### Beyond what GGIR does

These are features that differentiate our pipeline from "just running GGIR":

| Feature | What it does | Why it matters |
|---------|-------------|----------------|
| **Data quality dashboard** | Per-school visual report: validity, wear compliance, temperature profiles, clipping | GGIR buries this in CSVs nobody reads |
| **Schedule overlay plots** | ENMO time series with school schedule annotations (lessons, recess, lunch) | Makes data tangible; great for presentations and papers |
| **Meting 1 ↔ 2 comparison** | Automated paired analysis per pupil and per school | Probably her primary research question; saves manual wrangling |
| **Recess activity analysis** | MVPA per minute of break time, compared across schools | Publishable finding that falls out naturally from the schedule config |
| **Anomaly flagging** | Auto-detect zero-MVPA pupils, mid-day device removal, school-wide unusual days | Catches silent data quality issues |
| **Export-ready tables** | Publication-format summary tables (mean ± SD) in CSV, markdown, LaTeX | Saves hours of reformatting |
| **Reproducibility manifest** | Per-run log of inputs, parameters, versions, decisions | Increasingly required by journals |
| **MCP server interface** | Natural language access to pipeline results via Claude | Lets Veerle explore data without coding |

### The R Shiny prototype specifically

This is the fastest path to a demo Veerle can interact with. Proposed tabs:

1. **Overview**: Select school, measurement period. See summary stats, valid pupil count.
2. **Quality**: Wear time heatmap, clipping scores, temperature compliance.
3. **Activity**: Per-pupil daily SB/LPA/MVPA. Filterable by day, segment.
4. **Schedule view**: Interactive ENMO time series with schedule overlay for selected pupil + day.
5. **Comparison**: Meting 1 vs meting 2 paired analysis. Per-pupil and per-school.
6. **Export**: Download summary tables, quality reports, individual plots.

---

## Part 5 — Risks and open items

| Risk | Mitigation |
|------|-----------|
| **GDPR blocks access to real data** | Use Zenodo open CSV epochs for development; request Zenodo restricted `.bin` access; ask Veerle to share a single anonymized `.bin` file from her data |
| **Cut-point values unknown** | Ask Veerle for citation (7) or her exact GGIR config |
| **Missing school schedules (3 & 4)** | Flag to Veerle; build config system that handles partial data gracefully |
| **Autocalibration complexity** | Start from CSV (skip autocal); design for .bin upgrade path |
| **GGIR version differences** | Pin GGIR version in renv; document which version we validate against |
| **Sleep detection accuracy** | Start with L5 (simpler); upgrade to HDCZA if L5 proves insufficient |
| **Scope creep** | Define MVP: CSV → classified epochs → per-day summaries. Everything else is enhancement |

---

## Checklist: things to bring up Monday

- [ ] Confirm R-first → Python strategy makes sense
- [ ] Discuss SVMgs vs ENMO / CSV vs .bin tradeoff
- [ ] Ask about cut-point values (or how to get them)
- [ ] Propose using Zenodo dataset for development (open CSV epochs are immediately available)
- [ ] Ask about getting a `.bin` file — either request access to Zenodo restricted set, or ask Veerle to share a single anonymized `.bin` from her data (needed for parser + autocalibration development)
- [ ] Discuss autocalibration math (sphere fitting — Tim's domain)
- [ ] Align on scope: one-off vs reusable tool
- [ ] Discuss validation strategy: our output vs GGIR output
- [ ] Mention the GGIR `config.csv` artifact — should I ask Veerle for it?
- [ ] Flag missing school schedules
- [ ] Discuss R Shiny as fast prototype for Veerle
- [ ] Mention MCP server concept (gauge interest)
- [ ] Discuss timeline expectations

---

## Appendix: Key reference links

| Resource | URL |
|----------|-----|
| GGIR documentation | https://wadpac.github.io/GGIR/index.html |
| GGIR pipeline chapter | https://wadpac.github.io/GGIR/articles/chapter2_Pipeline.html |
| GGIR cut-points reference | https://wadpac.github.io/GGIR/articles/CutPoints.html |
| GGIR parameters reference | https://wadpac.github.io/GGIR/articles/GGIRParameters.html |
| GGIR day-segment tutorial | https://wadpac.github.io/GGIR/articles/TutorialDaySegmentAnalyses.html |
| Zenodo raw data (GENEActiv .bin) | https://zenodo.org/records/11594645 |
| Zenodo epoch CSVs (anonymized) | https://zenodo.org/records/12682660 |
| Context7 GGIR source | https://context7.com/wadpac/ggir |
| GENEActiv hardware manual | https://activinsights.com/wp-content/uploads/2022/06/GENEActiv-Instructions-for-Use-v1_31Mar2022.pdf |
| MCP Python SDK | https://github.com/modelcontextprotocol/python-sdk |

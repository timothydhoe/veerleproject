# Step 3 — Action plan, architecture, and output strategy

## Overview

This document consolidates three strategic dimensions of the accelerometer data pipeline project:

1. **Action plan** — phased implementation roadmap based on current knowledge and open blockers
2. **MCP server architecture** — how Model Context Protocol servers can make the pipeline accessible to non-technical researchers
3. **Output strategy** — what Veerle needs, and what value-adds would make the project stand out

---

## 1. Action plan

### Phase 0 — Unblock (before writing pipeline code)

Several items gate implementation. These should be resolved in the next meeting with Veerle.

#### Critical blockers

| Item | Why it blocks | Who to ask |
|------|--------------|------------|
| **Cut-point thresholds** | Cannot implement SB/LPA/MVPA classification without exact ENMO values | Veerle — referenced as citation (7) in her protocol |
| **CSV or .bin as input** | Determines entire Part 1 architecture (autocalibration yes/no) | Veerle — she mentioned converting .bin to .csv for us |
| **GGIR `config.csv`** | Contains every parameter she used — eliminates guesswork | Veerle — GGIR generates this automatically per run |
| **Missing school schedules** | Cannot run day-segment analysis for Schools 3 and 4 | Veerle — she noted these are still pending |
| **Day-segment definitions** | Need to agree on which time windows to segment (lessons, recess, lunch, after-school) | Veerle + research team |

#### Nice-to-have clarifications

- [ ] Does she use a sleep log, or is algorithmic sleep detection the only option?
- [ ] What epoch length does she configure in GGIR? (Protocol says 1-second, but confirm)
- [ ] Are there any pupils she already knows should be excluded (device failures, withdrawals)?
- [ ] What statistical software does she use downstream (R, SPSS, Stata)? Affects export format choices.
- [ ] Is the study longitudinal (meting 1 vs meting 2 comparison), cross-sectional, or both?

---

### Phase 1 — Scaffold + CSV ingestion (buildable now)

**Goal**: Get data in, structured and queryable, without needing any pipeline parameters yet.

| Component | Description | Depends on |
|-----------|-------------|------------|
| **CSV parser** | Parse 100-line header into metadata dict; parse data rows into DataFrame with proper column names and datetime index | Fictional example data (available) |
| **File naming decoder** | Extract school ID (digit 1) and pupil ID (digits 2–4) from filename | Email specification (available) |
| **Folder structure handler** | Map meting 1 / meting 2 directories; associate same-named files across measurements | Email specification (available) |
| **School schedule config** | Parse known schedules into structured format: per-school, per-day-of-week time windows for lessons, breaks, start/end | `Info_metingen.docx` (partially available) |
| **Test suite** | Unit tests against fictional example data for all of the above | All of the above |

**Deliverable**: A Python library that can ingest a folder of CSV files and produce a clean, indexed, metadata-enriched DataFrame ready for pipeline processing. Plus a structured school schedule config that can answer queries like "What time is morning recess at School 2 on a Wednesday?"

---

### Phase 2 — Core pipeline (once cut-points are confirmed)

**Goal**: Implement the GGIR-equivalent processing chain from epoch data to classified time series.

| Component | GGIR equivalent | Complexity | Notes |
|-----------|----------------|------------|-------|
| **ENMO derivation** | Part 1 | Low | `SVMgs / sample_count` from CSV, or full computation from raw data |
| **Non-wear detection** | Part 2 | Medium | Rolling window (default 15 min): std dev < threshold on ≥2 axes |
| **Clipping detection** | Part 2 | Low | Fraction of samples at ±8g; threshold < 0.150 |
| **Cut-point classification** | Part 2 | Low | Threshold comparisons once values are known |
| **Day validity** | Part 2 | Low | ≥16h wear, ≥3 valid days incl. ≥1 weekend day |
| **Measurement validity** | Part 2 | Low | Aggregate day validity per pupil per measurement period |

**Deliverable**: Each epoch in the dataset gets an ENMO value and a preliminary activity label (SB/LPA/MVPA/non-wear/invalid). Each day and each measurement gets a validity flag.

---

### Phase 3 — Sleep + integration (parallel or after Phase 2)

**Goal**: Exclude sleep from activity analysis; produce the fully classified time series.

| Component | GGIR equivalent | Complexity | Notes |
|-----------|----------------|------------|-------|
| **Arm angle (anglez)** | Part 1 | Medium | Requires raw data or approximation from epoch means |
| **SIB detection** | Part 3 | Medium | Sliding window on anglez: < 5° change for ≥ 30 min |
| **Sleep detection** | Part 4 | Medium–High | Start with L5 (least active 5h); upgrade to HDCZA if needed |
| **Full classification** | Part 5 | Low | Merge sleep labels with activity labels per epoch |
| **Day-segment analysis** | Part 5 | Low | Filter epochs by school schedule windows; aggregate |
| **Bout detection** | Part 5 | Medium | Sustained MVPA with configurable tolerance and duration |

**Deliverable**: A complete classified time series where every epoch of every valid day is labeled: `sleep`, `SB`, `LPA`, `MVPA`, `non-wear`, or `invalid`. Day-segment summaries per school schedule window.

---

### Phase 4 — Output + value-adds (see section 3)

**Goal**: Transform pipeline output into research-ready deliverables.

| Component | Description | Complexity |
|-----------|-------------|------------|
| **Per-pupil summary reports** | Minutes in SB/LPA/MVPA per valid day, averaged per measurement | Low |
| **Data quality dashboard** | Visual per-school report: validity, wear time, compliance | Medium |
| **Schedule overlay plots** | ENMO time series with school schedule annotations | Medium |
| **Meting 1 ↔ 2 comparison** | Paired change analysis per pupil and per school | Medium |
| **Export-ready tables** | Publication-format summary tables (mean ± SD) | Low |
| **Anomaly flagging** | Auto-detect unusual patterns (zero MVPA, school-wide anomalies) | Medium |
| **Reproducibility manifest** | Log of inputs, parameters, versions, decisions per run | Low |

---

### Timeline sketch

```
Phase 0 ████░░░░░░░░░░░░░░░░  Unblock (meeting with Veerle)
Phase 1 ░░██████░░░░░░░░░░░░  Scaffold + CSV ingestion
Phase 2 ░░░░░░██████░░░░░░░░  Core pipeline
Phase 3 ░░░░░░░░░░██████░░░░  Sleep + integration
Phase 4 ░░░░░░░░░░░░░░██████  Output + value-adds
```

Phases 2 and 3 can partially overlap: non-wear detection and cut-point classification don't depend on sleep detection. The sleep path can be developed in parallel and merged into the full classification later.

---

## 2. MCP server architecture

### What is MCP in this context

Model Context Protocol (MCP) allows an LLM (like Claude) to call tools exposed by external servers. In this project, wrapping the pipeline as an MCP server would let researchers interact with their accelerometer data through natural language — no Python or pandas required.

### Proposed MCP servers

#### Pipeline server

Wraps the core processing functions. Researchers can trigger processing and retrieve results through conversation.

| Tool | Description | Example query |
|------|-------------|---------------|
| `process_file` | Run the pipeline on a single pupil's CSV | "Process file 2063 from meting 1" |
| `process_school` | Run the pipeline on all files for a school | "Process all School 2 data" |
| `get_pupil_summary` | Retrieve per-day activity summary for a pupil | "Show me pupil 4001's activity breakdown" |
| `get_school_summary` | Aggregate activity summary across all valid pupils in a school | "What's the average MVPA for School 5?" |
| `compare_metingen` | Paired comparison between meting 1 and 2 | "How did School 1's recess activity change between measurements?" |

#### Data quality server

Exposes quality checks and validity information.

| Tool | Description | Example query |
|------|-------------|---------------|
| `check_validity` | Check if a pupil's measurement meets inclusion criteria | "Does pupil 3012 have enough valid days?" |
| `list_invalid` | List all pupils who don't meet validity criteria | "Which pupils from meting 1 are excluded?" |
| `get_wear_report` | Per-day wear time and non-wear breakdown | "Show me the wear time for pupil 1005 day by day" |
| `get_clipping_report` | Clipping scores per file | "Are there any files with clipping issues?" |
| `get_quality_dashboard` | Full quality overview for a school/measurement | "Give me a quality report for School 6 meting 2" |

#### Metadata server

Wraps the school schedule configuration and measurement calendar.

| Tool | Description | Example query |
|------|-------------|---------------|
| `get_schedule` | Return the school schedule for a given day | "What are School 2's hours on Wednesday?" |
| `get_measurement_dates` | Return start/end dates for a school's measurement | "When was School 4's second measurement?" |
| `get_segments` | Return the day-segment definitions for a school | "What time windows are defined for School 1?" |
| `list_schools` | Overview of all schools, their schedules, and measurement status | "Give me an overview of all schools" |

### Why this matters

**For Veerle**: She's a kinesiology researcher, not a data engineer. Instead of learning pandas, she asks questions in natural language. Claude calls the MCP tools, gets structured data, and presents results as tables or visualizations. When new data arrives (meting 2 is still in progress for some schools), she can process and explore it immediately without developer involvement.

**For the development team**: MCP tools enforce clean function interfaces. If `get_pupil_summary(school_id, pupil_id, meting)` works as an MCP tool, it also works as a library call, a CLI command, or an API endpoint. MCP-first design produces good software architecture as a side effect.

**For reproducibility**: Every MCP tool call is logged with its parameters in the conversation. This creates an automatic audit trail of which analyses were run with which settings — useful for methodology sections in papers.

### Implementation approach

1. Build the pipeline as a clean Python library with well-defined functions (Phases 1–3)
2. Write thin MCP wrappers around those functions using the MCP Python SDK
3. Register the servers so Claude can discover and call them
4. Iterate based on Veerle's actual usage patterns

The library is the hard part. The MCP wrapper layer is comparatively thin — each tool is essentially a function signature, a docstring, and a call to the underlying library.

---

## 3. Output strategy

### What Veerle explicitly needs

Based on the email, protocol excerpt, and measurement metadata, her core deliverables are:

#### Per-pupil, per-day summaries

For each valid day of each pupil:

- Total minutes in SB, LPA, MVPA (waking hours only, excluding sleep and non-wear)
- Total valid wear time
- Average ENMO

#### Per-pupil, per-measurement summaries

Averaged across all valid days within a measurement period:

- Mean daily minutes in SB, LPA, MVPA
- Number of valid days (and which days)
- Whether the measurement meets the inclusion criteria (≥3 valid days including ≥1 weekend)

#### Day-segment summaries

Activity broken down by time-of-day segments aligned to school schedules:

- **During lessons**: SB/LPA/MVPA minutes
- **During recess/breaks**: SB/LPA/MVPA minutes
- **Before school**: SB/LPA/MVPA minutes
- **After school**: SB/LPA/MVPA minutes

#### Meting 1 vs meting 2 comparison

For pupils with valid data in both measurement periods:

- Change in daily SB/LPA/MVPA minutes
- Per-school aggregation of changes

#### Validity report

- Which pupils are included/excluded and why
- Per-day breakdown of wear time and non-wear

---

### Value-adds that make the project stand out

#### 1. Data quality dashboard

**What**: A per-school visual report generated automatically after processing.

**Contents**:
- Number of pupils with valid vs invalid measurements (bar chart)
- Per-pupil wear time heatmap (days × hours, colored by wear/non-wear/sleep)
- Clipping score distribution
- Temperature profile summary (compliance indicator: was the device worn consistently?)
- List of specific issues (e.g., "Pupil 2017: only 2 valid days, missing weekend")

**Why it stands out**: GGIR produces this information scattered across multiple CSV files that nobody enjoys reading. A single visual dashboard per school saves Veerle hours of manual quality checking and gives her confidence in the data before she starts interpreting results.

#### 2. Schedule overlay visualization

**What**: Plot a pupil's ENMO time series for a single school day with the schedule overlaid.

**Contents**:
- X-axis: time of day (e.g., 7:00–18:00)
- Y-axis: ENMO (rolling average for readability)
- Background shading: lesson blocks (gray), recess (green), lunch (blue), before/after school (unshaded)
- Horizontal lines at cut-point thresholds
- Activity classification color-coded on the time series itself

**Why it stands out**: This makes the data *tangible*. Veerle can see exactly when a child is active vs sedentary, and how that maps to the school day. It's the kind of figure that works in presentations, papers, and conversations with school staff. GGIR produces nothing like this.

#### 3. Recess activity analysis

**What**: Compute activity intensity specifically during break times, comparable across schools.

**Contents**:
- Average ENMO per minute of recess, per school
- Percentage of recess time in MVPA, per school
- Comparison across schools (controlling for recess duration)
- Meting 1 vs meting 2 change in recess activity

**Why it stands out**: The school schedules encode specific break times. Computing activity during these windows is a publishable finding: "Children at School X spent Y% of recess in MVPA." This is the kind of fine-grained, schedule-aware analysis that GGIR supports in theory (via day-segment analysis) but that requires manual configuration per school. Automating it from the structured schedule config is a genuine contribution.

#### 4. Anomaly flagging

**What**: Automatically detect and report unusual patterns that warrant manual investigation.

**Flags to implement**:
- **Zero MVPA across all days**: Device compliance issue? Child mobility limitation?
- **Sudden temperature drop during school hours**: Device removed mid-day
- **Entire school shows unusual pattern on a specific day**: Field trip, school event, exam day?
- **Clipping spikes**: Device malfunction or extreme activity?
- **Non-wear concentrated at specific times**: Pattern of removal (e.g., always during PE class — ironic)

**Why it stands out**: These are insights that GGIR doesn't surface but that a researcher would want to investigate. Proactive flagging saves manual data inspection time and catches issues that might otherwise bias results silently.

#### 5. Export-ready tables

**What**: Publication-format summary tables that drop straight into a manuscript.

**Format**:
```
Table 1. Physical activity by school and measurement period (mean ± SD)

School  | N  | SB (min/day)   | LPA (min/day)  | MVPA (min/day) | Valid days
--------|-----|----------------|----------------|----------------|----------
School 1 | 23 | 342.1 ± 48.3  | 178.4 ± 32.1  | 41.2 ± 18.7   | 5.2 ± 1.1
School 2 | 19 | 356.8 ± 51.7  | 165.2 ± 28.9  | 38.7 ± 15.3   | 4.8 ± 1.3
...
```

**Formats**: CSV for statistical software, formatted markdown for manuscripts, and optionally LaTeX for journal submission.

**Why it stands out**: Researchers spend a surprising amount of time reformatting GGIR output into paper-ready tables. Having these generated automatically — with the right grouping, rounding, and layout — is a significant time saver.

#### 6. Reproducibility manifest

**What**: Every pipeline run produces a manifest file documenting exactly what was done.

**Contents**:
- Input files processed (paths, checksums)
- Pipeline version and commit hash
- All parameter values used (cut-points, epoch length, validity thresholds, etc.)
- Timestamp of processing
- Validity decisions made (which pupils included/excluded and why)
- Any anomalies flagged

**Why it stands out**: Increasingly required by journals. Makes the research defensible during peer review. Also useful internally: when Veerle reprocesses data with different parameters, the manifest shows exactly what changed.

---

### Output format recommendations

| Deliverable | Primary format | Secondary format | Notes |
|-------------|---------------|-----------------|-------|
| Per-pupil summaries | CSV | Excel (.xlsx) | One row per pupil-day; pivot-friendly |
| Per-school summaries | CSV | Formatted markdown | Ready for statistical software / manuscripts |
| Data quality dashboard | HTML | PDF | Interactive if HTML; printable if PDF |
| Schedule overlay plots | PNG/SVG | Interactive HTML | Per-pupil; batch-generate for all valid pupils |
| Meting comparison | CSV | Formatted markdown | Paired table with change scores |
| Validity report | CSV | HTML dashboard | Machine-readable + human-readable versions |
| Anomaly flags | CSV | Inline in quality dashboard | Structured for filtering |
| Reproducibility manifest | JSON | Plain text | Machine-readable with human-readable fallback |

---

## Summary: the pitch

If we execute this well, Veerle gets:

1. **A Python pipeline** that does everything GGIR does for her use case — but faster, more transparent, and without requiring R knowledge
2. **An MCP interface** that lets her explore her data through natural language — ask questions, get answers, no code
3. **Visual outputs** that GGIR doesn't produce — schedule overlays, quality dashboards, anomaly reports
4. **Research-ready deliverables** — publication tables, reproducibility manifests, comparison analyses
5. **A reusable tool** — the pipeline + MCP server can be used for future measurement waves, other schools, or other studies with the same hardware

The difference between "here are some CSVs" and "here's a system that understands your study" is what makes a data engineering project actually useful to a researcher.

---

## Sources

- Email from Veerle Van Oeckel (UGent), 23 March 2026 — study protocol, file conventions, processing decisions
- `Info_metingen.docx` — measurement dates and school schedules
- `Fictief_voorbeeld_data.csv` — fictional CSV export for format reference
- [GGIR documentation](https://wadpac.github.io/GGIR/index.html) — pipeline structure, parameters, output formats
- [GGIR Day-segment analysis tutorial](https://wadpac.github.io/GGIR/articles/TutorialDaySegmentAnalyses.html)
- [GGIR Output reference](https://wadpac.github.io/GGIR/articles/GGIRoutput.html)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) — for MCP server implementation
- [Zenodo dataset documentation](https://zenodo.org/records/12682660) — column definitions, study methodology reference

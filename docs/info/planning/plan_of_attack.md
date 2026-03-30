# Plan of Attack — SchoolMoves Pipeline

> Full phased plan for building the accelerometer data pipeline, analysis layer, user interface, and documentation for the SchoolMoves study.

---

## Summary timeline

| Phase | Focus | Dependencies | Target |
|---|---|---|---|
| 1 | Data foundation + dummy data | None | Week 1–2 |
| 2 | GGIR pipeline in R | Phase 1 | Week 2–5 |
| 3 | Analysis layer (R + Python) | Phase 2 | Week 4–8 |
| 4 | User interface | Phase 3 | Week 7–10 |
| 5 | Manual and documentation | Phases 2–4 | Week 9–11 |
| 6 | Testing and handover | All phases | Before June 2026 |

Phases 2 and 3 overlap intentionally — early analysis modules can be developed while the pipeline is still being finalized.

---

## Phase 1 — Data foundation

**Goal:** Have a working, realistic dataset to develop and test against before the full 400-pupil dataset is accessible.

### Why this comes first
The real data is too large to transfer easily (>31 MB per batch). Development cannot wait for it. A properly structured dummy dataset — one that mirrors the exact GENEActiv CSV format, school schedules, and realistic activity patterns — allows the entire pipeline to be built and validated before a single real file is processed.

### Deliverables
- Python script `generate_dummy_data.py` that produces one `.csv` per pupil per measurement period
- Files follow the exact GENEActiv header + data format (see [Data Dictionary](data_dictionary.md))
- Configurable number of pupils (default 20 for dev, 400 for full run)
- Activity patterns vary by time of day, school schedule, and day of week
- ~10% of generated pupils intentionally fail validity criteria (for testing the filter logic)
- Summary CSV: pupils generated, school distribution, validity pass/fail

### Key decisions
- Generate at 1 Hz (1-second epochs), not 100 Hz raw, to keep file sizes manageable during development
- Add a `--days` argument (default 7) and `--seed` for reproducibility
- ENMO values generated to match validated intensity cut-points

### See also
[Phase 1 detail](../phases/phase1_data_foundation.md)

---

## Phase 2 — GGIR pipeline (R)

**Goal:** A modular, reproducible R pipeline that takes raw GENEActiv files and produces clean, labelled, per-epoch output ready for analysis.

### Why GGIR
GGIR is the validated, published R package for processing GENEActiv accelerometer data. It handles the low-level signal processing (ENMO, g-calibration, sleep detection, non-wear detection) using methods with peer-reviewed validation. Building from scratch would be reinventing a validated wheel.

### Pipeline steps

```
Input: raw .bin or .csv per pupil
  │
  ├─ Step 1: .bin → .csv conversion (GGIR Part 1)
  ├─ Step 2: ENMO calculation + calibration (GGIR Part 1)
  ├─ Step 3: Epoch-level summaries at 1s and 1min (GGIR Part 2)
  ├─ Step 4: Sleep detection (GGIR Part 4)
  ├─ Step 5: Non-wear detection and flagging
  ├─ Step 6: Validity assessment (4-day / 5-night rule)
  ├─ Step 7: School-schedule labelling (custom layer)
  └─ Step 8: Export to parquet/CSV for analysis layer
```

### Custom layer on top of GGIR
GGIR produces per-epoch output with wear/non-wear flags and sleep flags. The custom layer adds:
- A `context` column: `in_class`, `recess`, `lunch`, `after_school`, `before_school`, `weekend`, `unknown`
- A `school_id` column derived from the filename (first digit)
- A `measurement_period` column (`meting_1` or `meting_2`)
- A `validity_flag` per pupil per day

The school-schedule lookup is stored in `config/school_schedules.yaml` so it can be updated without touching the code.

### Modularity principle
Each pipeline step is a separate R function with clear inputs and outputs. Functions are independently testable. A master script `run_pipeline.R` calls them in sequence but each can also be run standalone.

### See also
[Phase 2 detail](../phases/phase2_ggir_pipeline.md)

---

## Phase 3 — Analysis layer (R + Python)

**Goal:** Answer the specific research questions using the cleaned, labelled pipeline output.

### Research questions addressed

| Question | Tool | Notes |
|---|---|---|
| Total minutes per day per intensity level | R | By context (class / recess / after school / weekend) |
| Sedentary bouts ≥30 min | R | Count + total duration per day and context |
| Sleep duration and quality | R | From GGIR sleep output |
| Correlation between lesson duration and activity | R | Cross-school comparison |
| Attendance prediction | Python | Pattern-break detection + manual override |

### R–Python boundary
R handles all statistical analysis and outputs. Python handles the attendance prediction model (pattern recognition benefits from pandas/scikit-learn) and any batch preprocessing utilities. The two layers communicate via a shared parquet file in `data/processed/`.

### Attendance prediction logic
For each pupil, the typical daily arrival pattern (first sustained activity burst in the morning commute window) is modelled from the days they were present. Days where this pattern is absent or delayed are flagged as potential absence. The UI then surfaces these flags for manual confirmation by the researcher.

### See also
[Phase 3 detail](../phases/phase3_analysis_layer.md) · [Research Questions](research_questions.md)

---

## Phase 4 — User interface

**Goal:** A clean, usable dashboard that lets researchers explore results without writing code.

### Recommended stack: R Shiny
Shiny keeps the entire stack in R, avoids a Python–R bridge for the UI, and is familiar to the research community. If the Python analysis layer grows substantially, Streamlit is the fallback.

### Required views

| View | Purpose |
|---|---|
| School & pupil selector | Navigate from school-level overview to individual pupil |
| Activity summary | Daily totals by intensity, annotated with school hours |
| Sedentary bouts | Bout frequency and duration per context |
| Sleep panel | Duration and efficiency across the 7-day window |
| Attendance check | Flagged absence days with confirm/override controls |
| Data quality | Validity pass/fail per pupil, exclusion reasons |

### Design principles
- Researchers, not developers, are the primary users
- Every chart should be explainable in one sentence
- Filters and selectors update all views simultaneously
- Export buttons on every view (CSV, PNG)

### See also
[Phase 4 detail](../phases/phase4_user_interface.md)

---

## Phase 5 — Manual and documentation

**Goal:** Documentation that a non-technical researcher can follow without assistance, and code docs that allow Tim or a future developer to extend the system.

### User manual structure
1. System requirements and installation
2. Running the pipeline on a new batch of data
3. Understanding each dashboard view
4. Handling validity failures
5. Troubleshooting FAQ

### Code documentation
- R functions: `roxygen2` format
- Python functions: Google-style docstrings
- Config files: inline comments in YAML

### RAG-readiness
The manual is written in clearly chunked Markdown with descriptive headings so it can be split into chunks and embedded in a retrieval system. Each section is self-contained and answers a specific question.

### See also
[Phase 5 detail](../phases/phase5_manual_documentation.md)

---

## Phase 6 — Testing and handover

**Goal:** Validate the pipeline on real data, confirm with Tim, and hand over a production-ready system.

### Validation steps
1. Run the pipeline on 5–10 real pupil files and compare output to the existing system
2. Confirm ENMO values, sleep detection output, and validity classifications match
3. Run the full 400-pupil dataset and review validity statistics
4. User acceptance test with Veerle on the dashboard

### Handover package
- Clean git repository with README
- Installed dependencies documented (`renv.lock` for R, `requirements.txt` for Python)
- User manual (PDF + Markdown)
- Short walkthrough session with Tim and Veerle

### See also
[Phase 6 detail](../phases/phase6_testing_handover.md)

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Real data format differs from example CSV | Medium | High | Validate against real files as early as possible (Phase 6 step 1) |
| GGIR version incompatibilities | Low | Medium | Pin GGIR version in `renv.lock` |
| School schedule data incomplete (School 3/4) | High | Low | Use generic Belgian primary schedule as fallback; flag in output |
| Pupil validity rates lower than expected | Medium | Medium | Report exclusion stats; discuss threshold adjustments with Veerle |
| Timeline slips on UI | Medium | Low | UI can be delivered after core pipeline; analysis outputs are usable standalone |
| Attendance prediction accuracy insufficient | Medium | Low | Frame as a decision-support tool, not automated classification |

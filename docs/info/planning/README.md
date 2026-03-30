# SchoolMoves — Project Overview

> **Goal:** Build a reproducible, extensible pipeline for processing GENEActiv accelerometer data from ~400 primary school pupils across 6 schools, answering specific research questions about physical activity, sedentary behaviour, and sleep — with a user-friendly interface and documentation.

---

## Quick links

| Document | Description |
|---|---|
| [Plan of Attack](docs/plan_of_attack.md) | Full phased project plan |
| [Phase 1 — Data Foundation](phases/phase1_data_foundation.md) | Dummy data generation, file formats |
| [Phase 2 — GGIR Pipeline (R)](phases/phase2_ggir_pipeline.md) | Core R processing pipeline |
| [Phase 3 — Analysis Layer](phases/phase3_analysis_layer.md) | R + Python analysis modules |
| [Phase 4 — User Interface](phases/phase4_user_interface.md) | Dashboard and UI design (Shiny) |
| [Phase 5 — Manual & Docs](phases/phase5_manual_documentation.md) | User manual and code docs |
| [Phase 6 — Testing & Handover](phases/phase6_testing_handover.md) | Validation, review, delivery |
| [School Info](docs/school_info.md) | School schedules, measurement windows |
| [Data Dictionary](docs/data_dictionary.md) | All fields, formats, and units |
| [Research Questions](docs/research_questions.md) | Specific questions the pipeline must answer |

---

## Project at a glance

```
Raw .bin files (GENEActiv)
        │
        ▼
  GGIR Pipeline (R)
  ├── .bin → .csv conversion
  ├── ENMO calculation
  ├── Sleep detection
  ├── Non-wear detection
  └── Validity filtering
        │
        ▼
  Analysis Layer (R + Python)
  ├── Activity totals by context
  ├── Sedentary bout analysis
  ├── Sleep pattern analysis
  ├── School-hour correlations
  └── Attendance prediction
        │
        ▼
  User Interface (Shiny / Streamlit)
  ├── School & pupil selector
  ├── Activity summary dashboard
  ├── Sleep panel
  ├── Attendance check panel
  └── Data quality panel
        │
        ▼
  User Manual + Code Documentation
```

---

## Study context

- **6 schools**, approximately 400 pupils total (50–100 per school)
- **2 measurement periods** per pupil: before and after an intervention
- Each measurement: **7 days, 24h/day**
- Device: **GENEActiv 1.1**, worn on the non-dominant wrist
- Processing: **GGIR R package** for ENMO, sleep, non-wear, and validity
- Contact: Veerle (research), Tim (code/existing system)
- **Deadline: end of June 2026**

---

## Repository structure (target)

```
schoolmoves/
├── README.md
├── docs/
│   ├── plan_of_attack.md
│   ├── school_info.md
│   ├── data_dictionary.md
│   └── research_questions.md
├── phases/
│   ├── phase1_data_foundation.md
│   ├── phase2_ggir_pipeline.md
│   ├── phase3_analysis_layer.md
│   ├── phase4_user_interface.md
│   ├── phase5_manual_documentation.md
│   └── phase6_testing_handover.md
├── R/
│   ├── pipeline/
│   │   ├── 01_convert.R
│   │   ├── 02_ggir_process.R
│   │   ├── 03_classify_activity.R
│   │   ├── 04_label_schedule.R
│   │   ├── 05_filter_validity.R
│   │   └── 06_export.R
│   └── analysis/
│       ├── activity_totals.R
│       ├── sedentary_bouts.R
│       ├── sleep_analysis.R
│       └── school_correlations.R
├── python/
│   ├── pipeline/
│   │   ├── generate_dummy_data.py
│   │   └── preprocess.py
│   └── analysis/
│       ├── attendance_prediction.py
│       └── utils.py
├── ui/
│   ├── app.R              # Shiny app (or app.py for Streamlit)
│   └── modules/
├── config/
│   └── school_schedules.yaml
├── data/
│   ├── dummy/
│   │   ├── meting_1/
│   │   └── meting_2/
│   └── processed/
└── manual/
    └── user_manual.md
```

---

## Technology stack

| Layer | Technology | Rationale |
|---|---|---|
| Core processing | R + GGIR | GGIR is the validated package for GENEActiv data |
| Statistical analysis | R (tidyverse, ggplot2) | Natural fit for accelerometer research |
| Data wrangling / ML | Python (pandas, scikit-learn) | Attendance prediction, flexible pipelines |
| Shared data format | Parquet or CSV | Clean boundary between R and Python |
| User interface | R Shiny (preferred) or Streamlit | Shiny keeps everything in R; Streamlit if Python-heavy |
| Config | YAML | Human-readable, easily edited by researchers |
| Documentation | Markdown + roxygen2 + docstrings | Self-documenting, RAG-ready |

---

## Key contacts

| Role | Person | Scope |
|---|---|---|
| Research lead | Veerle | Content questions, analysis decisions |
| Technical lead | Tim | Code review, existing system, handover |

# Phase 5 — Manual and Documentation

> User manual for researchers and code documentation for developers. Written to be RAG-ready, self-contained, and maintainable.

---

## Goal

Produce documentation that:
- Allows a non-technical researcher to run the pipeline independently
- Allows a developer (Tim or successor) to extend the codebase without a handover session
- Is structured for retrieval-augmented generation (RAG) — each section answers one specific question
- Is maintainable: written in Markdown, version-controlled with the code

---

## Documents to produce

| Document | Audience | Format | Location |
|---|---|---|---|
| User manual | Researchers (Veerle) | Markdown + PDF export | `manual/user_manual.md` |
| Pipeline developer guide | Developers (Tim) | Markdown | `docs/developer_guide.md` |
| API / function reference | Developers | roxygen2 (R) + docstrings (Python) | Auto-generated |
| Quick-start card | Researchers | 1-page PDF | `manual/quick_start.pdf` |
| Troubleshooting FAQ | Researchers + developers | Markdown | `manual/faq.md` |

---

## User manual — structure

The user manual is written for a researcher who knows what ENMO means but has never run an R script. It uses plain language, numbered steps, and screenshots (added during Phase 6 once the UI is finalised).

### Table of contents

```
1. Introduction
   1.1 What this system does
   1.2 What you need (system requirements)
   1.3 How to get help

2. Installation
   2.1 Installing R and RStudio
   2.2 Installing required packages
   2.3 Verifying the installation

3. Running the pipeline
   3.1 Organising your data files
   3.2 Configuring the school schedules
   3.3 Running the pipeline for one measurement period
   3.4 Running the pipeline for both measurement periods
   3.5 What to do if the pipeline fails

4. Using the dashboard
   4.1 Opening the dashboard
   4.2 Selecting a school and pupil
   4.3 Reading the activity summary
   4.4 Reading the sedentary bouts panel
   4.5 Reading the sleep panel
   4.6 Reviewing attendance flags
   4.7 Exporting results

5. Understanding validity
   5.1 What validity means in this study
   5.2 How to find out which pupils were excluded
   5.3 What to do with excluded pupils

6. Troubleshooting
   6.1 The pipeline stops with an error
   6.2 A pupil's data looks wrong
   6.3 The dashboard is slow
   6.4 Attendance flags seem incorrect

7. Glossary
```

### RAG-readiness rules

Each section:
- Has a descriptive heading that could be a standalone question ("How do I run the pipeline for meting 1?")
- Is self-contained — reading section 3.3 should not require reading 3.1 first
- Contains no content that belongs in a different section
- Uses consistent terminology (terms in the Glossary are bolded on first use)

---

## Code documentation — R

All R functions use `roxygen2` format. Minimum required tags:

```r
#' Short one-line description
#'
#' One or two sentences explaining what the function does and why.
#'
#' @param input_dir Character. Path to folder containing raw .bin or .csv files.
#' @param output_dir Character. Path to write converted CSV files.
#' @param overwrite Logical. If TRUE, re-convert existing files. Default FALSE.
#'
#' @return Invisible data.frame with columns: file, status, message.
#'
#' @examples
#' \dontrun{
#' convert_to_csv("data/raw/meting_1", "data/csv/meting_1")
#' }
#'
#' @export
convert_to_csv <- function(input_dir, output_dir, overwrite = FALSE) {
```

Generate the HTML reference site with `pkgdown::build_site()` (optional but recommended before handover).

---

## Code documentation — Python

All Python functions use Google-style docstrings:

```python
def predict_attendance(
    pupil_df: pd.DataFrame,
    school_id: int,
    schedule_config: dict,
    arrival_window_minutes: int = 60
) -> pd.DataFrame:
    """Predict attendance for each school day based on morning activity patterns.

    Uses the presence or absence of a sustained morning activity burst around
    the school start time to infer whether the pupil was present.

    Args:
        pupil_df: Processed epoch data for one pupil.
            Required columns: timestamp, enmo_mg, context.
        school_id: School identifier (1-6), used to look up start time.
        schedule_config: Loaded school schedule configuration dictionary.
        arrival_window_minutes: Minutes around school start to check for
            arrival burst. Default 60.

    Returns:
        DataFrame with columns: date, predicted_present, confidence,
        arrival_time_detected.

    Example:
        >>> config = load_schedule_config("config/school_schedules.yaml")
        >>> result = predict_attendance(pupil_df, school_id=2, schedule_config=config)
    """
```

Generate the HTML reference with `pdoc`:
```bash
pdoc python/analysis/ python/pipeline/ -o docs/python_api/
```

---

## Inline documentation standards

### Config files (YAML)

Every key in `school_schedules.yaml` has an inline comment:

```yaml
school_1:
  schedule_source: actual  # "actual" = from school, "fallback" = generic estimate
  days:
    monday:
      start: "08:25"       # School day start time (HH:MM, 24-hour)
      end: "15:40"         # School day end time
      breaks:
        - start: "10:05"   # Morning break start
          end: "10:20"     # Morning break end
```

### Pipeline scripts

Each pipeline script starts with a comment block:

```r
# ============================================================
# 04_label_schedule.R
# Purpose: Add school-context labels to processed epoch data
# Input:   data.frame from 03_classify_activity.R
# Output:  Same data.frame with added columns: context, schedule_source
# Config:  config/school_schedules.yaml
# Author:  [name]
# Updated: [date]
# ============================================================
```

---

## Glossary (extract)

These terms are used consistently throughout all documentation.

| Term | Definition |
|---|---|
| ENMO | Euclidean Norm Minus One. A single number (in mg) summarising overall body movement from the three accelerometer axes. |
| Epoch | A fixed time interval (in this pipeline: 1 second) for which a single summary value is computed. |
| Intensity level | Classification of physical activity based on ENMO: sedentary, light, moderate, or vigorous. |
| Non-wear | A period when the accelerometer was not being worn, detected automatically by GGIR. |
| Validity | Whether a pupil has enough good-quality data to be included in a given analysis. |
| Meting 1 | The first 7-day measurement period, before the intervention. |
| Meting 2 | The second 7-day measurement period, during/after the intervention. |
| Context | The label describing what the pupil was doing: in class, at recess, at lunch, after school, or during the weekend. |
| GGIR | The R package used to process raw accelerometer data. Pronounced "gee-gee-ar". |
| Bout | A continuous unbroken period of a given activity type (e.g. a sedentary bout of 45 minutes). |

---

## Acceptance criteria

Before moving to Phase 6, verify:

- [ ] A researcher (Veerle) can complete section 3 (running the pipeline) without asking for help
- [ ] A developer (Tim) can add a new analysis module following the pattern in section 4 of the developer guide
- [ ] All R functions have roxygen2 docs; all Python functions have docstrings
- [ ] The glossary covers every technical term used in the dashboard UI
- [ ] The FAQ answers at least 5 real questions that came up during testing
- [ ] Manual is exportable to PDF (via `pandoc` or RMarkdown rendering)

# Step 2 — GGIR pipeline walkthrough

## Overview

GGIR is an R package for processing multi-day raw accelerometer data, designed for physical activity, sleep, and circadian rhythm research. It is the current tool used by Veerle's team at UGent to process GENEActiv data. Our goal is to understand the pipeline conceptually so we can port the relevant parts to Python.

GGIR is structured as a **6-part sequential pipeline**. Each part stores intermediate results as `.RData` milestone files, allowing re-runs from any point without reprocessing earlier stages. The parts together transform raw acceleration signals into per-day summaries of physical activity and sleep.

**Source**: [GGIR pipeline documentation (Chapter 2)](https://wadpac.github.io/GGIR/articles/chapter2_Pipeline.html)

---

## Pipeline summary

| Part | Purpose | Relevance to Veerle's study |
|------|---------|---------------------------|
| **Part 1** | Load, autocalibrate, compute metrics | **CRITICAL** — foundation of all downstream analysis |
| **Part 2** | Quality assessment + daily summaries | **CRITICAL** — validity criteria, cut-point classification |
| Part 3 | Sustained inactivity bout detection | NEEDED — input for sleep detection |
| Part 4 | Sleep period labeling | NEEDED — sleep must be excluded from PA analysis |
| **Part 5** | Time-use analysis | **CRITICAL** — produces the final SB/LPA/MVPA output |
| Part 6 | Cross-recording analyses | NOT NEEDED — circadian/household, outside current scope |

---

## Part 1: Load, calibrate, compute metrics

### What it does

Part 1 reads raw `.bin` files, applies autocalibration to correct sensor errors, computes acceleration metrics (primarily ENMO and arm angle), and aggregates them into fixed-length epochs.

### Autocalibration

Factory calibration of accelerometer axes drifts over time and with temperature. GGIR corrects this by:

1. Scanning the recording for periods of stillness (low variance across all axes)
2. During stillness, the total acceleration vector should equal exactly 1g
3. Fitting the observed still-points to a sphere of radius 1g to estimate per-axis offset and gain corrections
4. Applying corrections to all raw data before computing any metrics

The target calibration error is < 0.01g. GGIR loads data in chunks (starting at ~168 hours) and keeps loading more until this threshold is met.

**Source**: [GGIR Chapter 3 — Data Quality Assurance](https://wadpac.github.io/GGIR/articles/chapter3_QualityAssessment.html)

### Metric computation

After calibration, GGIR computes metrics at raw-data resolution (e.g., 100 Hz), then aggregates per epoch. Key metrics:

| Metric | Formula | Purpose |
|--------|---------|---------|
| **ENMO** | `max(0, √(x² + y² + z²) − 1)` averaged per epoch | Primary measure of body acceleration (gravity removed) |
| **anglez** | `atan(z / √(x² + y²))` after 5s rolling median | Arm angle relative to horizontal — used for sleep detection |
| EN | `√(x² + y² + z²)` averaged per epoch | Total acceleration (gravity included) |
| MAD | Mean absolute deviation of EN within epoch | Alternative activity metric based on variability |

The epoch length is configurable (default: 5 seconds). Multiple metrics can be computed in a single run.

**Source**: [GGIR Chapter 4 — From Raw Data to Acceleration Metrics](https://wadpac.github.io/GGIR/articles/chapter4_AccMetrics.html)

> **⚠️ VEERLE'S PROTOCOL**: Uses **ENMO** as the primary metric with **1-second epochs**. This differs from GGIR's default of 5-second epochs. The epoch length affects cut-point interpretation and must be consistent throughout the pipeline.

### Python porting implications

This is the heaviest part to port. Required components:

- `.bin` file reader (or accept CSV input with pre-computed SVMgs)
- Sphere-fitting autocalibration algorithm (if working from raw data)
- ENMO computation from calibrated tri-axial values
- Arm angle (`anglez`) computation for sleep detection
- Epoch aggregation at configurable window sizes

If starting from CSV files: autocalibration is skipped (factory calibration only), ENMO can be derived from the SVMgs column (`SVMgs / sample_count`), but `anglez` cannot be computed from epoch means — this limits sleep detection accuracy.

---

## Part 2: Quality assessment and daily summaries

### What it does

Part 2 evaluates data quality per day and per recording, detects non-wear periods, checks for signal clipping, and produces initial per-day physical activity summaries using cut-point classification.

### Clipping detection

Clipping occurs when acceleration readings saturate at the device's measurement limit (±8g for GENEActiv). GGIR computes a clipping score: the percentage of time during which any axis reads at or near the maximum range.

> **⚠️ VEERLE'S PROTOCOL**: Uses GGIR's default clipping score threshold of **< 0.150** (i.e., less than 15% of time clipped). Recordings exceeding this are considered invalid.

### Non-wear detection

GGIR detects non-wear using a rolling window approach (default: 15-minute windows evaluated every 5 minutes):

- If the standard deviation of acceleration is below a threshold on at least 2 of 3 axes, the window is classified as non-wear
- The value range of each axis within the window is also checked

Non-wear periods are excluded from analysis and affect the calculation of valid wear time per day.

**Practical note**: The temperature column (`tempm`) from the CSV can corroborate non-wear detection — skin contact produces readings of ~28–35°C, while a device on a table reads ~18–23°C. This is not used by GGIR's default non-wear algorithm but could be a useful additional signal in a Python implementation.

### Cut-point classification

Each epoch's ENMO value is compared against validated acceleration thresholds (cut-points) to classify it into an intensity category:

| Category | Meaning | ENMO range |
|----------|---------|------------|
| **SB** | Sedentary behavior | Below lower cut-point |
| **LPA** | Light physical activity | Between lower and upper cut-points |
| **MVPA** | Moderate-to-vigorous physical activity | Above upper cut-point |

The specific cut-point values depend on the population (children vs adults), device (GENEActiv vs ActiGraph), wear location (wrist vs hip), and epoch length. GGIR maintains a list of published cut-points.

**Source**: [GGIR Chapter 11 — Cut-points](https://wadpac.github.io/GGIR/articles/chapter11_DescribingDataCutPoints.html) and [Published cut-points reference](https://wadpac.github.io/GGIR/articles/CutPoints.html)

> **⚠️ VEERLE'S PROTOCOL**: Uses cut-points **specifically validated for children with data from wrist-worn GENEActiv accelerometers**. The exact cut-point values need to be confirmed with Veerle — they are referenced as citation (7) in her protocol but the specific thresholds are not stated in the email.

### Day validity

Part 2 also determines which days are valid for inclusion in the analysis based on wear time.

> **Superseded** — this was an early figure from Veerle's initial email, since replaced
> by the formal protocol citation: ≥9 valid hours of wear on ≥4 days (≥1 weekend day),
> matching `config.yaml`'s `min_wear_hours_per_day`/`min_valid_days` and `CLAUDE.md`'s
> Key Domain Concepts table. Kept below as a historical record, not current guidance.
>
> **⚠️ VEERLE'S PROTOCOL — VALIDITY CRITERIA** (from her email):
>
> - A **valid day** requires **≥ 16 hours** of accelerometer wear time
> - A **valid measurement** requires **≥ 3 valid days**, including **at least 1 weekend day**
> - Pupils who do not meet these criteria are **excluded from analysis**
>
> These are stricter than some defaults. The weekend day requirement is important: a measurement that captured only weekdays (Mon–Fri) is invalid even if it has 5+ valid days, because weekend activity patterns differ.

### Python porting implications

Moderately complex. Required components:

- Rolling-window non-wear detection (std dev + range checks per axis)
- Clipping score computation (fraction of samples at ±8g)
- Cut-point threshold comparisons (straightforward once cut-points are known)
- Per-day wear time calculation and validity flagging
- Per-measurement validity aggregation (counting valid days, weekend check)

---

## Part 3: Sustained inactivity bout detection (SIB)

### What it does

Part 3 identifies periods where the arm barely moves — candidate rest/sleep episodes. It uses the `anglez` metric from Part 1.

**Algorithm**: If the absolute change in arm angle (`anglez`) stays below 5° for at least 30 minutes continuously, the period is classified as a sustained inactivity bout (SIB). These are candidates for sleep, not confirmed sleep.

**Source**: [GGIR Chapter 8 — Sleep Fundamentals: SIB Detection](https://wadpac.github.io/GGIR/articles/chapter8_SleepFundamentalsSibs.html)

### Why this matters for Veerle's study

Sleep periods must be **excluded** from the physical activity analysis. Without sleep detection, nighttime stillness would be counted as sedentary behavior during waking hours, inflating SB and distorting the LPA/MVPA picture.

### Python porting implications

Requires `anglez` time series (computed from raw data in Part 1). The SIB detection itself is a sliding window algorithm — conceptually simple, but depends on having accurate angle data.

---

## Part 4: Sleep period detection

### What it does

Part 4 converts the candidate SIBs from Part 3 into actual sleep onset and wake-up times. It works in two steps:

1. **Guider detection**: Identifies the approximate time window where sleep is expected. Options:
   - **Algorithmic** (default for wrist-worn): The HDCZA algorithm detects the sleep window from the data itself, or the L5 method finds the least-active 5-hour period
   - **Sleep log**: A diary filled in by participants indicating when they went to bed / woke up

2. **Overlap assessment**: SIBs that overlap with the guider window are labeled as sleep. The start of the first overlapping SIB = sleep onset; end of the last = wake-up.

**Source**: [GGIR Chapter 10 — Sleep Analysis](https://wadpac.github.io/GGIR/articles/chapter10_SleepAnalysis.html)

### For Veerle's study

Since participants are children in a school study, a sleep log is unlikely. The pipeline will need the algorithmic approach. The HDCZA algorithm is GGIR's default for wrist-worn devices and is designed to work without external input.

### Python porting implications

The HDCZA algorithm is the most complex component here. It combines arm angle distribution analysis with a heuristic time window search. If you want a simpler starting point, the L5 method (least-active 5 hours in a 24-hour period) is a reasonable approximation that's much easier to implement.

---

## Part 5: Time-use analysis (the payoff)

### What it does

Part 5 is the integration layer. It combines:
- The epoch-level ENMO time series (Part 1)
- The non-wear and validity information (Part 2)
- The SIB detection (Part 3)
- The sleep period labels (Part 4)

...into a fully classified time series where every epoch of every valid day is labeled with both a sleep/wake state and a physical activity intensity level. From this, it produces the final per-day and per-person summaries.

### Key outputs

- Minutes per day in SB, LPA, and MVPA during **waking hours only**
- Average acceleration per behavioural category
- Bout detection: sustained periods of MVPA vs sporadic bursts
- **Day-segment analysis**: activity summaries for user-defined time windows

> **⚠️ VEERLE'S STUDY — DAY SEGMENTS**: The school schedules from `Info_metingen.docx` are the key metadata here. Part 5 can segment the day into custom windows (e.g., "school hours", "recess", "after school") and report activity separately for each. This is likely central to the research question: comparing physical activity during school time vs free time, or during lessons vs breaks.
>
> The school schedule metadata is **incomplete** — School 3 has no per-class timetable yet, and School 4 is entirely blank. These need to be resolved before day-segment analysis can run for those schools.

**Source**: [GGIR Chapter 12 — Time-Use Analysis](https://wadpac.github.io/GGIR/articles/chapter12_TimeUseAnalysis.html) and [Day-segment analyses tutorial](https://wadpac.github.io/GGIR/articles/TutorialDaySegmentAnalyses.html)

### Python porting implications

Mostly aggregation and joining logic once the classified time series exists. The bout detection algorithm requires a configurable rolling window with tolerance for brief interruptions (e.g., "80% of a 10-minute window must be MVPA"). The day-segment analysis is time-window filtering + groupby aggregation — natural pandas territory.

---

## Part 6: Cross-recording analyses

Facilitates circadian rhythm analysis (cosinor fitting, inter-daily stability, intra-daily variability) and household co-analysis (comparing activity patterns between household members).

**Not needed for Veerle's current study**. Can be deferred entirely.

**Source**: [GGIR Chapter 13 — Circadian Rhythm Analysis](https://wadpac.github.io/GGIR/articles/chapter13_CircadianRhythm.html)

---

## Summary: What to port, in priority order

### Tier 1 — Must have (core pipeline)

| Component | GGIR Part | Complexity | Notes |
|-----------|-----------|------------|-------|
| ENMO computation | Part 1 | Low | From raw data or from SVMgs column in CSV |
| Epoch aggregation | Part 1 | Low | Configurable window size (1s for this study) |
| Clipping detection | Part 2 | Low | Fraction of samples at ±8g |
| Non-wear detection | Part 2 | Medium | Rolling window std dev + range check |
| Cut-point classification | Part 2 | Low | Threshold comparisons (need exact values from Veerle) |
| Day validity | Part 2 | Low | ≥9h wear, ≥4 valid days incl. 1 weekend |
| Per-day summaries | Part 5 | Low | Aggregation of classified epochs |
| Day-segment analysis | Part 5 | Low | Filter by school schedule time windows |

### Tier 2 — Should have (required for correct analysis)

| Component | GGIR Part | Complexity | Notes |
|-----------|-----------|------------|-------|
| Autocalibration | Part 1 | High | Sphere fitting; skip if CSV-only approach is acceptable |
| Arm angle (anglez) | Part 1 | Medium | Needed for sleep detection |
| SIB detection | Part 3 | Medium | Sliding window on anglez |
| Sleep period detection | Part 4 | High | HDCZA algorithm or simplified L5 approach |
| Bout detection | Part 5 | Medium | Sustained MVPA with configurable tolerance |

### Tier 3 — Can defer

| Component | GGIR Part | Notes |
|-----------|-----------|-------|
| Circadian rhythm analysis | Part 6 | Outside current scope |
| Household co-analysis | Part 6 | Outside current scope |
| Multiple metric support | Part 1 | MAD, BFen, etc. — only ENMO needed for now |

---

## Checklist: Open questions for Veerle

Based on this pipeline analysis, the following items need clarification before implementation:

- [ ] **Cut-point values**: What are the exact ENMO thresholds for SB/LPA/MVPA? (Referenced as citation 7 in protocol — child-specific, wrist-worn GENEActiv)
- [ ] **CSV or .bin input?** Will the pipeline receive pre-converted CSV files, or raw .bin files? This determines whether autocalibration is possible/needed.
- [ ] **Sleep detection approach**: Is a sleep log available, or should we use algorithmic detection only?
- [ ] **Missing school schedules**: School 3 per-class timetables and School 4 hours are missing from `Info_metingen.docx`
- [ ] **Day-segment definitions**: What time windows should activity be segmented into? (e.g., "school hours", "morning recess", "lunch break", "after school")
- [ ] **GGIR configuration**: Does Veerle have a `config.csv` file from her GGIR runs that we could use as a reference for all parameter settings?

---

## Sources

- [GGIR Chapter 1 — What is GGIR](https://wadpac.github.io/GGIR/articles/chapter1_WhatIsGGIR.html)
- [GGIR Chapter 2 — The Pipeline](https://wadpac.github.io/GGIR/articles/chapter2_Pipeline.html)
- [GGIR Chapter 3 — Data Quality Assurance](https://wadpac.github.io/GGIR/articles/chapter3_QualityAssessment.html)
- [GGIR Chapter 4 — From Raw Data to Acceleration Metrics](https://wadpac.github.io/GGIR/articles/chapter4_AccMetrics.html)
- [GGIR Chapter 5 — Accounting for Study Protocol](https://wadpac.github.io/GGIR/articles/chapter5_StudyProtocol.html)
- [GGIR Chapter 6 — How GGIR Deals with Invalid Data](https://wadpac.github.io/GGIR/articles/chapter6_DataImputation.html)
- [GGIR Chapter 8 — Sleep Fundamentals: SIB Detection](https://wadpac.github.io/GGIR/articles/chapter8_SleepFundamentalsSibs.html)
- [GGIR Chapter 9 — Sleep Fundamentals: Guiders](https://wadpac.github.io/GGIR/articles/chapter9_SleepFundamentalsGuiders.html)
- [GGIR Chapter 10 — Sleep Analysis](https://wadpac.github.io/GGIR/articles/chapter10_SleepAnalysis.html)
- [GGIR Chapter 11 — Cut-points](https://wadpac.github.io/GGIR/articles/chapter11_DescribingDataCutPoints.html)
- [GGIR Chapter 12 — Time-Use Analysis](https://wadpac.github.io/GGIR/articles/chapter12_TimeUseAnalysis.html)
- [GGIR Chapter 13 — Circadian Rhythm Analysis](https://wadpac.github.io/GGIR/articles/chapter13_CircadianRhythm.html)
- [Published cut-points and how to use them](https://wadpac.github.io/GGIR/articles/CutPoints.html)
- [Day-segment analyses tutorial](https://wadpac.github.io/GGIR/articles/TutorialDaySegmentAnalyses.html)
- [GGIR Parameters reference](https://wadpac.github.io/GGIR/articles/GGIRParameters.html)
- [GGIR Output reference](https://wadpac.github.io/GGIR/articles/GGIRoutput.html)
- Study protocol excerpt: Email from Veerle Van Oeckel (UGent), 23 March 2026

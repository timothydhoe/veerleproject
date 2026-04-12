# Research Questions

> The specific questions the SchoolMoves pipeline must be able to answer. Each question is linked to the pipeline module that produces the output.

---

## Primary research questions

### RQ1 — Activity totals by context

**Question:** How many minutes per day does each pupil spend in sedentary, light, moderate, and vigorous physical activity — broken down by in-class time, recess, lunch, after school, and weekend?

**Why it matters:** The core outcome of the study. Separating school-time from non-school-time activity reveals whether the school environment is driving the observed levels.

**Pipeline module:** `R/analysis/activity_totals.R`

**Output:** Per-pupil, per-day table with columns:
`pupil_id | date | context | sedentary_min | light_min | moderate_min | vigorous_min`

---

### RQ2 — Sedentary bouts

**Question:** How many bouts of ≥30 consecutive minutes of sedentary behaviour occur per day, and in which context (class vs. other)?

**Why it matters:** Prolonged unbroken sitting is independently associated with health risk beyond total sedentary time. The 30-minute threshold is the study-specific definition of a "long" sedentary bout.

**Pipeline module:** `R/analysis/sedentary_bouts.R`

**Output:** Per-pupil, per-day table:
`pupil_id | date | context | n_bouts_30min | total_bout_min`

---

### RQ3 — Sleep patterns

**Question:** How long do pupils sleep, and what proportion of the night has valid accelerometer data?

**Why it matters:** Sleep is a secondary outcome of the study. GGIR's sleep detection allows sleep duration to be estimated without a sleep diary.

**Pipeline module:** `R/analysis/sleep_analysis.R`

**Output:** Per-pupil, per-night table:
`pupil_id | date | sleep_onset | sleep_offset | sleep_duration_h | pct_night_valid`

---

### RQ4 — School-hour correlations

**Question:** Is there a correlation between the duration of lesson blocks (which varies between schools) and the amount of in-class sedentary time or total activity?

**Why it matters:** If longer unbroken lesson periods are associated with more sedentary behaviour, this would support structural changes to the school day as part of the intervention.

**Pipeline module:** `R/analysis/school_correlations.R`

**Notes:** Requires the school-schedule config to be joined to the pupil data. Lesson duration is a school-level variable, not a pupil-level variable.

---

### RQ5 — Attendance prediction

**Question:** On which days was a pupil likely absent from school, based on breaks in their normal morning activity pattern?

**Why it matters:** Absence days must be identified and excluded (or annotated) before computing school-context activity totals. Manual review of 400 pupils × 7 days is not feasible; an automated first pass reduces researcher workload significantly.

**Pipeline module:** `python/analysis/attendance_prediction.py`

**Logic:**
1. For each pupil, compute the typical arrival window (time of first sustained activity burst above 50 mg on school days)
2. Flag days where no such burst occurs within the expected window as `probable_absent`
3. Surface these flags in the UI for manual confirmation

**Output:** Per-pupil, per-day flag:
`pupil_id | date | predicted_present | confidence | researcher_override | final_status`

**Important:** This is a decision-support tool. The researcher has the final say via the UI override.

---

### RQ6 — Pre vs. post intervention comparison

**Question:** Did physical activity levels, sedentary time, or sleep change between meting 1 (before intervention) and meting 2 (after intervention)?

**Why it matters:** This is the primary evaluation of the intervention's effectiveness.

**Pipeline module:** Comparison analysis built on top of RQ1–RQ4 outputs

**Notes:** Requires that the same pupil has valid data in both measurement periods. Only pupils who pass validity criteria in both periods are included in the comparison.

---

## Secondary / exploratory questions

These are lower-priority but the pipeline should not preclude answering them:

- Are there differences in activity levels between schools (after controlling for school-day structure)?
- Is there a relationship between morning commute activity and in-school sedentary time?
- Do pupils who sleep less show different activity patterns?
- Are there day-of-week effects in activity or sedentary time?

---

## Questions the pipeline does NOT answer

These are out of scope for this pipeline but noted here to avoid scope creep:

- Individual-level intervention recommendations (the study is observational/quasi-experimental, not prescriptive)
- Dietary data (not collected)
- Academic performance correlation (no data linkage)
- Long-term follow-up beyond the two measurement periods

---

## Output format requirements

All analysis outputs must be:
- Exportable as CSV from the UI
- Reproducible (same input → same output, with a fixed GGIR version and R/Python versions pinned)
- Accompanied by a validity note indicating how many pupils were excluded from each analysis and why

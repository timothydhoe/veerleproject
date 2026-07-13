# School Information

> All school schedules, measurement windows, and contextual labelling rules used by the pipeline.

---

## Overview

| School | Pupils (approx.) | Meting 1 window | Meting 2 window |
|---|---|---|---|
| School 1 | 70 | 23/2/2026 – 2/3/2026 (until 13:00) | 1/6/2026 – 8/6/2026 (until 13:00) |
| School 2 | 80 | 3/3/2026 – 10/3/2026 (until 15:35) | 26/5/2026 – 2/6/2026 (until 15:35) |
| School 3 | 60 | 19/1/2026 – 26/1/2026 (until 10:05) | 20/4/2026 – 27/4/2026 (until 10:05) |
| School 4 | 65 | 5/2/2026 – 12/2/2026 (until 16:35) | 21/5/2026 – 28/5/2026 (until 16:35) |
| School 5 | 55 | 9/1/2026 – 16/1/2026 (until 10:25) | 11/3/2026 – 18/3/2026 (until 09:20) |
| School 6 | 70 | 2/3/2026 – 9/3/2026 (until 10:10) | 4/5/2026 – 11/5/2026 (until 10:10) |
| **Total** | **400** | | |

---

## Detailed school schedules

### School 1

**School hours**

| Day | Start | End |
|---|---|---|
| Monday | 08:25 | 15:40 |
| Tuesday | 08:25 | 16:30 |
| Wednesday | 08:25 | 11:55 |
| Thursday | 08:25 | 15:40 |
| Friday | 08:25 | 15:40 |

**Breaks**

| Day | Break 1 | Lunch | Break 2 |
|---|---|---|---|
| Mon / Tue / Thu / Fri | 10:05–10:20 | 12:00–13:00 | 14:40–14:50 |
| Wednesday | 10:05–10:15 | — | — |

---

### School 2

**School hours**

| Day | Start | End |
|---|---|---|
| Monday | 08:25 | 15:35 |
| Tuesday | 08:25 | 15:35 |
| Wednesday | 08:25 | 12:00 |
| Thursday | 08:25 | 15:35 |
| Friday | 08:25 | 15:35 |

**Breaks**

| Day | Break 1 | Lunch | Break 2 |
|---|---|---|---|
| Mon / Tue / Thu / Fri | 10:05–10:20 | 12:00–12:50 | 14:30–14:45 |
| Wednesday | 10:05–10:20 | — | — |

---

### School 3

> **Update:** confirmed schedule now in `config.yaml` (`fallback: false`) — this
> was previously a generic fallback; that note is outdated.

**School hours**

| Day | Start | End |
|---|---|---|
| Monday | 08:25 | 15:35 |
| Tuesday | 08:25 | 15:35 |
| Wednesday | 08:25 | 12:00 |
| Thursday | 08:25 | 15:35 |
| Friday | 08:25 | 15:35 |

**Breaks**

| Day | Break 1 | Lunch | Break 2 |
|---|---|---|---|
| Mon / Tue / Thu / Fri | 10:05–10:20 | 12:00–12:50 | 14:30–14:45 |
| Wednesday | 10:05–10:20 | — | — |

**Per-class overrides:** 2nd-year classes (2Aa, 2Ab, 2Ba, 2Bb) have an 8th
lesson period on certain days, ending 16:25 instead of 15:35 — see
`config.yaml`'s `class_overrides` for the exact pupils/days (sourced from an
email from Veerle + `Info_metingen.docx`).

---

### School 4

> **Update:** confirmed schedule now in `config.yaml` (`fallback: false`) —
> the Wednesday end time is still an estimate (see note below), but Mon/Tue/
> Thu/Fri is confirmed.

**School hours**

| Day | Start | End |
|---|---|---|
| Monday | 08:40 | 16:35 |
| Tuesday | 08:40 | 16:35 |
| Wednesday | 08:40 | 12:15 (estimated — 4th period end; source timetable was image-only) |
| Thursday | 08:40 | 16:35 |
| Friday | 08:40 | 16:35 |

**Breaks**

| Day | Break | Lunch |
|---|---|---|
| Mon / Tue / Thu / Fri | 10:20–10:35 | 12:15–13:15 |
| Wednesday | 10:20–10:35 | — |

---

### School 5

**Lesson schedule (period-based)**

| Period | Start | End |
|---|---|---|
| 1st | 08:30 | 09:20 |
| 2nd | 09:20 | 10:10 |
| Break | 10:10 | 10:25 |
| 3rd | 10:25 | 11:15 |
| 4th | 11:15 | 12:05 |
| Lunch | 12:05 | 13:10 |
| 5th | 13:10 | 14:00 |
| 6th | 14:00 | 14:50 |
| Break | 14:50 | 15:05 |
| 7th | 15:05 | 15:55 |

> Wednesday schedule not separately specified — assume ends after 4th period (12:05).

---

### School 6

**School hours**

| Day | Start | End |
|---|---|---|
| Mon / Tue / Thu / Fri | 08:30 | 15:25 |
| Wednesday | 08:30 | 12:00 |

**Breaks**

| Day | Break 1 | Lunch |
|---|---|---|
| Mon / Tue / Thu / Fri | 11:00–11:15 | 12:55–13:45 |
| Wednesday | 10:10–10:20 | — |

---

## Context labelling rules

The pipeline assigns a `context` label to every 1-second epoch based on the school ID and the timestamp. The logic is:

```
IF day == Saturday OR day == Sunday
  → context = "weekend"
ELSE IF time < school_start - 30min
  → context = "before_school"
ELSE IF time >= school_start AND time < first_break_start
  → context = "in_class"
ELSE IF time >= first_break_start AND time < first_break_end
  → context = "recess"
ELSE IF time >= first_break_end AND time < lunch_start
  → context = "in_class"
ELSE IF time >= lunch_start AND time < lunch_end
  → context = "lunch"
ELSE IF time >= lunch_end AND time < second_break_start (if exists)
  → context = "in_class"
ELSE IF time >= second_break_start AND time < second_break_end (if exists)
  → context = "recess"
ELSE IF time >= second_break_end AND time < school_end
  → context = "in_class"
ELSE IF time >= school_end
  → context = "after_school"
ELSE
  → context = "unknown"
```

These rules are stored in `config/school_schedules.yaml` and loaded at runtime. Schools with missing timetable data use the fallback schedule and are flagged with `schedule_source = "fallback"` in the output.

---

## Pupil ID convention

File names use a 4-digit code:
- First digit: school ID (1–6)
- Remaining 3 digits: pupil ID within school (001–...)

Examples: `1001.csv` = pupil 001 from School 1, `2063.csv` = pupil 063 from School 2.

Measurement period 1 files are stored in `meting_1/`, period 2 in `meting_2/`.

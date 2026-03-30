# Phase 1 — Data Foundation

> Generate a realistic dummy dataset to develop and test the pipeline against, before the full 400-pupil real dataset is available.

---

## Goal

Produce a set of synthetic GENEActiv-format CSV files that:
- Match the exact file structure of real GENEActiv exports
- Reflect realistic activity patterns per time of day, school schedule, and day of week
- Cover all 6 schools with correct measurement windows
- Include ~10% of pupils who intentionally fail validity criteria (for testing the filter logic)
- Are configurable and reproducible

---

## Why dummy data first

The real dataset exceeds 31 MB per batch and cannot be shared for pipeline development. Building the pipeline against dummy data allows:
- Full end-to-end testing before a single real file is processed
- Controlled edge-case testing (non-wear periods, absent days, short recordings)
- Rapid iteration without waiting for data access approvals

---

## Dummy data generator — specification

### Script location
`python/pipeline/generate_dummy_data.py`

### Arguments

| Argument | Default | Description |
|---|---|---|
| `--n_pupils` | 20 | Number of pupils to generate (use 400 for full run) |
| `--days` | 7 | Days of recording per pupil |
| `--hz` | 1 | Output frequency in Hz (1 = 1-second epochs) |
| `--seed` | 42 | Random seed for reproducibility |
| `--output_dir` | `data/dummy/` | Root output directory |

### Output structure

```
data/dummy/
├── meting_1/
│   ├── 1001.csv
│   ├── 1002.csv
│   └── ...
├── meting_2/
│   ├── 1001.csv
│   └── ...
└── summary.csv
```

### Pupil distribution

| School | Pupils | ID range |
|---|---|---|
| School 1 | 70 | 1001–1070 |
| School 2 | 80 | 2001–2080 |
| School 3 | 60 | 3001–3060 |
| School 4 | 65 | 4001–4065 |
| School 5 | 55 | 5001–5055 |
| School 6 | 70 | 6001–6070 |

---

## Activity simulation logic

### Time-of-day activity profiles

Each 1-second epoch gets an ENMO value drawn from a distribution appropriate for the time and context:

| Time / Context | ENMO distribution (mg) | Notes |
|---|---|---|
| 00:00–06:30 | Normal(5, 2), clipped to [0, 15] | Sleep |
| 06:30–08:00 | Normal(80, 40) | Morning routine |
| In-class (lesson) | Normal(25, 15), clipped to [0, 100] | Mostly sedentary |
| Recess / break | Normal(180, 80) | Mixed activity |
| Lunch | Normal(100, 60) | Mixed eating + play |
| After school (15:30–19:00) | Normal(120, 70) | Variable activity |
| Evening (19:00–21:00) | Normal(20, 10) | Sedentary |
| Winding down (21:00–sleep) | Normal(10, 5) | Falling asleep |
| Weekend (daytime) | Normal(150, 90) | More variable |

Per-pupil variation: each pupil gets a fixed `activity_factor` drawn from Normal(1.0, 0.2) that scales their ENMO values, creating stable inter-individual differences across the week.

### x/y/z from ENMO

Work backwards from ENMO to plausible x/y/z values:
1. Start from a resting position (z ≈ −1g, x ≈ 0, y ≈ 0) during sleep
2. Add random orientation variation during wake time
3. Scale the noise amplitude so that `sqrt(x²+y²+z²) − 1 ≈ ENMO/1000`

### Non-wear simulation

Each pupil has 1–3 non-wear events of 60–180 minutes randomly placed during waking hours across the 7-day window. During non-wear: std of all axes < 13 mg, range < 50 mg.

### Invalid pupils (for testing)

~10% of generated pupils are configured to fail validity:
- Short recordings (only 3–4 days of data)
- Excessive non-wear (>80% of one or more days)
- Flagged as `validity_status = "FAIL"` in `summary.csv`

---

## Summary output (`summary.csv`)

| Column | Description |
|---|---|
| pupil_id | 4-digit ID |
| school_id | 1–6 |
| measurement_period | `meting_1` or `meting_2` |
| n_days | Days of generated data |
| pct_valid_days_sedentary | % of days meeting 9h valid waking threshold |
| pct_valid_nights_sleep | % of nights meeting 50% sleep threshold |
| meets_sedentary_validity | TRUE/FALSE |
| meets_sleep_validity | TRUE/FALSE |
| activity_factor | Per-pupil scaling factor used |

---

## Acceptance criteria

Before moving to Phase 2, verify:

- [ ] Files open without errors in R (`read.csv`, `data.table::fread`)
- [ ] GGIR can ingest the generated CSV files (test with 2–3 dummy pupils)
- [ ] Activity patterns look plausible when plotted (school hours show lower ENMO than recess)
- [ ] Non-wear periods are detected by GGIR's algorithm
- [ ] ~10% of pupils are correctly flagged as failing validity

---

## Dependencies

```
Python:
  - numpy >= 1.24
  - pandas >= 2.0
  - pyyaml >= 6.0
```

Install: `pip install -r requirements.txt`

# Old Pipeline Reference

Analysis of `r/_examples/` — Veerle's previous study scripts.

---

## Context

The files in `r/_examples/` are from a **previous study**, not the current SchoolMove project. The key difference:

| | Old study | Current project |
|---|---|---|
| Device | Axivity (thigh-worn) | GENEActiv (wrist-worn) |
| Raw format | `.cwa` binary | `.csv` pre-converted |
| Activity classification | Random Forest (posture type) | GGIR cut-points (intensity) |
| Metingen | NUL, PRE, POST (3 waves) | Meting 1, Meting 2 (2 waves) |

---

## File-by-file breakdown

### `1_thigh_PA_type/resample_boundaries_calibration.R`
Reads raw Axivity `.cwa` files, applies sphere-fitting autocalibration via `GGIR::g.calibrate()`, saves calibrated data as `.Rds`.

**Not applicable** — we have GENEActiv CSVs, autocalibration is not possible from pre-converted data.

---

### `1_thigh_PA_type/generate_activity_features.R`
For each 5-second window at 100 Hz, extracts features per axis:
- FFT dominant frequency and power
- Mean, SD, quantiles, min/max of filtered signal
- Orientation angles (roll, pitch, yaw) — thigh-specific geometry
- Kurtosis, skewness, cross-axis correlations

These features feed the Random Forest classifier.

**Not applicable** — features are thigh-placement-specific and tied to the RF model.

---

### `1_thigh_PA_type/predict_AT.R`
Applies the saved RF model (`model.rf.thigh.rds`) to classify each 5-second epoch as: Sitting / Lying / Standing / Walking / Running / Cycling.

**Not applicable** — model was trained on thigh data; incompatible with wrist placement.

---

### `1_thigh_PA_type/enmo_nonwear.R`
Reads GGIR Part 1 intermediate `.RData` files:
- `M[['metashort']]` → per-second ENMO
- `M[['metalong']]` → 15-minute non-wear scores

Aggregates both to minute level per participant.

**Partially applicable** — shows the correct pattern for reading GGIR internals if needed. In practice, GGIR Part 2/5 output CSVs should be sufficient.

---

### `1_thigh_PA_type/rbind_5s.R`
Combines per-participant files into one dataset.

**Key detail to keep:** observation days are defined as **3am–3am**, not midnight. This handles daylight saving time gracefully and should be carried over to the current project.

---

### `1_general.R` — the main script (~1000 lines)

| Section | Lines | What it does | Reusability |
|---|---|---|---|
| School metadata loading | ~140–200 | Reads observation start/stop per school per meting from SPSS | Pattern reusable; data will come from `config.yaml` |
| School schedule annotation | ~200–290 | Flags each row: `during_observation`, `during_school_hours`, `during_class_1`–`7` | **Keep — core domain logic** |
| Absence annotation | ~290–310 | Flags rows where the student was absent | Not yet in scope; data source TBD |
| Sleep annotation | ~310–330 | Overrides activity type with "Sleeping" from external file | GGIR Part 4 handles this now |
| Non-wear merge | ~350–390 | Combines GGIR-detected + self-reported non-wear into `nonwear_unique` | Pattern reusable; self-reported non-wear is TBD |
| Location context flags | ~395–415 | Derives `at_school_activity`, `in_class_activity`, `out_class_activity`, `out_school_activity` | **Keep — core output logic** |
| Sitting bout detection | ~420–500 | Detects bouts of Sitting/Lying, tracks duration per bout at 5-sec resolution | GGIR Part 5 does this natively; may be redundant |
| Bout classification | ~500–760 | Bins bouts by duration (0–1, 1–4, 5–9, 10–19, 20–29, 30+ min) × location context | Keep if bout analysis is a research deliverable |
| Daily summaries | ~760–980 | Aggregates to day level across all contexts | **Keep — this is the core output** |
| Export | ~985–1010 | Writes `.Rds` + `.sav` (SPSS) + `.csv` | **Keep — Veerle uses SPSS downstream** |

---

## What to carry over

### Keep

- **School schedule annotation** — `during_observation`, `during_school_hours`, `during_class_X` flag logic. Bespoke domain logic that GGIR does not provide. Needs to read from `config.yaml` instead of SPSS files.
- **Location-based daily summaries** — breakdown by total / at_school / in_class / out_class / elsewhere. This is the core analytical deliverable.
- **3am–3am observation day** convention.
- **Multi-format export** — `.Rds` + `.sav` + `.csv`.
- **Sedentary bout bins** (0–1, 1–4, 5–9, 10–19, 20–29, 30+ min) if bout analysis remains a research question. GGIR Part 5 provides some of this but not broken down by school context.

### Skip

- Everything in `1_thigh_PA_type/` — wrong device, wrong placement.
- Self-reported non-wear and absence lookups — not yet in scope.
- Sleep override from external file — GGIR Part 4 handles this.

---

## Role of `x_std`, `y_std`, `z_std` in the CSV

Each row in the GENEActiv CSV is a **1-second epoch** summarising 100 raw 100 Hz samples. Instead of storing all 100 samples, the device stores the mean (→ `x`, `y`, `z`) and the within-epoch spread (→ `x_std`, `y_std`, `z_std`).

**Primary use: non-wear detection.**
When the device is stationary (lying on a table), all three axes are nearly constant and the SDs approach zero. GGIR's Part 1 non-wear algorithm scans rolling windows (typically 15 or 60 minutes) and flags a window as non-wear when the SD across all axes stays below a threshold (~13 mg). The `nonwearscore` in GGIR's output is derived from this.

This feeds directly into validity criteria: a day is only valid if wear time ≥ 16 hours.

**Not a research variable** — Veerle doesn't study the SD itself. But it is a data quality gatekeeper: without reliable non-wear detection, valid days can't be determined and school-context summaries will be contaminated. GGIR reads the SD columns from the CSV and handles non-wear internally in Part 1; no manual handling needed.

**Note on autocalibration:** because we're working from pre-converted CSV (not raw `.bin`), GGIR cannot perform sphere-fitting autocalibration. The SD values identify stationary periods that would normally be used for calibration, but this step is skipped. ENMO values will therefore be based on uncalibrated data. Accepted trade-off for this phase — revisit if Veerle provides `.bin` files.

---

## Open questions (as of 2026-04-01)

1. **Meting structure** — Old study had 3 metingen (NUL, PRE, POST). Current project mentions meting 1 and meting 2 only. Confirm.
2. **Absence tracking** — Will student absence data be available and included in the output?
3. **Self-reported non-wear** — Will students report non-wear periods? If yes, needs a data source.
4. **Activity type vs intensity** — Old pipeline classified posture type (Sitting/Standing/Walking/etc.) via RF. Current approach gives intensity bands (SB/LPA/MVPA) via ENMO cut-points. Is intensity sufficient, or does Veerle need posture classification too?
5. **SPSS output** — Confirm `.sav` is still a required output format.

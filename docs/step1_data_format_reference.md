# Step 1 — GENEActiv CSV data format reference

## Overview

This document describes the structure of GENEActiv accelerometer CSV files as used in
the UGent school physical activity study. The CSV files are 1-second epoch exports
converted from raw `.bin` files using the GENEActiv PC software.

**Study context**: Children across 6 Belgian schools wear GENEActiv wrist accelerometers
for ~7 days. Each child has two measurement periods. The goal is to classify activity
into sedentary behavior (SB), light physical activity (LPA), and moderate-to-vigorous
physical activity (MVPA).

---

## File naming convention

Each accelerometer data file is named with a **4-digit code**:

- **1st digit** (1–6): school number
- **Digits 2–4** (001–…): pupil ID within that school

Example: `2063` → school 2, pupil 063.

Files are organized into two folders: one per measurement period (`meting 1` and
`meting 2`). A given pupil has one file per measurement, with the same filename in each
folder.

**Source**: Email from Veerle Van Oeckel (UGent), 23 March 2026.

---

## File structure

The CSV has two distinct sections:

### Header block (rows 1–100)

The first 100 rows contain key-value metadata about the device, recording configuration,
subject, and sensor specifications. This is **not** tabular CSV — each row is a
label-value pair. Key fields:

| Row(s) | Field                 | Example value             | Notes                                            |
|--------|-----------------------|---------------------------|--------------------------------------------------|
| 1      | Device Type           | `GENEActiv`               |                                                  |
| 2      | Device Model          | `1.1`                     | Hardware version; relevant for calibration       |
| 3      | Serial Code           | `068006`                  | Unique device identifier                         |
| 11     | Measurement Frequency | `100 Hz`                  | Samples per second (Zenodo reference uses 60 Hz) |
| 12     | Start Time            | `2026-02-05 12:22:19:500` | Recording start (note colon before ms)           |
| 14     | Device Location Code  | `left wrist`              | Cut-points are location-specific                 |
| 15     | Time Zone             | `GMT +01:00`              | Belgian time zone (CET)                          |
| 21     | Subject Code          | `4001`                    | School 4, pupil 001                              |
| 36     | Config Time           | `2026-02-04 14:38:35:114` | When device was configured                       |
| 39     | Extract Time          | `2026-02-17 11:50:43:998` | When data was extracted                          |
| 51–80  | Sensor specifications | (see below)               | 6 sensor blocks                                  |

**Sensor specifications** (rows 51–80, six sensor blocks):

| Sensor                    | Range     | Resolution | Units |
|---------------------------|-----------|------------|-------|
| MEMS accelerometer x-axis | −8 to 8   | 0.0039     | g     |
| MEMS accelerometer y-axis | −8 to 8   | 0.0039     | g     |
| MEMS accelerometer z-axis | −8 to 8   | 0.0039     | g     |
| Lux Photodiode 400–1100nm | 0 to 5000 | 5          | lux   |
| User button event marker  | 1 or 0    | —          | —     |
| Linear active thermistor  | 0 to 70   | 0.1        | °C    |

### Data rows (from row 101)

Each row represents a **1-second epoch** — an aggregation of 100 raw samples (at 100
Hz). There are **12 columns**, comma-separated, with no header row.

| Column | Name      | Type     | Unit | Description                                                                    |
|--------|-----------|----------|------|--------------------------------------------------------------------------------|
| 1      | timestamp | datetime | —    | Epoch start time. Format: `YYYY-MM-DD HH:MM:SS:mmm` (colon before ms, not dot) |
| 2      | xm        | float    | g    | Mean x-axis acceleration over 100 samples                                      |
| 3      | ym        | float    | g    | Mean y-axis acceleration over 100 samples                                      |
| 4      | zm        | float    | g    | Mean z-axis acceleration over 100 samples                                      |
| 5      | lightm    | int      | lux  | Mean ambient light over 100 samples                                            |
| 6      | button    | int      | 0/1  | Event marker (1 = button pressed during epoch)                                 |
| 7      | tempm     | float    | °C   | Mean temperature over 100 samples                                              |
| 8      | **SVMgs** | float    | g    | **Sum** of per-sample ENMO across the epoch (see below)                        |
| 9      | sdx       | float    | g    | Standard deviation of x-axis within the epoch (see note below)                 |
| 10     | sdy       | float    | g    | Standard deviation of y-axis within the epoch (see note below)                 |
| 11     | sdz       | float    | g    | Standard deviation of z-axis within the epoch (see note below)                 |
| 12     | peak lux  | int      | lux  | Maximum light reading within the epoch                                         |

**Note on sdx / sdy / sdz (columns 9–11):** These are the within-epoch standard
deviations computed by the GENEActiv firmware from the 100 raw samples in each second.
They represent intra-second variability — a proxy for how much the wrist was moving
*within* that second, beyond what the mean x/y/z can capture.

In the current pipeline, GGIR reads the data via `read.myacc.csv` and only maps columns
1 (time), 2–4 (x/y/z means), and 7 (temperature). **Columns 9–11 are not mapped and are
ignored by GGIR.** GGIR computes its own variance-based metrics (including non-wear
detection) from the x/y/z values it reads, not from pre-computed standard deviations.

In the dummy data, sdx/sdy/sdz are approximated as `ENMO_target × 0.15 + 0.005` — a
rough proportional estimate rather than true within-second variance. This is intentional:
since the dummy generator works at 1 Hz directly (no 100 raw samples to aggregate), there
are no real intra-second samples to compute std from. The approximation preserves the
correct column layout of the GENEActiv format without affecting pipeline output.

**Example data rows** (from the fictional example):

```csv
2026-02-05 12:22:24:000,0.7198,0.2603,-0.5787,41,0,23.1,5.88,0.1425,0.1551,0.0968,70
2026-02-05 12:22:25:000,0.5624,0.3652,-0.6915,65,0,22.1,6.54,0.1745,0.1326,0.1435,247
2026-02-05 12:22:26:000,0.1966,0.2316,-0.7956,159,0,22.1,14.79,0.3565,0.4266,0.1896,247
```

---

## Key concepts

### The g unit

`g` is the standard acceleration due to gravity ≈ 9.81 m/s². It is the conventional unit
for accelerometer data. A stationary sensor reads approximately `1g` total magnitude (
from gravity alone). The ±8g device range means it can measure accelerations up to 8×
gravitational acceleration; readings that exceed this **clip** and data is lost.

### Epoch

A fixed-duration time window over which raw high-frequency samples are aggregated into
summary statistics. In this dataset, epochs are 1 second long, each containing 100 raw
samples (at 100 Hz). GGIR's default is 5-second epochs, but Veerle's protocol uses
1-second epochs.

### ENMO (Euclidean Norm Minus One)

For a single raw sample with acceleration (x, y, z):

```
ENMO = max(0, √(x² + y² + z²) − 1)
```

- `√(x² + y² + z²)` is the Euclidean norm (total acceleration magnitude)
- `− 1` subtracts gravity, so a motionless sensor reads ~0 instead of ~1g
- `max(0, …)` clamps negative values (from calibration imprecision when still)

ENMO is the standard omnidirectional measure of body acceleration used in physical
activity research.

### SVMgs (column 8) — relationship to ENMO

SVMgs stands for "Sum of Vector Magnitudes minus gravity, summed." It is computed by the
GENEActiv software as:

```
SVMgs = Σᵢ₌₁ⁿ max(0, √(xᵢ² + yᵢ² + zᵢ²) − 1)
```

where `n` = number of raw samples in the epoch (100 at 100 Hz).

**To get mean ENMO per epoch**: `mean_ENMO = SVMgs / n`

Example from data row 1: `5.88 / 100 = 0.0588g` mean ENMO.

### Why GGIR recomputes ENMO from raw data

GGIR does **not** use the pre-computed SVMgs from the CSV. Instead, it reads the raw
`.bin` files and recomputes ENMO after applying its own **autocalibration** procedure.
Reasons:

1. **Calibration drift**: Factory calibration degrades over time and varies with
   temperature. GGIR identifies stationary periods in the data and uses them to
   re-estimate per-axis offset and scale, correcting systematic errors of a few milli-g
   that affect cut-point classification.

2. **Reproducibility**: By controlling the entire computation from raw data, GGIR
   ensures consistent methodology across studies.

### Why you can't reconstruct ENMO from epoch means

Computing `√(xm² + ym² + zm²) − 1` from the epoch-averaged columns gives a **different
** (and incorrect) result compared to averaging per-sample ENMO. This is due to *
*Jensen's inequality**: the norm of the mean ≤ the mean of the norms, because `√(·)` is
a concave function.

**Demonstration from the data**:

|       | SVM from epoch means | ENMO from means | SVMgs (true sum) | True mean ENMO |
|-------|----------------------|-----------------|------------------|----------------|
| Row 1 | 0.9596               | 0.0000          | 5.88             | 0.0588         |
| Row 2 | 0.9632               | 0.0000          | 6.54             | 0.0654         |
| Row 3 | 0.8516               | 0.0000          | 14.79            | 0.1479         |

The means cancel out within-epoch variation (e.g., arm swinging back and forth), so the
mean-based ENMO appears as zero activity when there's actually substantial movement. The
sd columns (sdx, sdy, sdz) quantify how much information is lost in this averaging.

### Temperature as a quality signal

The temperature column (`tempm`) is useful beyond calibration:

- **Skin contact** ≈ 28–35°C → device is being worn
- **Room temperature** ≈ 18–23°C → device may be off the wrist (non-wear)
- The example values (22–23°C) suggest the device was freshly placed on the wrist and
  hadn't warmed up yet

---

## Column definition differences: Veerle's CSV vs Zenodo CSV

The fictional example CSV (from the GENEActiv PC software) and the Zenodo open dataset
use slightly different column layouts:

| Column | Veerle's CSV export | Zenodo epoch CSV      |
|--------|---------------------|-----------------------|
| 1      | timestamp           | timestamp             |
| 2      | xm                  | xm                    |
| 3      | ym                  | ym                    |
| 4      | zm                  | zm                    |
| 5      | lightm              | lightm                |
| 6      | **button**          | *(not present)*       |
| 7      | tempm               | tempm                 |
| 8      | SVMgs (svmgsum)     | svmgsum               |
| 9      | sdx                 | sdx                   |
| 10     | sdy                 | sdy                   |
| 11     | sdz                 | sdz                   |
| 12     | **peak lux**        | **id** (bin filename) |

The Zenodo format omits `button` and `peak lux`, and appends a participant `id` column
instead.

---

## Pipeline design implication

For your Python pipeline, there are two paths:

| Approach  | Input              | Pro                                                  | Con                                  |
|-----------|--------------------|------------------------------------------------------|--------------------------------------|
| CSV-based | `.csv` epoch files | Simpler; SVMgs is pre-computed                       | No autocalibration; factory cal only |
| Bin-based | `.bin` raw files   | Full GGIR-equivalent processing with autocalibration | More complex; need bin parser        |

If working from CSVs: use `SVMgs / sample_count` as your ENMO estimate. Be aware this
uses factory calibration only.

If matching GGIR exactly: you'll need to parse `.bin` files, implement autocalibration,
and compute ENMO from raw tri-axial data.

---

## Sources

- **Column definitions (Zenodo)
  **: [zenodo.org/records/12682660](https://zenodo.org/records/12682660) — anonymized
  epoch CSV dataset with explicit column documentation
- **GENEActiv hardware manual
  **: [Activinsights instructions for use (PDF)](https://activinsights.com/wp-content/uploads/2022/06/GENEActiv-Instructions-for-Use-v1_31Mar2022.pdf) —
  device specs, CSV format description ("data starts from line 101")
- **GENEActiv software manual
  **: [Activinsights GENEActiv software guide (PDF)](https://activinsights.com/wp-content/uploads/2023/10/GENEActiv-1.2-July-2023-instructions-WC.pdf) —
  bin-to-CSV conversion, epoch computation
- **Zenodo raw data
  **: [zenodo.org/records/11594645](https://zenodo.org/records/11594645) — reference
  GENEActiv `.bin` dataset (restricted) and study description
- **GGIR R package
  **: [wadpac.github.io/GGIR](https://wadpac.github.io/GGIR/index.html) — data
  processing pipeline documentation
- **Study protocol**: Email from Veerle Van Oeckel (UGent), 23 March 2026 — file naming,
  folder structure, processing decisions, validity criteria
- **Measurement schedule**: `Info_metingen.docx` — school-specific measurement dates and
  class hours

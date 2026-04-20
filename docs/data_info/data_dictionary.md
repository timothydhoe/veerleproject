# Data Dictionary

> All file formats, fields, units, and derived variables used in the SchoolMoves pipeline.

---

## Raw GENEActiv CSV file

Each raw file has two sections separated by blank lines: a metadata header block and a time-series data block.

### Header block (key–value pairs)

| Field | Example value | Notes |
|---|---|---|
| Device Type | `GENEActiv` | Always GENEActiv |
| Device Model | `1.1` | Version of device |
| Device Unique Serial Code | `068006` | 6-digit serial number |
| Device Firmware Version | `Ver4.08a date14Jul14` | |
| Calibration Date | `2022-03-23 07:22:25:000` | |
| Application name & version | `GeneaLibrary` | |
| Measurement Frequency | `100 Hz` | Raw sampling rate |
| Start Time | `2026-02-05 12:22:19:500` | When recording started |
| Last measurement | *(empty)* | Often blank |
| Device Location Code | `left wrist` | Non-dominant wrist |
| Time Zone | `GMT +01:00` | Belgium (CET) |
| Subject Code | `4001` | 4-digit pupil ID (school + pupil) |
| Date of Birth | `1900-01-01` | Anonymised placeholder |
| Sex | *(empty)* | Not collected |
| Height | *(empty)* | Not collected |
| Weight | *(empty)* | Not collected |
| Handedness Code | *(empty)* | |
| Subject Notes | *(empty)* | |
| Study Centre | *(empty)* | |
| Study Code | *(empty)* | |
| Investigator ID | *(empty)* | |
| Config Time | `2026-02-04 14:38:35:114` | When device was configured |
| Extract Time | `2026-02-17 11:50:43:998` | When data was downloaded |

**Sensor metadata** (repeated for each sensor):

| Sensor | Range | Resolution | Units |
|---|---|---|---|
| MEMS accelerometer x-axis | −8 to 8 | 0.0039 | g |
| MEMS accelerometer y-axis | −8 to 8 | 0.0039 | g |
| MEMS accelerometer z-axis | −8 to 8 | 0.0039 | g |
| Lux photodiode | 0 to 5000 | 5 | lux |
| User button event marker | 0 or 1 | — | — |
| Linear active thermistor | 0 to 70 | 0.1 | deg. C |

---

### Data block (time-series rows)

One row per second after epoch-averaging (raw is 100 Hz). Format:

```
<timestamp>,<x>,<y>,<z>,<lux>,<button>,<temp>,<ENMO>,<std_x>,<std_y>,<std_z>,<peak_lux>
```

| Column | Type | Unit | Description |
|---|---|---|---|
| timestamp | datetime | `YYYY-MM-DD HH:MM:SS:mmm` | Epoch start time |
| x | float | g | Mean x-axis acceleration |
| y | float | g | Mean y-axis acceleration |
| z | float | g | Mean z-axis acceleration |
| lux | int | lux | Light level |
| button | int | 0 or 1 | Button press event |
| temp | float | °C | Wrist temperature |
| ENMO | float | mg | Euclidean Norm Minus One (see below) |
| std_x | float | g | Std deviation of x within epoch |
| std_y | float | g | Std deviation of y within epoch |
| std_z | float | g | Std deviation of z within epoch |
| peak_lux | int | lux | Maximum lux within epoch |

---

## ENMO — Euclidean Norm Minus One

ENMO is the primary measure of body acceleration.

```
ENMO = max(0, sqrt(x² + y² + z²) − 1) × 1000   [result in mg]
```

Raw tri-axial values are converted to a single omnidirectional measure by taking the Euclidean norm of the three axes, subtracting 1g (gravity), and clipping negative values to zero. Values are expressed in milli-g (mg).

**Reference:** van Hees et al. (2013), PLoS One 8(4):e61691

---

## Activity intensity cut-points

Validated for wrist-worn accelerometers in children:

| Intensity level | ENMO range (mg) | Label in output |
|---|---|---|
| Sedentary | < 56.3 | `sedentary` |
| Light PA | 56.3 – 191.6 | `light` |
| Moderate PA | 191.6 – 695.8 | `moderate` |
| Vigorous PA | > 695.8 | `vigorous` |

**References:** Hildebrand et al. (2014) Med Sci Sports Exerc; Hildebrand et al. (2017) Scand J Med Sci Sports

---

## Non-wear detection

GGIR identifies non-wear when, for **at least 2 of 3 axes**:
- Standard deviation of raw acceleration < **13 mg**
- Data range < **50 mg**

Assessment is done over 60-minute blocks, evaluated every 15 minutes.

Non-wear epochs are flagged as `wear = FALSE` in the pipeline output and excluded from all activity and validity calculations.

---

## Sleep detection

GGIR uses sustained inactivity to detect sleep: a period in which the arm angle changes by less than **5 degrees** over a **5-minute** window.

Output columns from GGIR sleep detection:

| Column | Description |
|---|---|
| sleep_onset | Estimated time of sleep onset |
| sleep_offset | Estimated wake time |
| sleep_duration_h | Total sleep duration in hours |
| pct_night_valid | Percentage of the night with valid data |
| pct_night_invalid | Percentage of the night flagged as invalid (non-wear or missing) |

The pipeline converts `pct_night_invalid` to `pct_night_valid` = 100 − `pct_night_invalid`.

---

## Validity criteria

To be included in analyses, a pupil must meet **both** thresholds:

| Analysis | Minimum requirement |
|---|---|
| Sedentary time analysis | ≥ 9 valid waking wear hours on **4 days** |
| Sleep duration analysis | ≥ 50% valid sleep data on **5 nights** |

Pupils who fail either criterion are excluded from the respective analysis and flagged in the data quality report. They are not deleted from the dataset.

**Reference:** Antczak et al. (2021), Int J Behav Nutr Phys Act 18(1):73

---

## Pipeline output schema

After running the full pipeline, each pupil's data is stored as a single parquet file with the following columns:

| Column | Type | Description |
|---|---|---|
| pupil_id | string | 4-digit ID (e.g. `2063`) |
| school_id | int | 1–6 |
| measurement_period | string | `meting_1` or `meting_2` |
| timestamp | datetime | 1-second epoch |
| enmo_mg | float | ENMO value in mg |
| intensity | string | `sedentary`, `light`, `moderate`, `vigorous` |
| wear | bool | TRUE if valid wear time |
| sleep | bool | TRUE if epoch is within detected sleep period |
| context | string | See [School Info](school_info.md) for values |
| schedule_source | string | `actual` or `fallback` |
| day_valid_waking_h | float | Valid waking wear hours for this calendar day |
| night_pct_valid | float | Percentage of the night with valid sleep data |
| pupil_valid_sedentary | bool | Meets 4-day / 9h sedentary validity threshold |
| pupil_valid_sleep | bool | Meets 5-night / 50% sleep validity threshold |

---

## Config file format (`school_schedules.yaml`)

```yaml
school_1:
  schedule_source: actual
  days:
    monday:    { start: "08:25", end: "15:40", breaks: [{start: "10:05", end: "10:20"}, {start: "12:00", end: "13:00"}, {start: "14:40", end: "14:50"}] }
    tuesday:   { start: "08:25", end: "16:30", breaks: [{start: "10:05", end: "10:20"}, {start: "12:00", end: "13:00"}, {start: "14:40", end: "14:50"}] }
    wednesday: { start: "08:25", end: "11:55", breaks: [{start: "10:05", end: "10:15"}] }
    thursday:  { start: "08:25", end: "15:40", breaks: [{start: "10:05", end: "10:20"}, {start: "12:00", end: "13:00"}, {start: "14:40", end: "14:50"}] }
    friday:    { start: "08:25", end: "15:40", breaks: [{start: "10:05", end: "10:20"}, {start: "12:00", end: "13:00"}, {start: "14:40", end: "14:50"}] }
```

# SchoolMove Pipeline: Plan of Attack 

## The Problem

Setting up a pipeline that monitors the physical activity in Belgian schoolchildren.
Around 400 pupils across 6 schools wore a wrist sensor for one week, twice per school year.
The sensors recorded continuous movement data, producing one large file per pupil per
measurement period.

The core question is: **how active are children during the school day, and does it vary
by context?**

- How much time do they spend sitting still, moving lightly, or exercising?
- Does this differ between lessons, recess, and after school?
- How do schools compare to each other across both measurement waves?
- Are children sleeping enough?

The raw sensor files cannot answer these questions on their own. They need to be
processed, cleaned, labelled with school context, and presented in a usable form.
That is what this pipeline does.

---

## The Big Picture

```
Raw sensor files (one per pupil)
         |
         v
   GGIR cleans each file
   (removes noise, detects non-wear periods and sleep)
         |
         v
   School schedule applied
   (labels every minute: lesson / recess / lunch / after school / weekend)
         |
         v
   Summary tables per pupil per day
         |
         v
   Shiny dashboard
   (Veerle explores results, no code required)
```

---

## What the System Produces

By the end of the pipeline, Veerle has access to:

| Output | What it answers |
|--------|----------------|
| **Activity summary** | Minutes per day each pupil spent sedentary, lightly active, or vigorously active, broken down by school context |
| **Sedentary bouts** | How long children sit without moving, and whether this happens more during lessons or elsewhere |
| **Sleep summary** | Estimated sleep duration and quality per pupil per night |
| **Data quality report** | Which pupils meet minimum wear criteria and which are excluded, with clear reasons |
| **School comparison** | Side-by-side view across all 6 schools and both measurement waves |

Everything is accessible through a dashboard. Veerle does not need to touch any code.

---

## How We Build It

### Phase 1 — Dummy data *(Week 1-2)*

The full dataset is large and not yet fully accessible. Before it arrives, we generate
fictional sensor files that follow the exact same format as the real ones. This lets us
build and test the entire pipeline without waiting, and without touching real pupil data.

### Phase 2 — GGIR pipeline *(Week 2-5)*

GGIR is the standard R package for processing wrist-worn accelerometer data. The whole
pipeline runs through a single function call, `GGIR()`, which executes six parts in
sequence. Each part builds on the previous one. Below is roughly what our call will look
like, with each parameter explained:

```r
GGIR(
  datadir        = "data/raw/meting_1",      # folder with the pupil CSV files
  outputdir      = "data/processed/meting_1",
  mode           = 1:5,                      # run parts 1 through 5
  do.cal         = FALSE,                    # skip autocalibration (CSV input, not raw binary)
  windowsizes    = c(1, 900, 3600),          # 1s epochs / 15-min non-wear check / 60-min non-wear block
  HASPT.algo     = "HDCZA",                  # wrist-validated sleep detection algorithm
  anglethreshold = 5,                        # arm angle change below 5 degrees = sustained stillness
  timethreshold  = 5,                        # must hold for at least 5 minutes to count as sleep candidate
  threshold.lig  = 56.3,                     # mg boundary: sedentary / light
  threshold.mod  = 191.6,                    # mg boundary: light / moderate
  threshold.vig  = 695.8,                    # mg boundary: moderate / vigorous
  boutdur.in     = c(10, 20, 30),            # sedentary bout lengths (minutes) to extract separately
  includedaycrit = 9,                        # minimum valid waking hours for a day to count
  qwindow        = c(0, 8.75, 10, 12, 13, 15.5, 24)  # time segment boundaries (hours)
)
```

This runs once per measurement wave. Because meting 1 and meting 2 share the same
filenames, they are kept in completely separate folders and the pipeline is run
independently for each.

**Part 1** reads each pupil's sensor file and computes ENMO (a gravity-subtracted
movement metric) at 1-second intervals. Since we are working with pre-converted CSV
files rather than raw binary files, we disable autocalibration (`do.cal = FALSE`).
The `windowsizes` parameter controls the three time resolutions GGIR works at: 1-second
epochs for the signal itself, 15-minute windows for checking non-wear, and 60-minute
blocks for confirming it.

**Part 2** is where quality control happens. GGIR detects non-wear periods using a
rolling window approach: if at least 2 of 3 axes show a standard deviation below 13 mg
and a range below 50 mg over a 60-minute block (checked every 15 minutes), that period
is flagged as non-wear. It also flags clipping artefacts and produces the first
day-level summaries. Validity in this study is split by analysis type: for sedentary
behaviour, pupils need at least 9 valid waking hours on 4 days; for sleep, at least 50%
valid sleep data on 5 nights. This is also where school schedule segments get wired in:
the `qwindow` parameter defines time boundaries for a typical school day, and GGIR will
compute activity summaries separately for each segment.

**Parts 3 and 4** handle sleep detection. Part 3 identifies periods of sustained
stillness using the angle of the wrist relative to gravity (anglez). If the arm angle
changes by less than 5 degrees over a 5-minute window, that window is flagged as a sleep
candidate (`anglethreshold = 5`, `timethreshold = 5`). These thresholds come directly
from Veerle's protocol and have been validated against polysomnography, the gold standard
sleep measure. Part 4 converts those candidates into confirmed sleep windows per night,
with onset and wake times.

**Part 5** brings everything together into the final time-use output. Every second of
recording gets a label: sleeping, inactive, light activity, or moderate-to-vigorous
activity. From this, GGIR produces per-day and per-person summaries including bout
analysis. The `boutdur.in = c(10, 20, 30)` parameter tells GGIR to separately count
sedentary bouts of 10, 20, and 30 minutes or longer, which feeds directly into Veerle's
research question on prolonged sitting. The activity thresholds used are validated
wrist-worn cut-points for children (Hildebrand 2014/2017): sedentary below 56.3 mg,
light from 56.3 to 191.6 mg, moderate from 191.6 to 695.8 mg, and vigorous above 695.8 mg.

**Part 6** covers circadian rhythm analysis, which is outside the scope of this study.

#### Key outputs from GGIR:

| File | What it contains |
|------|-----------------|
| `part2_daysummary.csv` | One row per pupil per day: valid wear hours, ENMO, activity by segment |
| `part4_nightsummary.csv` | One row per night: sleep onset, wake time, duration, efficiency |
| `part5_daysummary.csv` | Full day-level breakdown of activity intensity, bouts, and fragmentation |
| `part5_personsummary.csv` | One row per pupil: averages across valid days, split by weekday/weekend |

On top of GGIR's output, we add a custom labelling layer that assigns each minute to a
school context (lesson, recess, lunch, after school, or weekend) using the timetables in
`config.yaml`. This is what makes the school-by-school comparison possible.

### Phase 3 — Analysis *(Week 4-8)*

Using the cleaned, labelled data, we compute the summaries Veerle needs: daily activity
totals by context, sedentary bout counts and durations, sleep statistics, and school-level
comparisons across both measurement waves.

*Phases 2 and 3 overlap intentionally. Early analysis can begin while the pipeline is
still being refined.*

### Phase 4 — Dashboard *(Week 7-10)*

We build an R Shiny dashboard where Veerle can explore results by school, by pupil, or
across the full dataset. Every view can be exported as a table or image. The interface is
designed for researchers, not developers. Every chart is self-explanatory and filters
apply across all views simultaneously.

### Phase 5 — Documentation *(Week 9-11)*

A plain-language user manual so Veerle and future researchers can run the pipeline and
use the dashboard without assistance.

### Phase 6 — Testing and handover *(before July 2026)*

We validate the pipeline on real pupil files, confirm outputs match expectations, and
hand the complete system over to Veerle with a short walkthrough session. Reproducibility
is guaranteed by `renv`, which locks the exact versions of all R packages used, so the
pipeline produces the same results regardless of when or where it is run.

---

## Open Questions

A couple of details still need to be confirmed before the pipeline can be fully finalised:

- **GGIR settings** — the full configuration Veerle used in her previous analyses, so new
  results stay comparable
- **School schedules** — timetables for schools 3 and 4 are still missing

---

## Out of Scope (for now)

**Automatic attendance detection** — inferring from the sensor data whether a pupil was
absent on a given day — is a possible future feature. It is not part of the current plan.

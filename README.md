# SchoolMove

A data analysis pipeline for wrist-worn accelerometer data collected from ~400 Belgian
schoolchildren across 6 schools. The goal is to measure how much time children spend
sitting still, doing light activity, and doing moderate-to-vigorous physical activity —
and how that changes between two measurement periods.

**Client**: Veerle Van Oeckel (UGent)

---

## What this project does

Each child wore a small wrist sensor (a GENEActiv accelerometer) for about a week. The
sensor recorded movement every hundredth of a second, around the clock. That raw data
needs to be cleaned, processed, and turned into meaningful numbers — for example: "On
average, this child spent 45 minutes in moderate-to-vigorous activity on school days."

This project automates that entire process. It takes the raw sensor files as input and
produces summary tables and an interactive dashboard as output.

---

## How it works — step by step

### Step 1 — The sensor data comes in as CSV files

After each measurement period, the raw sensor recordings are exported as
spreadsheet-like
files (`.csv`). Each file belongs to one child, named with a 4-digit code: the first
digit is the school number, the remaining three digits are the child's ID within that
school. For example, `2063.csv` is child 063 from School 2.

Files are organised into two folders: `meting_1` and `meting_2`, one per measurement
wave.

### Step 2 — GGIR processes the raw data

The sensor files are fed into **GGIR**, a specialised scientific software package built
by movement researchers. GGIR does the heavy lifting:

- It calculates **ENMO** — a standardised measure of how much the wrist was moving at
  each moment, expressed in units called *milli-g* (mg).
- It detects **non-wear periods** — times when the sensor was probably not on the wrist
  (identified by very little movement across all axes for 15 minutes or more).
- It detects **sleep** — using the arm angle and movement patterns overnight.
- It **classifies every second** of the recording as one of: sedentary (SB), light
  physical activity (LPA), moderate-to-vigorous physical activity (MVPA), non-wear, or
  sleep.
- It flags **invalid days** — days where the child wore the sensor for fewer than 16
  hours — and marks **invalid recordings** — where a child has fewer than 3 valid days,
  including at least one weekend day.
- It produces **summary tables** as CSV files, ready for further analysis.

GGIR runs in six sequential stages (called "parts"). Each part builds on the previous
one. You do not need to understand the internals — the pipeline runs all six stages
automatically.

### Step 3 — Results appear in the dashboard

Once GGIR has finished, the **Shiny dashboard** reads the summary tables and presents
them visually. Veerle and colleagues can:

- Browse data quality per school and per child
- See activity breakdowns (SB / LPA / MVPA) by school, day, and time of day
- Compare meting 1 against meting 2
- Download export-ready tables for use in statistical software

No coding is required to use the dashboard.

---

## How to run the pipeline

> You only need to do this when new data arrives or when you want to re-run the analysis
> with different settings.

### 1. Open the project in RStudio

Open the file `r/SchoolMove.Rproj` in RStudio or VSCode. This sets everything up
automatically. You do not need to change any folder settings.

### 2. First time only — install the required packages

If this is your first time running the project, open `r/install.R` in RStudio and click
**Source**. This downloads and installs all the R packages the project needs. It only
needs to be done once per computer.

If someone else has already done this and shared the project with you, run
`renv::restore()` in the R console instead. This installs the exact same package
versions the team used, ensuring consistent results.

### 3. Adjust settings if needed

Open `config.yaml` in any text editor (or in RStudio). This file contains all the
parameters you might want to change:

- Which schools and measurement periods to include
- Activity thresholds (once confirmed)
- School timetables
- Validity criteria

You should not need to edit any `.R` files. Everything is controlled through
`config.yaml`.

### 4. Run the pipeline

Open `r/pipeline/01_run_ggir.R` and click **Source**. GGIR will process all the sensor
files and write results to `data/processed/ggir/`. This may take some time depending on
how many files there are.

### 5. Check the output

Open `r/validation/check_outputs.R` and click **Source**. This runs a quick set of
checks and prints a summary to the console — letting you know if everything looks
correct before opening the dashboard.

### 6. Open the dashboard

In the RStudio console, run:

```r
shiny::runApp("shiny")
```

The dashboard will open in your browser.

---

## Project structure

```
SchoolMove/
│
├── config.yaml                   ← All settings live here. Edit this, not the R files.
│
├── r/                            ← All R code
│   ├── SchoolMove.Rproj          ← Open this in RStudio to start working
│   ├── install.R                 ← Run once to install packages
│   │
│   ├── pipeline/
│   │   └── 01_run_ggir.R         ← Runs the full GGIR analysis pipeline
│   │
│   ├── shiny/
│   │   ├── global.R              ← Shared setup for the dashboard
│   │   ├── ui.R                  ← Dashboard layout and tabs
│   │   └── server.R              ← Dashboard logic
│   │
│   └── validation/
│       └── check_outputs.R       ← Sanity checks after running the pipeline
│
├── data/
│   ├── raw/                      ← Input CSV files (NOT included in this repository
│   │   ├── meting_1/             │  for privacy reasons — stored separately)
│   │   └── meting_2/             ┘
│   ├── processed/                ← GGIR output (generated automatically)
│   └── example/                  ← Fictional test data (safe to share)
│
└── docs/                         ← Background documentation and reference material
```

---

## The configuration file (`config.yaml`)

`config.yaml` is the control panel for the entire pipeline. It is written in a simple
format called YAML — essentially a structured list of settings. You do not need any
programming knowledge to edit it.

Here is a quick guide to the sections:

| Section        | What it controls                                                                              |
|----------------|-----------------------------------------------------------------------------------------------|
| `paths`        | Where the pipeline looks for data and where it saves results                                  |
| `ggir`         | Technical settings for the GGIR analysis (epoch length, cut-points once confirmed)            |
| `validity`     | Rules for deciding whether a day or recording is usable (minimum wear time, etc.)             |
| `measurements` | The date ranges for each school's two measurement periods                                     |
| `schedules`    | Each school's daily timetable — used to label epochs by context (lesson, recess, lunch, etc.) |
| `output`       | Timezone and locale settings                                                                  |

> **Note on cut-points**: The activity thresholds (how many mg counts as "light" vs
> "moderate" activity) are not yet filled in — they are waiting for confirmation from
> the
> research protocol. They appear as commented-out lines (`# cut_points_mg: ...`) and
> will
> be added once confirmed.

> **Note on school schedules**: Schools 3 and 4 are marked `fallback: true` in the
> config — their timetables are approximate because the detailed schedules were not yet
> available. The pipeline will still run, but results for those schools should be
> interpreted with care until the confirmed schedules are added.

---

## Open questions

The following items are still to be resolved before the analysis can be completed:

| Item                       | Why it matters                                                                    | Who to ask                                        |
|----------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------|
| Activity cut-points        | Without exact ENMO thresholds, the SB/LPA/MVPA classification cannot be finalised | Veerle (referenced as citation 7 in the protocol) |
| Schools 3 and 4 timetables | Current schedules are approximate fallbacks                                       | Veerle                                            |
| Day-segment definitions    | Agreement needed on which time windows to use (lessons, recess, lunch, PE, etc.)  | Veerle + research team                            |
| Sleep log availability     | If children kept a sleep diary, it can improve sleep detection accuracy           | Veerle                                            |

---

## Data privacy

The raw sensor files contain data from identifiable children and are **not stored in
this repository**. They must be kept on a secure, access-controlled system in line with GDPR
requirements. The `data/raw/` folder is excluded from version control (listed in
`.gitignore`).

The `data/example/` folder contains entirely fictional data that is safe to share and
use for testing.

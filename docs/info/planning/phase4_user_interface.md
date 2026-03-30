# Phase 4 — User Interface

> A clean, researcher-facing dashboard built in R Shiny that allows exploration of all analysis results without writing code.

---

## Goal

Build a dashboard that:
- Requires no coding knowledge to operate
- Updates all views simultaneously when filters change
- Makes every output exportable (CSV + PNG)
- Surfaces attendance flags clearly for manual review
- Is fast enough to load a full-school view within 5 seconds

---

## Technology recommendation: R Shiny

**Why Shiny over Streamlit:**
- The entire pipeline is in R; Shiny keeps everything in one language
- Shiny's reactive model handles the school/pupil selector driving all views naturally
- `bslib` and `plotly` provide modern, clean UI with minimal boilerplate
- Familiar to the R-using research community

**Fallback:** If the Python analysis layer (attendance prediction) grows significantly, Streamlit + `rpy2` is the alternative. Decide after Phase 3.

---

## Application structure

```
ui/
├── app.R                  # Main app entry point
├── global.R               # Load data, configs, shared functions
└── modules/
    ├── mod_selector.R     # School + pupil selector sidebar
    ├── mod_activity.R     # Activity summary panel
    ├── mod_bouts.R        # Sedentary bouts panel
    ├── mod_sleep.R        # Sleep panel
    ├── mod_attendance.R   # Attendance check panel
    └── mod_quality.R      # Data quality panel
```

Each panel is a Shiny module (`moduleServer` + `moduleUI`) so it can be developed and tested independently.

---

## Layout

```
┌─────────────────────────────────────────────────────────────┐
│  SchoolMoves — Accelerometer Dashboard          [?] Help    │
├──────────────┬──────────────────────────────────────────────┤
│              │                                              │
│  FILTERS     │   [Activity] [Bouts] [Sleep] [Attendance]   │
│              │   [Quality]                                  │
│  School: ▼   ├──────────────────────────────────────────────┤
│  Pupil:  ▼   │                                              │
│  Period: ▼   │   Active panel content                       │
│  Dates:  ▼   │                                              │
│              │                                              │
│  [Apply]     │                                              │
│  [Export ▼]  │                                              │
│              │                                              │
└──────────────┴──────────────────────────────────────────────┘
```

---

## Panel specifications

### Sidebar — School & pupil selector

| Control | Type | Options |
|---|---|---|
| School | Dropdown | All schools, or School 1–6 |
| Pupil | Dropdown | Populated from selected school; "All pupils" option |
| Measurement period | Radio | Meting 1, Meting 2, Both |
| Date range | Date range picker | Defaults to full 7-day window |
| Show only valid pupils | Checkbox | Default: ON |

When "All pupils" is selected, views show school-level aggregates. When a single pupil is selected, views show individual-level detail.

---

### Panel 1 — Activity summary

**Purpose:** Show daily activity totals by intensity level and context.

**Views:**

1. **Stacked bar chart** — one bar per day, stacked by intensity (sedentary/light/moderate/vigorous). Colour legend below the chart. School-day annotations (vertical dashed lines at school start/end).

2. **Context breakdown table** — for the selected date range, mean minutes per intensity level per context. Columns: Context | Sedentary | Light | Moderate | Vigorous.

3. **Individual day timeline** (single-pupil view only) — a horizontal swimlane showing every epoch coloured by intensity, with school-schedule annotations overlaid.

**Export:** CSV button (summary table) + PNG button (chart).

---

### Panel 2 — Sedentary bouts

**Purpose:** Show frequency and duration of sedentary bouts ≥30 minutes.

**Views:**

1. **Bar chart** — number of ≥30-min bouts per day, coloured by context (in-class vs. other).

2. **Bout detail table** — each bout listed with: date, start time, end time, duration (min), context.

3. **Summary card** — mean bouts per day, mean bout duration, % of sedentary time in bouts ≥30 min.

**Export:** CSV (bout table) + PNG (bar chart).

---

### Panel 3 — Sleep

**Purpose:** Show sleep duration and quality across the 7-day window.

**Views:**

1. **Sleep timeline** — horizontal bars per night showing sleep onset → offset, coloured by % valid (green = high validity, amber = borderline, red = low validity).

2. **Summary table** — per-night: onset, offset, duration (h), % night valid.

3. **Summary card** — mean sleep duration, mean % valid, number of valid nights.

**Export:** CSV + PNG.

---

### Panel 4 — Attendance check

**Purpose:** Surface predicted absence days for manual researcher review.

**Views:**

1. **Flagged days table** — one row per flagged day:

| Pupil | Date | Prediction | Confidence | Override | Final status |
|---|---|---|---|---|---|
| 2063 | 2026-03-06 | Absent | High | — | Pending |
| 1015 | 2026-02-27 | Absent | Low | — | Pending |

2. **Override controls** — for each row, the researcher can:
   - Mark as `Present` (removes the flag)
   - Confirm as `Absent` (flag is kept)
   - Mark as `Unknown` (flag is kept but noted as unresolved)

3. **Override log** — all researcher decisions are logged with timestamp and saved to `data/processed/attendance_overrides.csv`.

**Implementation note:** Override decisions persist between sessions. The app reads the override file on startup and applies it to the predictions.

---

### Panel 5 — Data quality

**Purpose:** Show validity status for every pupil so the researcher understands the effective sample size.

**Views:**

1. **Validity summary table** — one row per pupil:

| Pupil | School | Period | Valid days | Valid nights | Sedentary analysis | Sleep analysis | Exclusion reason |
|---|---|---|---|---|---|---|---|
| 2063 | 2 | Meting 1 | 7 / 7 | 6 / 7 | ✓ | ✓ | — |
| 1042 | 1 | Meting 1 | 3 / 7 | 2 / 7 | ✗ | ✗ | Insufficient valid days |

2. **Summary cards** — total pupils | passing sedentary validity | passing sleep validity | excluded entirely.

3. **Exclusion breakdown** — pie or bar chart showing exclusion reasons.

**Export:** CSV.

---

## Technical requirements

### Performance
- Pre-aggregate all analysis outputs at app startup (`global.R`) so panel switches are near-instant
- Use `plotly` for interactive charts (zoom, hover, pan) rather than static `ggplot2`
- Large tables use `DT::datatable()` with server-side pagination

### Persistence
- Attendance override decisions saved to `data/processed/attendance_overrides.csv`
- App reads this file on startup; writes on every override action

### Help system
- A `[?] Help` button in the header opens a modal with a brief explanation of the current panel
- Links to the relevant section of the user manual

### Deployment
- The app runs locally with `shiny::runApp()` — no server deployment required for the research team
- If deployment to a shared server is needed, standard `shinyapps.io` or a university RStudio Server deployment applies

---

## Acceptance criteria

Before moving to Phase 5, verify:

- [ ] All 5 panels load without errors on dummy data
- [ ] Switching from school-level to individual-pupil view updates all charts correctly
- [ ] Attendance override decisions persist after restarting the app
- [ ] Every chart and table has a working export button
- [ ] Help modal text is accurate and links to the correct manual section
- [ ] A non-technical user (Veerle) can navigate from school overview to individual pupil sleep data in under 60 seconds without instructions

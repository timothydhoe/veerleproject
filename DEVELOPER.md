# Developer Guide — SchoolMove

Your personal reference for working on this project. Covers the day-to-day workflow,
what's built, and all the tools available to you.

---

## Mental model

The project has one job: take accelerometer CSV files → run GGIR → show results in
Shiny. Everything else (config, hooks, commands, validation) exists to support that loop.

```
config.yaml          ← you control all parameters here
     ↓
01_run_ggir.R        ← feeds config into GGIR, runs Parts 1–6 for each meting
     ↓
data/processed/ggir/
  meting_1/output_meting_1/results/   ← Part 2 and Part 5 summary CSVs
  meting_2/output_meting_2/results/
     ↓
shiny/               ← reads those CSVs, presents them to Veerle
```

The Shiny dashboard is the deliverable Veerle actually uses. Everything upstream is
infrastructure to get her good data.

---

## Day-to-day workflow

### Starting a session

1. Open `r/SchoolMove.Rproj` in RStudio — working directory is set automatically
2. Open Claude Code in the project root (`veerleproject/`)
3. Run `/blocker-check` to remind yourself where things stand

### Making changes

| What you want to change | Where to do it |
|-------------------------|----------------|
| Pipeline parameters, cut-points, schedules | `config.yaml` only — never hardcode in `.R` files |
| GGIR pipeline logic | `r/pipeline/01_run_ggir.R` |
| Dashboard layout / tabs | `r/shiny/ui.R` |
| Dashboard reactive logic | `r/shiny/server.R` |
| Shared data loading and helpers | `r/shiny/global.R` |
| Post-pipeline sanity checks | `r/validation/check_outputs.R` |
| Package dependencies | Add to `r/install.R`, then run `renv::snapshot()` in R |

### Testing locally

```r
# 1. Make sure config.yaml has dev.example_mode: true  (it does by default)
# 2. Run the pipeline on dummy data
source("pipeline/01_run_ggir.R")

# 3. Check outputs
source("validation/check_outputs.R")

# 4. Launch the dashboard
shiny::runApp("shiny")
```

---

## What's built

| Component | Status | Notes |
|-----------|--------|-------|
| `config.yaml` | Done | All 6 schools, measurement dates, confirmed schedules, cut-points |
| `pipeline/01_run_ggir.R` | Done | Loops meting_1 / meting_2; reads rmc.* params for GENEActiv CSV; dev overrides wired up |
| `shiny/global.R` | Done | Loads Part 2 + Part 5 from both metingen; derives validity summary |
| `shiny/ui.R` | Done | 5 tabs: Overview, Data Quality, Activity, Meting Comparison, Export |
| `shiny/server.R` | Done | All tabs implemented with reactive filters, plots, and download handlers |
| `validation/check_outputs.R` | Done | Checks both metingen; validates Part 2/5 files and column presence |
| Hooks | Done | GDPR guard, config guard, R syntax check — all active |
| Commands | Done | 5 slash commands available |

---

## GGIR output structure

GGIR writes output under a subdirectory it creates automatically. The full path is:

```
data/processed/ggir/
  meting_1/
    output_meting_1/
      meta/          ← intermediate milestone files (RData)
      results/
        part2_daysummary.csv                          ← daily wear time (Part 2)
        part2_summary.csv                             ← person-level Part 2 summary
        part5_daysummary_WW_L56.3M191.6V695.8_T5A5.csv   ← daily SB/LPA/MPA/VPA
        part5_personsummary_WW_L56.3M191.6V695.8_T5A5.csv ← person-level activity
        visualisation_sleep.pdf
  meting_2/
    output_meting_2/
      results/  (same structure)
```

The Part 5 filenames embed the cut-point values used. `global.R` finds them with a glob
pattern (`^part5_daysummary_WW_`) so the exact filename doesn't need to be hardcoded.

### Key Part 2 columns

| Column | Meaning |
|--------|---------|
| `ID` | Filename (e.g. `1001.csv`) — first digit(s) = school, last 3 = pupil |
| `N valid hours` | Hours classified as worn that day (production threshold: ≥16 h) |
| `N hours` | Total hours in the day window |
| `calendar_date` | Date |
| `weekday` | Day name |

### Key Part 5 columns

| Column | Meaning |
|--------|---------|
| `dur_day_total_IN_min` | Sedentary (SB) minutes — waking day |
| `dur_day_total_LIG_min` | Light PA (LPA) minutes |
| `dur_day_total_MOD_min` | Moderate PA (MPA) minutes |
| `dur_day_total_VIG_min` | Vigorous PA (VPA) minutes |
| `dur_day_MVPA_bts_10_min` | MVPA in bouts ≥10 min |
| `nonwear_perc_day` | % of waking day classified as non-wear |

---

## `config.yaml` — developer reference

The config has two audiences: sections Veerle edits (`ggir`, `validity`, `schedules`,
`measurements`) and a `dev` section only developers touch.

### `dev` section — when and how to use it

```yaml
dev:
  example_mode: true        # true  → pipeline uses data/example/dummy_data/
                            # false → pipeline uses data/raw/

  # ⚠ The three settings below exist only for 1 Hz dummy data compatibility.
  # Remove them (or set to null) before running on real 100 Hz participant data.

  nonwear_approach: "2013"  # 2023 default resamples to 5 Hz internally, which
                            # zeros out all variance in 1 Hz signals → everything
                            # flagged as non-wear. "2013" uses the raw signal as-is.

  includedaycrit: 5         # GGIR Part 2: min valid hours/day to count a day.
                            # Production = 16. Dummy data caps out at ~7 h/day.

  includedaycrit_part5: 0.3 # GGIR Part 5: min fraction of waking window that must
                            # be valid. Production = 0.667. Lowered for dummy data.
```

The pipeline runner reads all three at startup and logs a warning if any override is
active. `global.R` also picks up `includedaycrit` so the Shiny validity table uses the
same threshold as GGIR.

**Before switching to real data:**

1. Set `example_mode: false`
2. Remove (or null out) `nonwear_approach`, `includedaycrit`, `includedaycrit_part5`
3. Set `overwrite: false` once the first real run looks good

### Activity cut-points

Confirmed by Veerle's protocol (wrist-worn GENEActiv, Hildebrand et al. 2014):

| Intensity | ENMO range |
|-----------|-----------|
| SB (sedentary) | < 56.3 mg |
| LPA (light) | 56.3 – 191.6 mg |
| MPA (moderate) | 191.6 – 695.8 mg |
| VPA (vigorous) | > 695.8 mg |

These are set in `config.yaml` under `ggir.cut_points_mg` and passed to GGIR as
`threshold.lig`, `threshold.mod`, `threshold.vig`.

---

## GENEActiv CSV reading

GENEActiv native CSV reading was deprecated in GGIR 2.6-4. We use `read.myacc.csv`
via the `rmc.*` parameter family. The dummy data (and real data) has a 100-row metadata
header; data starts at row 101. Columns 2–4 are x/y/z (in g), column 1 is the timestamp.

The dummy data was generated at 1 Hz (one row per second). Real device recordings are
100 Hz. Change `rmc.sf` in `01_run_ggir.R` if the real data turns out to be a different
frequency.

The GENEActiv CSV also contains `sdx`, `sdy`, `sdz` columns (9–11) — the within-epoch
standard deviations computed by the device firmware. These are **not mapped** in the
`rmc.*` parameters and are ignored by GGIR. GGIR computes its own variance metrics from
the x/y/z values it reads. In the dummy data, these columns contain approximated values
(not real within-second variance) purely to match the expected column layout.

---

## Open blockers

| Item | Status | Notes |
|------|--------|-------|
| Schools 3 and 4 timetables | ⚠ Fallback | Approximate schedules in config — update when confirmed timetables arrive (use `/add-schedule`) |
| Real participant data | Pending | Pipeline tested on dummy data; ready for real data once `example_mode: false` and dev overrides removed |
| Sleep log availability | Unknown | If children kept a diary, it improves GGIR sleep detection — ask Veerle |

---

## Claude Code tools

### Slash commands

| Command | What it does |
|---------|-------------|
| `/validate-config` | Checks `config.yaml` for errors and gaps — run before every pipeline run |
| `/pipeline-status` | Shows what GGIR has processed and what's missing |
| `/add-schedule` | Converts plain-text timetable info into correct YAML — use when school schedules arrive |
| `/blocker-check` | Produces a meeting-ready summary of open questions for Veerle |
| `/shiny-plan` | Plans a new dashboard feature before any code is written — always run this first |

### Hooks (fire automatically)

| Hook | When | What it does |
|------|------|-------------|
| GDPR guard | Before `git commit` | Blocks commit if `data/raw/` or `data/processed/` files are staged |
| Config guard | After saving `config.yaml` | Validates YAML syntax + warns about missing values |
| R syntax check | After saving any `.R` file | Catches syntax errors immediately |

Hook scripts are in `.claude/hooks/` — plain Python, easy to edit.

### MCP server

**context7** is configured and active. Use it to pull up-to-date documentation for any
library without leaving Claude Code:

```
# In a Claude Code message, just ask:
"Check the GGIR docs for the desiredtz parameter"
"Show me how to use bslib's value_box() in Shiny"
```

Key library IDs:
- Shiny → `shiny_posit_co`
- GGIR → search for `ggir` or `wadpac`

---

## Rules

- **Never hardcode a parameter in an `.R` file** — it goes in `config.yaml`
- **Never commit anything from `data/raw/` or `data/processed/`** — the GDPR hook will stop you, but don't try to bypass it
- **Never introduce Python** unless R/Shiny genuinely can't do it — the architecture decision was deliberate
- **Always run `/shiny-plan` before adding a new Shiny feature** — keeps tabs consistent and avoids rework

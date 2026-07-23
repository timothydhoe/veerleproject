---
description: Check what has and hasn't been processed yet — which pipeline steps completed, how many participants, what's missing.
---

Check the current state of the SchoolMove pipeline. Write the report in plain language for a non-technical reader.

Do the following:

1. **GGIR output** — look inside `data/processed/meting_1/` and `data/processed/meting_2/`. For each meting, check under `output_meting_N/results/` for:
    - `part2_daysummary.csv` — if present, report the number of rows (= participant-days)
    - `part4_nightsummary.csv` — if present, report the number of rows (= nights)
    - `part5_daysummary_WW_*.csv` — if present, report the number of rows
    - `part5_personsummary_WW_*.csv` — if present, report the number of rows (= participants)

2. **Segment labels** — check whether `data/processed/summaries/segment_summary.csv` exists. If it does, report how many rows it has and how many unique participants it covers.

3. **Analysis-ready data** — check whether `data/processed/summaries/analysis_ready.csv` and `data/processed/summaries/validity_summary.csv` exist. If so, report participant counts and how many meet validity criteria.

4. Based on what you find, report:
    - Which pipeline steps have completed (01_run_ggir, 02_label_segments, 03_build_summaries)
    - Approximately how many participants have been processed per meting
    - What is still missing or hasn't run
    - Whether the Shiny dashboard has enough output to open meaningfully

5. If nothing has run yet, explain clearly: open `r/pipeline/run_all.R` in RStudio and click Source — or run each step individually starting with `r/pipeline/01_run_ggir.R`.

If `data/processed/` does not exist at all, say so clearly — it means the pipeline hasn't been run yet.

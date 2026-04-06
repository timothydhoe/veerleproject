---
description: Check what has and hasn't been processed yet — which GGIR parts completed, how many participants, what's missing.
---

Check the current state of the pipeline. Write the report in plain language for a
non-technical reader.

Do the following:

1. Look inside `data/processed/ggir/results/` for output files. For each of the
   following, note whether it exists and (if it's a CSV) how many rows it contains:
    - `part2_daysummary.csv`
    - `part4_nightsummary.csv`
    - `part5_daysummary.csv`

2. Look inside `data/processed/ggir/meta/` (or equivalent GGIR milestone folders) to see
   which participant files have been processed.

3. Based on what you find, report:
    - Which pipeline stages have completed
    - Approximately how many participants have been processed
    - What is still missing or hasn't run
    - Whether the Shiny dashboard has enough output to open meaningfully

4. If nothing has run yet, explain in one clear sentence what to do: open
   `r/pipeline/01_run_ggir.R` in RStudio and click Source.

If `data/processed/` does not exist at all, say so clearly — it means the pipeline
hasn't been run yet.

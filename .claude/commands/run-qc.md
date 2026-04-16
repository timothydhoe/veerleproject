---
description: Run the QC checks for one or all pipeline steps and summarize the results. Use after running a pipeline step to confirm its output is valid.
---

The user wants to run QC checks on the pipeline output.

$ARGUMENTS

If a specific step is mentioned (e.g. "step 1", "qc_01", "segments"), run only that QC script. Otherwise run all three in sequence.

Do the following:

1. **Determine which QC scripts to run** based on $ARGUMENTS:
    - Step 1 / GGIR output → `r/qc/qc_01_ggir.R`
    - Step 2 / segments → `r/qc/qc_02_segments.R`
    - Step 3 / summaries → `r/qc/qc_03_summaries.R`
    - No argument or "all" → run all three

2. **Run each script** using:
    ```
    cd r && Rscript --vanilla qc/qc_01_ggir.R
    ```
    (adjust filename per step)

3. **Interpret the output** in plain language:
    - Report how many PASS / WARN / FAIL items were found per step
    - Highlight any FAILs or WARNs with a plain explanation of what they mean
    - For fallback school warnings: explain that schools 3 and 4 use approximate schedules and results should be treated with caution until confirmed timetables arrive
    - If a QC script can't run (output files missing), explain which pipeline step needs to run first

4. **Conclude** with one of:
    - **All checks passed** — safe to continue to the next pipeline step
    - **Warnings only** — pipeline can continue but flag the issues to Veerle before sharing results
    - **Failures found** — stop and fix before proceeding; list exactly what needs to be done

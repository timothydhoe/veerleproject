# Prompt: Process 24h test data through both pipelines

Paste this into a new Claude Code conversation opened in the `veerleproject` directory.

---

## The prompt

```
I have two 24h test recordings from a single test subject in `data/raw/veerle_testdata/meting_1/`:

- `1001_left wrist_109488_2026-04-27 11-10-01.bin` — GENEActiv wrist accelerometer (.bin, raw 100 Hz)
- `73044_0000001002.cwa` — Axivity accelerometer (.cwa, raw)

Both config files and pipeline code have already been updated:
- .cwa/.bin support added to both pipelines (format detection + conditional GGIR calls)
- Validity criteria relaxed for single-day test data
- `config.yaml` points at the test data folder and uses the 2023 non-wear algorithm

I need you to run these files through BOTH pipelines and verify the output. Here's exactly what to do:

### Pipeline 1: project_1/

1. `cd` to `project_1/`
2. Update `config/pipeline_params.yaml`: set `input_dir` to `../data/raw/veerle_testdata/meting_1/`
3. Run: `Rscript R/pipeline/run_pipeline.R`
4. If the orchestrator fails (e.g. missing function), run step 02 directly:
   ```r
   source("R/pipeline/utils.R")
   source("R/pipeline/04_label_schedule.R")
   source("R/pipeline/02_run_ggir.R")
   params <- read_pipeline_params("config/pipeline_params.yaml")
   run_ggir("../data/raw/veerle_testdata/meting_1/", "data/processed/", params,
            schedule_path = "config/school_schedules.yaml", n_cores = 1)
   ```
5. Verify output: check that `data/processed/ggir/output_*/results/` contains `part2_daysummary.csv`, `part4_nightsummary_sleep_cleaned.csv`, and `part5_daysummary_WW_*.csv`

### Pipeline 2: r/

1. `cd` to `r/`
2. Verify `../config.yaml` has:
   - `paths.data_raw: "../data/raw/veerle_testdata"`
   - `dev.example_mode: false`
   - `dev.nonwear_approach: "2023"`
3. Run: `Rscript --vanilla pipeline/run_all.R`
   - This will process `meting_1/` (skips `meting_2/` since it doesn't exist)
   - GGIR will auto-detect .bin and .cwa formats and enable autocalibration
4. Verify output: check that `../data/processed/ggir/meting_1/output_*/results/` contains the same three files

### Important notes

- Processing will take ~15-30 minutes per pipeline (raw 100 Hz data through all 5 GGIR parts)
- The .bin filename has spaces — GGIR handles this but watch for path issues
- Pupil ID `73044` maps to school_7 which doesn't exist in schedules — context labels will be NA for that participant, which is fine for testing
- If GGIR throws errors about GGIRread not being installed, run `install.packages("GGIRread")` first
- After processing, show me the first few rows of `part2_daysummary.csv` so I can verify the output structure

### After testing — rollback checklist

Before running on real study data, restore these values:

**config.yaml:**
- `paths.data_raw: "../data/raw"`
- `validity.min_wear_hours_per_day: 16`
- `validity.min_valid_days: 3`
- `validity.require_weekend_day: true`
- `validity.min_valid_nights_sleep: 5`
- `dev.example_mode: true` (or false for real data)
- `dev.nonwear_approach: "2013"` (for dummy CSV) or remove (for real .bin data)
- `dev.includedaycrit: 5` (for dummy) or remove (for real)

**project_1/config/pipeline_params.yaml:**
- `input_dir: "data/raw/"`
- `min_valid_days_waking: 4`
- `min_valid_hours_per_day: 9`
- `min_valid_nights_sleep: 5`
```

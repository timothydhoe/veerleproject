============================================================
 SchoolMove - Stap 1: Pipeline uitvoeren
============================================================

Dit verwerkt de data in data\raw\meting_1 en data\raw\meting_2.
Zorg dat je bestanden daar staan voor je verdergaat.

Dit kan 30-60 minuten duren voor de volledige dataset.
Sluit dit venster niet terwijl de pipeline draait.

Press any key to continue . . .
═══ SchoolMove Pipeline ══════════════════════════════════════════
Starting at: 2026-07-14 09:07:21

[config] Validation OK
[input] Found 4 files: 4 GGIR-compatible (2 .bin), 0 pre-processed
[input] Manifest written to: logs/input_manifest.csv

── Step 01: GGIR (Parts 1–5) ────────────────────────────────────
[profile] Loaded: 'default' from profiles//default.yaml
Using MANUAL qwindow from config.
Running on REAL DATA from: ../data/raw

── GGIR: meting_1 (2 files) ─────────────────────────
   input:  ../data/raw/meting_1
   output: ../data/processed/meting_1
   format: native (.bin/.cwa) — autocalibration ON

   GGIR version: 3.3.6

   << Please cite GGIR in your publications with doi: 10.5281/zenodo.1051064 >>

   [Note #2]
   To make your research reproducible and interpretable always report:
     (1) GGIR version
     (2) Accelerometer brand and product name
     (3) How you configured the accelerometer
     (4) Study protocol and wear instructions given to the participants
     (5) How GGIR was used: Share the config.csv file or your R script.
     (6) How you post-processed / cleaned GGIR output
     (7) How reported outcomes relate to the specific variable names in GGIR

________________________________________________________________________________
 Part 1

Checking that user has read access permission for all files in data directory: Yes
1
P1 file 1

Investigate calibration of the sensors with function g.calibrate:

Loading chunk: 1 2
Extract signal features (metrics) with the g.getmeta function:

Loading chunk: 1
Save .RData-file with: calibration report, file inspection report and all signal features...
2
P1 file 2

Investigate calibration of the sensors with function g.calibrate:

Loading chunk: 1 2 3
Extract signal features (metrics) with the g.getmeta function:

Loading chunk: 1 2
Save .RData-file with: calibration report, file inspection report and all signal features...

________________________________________________________________________________
 Part 2
1 2
________________________________________________________________________________
 Part 3
1 2
________________________________________________________________________________
 Part 4
 1 2
________________________________________________________________________________
 Part 5
1 2
________________________________________________________________________________
 Report part 2
 1 2
________________________________________________________________________________
 Report part 4
 loading all the milestone data from part 4 this can take a few minutes

part 4 cleaned report not stored, because no results available
________________________________________________________________________________
 Report part 5
 loading all the milestone data from part 5 this can take a few minutes
 generating csv report for every parameter configurations...
 MM-56.3-191.6-695.8-T5A5 Segments-56.3-191.6-695.8-T5A5
________________________________________________________________________________
 Generate visual reports
── Done: meting_1 ───────────────────────────────────────────────


── GGIR: meting_2 (2 files) ─────────────────────────
   input:  ../data/raw/meting_2
   output: ../data/processed/meting_2
   format: native (.bin/.cwa) — autocalibration ON

   GGIR version: 3.3.6

   << Please cite GGIR in your publications with doi: 10.5281/zenodo.1051064 >>

   [Note #2]
   To make your research reproducible and interpretable always report:
     (1) GGIR version
     (2) Accelerometer brand and product name
     (3) How you configured the accelerometer
     (4) Study protocol and wear instructions given to the participants
     (5) How GGIR was used: Share the config.csv file or your R script.
     (6) How you post-processed / cleaned GGIR output
     (7) How reported outcomes relate to the specific variable names in GGIR

________________________________________________________________________________
 Part 1

Checking that user has read access permission for all files in data directory: Yes
1
P1 file 1

Investigate calibration of the sensors with function g.calibrate:

Loading chunk: 1 2
Extract signal features (metrics) with the g.getmeta function:

Loading chunk: 1
Save .RData-file with: calibration report, file inspection report and all signal features...
2
P1 file 2

Investigate calibration of the sensors with function g.calibrate:

Loading chunk: 1 2 3
Extract signal features (metrics) with the g.getmeta function:

Loading chunk: 1 2
Save .RData-file with: calibration report, file inspection report and all signal features...

________________________________________________________________________________
 Part 2
1 2
________________________________________________________________________________
 Part 3
1 2
________________________________________________________________________________
 Part 4
 1 2
________________________________________________________________________________
 Part 5
1 2
________________________________________________________________________________
 Report part 2
 1 2
________________________________________________________________________________
 Report part 4
 loading all the milestone data from part 4 this can take a few minutes

part 4 cleaned report not stored, because no results available
________________________________________________________________________________
 Report part 5
 loading all the milestone data from part 5 this can take a few minutes
 generating csv report for every parameter configurations...
 MM-56.3-191.6-695.8-T5A5 Segments-56.3-191.6-695.8-T5A5
________________________________________________________________________________
 Generate visual reports
── Done: meting_2 ───────────────────────────────────────────────

Step 01 complete. Run qc/qc_01_ggir.R to verify outputs.
[repro] Archived GGIR config: logs/ggir_config_meting_1_20260714.csv
[repro] Archived GGIR config: logs/ggir_config_meting_2_20260714.csv
[repro] Run record appended to logs/pipeline_runs.csv

── Step 02: Segment labels ──────────────────────────────────────

Attaching package: 'data.table'

The following object is masked from 'package:base':

    %notin%

[profile] Loaded: 'default' from profiles//default.yaml
Using qwindow resolved from GGIR's own config.csv: 0, 8.5, 10, 12, 13, 15.5, 24
part5 Segments data loaded (16 window-rows, 2 participants) — using true per-window activity for segment estimates

Building segment schedule lookup...
Class overrides loaded for 13 pupils
Schedule cache built for 36 school × day combinations
Expanding part2 to segment-level summary...

Segment summary written: C:\SchoolMove_test\data\segment_summary.csv
  32 rows | 2 participants | 2 metingen

Step 02 complete. Run qc/qc_02_segments.R to verify outputs.
── Step 03: Build summaries ─────────────────────────────────────
[profile] Loaded: 'default' from profiles//default.yaml
Loading GGIR outputs...
[utils_ggir] Part 4 sleep: part4_nightsummary_sleep_full.csv (QC/)
[utils_ggir] Part 4 sleep: part4_nightsummary_sleep_full.csv (QC/)
Loading segment summary...
Computing validity flags...
Sleep validity: ≥50% valid-data threshold, ≥5 nights required
[WARN] labeled_epochs.csv not found — context-aware bout columns will be NA.
  Epoch-level school context labeling is not yet implemented (see comment above).
Joining tables...

Outputs written:
  C:\SchoolMove_test\data\analysis_ready.csv
  C:\SchoolMove_test\data\validity_summary.csv

Validity summary: 0 / 4 participants meet sedentary criteria (0%)

Step 03 complete. Run qc/qc_03_summaries.R to verify outputs.
The Shiny dashboard is now ready: shiny::runApp('shiny')

═══ Pipeline complete ════════════════════════════════════════════
Total time: 135 s

Next steps:
  Verify:   source('qc/qc_01_ggir.R')
            source('qc/qc_02_segments.R')
            source('qc/qc_03_summaries.R')
  Dashboard: shiny::runApp('shiny')
Warning message:
In write_input_manifest(data_dirs = list(meting_1 = file.path(raw_base,  :
  [input] 2 file(s) have a school ID that doesn't match any configured school (1, 2, 3, 4, 5, 6):
  73044_0000001002.cwa -> pupil_id=73044, school_id=7
  73044_0000001002.cwa -> pupil_id=73044, school_id=7
  These participants will get school_NA / outside_school segments later in the pipeline — check the filename/ID convention now if this is unexpected.

============================================================
 Klaar. Start nu "2 - Dashboard starten.bat" om de
 resultaten te bekijken.
============================================================
Press any key to continue . . .
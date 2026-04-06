---
description: Validate config.yaml — check syntax, missing fields, fallback schedules, and open blockers. Written for non-technical users.
---

Read `config.yaml` at the repository root and perform a full validation. Write the report for an academic researcher, not a developer — no jargon, plain sentences.

Check the following:

1. **Syntax** — is the file valid YAML? (If broken, stop here and explain what to fix.)
2. **Required sections** — are `paths`, `ggir`, `validity`, `measurements`, `schedules`, and `output` all present?
3. **Cut-points** — are activity thresholds (`cut_points_mg`) configured? If not, explain that the pipeline can run but activity classification (SB/LPA/MVPA) will be incomplete until Veerle confirms the values.
4. **School schedules** — list any schools marked `fallback: true` by name. Explain what that means: their timetable is approximate and results for those schools should be treated with caution.
5. **Measurement dates** — do all 6 schools have dates for both `meting_1` and `meting_2`? Do start dates come before end dates?
6. **Data paths** — do the folders referenced under `paths` actually exist on disk? Note which ones are missing (this is normal for `data/raw/` before data arrives).

End with one of:
- **Ready to run** — all required settings are in place.
- **Not ready — [specific issue]** — what exactly needs to be filled in before the pipeline can run.

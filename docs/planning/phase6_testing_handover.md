# Phase 6 — Testing and Handover

> Validate the pipeline on real data, confirm with Tim, and deliver a production-ready system before the end of June 2026.

---

## Goal

Confirm that:
- The pipeline produces correct output on real GENEActiv files
- Output matches (or improves on) the existing system where comparable
- The dashboard works for a real researcher with real data
- The codebase is clean, documented, and reproducible from a fresh install

---

## Validation checklist

### Step 1 — Small real-data smoke test

Run the pipeline on 5–10 real pupil files (requesting a small sample from Veerle or Tim is sufficient). This catches format surprises before processing all 400 pupils.

- [ ] Pipeline runs end-to-end without errors on real `.bin` files
- [ ] ENMO values for 3 sample epochs match manual calculation
- [ ] Non-wear detection output matches the existing system's output for the same files
- [ ] Sleep onset/offset times are plausible (not at 3am or 11am)
- [ ] Context labels are correct for the school and day of the sample files

### Step 2 — Comparison with existing system

For the 5–10 sample pupils, compare key metrics between the new pipeline and Tim's existing system:

| Metric | Expected match |
|---|---|
| Mean ENMO per day | Within ±5 mg |
| Total sedentary minutes per school day | Within ±10 min |
| Sleep onset time | Within ±15 min |
| Non-wear episode count | Exact match |
| Validity flag (pass/fail) | Exact match |

Any systematic discrepancies must be investigated and resolved before the full run.

### Step 3 — Full 400-pupil run

- [ ] Pipeline completes without errors
- [ ] Validity report: document % of pupils passing each threshold
- [ ] Review distribution of activity totals — flag any statistical outliers for manual inspection
- [ ] Confirm that both meting 1 and meting 2 have processed correctly and can be compared
- [ ] File sizes and processing time are within acceptable limits (document both)

### Step 4 — Dashboard user acceptance test

Session with Veerle (1 hour, no developer present):

- [ ] Veerle can open the dashboard independently
- [ ] Veerle can navigate to her school's data and a specific pupil
- [ ] Veerle can interpret the activity summary chart without explanation
- [ ] Veerle can process all attendance flags for one school (confirm / override)
- [ ] Veerle can export the activity summary table as CSV
- [ ] Veerle's feedback is documented and actioned before handover

---

## Handover package

The handover package is a clean git repository with the following in place:

### Repository health

- [ ] `README.md` up to date with current installation instructions
- [ ] All analysis outputs reproducible from a fresh clone (no hardcoded paths, no local-only files)
- [ ] `renv.lock` committed — `renv::restore()` installs all R dependencies at the correct versions
- [ ] `requirements.txt` committed — `pip install -r requirements.txt` installs all Python dependencies
- [ ] No credentials, real pupil data, or large binary files committed to the repository

### Documentation

- [ ] User manual complete and exported to PDF
- [ ] Quick-start card printed and handed over
- [ ] Troubleshooting FAQ covers real issues encountered during testing
- [ ] All R functions have roxygen2 docs; all Python functions have docstrings
- [ ] `CHANGELOG.md` lists what was built in this project

### Code quality

- [ ] No commented-out code blocks (cleaned before handover)
- [ ] No hardcoded file paths (all paths from config or function arguments)
- [ ] Pipeline runs from a single entry point (`Rscript run_pipeline.R --help` works)
- [ ] Shiny app starts with `shiny::runApp("ui/")` and no errors in the R console

---

## Handover session agenda (1–2 hours with Tim)

1. Walk through the repository structure (15 min)
2. Run the pipeline on a fresh machine together (30 min)
3. Walk through the Shiny app modules (20 min)
4. Review the extensibility guide — how to add a new analysis module (15 min)
5. Q&A and open issues (15 min)

---

## Known limitations to document at handover

| Limitation | Notes |
|---|---|
| Schools 3 and 4 use fallback schedules | Update `config/school_schedules.yaml` when actual schedules are received |
| Attendance prediction is heuristic | Manual researcher review is required for all flagged days |
| 6-school sample too small for confirmatory cross-school statistics | School-level correlations (RQ4) are exploratory |
| Pipeline tested on GENEActiv model 1.1 only | Other models may have different header formats |
| No automated tests (unit tests) in v1 | Recommended addition for v2 if the project continues |

---

## Post-handover support

The following is in scope for a brief post-handover period (suggest 2 weeks):
- Bug fixes for issues discovered during the first real-data analysis
- Clarifications on how to run or interpret the pipeline

The following is out of scope after handover:
- New analysis modules or research questions
- Changes to the dashboard layout
- Processing data from additional schools or studies

---

## Final deadline

All deliverables handed over by **end of June 2026**.

| Milestone | Target date |
|---|---|
| Phase 1 complete (dummy data ready) | Week 2 |
| Phase 2 complete (GGIR pipeline on dummy data) | Week 5 |
| Phase 3 complete (all analysis modules) | Week 8 |
| Phase 4 complete (dashboard, user-tested) | Week 10 |
| Phase 5 complete (manual + docs) | Week 11 |
| Phase 6 complete (real data validated, handover done) | End of June 2026 |

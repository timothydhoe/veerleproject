# qc_03_summaries.R
# ─────────────────────────────────────────────────────────────────────────────
# QC check after running 03_build_summaries.R.
#
# Verifies analysis_ready.csv and validity_summary.csv: participant counts,
# inclusion rates, activity distributions, cut-point confirmation.
#
# Run from r/ directory:  Rscript --vanilla qc/qc_03_summaries.R
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

cfg      <- yaml::read_yaml("../config.yaml")
out_dir  <- file.path(cfg$paths$data_processed, "summaries")

pass  <- function(msg) cat(sprintf("  [PASS] %s\n", msg))
warn  <- function(msg) cat(sprintf("  [WARN] %s\n", msg))
fail  <- function(msg) cat(sprintf("  [FAIL] %s\n", msg))

cat("\n── QC 03: Analysis-Ready Summaries ──────────────────────────────\n")

# ── 1. Files exist ────────────────────────────────────────────────────────────
ready_path    <- file.path(out_dir, "analysis_ready.csv")
validity_path <- file.path(out_dir, "validity_summary.csv")

for (fpath in c(ready_path, validity_path)) {
  if (!file.exists(fpath)) {
    fail(paste(basename(fpath), "not found:", fpath))
    fail("Run pipeline/03_build_summaries.R first.")
  } else {
    pass(paste(basename(fpath), "found"))
  }
}

if (!file.exists(ready_path) || !file.exists(validity_path)) quit(status = 1)

ar  <- fread(ready_path,    data.table = TRUE)
val <- fread(validity_path, data.table = TRUE)

# ── 2. Participant counts ─────────────────────────────────────────────────────
cat("\n  Participant counts:\n")
for (meting in sort(unique(ar$meting))) {
  n_total    <- nrow(val[meting == get("meting")])
  n_included <- sum(val[meting == get("meting")]$meets_sedentary_criteria, na.rm = TRUE)
  pct        <- round(100 * n_included / max(n_total, 1), 1)
  cat(sprintf("    %-12s %3d participants | %3d included (%s%%)\n",
              meting, n_total, n_included, pct))

  if (pct < 50) {
    warn(sprintf("%s: only %.0f%% of participants meet validity criteria — check wear compliance", meting, pct))
  } else {
    pass(sprintf("%s: %.0f%% inclusion rate", meting, pct))
  }
}

# Per-school breakdown
cat("\n  Inclusion by school:\n")
school_summary <- val[
  , .(n = .N, n_included = sum(meets_sedentary_criteria, na.rm = TRUE)),
  by = .(school, meting)
][order(school, meting)]

for (i in seq_len(nrow(school_summary))) {
  r   <- school_summary[i]
  pct <- round(100 * r$n_included / max(r$n, 1), 1)
  cat(sprintf("    %-12s %-12s %3d / %3d  (%s%%)\n",
              r$school, r$meting, r$n_included, r$n, pct))
}

# ── 3. Exclusion reasons ──────────────────────────────────────────────────────
if ("exclusion_reason" %in% names(val)) {
  excluded <- val[!is.na(exclusion_reason)]
  if (nrow(excluded) > 0) {
    cat("\n  Exclusion reasons:\n")
    reason_counts <- excluded[, .N, by = exclusion_reason][order(-N)]
    for (i in seq_len(nrow(reason_counts))) {
      cat(sprintf("    %3d × %s\n", reason_counts$N[i], reason_counts$exclusion_reason[i]))
    }
  }
}

# ── 4. MVPA distribution check ───────────────────────────────────────────────
mvpa_col <- grep("mvpa", names(ar), value = TRUE, ignore.case = TRUE)
if (length(mvpa_col) > 0) {
  mvpa <- ar[meets_sedentary_criteria == TRUE, get(mvpa_col[1])]
  mvpa <- mvpa[!is.na(mvpa)]
  if (length(mvpa) > 0) {
    cat(sprintf("\n  MVPA (valid participants, min/day): median=%.0f | IQR=%.0f–%.0f | max=%.0f\n",
                median(mvpa), quantile(mvpa, 0.25), quantile(mvpa, 0.75), max(mvpa)))
    if (median(mvpa) == 0) {
      warn("Median MVPA is 0 — check cut-point values or activity classification")
    } else if (median(mvpa) > 120) {
      warn(sprintf("Median MVPA of %.0f min/day seems high — verify cut-points", median(mvpa)))
    } else {
      pass(sprintf("MVPA distribution looks plausible (median %.0f min/day)", median(mvpa)))
    }
  } else {
    warn("No MVPA values in valid participants — activity columns may be missing")
  }
} else {
  warn("No MVPA column found in analysis_ready.csv — check part5 output")
}

# ── 5. Sleep check ────────────────────────────────────────────────────────────
sleep_col <- grep("sleep_duration", names(ar), value = TRUE)
if (length(sleep_col) > 0) {
  sleep_h <- ar[meets_sedentary_criteria == TRUE, get(sleep_col[1])]
  sleep_h <- sleep_h[!is.na(sleep_h)]
  if (length(sleep_h) > 0) {
    cat(sprintf("  Sleep duration (h): median=%.1f | range=%.1f–%.1f\n",
                median(sleep_h), min(sleep_h), max(sleep_h)))
    if (median(sleep_h) < 6 || median(sleep_h) > 12) {
      warn(sprintf("Median sleep %.1f h seems unusual for schoolchildren — check part4", median(sleep_h)))
    } else {
      pass(sprintf("Sleep duration plausible (median %.1f h)", median(sleep_h)))
    }
  }
} else {
  warn("No sleep duration column found — part4 output may be missing")
}

# ── 6. Cut-points match config ────────────────────────────────────────────────
cp <- cfg$ggir$cut_points_mg
if (is.null(cp$sedentary_to_light) || is.null(cp$light_to_moderate) || is.null(cp$moderate_to_vigorous)) {
  warn("Cut-points not configured in config.yaml — activity classification may be incorrect")
} else {
  pass(sprintf("Cut-points in config: SB/LPA=%.1f | LPA/MPA=%.1f | MPA/VPA=%.1f mg",
               cp$sedentary_to_light, cp$light_to_moderate, cp$moderate_to_vigorous))
}

# ── 7. Fallback school warning ────────────────────────────────────────────────
fallback_schools <- names(Filter(function(s) isTRUE(s$fallback), cfg$schedules))
if (length(fallback_schools) > 0) {
  warn(paste("Fallback schedules still in use for:", paste(fallback_schools, collapse = ", ")))
  warn("Segment-level results for these schools should be treated with caution.")
}

# ── Summary ───────────────────────────────────────────────────────────────────
cat("\n── QC 03 Complete ───────────────────────────────────────────────\n")
cat("  The Shiny dashboard can now be launched: shiny::runApp('shiny')\n")
cat("  Or run /run-qc for a plain-language interpretation.\n")

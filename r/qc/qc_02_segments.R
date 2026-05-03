# qc_02_segments.R
# ─────────────────────────────────────────────────────────────────────────────
# QC check after running 02_label_segments.R.
#
# Verifies segment_summary.csv: coverage, label distribution, fallback warnings.
#
# Run from r/ directory:  Rscript --vanilla qc/qc_02_segments.R
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

cfg      <- yaml::read_yaml("../config.yaml")
out_path <- file.path(cfg$paths$data_processed, "..", "segment_summary.csv")

pass  <- function(msg) cat(sprintf("  [PASS] %s\n", msg))
warn  <- function(msg) cat(sprintf("  [WARN] %s\n", msg))
fail  <- function(msg) cat(sprintf("  [FAIL] %s\n", msg))

cat("\n── QC 02: Segment Labels ─────────────────────────────────────────\n")

# ── 1. File exists ────────────────────────────────────────────────────────────
if (!file.exists(out_path)) {
  fail(paste("segment_summary.csv not found:", out_path))
  fail("Run pipeline/02_label_segments.R first.")
  quit(status = 1)
}
pass(paste("segment_summary.csv found:", out_path))

seg <- fread(out_path, data.table = TRUE)

# ── 2. Basic structure ────────────────────────────────────────────────────────
required_cols <- c("ID", "school", "meting", "weekday", "segment", "duration_h")
missing_cols  <- setdiff(required_cols, names(seg))
if (length(missing_cols) > 0) {
  fail(paste("Missing columns:", paste(missing_cols, collapse = ", ")))
} else {
  pass(paste("Required columns present:", paste(required_cols, collapse = ", ")))
}

# ── 3. Participant counts ─────────────────────────────────────────────────────
n_participants <- uniqueN(seg$ID)
n_metingen     <- uniqueN(seg$meting)
n_schools      <- uniqueN(seg$school)
cat(sprintf("  [INFO] %d participants × %d metingen × %d schools\n",
            n_participants, n_metingen, n_schools))

# ── 4. Segment distribution ───────────────────────────────────────────────────
cat("\n  Segment distribution (school days only):\n")
school_days <- seg[!weekday %in% c("Saturday", "Sunday") & segment != "weekend"]
if (nrow(school_days) > 0) {
  seg_dist <- school_days[, .(n_rows = .N, total_h = sum(duration_h, na.rm = TRUE)),
                           by = segment][order(-total_h)]
  for (i in seq_len(nrow(seg_dist))) {
    cat(sprintf("    %-20s %5d rows | %.1f h total\n",
                seg_dist$segment[i], seg_dist$n_rows[i], seg_dist$total_h[i]))
  }

  # Warn if any expected segment is completely missing
  expected_segments <- c("before_school", "in_class", "recess", "lunch", "after_school")
  missing_segs <- setdiff(expected_segments, school_days$segment)
  if (length(missing_segs) > 0) {
    warn(paste("Missing segments:", paste(missing_segs, collapse = ", "),
               "— check school schedule in config.yaml"))
  } else {
    pass("All expected segments present (before_school, in_class, recess, lunch, after_school)")
  }
} else {
  warn("No school day rows found — check that weekday column is populated")
}

# ── 5. Fallback schools ───────────────────────────────────────────────────────
fallback_schools <- names(Filter(function(s) isTRUE(s$fallback), cfg$schedules))
if (length(fallback_schools) > 0) {
  warn(paste("Fallback schedules (unconfirmed timetables):",
             paste(fallback_schools, collapse = ", ")))
  warn("Results for these schools use approximate bell times — treat with caution.")
} else {
  pass("All school schedules confirmed (no fallback flags)")
}

# ── 6. Missing-school check ───────────────────────────────────────────────────
config_schools <- names(cfg$schedules)
data_schools   <- unique(seg$school)
no_schedule    <- setdiff(data_schools, config_schools)
if (length(no_schedule) > 0) {
  warn(paste("Participants found with no schedule in config.yaml:",
             paste(no_schedule, collapse = ", ")))
} else {
  pass("All participant school IDs match config.yaml schedules")
}

# ── 7. Suspiciously low in-class coverage ─────────────────────────────────────
# Flag participants with < 2 h of in_class time on school days
if ("in_class" %in% seg$segment) {
  in_class_per_id <- seg[segment == "in_class",
                          .(in_class_h = sum(duration_h, na.rm = TRUE)),
                          by = .(ID, meting)]
  low_coverage <- in_class_per_id[in_class_h < 2]
  if (nrow(low_coverage) > 0) {
    warn(sprintf("%d participant-metingen have < 2 h of in_class time (possible absence or non-wear)",
                 nrow(low_coverage)))
    cat(sprintf("    First few: %s\n",
                paste(head(paste(low_coverage$ID, low_coverage$meting), 5), collapse = ", ")))
  } else {
    pass("All participants have ≥ 2 h of in_class time on school days")
  }
}

# ── 8. Absence rows ───────────────────────────────────────────────────────────
if ("absent" %in% seg$segment) {
  absent_rows <- seg[segment == "absent"]
  n_combos    <- uniqueN(paste(absent_rows$ID, absent_rows$date))
  schools_abs <- paste(sort(unique(absent_rows$school)), collapse = ", ")
  pass(sprintf("%d absent (pupil × date) combinations registered — schools: %s",
               n_combos, schools_abs))
} else {
  abs_path <- file.path(cfg$paths$data_processed, "..", "..", "data", "absences.csv")
  if (file.exists(abs_path)) {
    abs_dt <- tryCatch(fread(abs_path), error = function(e) NULL)
    if (!is.null(abs_dt) && nrow(abs_dt) > 0)
      warn("absences.csv has rows but no 'absent' segments found — re-run step 02")
    else
      pass("No absences registered (absences.csv is empty)")
  } else {
    pass("No absences registered")
  }
}

# ── Summary ───────────────────────────────────────────────────────────────────
cat("\n── QC 02 Summary ────────────────────────────────────────────────\n")
cat("  Next step: run pipeline/03_build_summaries.R\n")
cat("  Or run /run-qc to get a plain-language interpretation.\n")

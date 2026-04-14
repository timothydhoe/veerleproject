# qc_01_ggir.R
# ─────────────────────────────────────────────────────────────────────────────
# QC check after running 01_run_ggir.R.
#
# Verifies that GGIR produced the expected output files for both metingen,
# checks column structure, and reports participant counts.
#
# Run from r/ directory:  Rscript --vanilla qc/qc_01_ggir.R
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

source("pipeline/utils_ggir.R", local = TRUE)

cfg         <- yaml::read_yaml("../config.yaml")
base_out    <- cfg$paths$data_processed
metingen    <- c("meting_1", "meting_2")

pass  <- function(msg) cat(sprintf("  [PASS] %s\n", msg))
warn  <- function(msg) cat(sprintf("  [WARN] %s\n", msg))
fail  <- function(msg) cat(sprintf("  [FAIL] %s\n", msg))

results <- list()  # collect pass/warn/fail counts per meting

for (meting in metingen) {

  cat(sprintf("\n── %s ────────────────────────────────────────────────────\n", meting))

  results_dir <- find_ggir_results_dir(file.path(base_out, meting))

  # ── 1. Results directory exists ────────────────────────────────────────────
  if (is.null(results_dir) || !dir.exists(results_dir)) {
    fail(paste("Results directory not found under:", file.path(base_out, meting)))
    fail("Run pipeline/01_run_ggir.R first.")
    results[[meting]] <- "FAIL"
    next
  }
  pass(paste("Results directory exists:", results_dir))

  # ── 2. Required output files ────────────────────────────────────────────────
  # part2: exact name
  part2_path <- file.path(results_dir, "part2_daysummary.csv")
  if (!file.exists(part2_path)) {
    fail("part2_daysummary.csv not found")
  } else {
    dt <- tryCatch(fread(part2_path, data.table = TRUE), error = function(e) NULL)
    if (is.null(dt)) {
      fail("part2_daysummary.csv exists but could not be read")
    } else {
      pass(sprintf("part2_daysummary.csv — %d rows, %d columns", nrow(dt), ncol(dt)))
    }
  }

  # part4: name varies by GGIR version (≥2.6 uses *_sleep_cleaned.csv)
  part4_files <- list.files(results_dir, pattern = "^part4.*\\.csv$", full.names = TRUE)
  if (length(part4_files) == 0) {
    fail("part4 nightsummary CSV not found (expected ^part4.*\\.csv)")
  } else {
    dt4 <- tryCatch(fread(part4_files[1], data.table = TRUE), error = function(e) NULL)
    if (is.null(dt4)) {
      fail(paste(basename(part4_files[1]), "exists but could not be read"))
    } else {
      pass(sprintf("%s — %d rows, %d columns", basename(part4_files[1]), nrow(dt4), ncol(dt4)))
    }
  }

  # Part 5 uses a dynamic filename — search by pattern
  part5_files <- list.files(results_dir, pattern = "^part5_daysummary_WW_", full.names = TRUE)
  part5_pers  <- list.files(results_dir, pattern = "^part5_personsummary_WW_", full.names = TRUE)

  if (length(part5_files) == 0) {
    fail("part5_daysummary_WW_*.csv not found")
  } else {
    dt5 <- tryCatch(fread(part5_files[1], data.table = TRUE), error = function(e) NULL)
    if (is.null(dt5)) {
      fail(paste(basename(part5_files[1]), "exists but could not be read"))
    } else {
      pass(sprintf("%s — %d rows", basename(part5_files[1]), nrow(dt5)))
    }
  }

  if (length(part5_pers) == 0) {
    warn("part5_personsummary_WW_*.csv not found (may appear after more participants are processed)")
  } else {
    dtp <- tryCatch(fread(part5_pers[1], data.table = TRUE), error = function(e) NULL)
    if (!is.null(dtp)) {
      pass(sprintf("%s — %d participants", basename(part5_pers[1]), nrow(dtp)))
    }
  }

  # ── 3. Column checks (part2) ────────────────────────────────────────────────
  part2_path <- file.path(results_dir, "part2_daysummary.csv")
  if (file.exists(part2_path)) {
    part2 <- fread(part2_path, data.table = TRUE)

    # Wear time columns
    wear_cols <- c("N valid hours", "N hours")
    missing_wear <- setdiff(wear_cols, names(part2))
    if (length(missing_wear) > 0) {
      warn(paste("part2: missing expected columns:", paste(missing_wear, collapse = ", ")))
    } else {
      pass("part2: wear time columns present (N valid hours, N hours)")
    }

    # Activity intensity columns
    # GGIR uses various naming conventions — check for common variants
    has_activity <- any(grepl("^(SB|IN|LIG|MOD|VIG|MVPA)", names(part2), ignore.case = TRUE))
    if (!has_activity) {
      warn("part2: no activity intensity columns detected (SB/LIG/MOD/VIG) — check GGIR output")
    } else {
      activity_cols <- grep("^(SB|IN|LIG|MOD|VIG|MVPA)", names(part2), value = TRUE, ignore.case = TRUE)
      pass(paste("part2: activity columns found:", paste(head(activity_cols, 6), collapse = ", ")))
    }

    # Participant count
    n_participants <- uniqueN(part2$ID)
    n_days         <- nrow(part2)
    mean_days      <- round(n_days / max(n_participants, 1), 1)
    cat(sprintf("  [INFO] %d participants × %.1f days avg = %d participant-days\n",
                n_participants, mean_days, n_days))

    # Wear time distribution
    if ("N valid hours" %in% names(part2)) {
      setnames(part2, "N valid hours", "n_valid_hours")
      min_wear <- if (isTRUE(cfg$dev$example_mode) && !is.null(cfg$dev$includedaycrit)) {
        cfg$dev$includedaycrit
      } else {
        cfg$validity$min_wear_hours_per_day
      }
      pct_valid <- round(100 * mean(part2$n_valid_hours >= min_wear, na.rm = TRUE), 1)
      cat(sprintf("  [INFO] %.1f%% of days meet ≥%d h validity threshold\n", pct_valid, min_wear))
      if (pct_valid < 30) {
        warn(sprintf("Only %.1f%% valid days — check non-wear settings or data quality", pct_valid))
      }
    }
  }

  # ── 4. Cut-point values match config ───────────────────────────────────────
  cp <- cfg$ggir$cut_points_mg
  if (is.null(cp$sedentary_to_light) || is.null(cp$light_to_moderate) || is.null(cp$moderate_to_vigorous)) {
    warn("Cut-points not set in config.yaml — activity classification is incomplete")
  } else {
    pass(sprintf("Cut-points configured: SB/LPA=%.1f | LPA/MPA=%.1f | MPA/VPA=%.1f mg",
                 cp$sedentary_to_light, cp$light_to_moderate, cp$moderate_to_vigorous))
  }

  results[[meting]] <- "OK"
}

# ── Summary ───────────────────────────────────────────────────────────────────
cat("\n── QC 01 Summary ────────────────────────────────────────────────\n")
for (meting in names(results)) {
  cat(sprintf("  %s: %s\n", meting, results[[meting]]))
}
cat("\nNext step: run pipeline/02_label_segments.R\n")
cat("Or run /run-qc to get a plain-language interpretation.\n")

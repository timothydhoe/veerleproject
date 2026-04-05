# =============================================================================
# SchoolMoves Pipeline — Test Script
# =============================================================================
# Exercises the pipeline using example and real data files.
# Run from the project_1/ directory:
#   Rscript test_with_example.R
# =============================================================================

cat("=== SchoolMoves Pipeline Tests ===\n\n")

# Source all pipeline modules
source("R/pipeline/utils.R")
source("R/pipeline/01_convert.R")
source("R/pipeline/02_ggir_process.R")
source("R/pipeline/03_classify_activity.R")
source("R/pipeline/04_label_schedule.R")
source("R/pipeline/05_filter_validity.R")
source("R/pipeline/06_export.R")

# Source analysis modules
source("R/analysis/activity_totals.R")
source("R/analysis/sedentary_bouts.R")
source("R/analysis/sleep_analysis.R")
source("R/analysis/school_correlations.R")

# Test output directory
test_output <- tempdir()
test_errors <- 0

assert <- function(condition, msg) {
  if (!condition) {
    cat("  FAIL:", msg, "\n")
    test_errors <<- test_errors + 1
  } else {
    cat("  OK:", msg, "\n")
  }
}

# =============================================================================
# TEST 1: Format A — GENEActiv direct export CSV
# =============================================================================
cat("\n--- Test 1: Format A (GENEActiv export) ---\n")

format_a_path <- "../data/example/Fictief voorbeeld data.csv"

if (file.exists(format_a_path)) {
  # Test format detection
  fmt <- detect_format(format_a_path)
  assert(fmt == "geneactiv_export",
         paste("Format detection: expected 'geneactiv_export', got", fmt))

  # Test single file conversion
  out_dir_a <- file.path(test_output, "test_format_a")
  log_entry <- convert_single_file(format_a_path, out_dir_a, overwrite = TRUE)

  assert(log_entry$status == "success",
         paste("Conversion status:", log_entry$status, log_entry$message))
  assert(log_entry$detected_format == "geneactiv_export",
         paste("Detected format:", log_entry$detected_format))
  assert(log_entry$pupil_id == "4001",
         paste("Pupil ID: expected '4001', got", log_entry$pupil_id))

  # Read back and check columns
  out_file <- file.path(out_dir_a, "4001.csv")
  if (file.exists(out_file)) {
    df_a <- read.csv(out_file, stringsAsFactors = FALSE)
    expected_cols <- c("pupil_id", "timestamp", "x", "y", "z",
                       "light", "temperature", "svmg", "x_std", "y_std", "z_std")
    assert(all(expected_cols %in% names(df_a)),
           paste("Standard columns present:", paste(names(df_a), collapse = ", ")))
    assert(all(df_a$pupil_id == "4001"), "All rows have pupil_id = '4001'")
    assert(nrow(df_a) > 0, paste("Data rows:", nrow(df_a)))
  } else {
    assert(FALSE, "Output file not created")
  }
} else {
  cat("  SKIP: Format A test file not found at", format_a_path, "\n")
}

# =============================================================================
# TEST 2: Format B — Tim's pre-processed CSVs
# =============================================================================
cat("\n--- Test 2: Format B (Tim's preprocessed) ---\n")

format_b_dir <- "../data/raw/GENEActiv/12615468/"

if (dir.exists(format_b_dir)) {
  # Get first 3 CSV files (not the R script)
  all_csvs <- list.files(format_b_dir, pattern = "\\.csv$", full.names = TRUE)
  all_csvs <- all_csvs[!grepl("\\.R$", all_csvs, ignore.case = TRUE)]
  test_csvs <- head(all_csvs, 3)

  if (length(test_csvs) > 0) {
    for (csv_path in test_csvs) {
      fname <- basename(csv_path)
      fmt <- detect_format(csv_path)
      assert(fmt == "tim_preprocessed",
             paste(fname, "-> format:", fmt))

      expected_pid <- strsplit(fname, "_")[[1]][1]
      out_dir_b <- file.path(test_output, "test_format_b")
      log_entry <- convert_single_file(csv_path, out_dir_b, overwrite = TRUE)

      assert(log_entry$pupil_id == expected_pid,
             paste(fname, "-> pupil_id:", log_entry$pupil_id, "(expected", expected_pid, ")"))
      assert(log_entry$status == "success",
             paste(fname, "-> status:", log_entry$status))
    }
  } else {
    cat("  SKIP: No CSV files found in", format_b_dir, "\n")
  }
} else {
  cat("  SKIP: Format B directory not found at", format_b_dir, "\n")
}

# =============================================================================
# TEST 3: Format C — Raw .bin (COMMENTED OUT — needs real .bin file)
# =============================================================================
cat("\n--- Test 3: Format C (raw .bin) ---\n")
cat("  SKIP: No .bin files available for testing.\n")
cat("  To test, uncomment below and provide a .bin file path:\n")
# format_c_path <- "../data/raw/some_file.bin"
# if (file.exists(format_c_path)) {
#   fmt <- detect_format(format_c_path)
#   assert(fmt == "raw_bin", paste("Format detection:", fmt))
#   out_dir_c <- file.path(test_output, "test_format_c")
#   log_entry <- convert_single_file(format_c_path, out_dir_c, overwrite = TRUE)
#   assert(log_entry$status == "success", paste("Conversion:", log_entry$status))
# }

# =============================================================================
# TEST 4: Downstream pipeline — classify, label, validate
# =============================================================================
cat("\n--- Test 4: Downstream pipeline (classify -> label -> validate) ---\n")

# Use Format A output for downstream tests
out_file_a <- file.path(test_output, "test_format_a", "4001.csv")
if (file.exists(out_file_a)) {
  # Load config
  params <- read_pipeline_params("config/pipeline_params.yaml")

  # Run bypass to get epoch data
  bypass_dir <- file.path(test_output, "test_format_a")
  epochs <- run_bypass(bypass_dir, params)

  assert(nrow(epochs) > 0, paste("Bypass loaded", nrow(epochs), "epochs"))
  assert("enmo_mg" %in% names(epochs), "enmo_mg column present")

  # Classify intensity
  thresholds <- build_thresholds(params)
  epochs <- classify_intensity(epochs, thresholds)
  assert("intensity" %in% names(epochs), "intensity column added")
  assert(all(levels(epochs$intensity) == c("sedentary", "light", "moderate", "vigorous")),
         "Intensity levels correct")

  # Label school context
  epochs <- label_school_context(epochs, "config/school_schedules.yaml")
  assert("context" %in% names(epochs), "context column added")
  assert("schedule_source" %in% names(epochs), "schedule_source column added")

  # Add school_id if not present
  if (!"school_id" %in% names(epochs)) {
    epochs$school_id <- as.integer(substr(epochs$pupil_id, 1, 1))
  }

  # Assess validity
  validity <- assess_validity(epochs, params)
  assert(nrow(validity) > 0, paste("Validity assessed for", nrow(validity), "pupils"))
  assert(all(c("pupil_valid_sedentary", "pupil_valid_sleep") %in% names(validity)),
         "Validity columns present")

  # Print summary
  cat("\n  Epoch summary:\n")
  cat("    Total epochs:", nrow(epochs), "\n")
  cat("    Intensity distribution:\n")
  print(table(epochs$intensity))
  cat("    Context distribution:\n")
  print(table(epochs$context))
  cat("    Validity:\n")
  print(validity[, c("pupil_id", "n_valid_days", "n_valid_nights",
                      "pupil_valid_sedentary", "pupil_valid_sleep")])

} else {
  cat("  SKIP: No Format A output available for downstream tests\n")
}

# =============================================================================
# TEST 5: Analysis modules
# =============================================================================
cat("\n--- Test 5: Analysis modules ---\n")

if (exists("epochs") && nrow(epochs) > 0) {
  # Activity totals
  totals <- compute_activity_totals(epochs, valid_only = FALSE)
  assert(nrow(totals) > 0, paste("Activity totals:", nrow(totals), "rows"))
  assert(all(c("sedentary_min", "light_min", "moderate_min", "vigorous_min") %in% names(totals)),
         "Activity total columns present")

  cat("  Activity totals sample:\n")
  print(head(totals))

  # Bout detection (all intensities)
  bout_configs <- list(
    sedentary = params$bout_min_minutes$sedentary %||% 30,
    light     = params$bout_min_minutes$light %||% 10,
    moderate  = params$bout_min_minutes$moderate %||% 5,
    vigorous  = params$bout_min_minutes$vigorous %||% 5
  )
  all_bouts <- detect_all_bouts(epochs, bout_configs, valid_only = FALSE)
  cat("  Bout detection results:\n")
  if (nrow(all_bouts) > 0) {
    cat("    Bouts found by intensity:\n")
    print(table(all_bouts$intensity))
    cat("    Sample:\n")
    print(head(all_bouts))
  } else {
    cat("    No bouts detected (data may be too short for minimum bout durations)\n")
  }
  assert(is.data.frame(all_bouts), "Bout detection returns a data.frame")

} else {
  cat("  SKIP: No epoch data available for analysis tests\n")
}

# =============================================================================
# TEST 6: Cross-validation with old pipeline patterns (Format B)
# =============================================================================
cat("\n--- Test 6: Cross-validation (Format B — structural patterns) ---\n")

format_b_test_dir <- file.path(test_output, "test_format_b")
if (dir.exists(format_b_test_dir) && length(list.files(format_b_test_dir, "\\.csv$")) > 0) {
  params_cv <- read_pipeline_params("config/pipeline_params.yaml")
  epochs_b <- run_bypass(format_b_test_dir, params_cv)

  if (nrow(epochs_b) > 0) {
    thresholds_cv <- build_thresholds(params_cv)
    epochs_b <- classify_intensity(epochs_b, thresholds_cv)
    epochs_b <- label_school_context(epochs_b, "config/school_schedules.yaml")
    if (!"school_id" %in% names(epochs_b)) {
      epochs_b$school_id <- as.integer(substr(epochs_b$pupil_id, 1, 1))
    }

    cat("\n  Cross-validation summary:\n")

    # Daily observed time should be plausible
    daily <- epochs_b |>
      dplyr::group_by(pupil_id, date) |>
      dplyr::summarise(
        total_hours = dplyr::n() / 3600,
        wear_hours  = sum(wear) / 3600,
        .groups = "drop"
      )

    cat("  Daily total hours per pupil (should be ~20-24h if full day):\n")
    cat("    Mean:", round(mean(daily$total_hours), 1), "h\n")
    cat("    Range:", round(min(daily$total_hours), 1), "-",
        round(max(daily$total_hours), 1), "h\n")

    # Context distribution during weekdays
    weekday_epochs <- epochs_b[!epochs_b$context %in% c("weekend"), ]
    if (nrow(weekday_epochs) > 0) {
      ctx_dist <- table(weekday_epochs$context)
      cat("\n  Weekday context distribution (epoch counts):\n")
      print(ctx_dist)
    }

    # Sedentary during in-class should dominate
    if ("in_class" %in% epochs_b$context) {
      in_class <- epochs_b[epochs_b$context == "in_class", ]
      if (nrow(in_class) > 0) {
        in_class_int <- table(in_class$intensity)
        pct_sed <- round(in_class_int["sedentary"] / sum(in_class_int) * 100, 1)
        cat("\n  In-class intensity distribution:\n")
        print(in_class_int)
        cat("  Sedentary % in class:", pct_sed, "%\n")
        assert(pct_sed > 30,
               paste("In-class sedentary is plausible (>30%):", pct_sed, "%"))
      }
    }

    # Bout detection across intensities
    bout_configs_cv <- list(sedentary = 30, light = 10, moderate = 5, vigorous = 5)
    bouts_b <- detect_all_bouts(epochs_b, bout_configs_cv, valid_only = FALSE)
    cat("\n  Bout detection (all intensities):\n")
    if (nrow(bouts_b) > 0) {
      bout_summary <- bouts_b |>
        dplyr::group_by(intensity) |>
        dplyr::summarise(
          total_bouts = sum(n_bouts),
          mean_duration = round(mean(mean_bout_min), 1),
          .groups = "drop"
        )
      print(as.data.frame(bout_summary))

      # Check that bouts exist in different contexts (= splitting works)
      bout_contexts <- unique(bouts_b$context)
      cat("  Bouts found in contexts:", paste(bout_contexts, collapse = ", "), "\n")
    } else {
      cat("  No bouts detected\n")
    }
  }
} else {
  cat("  SKIP: No Format B converted files available\n")
}

# =============================================================================
# TEST 7: Conversion log
# =============================================================================
cat("\n--- Test 7: Conversion log ---\n")

log_path <- file.path(test_output, "logs", "conversion_log.csv")
# The convert_to_standard function writes logs relative to output_dir
# Check both possible locations
possible_logs <- c(
  file.path(test_output, "test_format_a", "..", "logs", "conversion_log.csv"),
  file.path(dirname(test_output), "logs", "conversion_log.csv"),
  "logs/conversion_log.csv"
)
log_found <- FALSE
for (lp in possible_logs) {
  if (file.exists(lp)) {
    log_df <- read.csv(lp)
    cat("  Conversion log found at:", lp, "\n")
    cat("  Entries:", nrow(log_df), "\n")
    print(log_df[, c("file", "detected_format", "pupil_id", "status")])
    log_found <- TRUE
    break
  }
}
if (!log_found) {
  cat("  Note: Conversion log not found (individual file tests don't write batch logs)\n")
}

# =============================================================================
# Summary
# =============================================================================
cat("\n", strrep("=", 50), "\n")
if (test_errors == 0) {
  cat("All checks passed.\n")
} else {
  cat("FAILURES:", test_errors, "test(s) failed.\n")
}
cat(strrep("=", 50), "\n")

# Return exit code for scripted use
if (test_errors > 0) quit(status = 1)

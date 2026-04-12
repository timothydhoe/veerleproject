# =============================================================================
# SchoolMoves Pipeline — Step 2: GGIR Processing
# =============================================================================
# Runs GGIR Parts 1-4 on standardised CSV files.
#
# For pre-processed CSVs that already contain SVMg values (Format A/B),
# a bypass path is available that skips GGIR and uses the existing SVMg
# directly as the ENMO proxy.
#
# ALTERNATIVE APPROACHES (for future investigation):
#   - GGIR alternative: the 'activityCounts' package can compute activity
#     counts from raw data, compatible with ActiGraph-based cut-points.
#   - GGIR alternative: the 'runact' package provides a simpler pipeline
#     for basic ENMO and non-wear detection without GGIR's full complexity.
#   - Custom approach: compute ENMO directly from x/y/z using the formula
#     ENMO = sqrt(x^2 + y^2 + z^2) - 1, then apply non-wear and sleep
#     detection separately. This avoids GGIR dependency entirely.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Build a GGIR configuration list from pipeline parameters
#'
#' @param params Named list from read_pipeline_params()
#' @return Named list of GGIR-compatible configuration values
build_ggir_config <- function(params) {
  list(
    windowsizes     = params$epoch_lengths,
    threshold.lig   = params$threshold_lig,
    threshold.mod   = params$threshold_mod,
    threshold.vig   = params$threshold_vig,
    do.cal          = params$do_calibration,
    acc.metric      = params$acc_metric,
    sensor.location = params$sensor_location,

    # Non-wear
    nonWearEdge   = params$nonwear_edge_min,
    nonWearWindow = params$nonwear_window_min,
    nonWearStd    = params$nonwear_std_mg,
    nonWearRange  = params$nonwear_range_mg,

    # Sleep
    anglethreshold = params$sleep_angle_threshold_deg,
    timethreshold  = params$sleep_time_threshold_min,
    ignorenonwear  = params$sleep_ignore_nonwear,

    # Output
    do.report      = c(2, 4),
    save_ms2       = TRUE,
    save_ms2summary = TRUE
  )
}

#' Run GGIR pipeline on standardised CSV files
#'
#' @param input_dir Path to directory with standardised CSVs (from 01_convert.R)
#' @param output_dir Path for GGIR output directory
#' @param params Named list from read_pipeline_params()
#' @param n_cores Number of parallel cores. Default 1.
#' @return Invisible path to GGIR output directory
run_ggir <- function(input_dir, output_dir, params, n_cores = 1) {
  if (!requireNamespace("GGIR", quietly = TRUE)) {
    stop("Package 'GGIR' is required for full pipeline processing.\n",
         "Install it with: install.packages('GGIR')\n",
         "Alternatively, use run_bypass() for pre-processed CSVs.")
  }

  ggir_config <- build_ggir_config(params)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  log_step("Starting GGIR processing")
  log_step(paste("Input:", input_dir))
  log_step(paste("Output:", output_dir))

  # GGIR::g.shell.GGIR is the main entry point for the full pipeline.
  # It runs Parts 1-5 depending on configuration.
  #
  # ALTERNATIVE: If GGIR proves too rigid, each Part can be called separately:
  #   GGIR::g.part1() for raw data reading and calibration
  #   GGIR::g.part2() for non-wear detection and basic metrics
  #   GGIR::g.part3() for sustained inactivity bout detection
  #   GGIR::g.part4() for sleep detection
  #   GGIR::g.part5() for summary reports

  GGIR::g.shell.GGIR(
    datadir          = input_dir,
    outputdir        = output_dir,
    mode             = c(1, 2, 3, 4),
    windowsizes      = ggir_config$windowsizes,
    threshold.lig    = ggir_config$threshold.lig,
    threshold.mod    = ggir_config$threshold.mod,
    threshold.vig    = ggir_config$threshold.vig,
    do.cal           = ggir_config$do.cal,
    acc.metric       = ggir_config$acc.metric,
    do.report        = ggir_config$do.report,
    do.parallel      = n_cores > 1,
    maxNcores        = n_cores,
    overwrite        = FALSE,
    desiredtz        = "Europe/Brussels"
  )

  log_step("GGIR processing complete")
  invisible(output_dir)
}

#' Bypass path: load pre-processed epoch data directly
#'
#' For files that already contain SVMg values (Format A/B), skip GGIR
#' and use SVMg as the ENMO proxy. This path handles:
#'   - Loading the standardised CSVs
#'   - Converting SVMg to milligravity (mg) units
#'   - Adding basic non-wear flags based on std dev thresholds
#'   - Returning an epoch-level data.frame ready for classification
#'
#' NOTE: This bypass does NOT perform auto-calibration or sleep detection.
#' Use run_ggir() for the full pipeline when raw .bin files are available.
#'
#' @param input_dir Path to directory with standardised CSVs
#' @param params Named list from read_pipeline_params()
#' @return data.frame with columns: pupil_id, timestamp, enmo_mg, wear, date
run_bypass <- function(input_dir, params) {
  csv_files <- list.files(input_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(csv_files) == 0) {
    stop("No CSV files found in: ", input_dir)
  }

  log_step(paste("Bypass mode: loading", length(csv_files), "standardised CSVs"))

  all_epochs <- lapply(csv_files, function(f) {
    df <- read.csv(f, stringsAsFactors = FALSE)

    # SVMg in the standardised format:
    #   Format A (GENEActiv export, 100 Hz): svmg = sum of per-sample abs(svm - 1)
    #   Format B (Tim's preprocessed, 60 Hz): svmg = sum of per-sample abs(svm - 1)
    #   Format C (.bin, variable Hz): svmg = sum of per-sample abs(svm - 1)
    #
    # To get mean ENMO in g per epoch, divide by recording frequency.
    # Since we lose frequency info after normalisation, we treat svmg as
    # a proportional ENMO metric. The values (typically 5-15 for sedentary)
    # are already in a mg-compatible range when used directly.
    #
    # For cut-point comparison: svmg values of ~5-15 map to sedentary,
    # ~50-200 to light/moderate, which aligns with the Hildebrand thresholds.
    enmo_mg <- df$svmg

    # Basic non-wear detection: flag epochs where all axis std devs are
    # below the threshold AND acceleration range is low
    nonwear_std_threshold <- params$nonwear_std_mg / 1000  # threshold in g for comparison with std columns
    wear <- !(df$x_std < nonwear_std_threshold &
              df$y_std < nonwear_std_threshold &
              df$z_std < nonwear_std_threshold)
    # Handle NA in std columns (treat as wear to be conservative)
    wear[is.na(wear)] <- TRUE

    ts <- as.POSIXct(df$timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "Europe/Brussels")
    if (all(is.na(ts))) {
      # Try alternative format with milliseconds
      ts <- as.POSIXct(df$timestamp, format = "%Y-%m-%d %H:%M:%S:%OS", tz = "Europe/Brussels")
    }

    data.frame(
      pupil_id  = df$pupil_id,
      timestamp = ts,
      enmo_mg   = enmo_mg,
      x         = df$x,
      y         = df$y,
      z         = df$z,
      wear      = wear,
      date      = as.Date(ts),
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, all_epochs)
  log_step(paste("Loaded", nrow(result), "epochs for",
                 length(unique(result$pupil_id)), "pupils"))

  # Clean up
  rm(all_epochs)
  gc()

  result
}

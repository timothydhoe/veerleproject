# =============================================================================
# SchoolMoves Pipeline — Step 2: Run GGIR (Parts 1-5)
# =============================================================================
# Official GGIR pipeline as the primary processing engine.
# Handles .bin and .csv files natively. Runs Parts 1-5:
#   Part 1: Load raw data, autocalibrate, compute ENMO + angle metrics
#   Part 2: Non-wear detection, cut-point classification, daily summaries
#   Part 3: Sustained inactivity bout detection (sleep candidates)
#   Part 4: Sleep period detection (HDCZA algorithm)
#   Part 5: Time-use analysis with day-segment breakdowns
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)
source("R/pipeline/04_label_schedule.R", local = TRUE)

#' Run the official GGIR pipeline (Parts 1-5)
#'
#' @param input_dir Path to directory with .bin or .csv files
#' @param output_dir Path for GGIR output
#' @param params Named list from read_pipeline_params()
#' @param schedule_path Path to school_schedules.yaml (for qwindow derivation)
#' @param n_cores Number of parallel cores. Default 1.
#' @return Invisible path to GGIR output directory
run_ggir <- function(input_dir, output_dir, params, schedule_path = NULL, n_cores = 1) {
  if (!requireNamespace("GGIR", quietly = TRUE)) {
    stop("Package 'GGIR' is required.\n",
         "Install it with: install.packages('GGIR')")
  }

  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # Determine qwindow
  qwindow <- c(0, 24)  # default: full day
  if (!is.null(params$qwindow_strategy) && params$qwindow_strategy == "auto") {
    if (!is.null(schedule_path) && file.exists(schedule_path)) {
      qwindow <- build_qwindow_from_schedules(schedule_path)
    } else {
      log_step("Warning: qwindow_strategy='auto' but no schedule file found. Using full-day window.")
    }
  }

  log_step("Starting GGIR pipeline (Parts 1-5)")
  log_step(paste("Input:", input_dir))
  log_step(paste("Output:", output_dir))
  log_step(paste("Cores:", n_cores))

  # Detect input format: .bin files use GGIR's native reader,
  # .csv files use read.myacc.csv with rmc.* parameters
  input_files <- list.files(input_dir, full.names = TRUE)
  has_bin <- any(grepl("\\.bin$", input_files, ignore.case = TRUE))
  has_cwa <- any(grepl("\\.cwa$", input_files, ignore.case = TRUE))
  has_csv <- any(grepl("\\.csv$", input_files, ignore.case = TRUE))

  # Base GGIR arguments
  ggir_args <- list(
    mode             = params$ggir_mode,
    datadir          = input_dir,
    outputdir        = output_dir,

    # Calibration & metrics
    do.cal           = params$do_calibration,
    acc.metric       = params$acc_metric,
    windowsizes      = params$epoch_lengths,
    desiredtz        = params$desiredtz,

    # Part 2: cut-points
    threshold.lig    = params$threshold_lig,
    threshold.mod    = params$threshold_mod,
    threshold.vig    = params$threshold_vig,
    qwindow          = qwindow,

    # Part 3-4: sleep detection
    HASPT.algo       = params$sleep_algorithm,

    # Part 5: time-use analysis
    save_ms5rawlevels          = params$save_ms5rawlevels,
    save_ms5raw_without_invalid = params$save_ms5raw_without_invalid,

    # Part 5: bout detection
    boutdur.mvpa     = params$boutdur_mvpa,
    boutdur.in       = params$boutdur_in,
    boutdur.lig      = params$boutdur_lig,

    # Reports
    do.report        = params$do_report,

    # Processing
    do.parallel      = n_cores > 1,
    maxNcores        = n_cores,
    overwrite        = FALSE,
    minimumFileSizeMB = 0.2
  )

  # For CSV files: add rmc.* parameters so GGIR reads them via read.myacc.csv
  # GENEActiv CSV format: 100-row header, then epoch data
  # Columns: timestamp, x, y, z, light, button, temperature, SVMgs, x_std, y_std, z_std, peak_lux
  if (has_csv && !has_bin && !has_cwa) {
    log_step("CSV input detected: configuring rmc.* parameters for read.myacc.csv")
    csv_args <- list(
      rmc.firstrow.acc    = 101,      # Data starts at row 101 (after 100-row header)
      rmc.firstrow.header = NULL,     # Skip header parsing (has duplicate keys)
      rmc.header.length   = 100,      # 100 metadata rows to skip
      rmc.col.acc         = 2:4,      # Columns 2-4 = x, y, z acceleration (mean g)
      rmc.col.temp        = 7,        # Column 7 = temperature
      rmc.col.time        = 1,        # Column 1 = timestamp
      rmc.unit.acc        = "g",      # Acceleration in g units
      rmc.unit.temp       = "C",      # Temperature in Celsius
      rmc.unit.time       = "character", # Timestamps as character strings
      rmc.format.time     = "%Y-%m-%d %H:%M:%S:%OS", # Timestamp format with ms
      rmc.sf              = 1,        # Data is at 1 Hz (epoch-aggregated)
      rmc.dec             = ".",      # Decimal separator
      rmc.noise           = 13,       # Calibration noise level in mg
      rmc.check4timegaps  = TRUE,
      rmc.doresample      = FALSE     # Don't resample (already at desired epoch)
    )
    # Note: autocalibration (do.cal) won't work well on epoch data since it
    # needs raw multi-Hz samples for sphere-fitting. Disable for CSV input.
    ggir_args$do.cal <- FALSE
    log_step("Warning: Autocalibration disabled for epoch-level CSV data.")

    ggir_args <- c(ggir_args, csv_args)
  }

  do.call(GGIR::GGIR, ggir_args)

  log_step("GGIR pipeline complete")
  invisible(output_dir)
}

#' Legacy bypass for pre-processed epoch CSVs
#'
#' For files that GGIR cannot process (already epoch-aggregated, no raw data).
#' Uses SVMg as ENMO proxy. No calibration, no validated sleep/non-wear.
#'
#' @param file_paths Character vector of CSV file paths
#' @param params Named list from read_pipeline_params()
#' @return data.frame with columns: pupil_id, timestamp, enmo_mg, wear, date
run_legacy_bypass <- function(file_paths, params) {
  warning("Legacy bypass mode: no autocalibration, no validated non-wear/sleep detection.\n",
          "Results should be interpreted with caution.")

  all_epochs <- lapply(file_paths, function(f) {
    df <- read.csv(f, stringsAsFactors = FALSE)
    fname <- tools::file_path_sans_ext(basename(f))
    pupil_id <- strsplit(fname, "_")[[1]][1]

    enmo_mg <- if ("svmg" %in% names(df)) df$svmg
               else if ("svmgsum" %in% names(df)) df$svmgsum
               else stop("No SVMg column found in: ", basename(f))

    ts <- as.POSIXct(df$timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "Europe/Brussels")
    if (all(is.na(ts))) {
      ts <- as.POSIXct(df$timestamp, format = "%Y-%m-%d %H:%M:%S:%OS", tz = "Europe/Brussels")
    }

    # Basic non-wear: flag when all axis std devs are very low
    wear <- rep(TRUE, nrow(df))
    if (all(c("sdx", "sdy", "sdz") %in% names(df))) {
      std_thresh <- 0.013  # 13 mg in g
      wear <- !(df$sdx < std_thresh & df$sdy < std_thresh & df$sdz < std_thresh)
      wear[is.na(wear)] <- TRUE
    } else if (all(c("x_std", "y_std", "z_std") %in% names(df))) {
      std_thresh <- 0.013
      wear <- !(df$x_std < std_thresh & df$y_std < std_thresh & df$z_std < std_thresh)
      wear[is.na(wear)] <- TRUE
    }

    data.frame(
      pupil_id  = pupil_id,
      timestamp = ts,
      enmo_mg   = enmo_mg,
      wear      = wear,
      date      = as.Date(ts),
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, all_epochs)
  log_step(paste("Legacy bypass: loaded", nrow(result), "epochs for",
                 length(unique(result$pupil_id)), "pupils"))
  result
}

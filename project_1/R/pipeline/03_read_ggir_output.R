# =============================================================================
# SchoolMoves Pipeline — Step 3: Read GGIR Output
# =============================================================================
# Parses GGIR's output directory structure into tidy R data frames.
#
# GGIR output structure:
#   output_dir/output_<datadir_name>/
#     meta/basic/              — Part 1 raw metrics (.RData)
#     meta/ms2.out/            — Part 2 milestones
#     meta/ms3.out/            — Part 3 milestones
#     meta/ms4.out/            — Part 4 milestones
#     meta/ms5.out/            — Part 5 milestones
#     meta/ms5.outraw/         — Part 5 epoch-level time series
#     results/
#       part2_daysummary.csv
#       part2_summary.csv
#       part4_nightsummary_sleep_cleaned.csv
#       part5_daysummary_*.csv
#       part5_personsummary_*.csv
#       QC/
#     config.csv               — full GGIR parameter record
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Find the GGIR output directory
#'
#' GGIR creates an output subdirectory named "output_<datadir_name>".
#'
#' @param output_base The outputdir passed to GGIR::GGIR()
#' @return Path to the GGIR output directory (containing meta/ and results/)
find_ggir_output_dir <- function(output_base) {
  output_dirs <- list.dirs(output_base, full.names = TRUE, recursive = FALSE)
  ggir_dirs <- output_dirs[grepl("^output_", basename(output_dirs))]

  if (length(ggir_dirs) == 0) {
    stop("No GGIR output directory found in: ", output_base,
         "\n  Expected a subdirectory named 'output_<datadir_name>'")
  }

  if (length(ggir_dirs) > 1) {
    log_step(paste("Multiple GGIR output dirs found, using most recent:", basename(ggir_dirs[1])))
  }

  ggir_dir <- ggir_dirs[1]
  log_step(paste("Found GGIR output:", ggir_dir))
  ggir_dir
}

#' Read GGIR Part 2 day summary
#'
#' @param ggir_dir Path to GGIR output directory (containing results/)
#' @return data.frame with daily summaries per participant
read_part2_daysummary <- function(ggir_dir) {
  results_dir <- file.path(ggir_dir, "results")
  csv_path <- file.path(results_dir, "part2_daysummary.csv")

  if (!file.exists(csv_path)) {
    stop("Part 2 day summary not found: ", csv_path)
  }

  df <- read.csv(csv_path, stringsAsFactors = FALSE)
  log_step(paste("Part 2 day summary:", nrow(df), "rows,", ncol(df), "columns"))
  df
}

#' Read GGIR Part 2 person summary
#'
#' @param ggir_dir Path to GGIR output directory
#' @return data.frame with per-person summaries
read_part2_summary <- function(ggir_dir) {
  csv_path <- file.path(ggir_dir, "results", "part2_summary.csv")
  if (!file.exists(csv_path)) {
    stop("Part 2 summary not found: ", csv_path)
  }
  read.csv(csv_path, stringsAsFactors = FALSE)
}

#' Read GGIR Part 4 sleep summary
#'
#' @param ggir_dir Path to GGIR output directory
#' @return data.frame with nightly sleep onset/offset/duration
read_part4_sleep <- function(ggir_dir) {
  results_dir <- file.path(ggir_dir, "results")

  # Try cleaned version first, then full
  csv_path <- file.path(results_dir, "part4_nightsummary_sleep_cleaned.csv")
  if (!file.exists(csv_path)) {
    csv_path <- file.path(results_dir, "part4_nightsummary_sleep_full.csv")
  }
  if (!file.exists(csv_path)) {
    # Search for any part4 file
    p4_files <- list.files(results_dir, pattern = "^part4.*\\.csv$", full.names = TRUE)
    if (length(p4_files) > 0) {
      csv_path <- p4_files[1]
    } else {
      # Sleep data may be embedded in Part 5 Segments output (sleeponset, wakeup columns)
      log_step("No separate Part 4 sleep CSV found. Sleep data may be in Part 5 Segments.")
      return(NULL)
    }
  }

  df <- read.csv(csv_path, stringsAsFactors = FALSE)
  log_step(paste("Part 4 sleep summary:", nrow(df), "rows from", basename(csv_path)))
  df
}

#' Read GGIR Part 5 day summary
#'
#' Prefers the Segments version (has qwindow breakdowns) over the MM version.
#' Part 5 output filename includes the threshold values used, e.g.:
#' part5_daysummary_Segments_L56.3M191.6V695.8_T5A5.csv
#'
#' @param ggir_dir Path to GGIR output directory
#' @return data.frame with time-use per day per segment
read_part5_daysummary <- function(ggir_dir) {
  results_dir <- file.path(ggir_dir, "results")

  # Prefer Segments version (has qwindow breakdowns)
  seg_files <- list.files(results_dir, pattern = "^part5_daysummary_Segments.*\\.csv$",
                          full.names = TRUE)
  if (length(seg_files) > 0) {
    df <- read.csv(seg_files[1], stringsAsFactors = FALSE)
    log_step(paste("Part 5 Segments day summary:", nrow(df), "rows from", basename(seg_files[1])))
    return(df)
  }

  # Fallback to any Part 5 day summary
  p5_files <- list.files(results_dir, pattern = "^part5_daysummary.*\\.csv$",
                         full.names = TRUE)
  if (length(p5_files) == 0) {
    log_step("Warning: No Part 5 day summary found. Time-use analysis will be limited.")
    return(NULL)
  }

  csv_path <- p5_files[1]
  df <- read.csv(csv_path, stringsAsFactors = FALSE)
  log_step(paste("Part 5 day summary:", nrow(df), "rows from", basename(csv_path)))
  df
}

#' Read GGIR Part 5 person summary
#'
#' @param ggir_dir Path to GGIR output directory
#' @return data.frame with per-person time-use summaries
read_part5_personsummary <- function(ggir_dir) {
  results_dir <- file.path(ggir_dir, "results")

  p5_files <- list.files(results_dir, pattern = "^part5_personsummary.*\\.csv$",
                         full.names = TRUE)
  if (length(p5_files) == 0) {
    return(NULL)
  }

  read.csv(p5_files[1], stringsAsFactors = FALSE)
}

#' Read GGIR Part 5 epoch-level time series
#'
#' Only available when save_ms5rawlevels = TRUE in GGIR config.
#'
#' @param ggir_dir Path to GGIR output directory
#' @return List of data.frames (one per participant), or NULL if not available
read_part5_timeseries <- function(ggir_dir) {
  ts_dir <- file.path(ggir_dir, "meta", "ms5.outraw")
  if (!dir.exists(ts_dir)) {
    log_step("Part 5 epoch-level time series not available (save_ms5rawlevels was FALSE)")
    return(NULL)
  }

  csv_files <- list.files(ts_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(csv_files) == 0) {
    return(NULL)
  }

  log_step(paste("Reading", length(csv_files), "Part 5 time series files"))
  ts_list <- lapply(csv_files, function(f) {
    read.csv(f, stringsAsFactors = FALSE)
  })
  names(ts_list) <- tools::file_path_sans_ext(basename(csv_files))
  ts_list
}

#' Read GGIR config.csv (parameter record)
#'
#' @param ggir_dir Path to GGIR output directory
#' @return data.frame with all GGIR parameters used
read_ggir_config <- function(ggir_dir) {
  csv_path <- file.path(ggir_dir, "config.csv")
  if (!file.exists(csv_path)) {
    return(NULL)
  }
  read.csv(csv_path, stringsAsFactors = FALSE)
}

#' Load all GGIR output into a structured list
#'
#' Convenience function that reads all available GGIR output.
#'
#' @param output_base The outputdir passed to GGIR::GGIR()
#' @return Named list with:
#'   - ggir_dir: path to the GGIR output directory
#'   - part2_daysummary: daily summaries
#'   - part2_summary: person summaries
#'   - part4_sleep: nightly sleep data
#'   - part5_daysummary: day-segment time-use
#'   - part5_personsummary: person-level time-use
#'   - part5_timeseries: epoch-level data (if available)
#'   - config: GGIR parameters used
load_all_ggir_output <- function(output_base) {
  ggir_dir <- find_ggir_output_dir(output_base)

  list(
    ggir_dir           = ggir_dir,
    part2_daysummary   = tryCatch(read_part2_daysummary(ggir_dir), error = function(e) { log_step(paste("Part 2 day summary error:", e$message)); NULL }),
    part2_summary      = tryCatch(read_part2_summary(ggir_dir), error = function(e) NULL),
    part4_sleep        = tryCatch(read_part4_sleep(ggir_dir), error = function(e) NULL),
    part5_daysummary   = tryCatch(read_part5_daysummary(ggir_dir), error = function(e) NULL),
    part5_personsummary = tryCatch(read_part5_personsummary(ggir_dir), error = function(e) NULL),
    part5_timeseries   = tryCatch(read_part5_timeseries(ggir_dir), error = function(e) NULL),
    config             = tryCatch(read_ggir_config(ggir_dir), error = function(e) NULL)
  )
}

#' Extract pupil ID from GGIR filename column
#'
#' GGIR stores the source filename in its output. This extracts the pupil ID
#' using the same convention: first digit = school_id, remaining = pupil number.
#'
#' @param filename Character vector of GGIR source filenames
#' @return Character vector of pupil IDs
extract_pupil_from_ggir <- function(filename) {
  # Remove file extension and path
  fname <- tools::file_path_sans_ext(basename(filename))
  # Take first token (before underscore or space)
  sapply(strsplit(fname, "[_ ]"), `[`, 1)
}

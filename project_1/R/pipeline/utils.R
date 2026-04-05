# =============================================================================
# SchoolMoves Pipeline — Shared Utilities
# =============================================================================

suppressPackageStartupMessages({
  library(yaml)
  library(dplyr)
  library(lubridate)
})

#' Read pipeline parameters from YAML config
#'
#' @param config_path Path to pipeline_params.yaml
#' @return Named list of all pipeline parameters
read_pipeline_params <- function(config_path = "config/pipeline_params.yaml") {
  if (!file.exists(config_path)) {
    stop("Config file not found: ", config_path,
         "\n  Expected location: ", normalizePath(config_path, mustWork = FALSE),
         "\n  Make sure you are running from the project_1/ directory.")
  }
  params <- yaml::read_yaml(config_path)
  log_step(paste("Loaded config from", config_path))
  params
}

#' Extract pupil ID from a file path based on detected format
#'
#' @param filepath Path to the input file
#' @param format_type One of "geneactiv_export", "tim_preprocessed", "raw_bin"
#' @return Character string with the pupil ID
extract_pupil_id <- function(filepath, format_type) {
  fname <- basename(filepath)

  if (format_type == "geneactiv_export") {
    # Format A: pupil ID is in the file header, row 21 (Subject Code)
    # This function only handles filename-based extraction;
    # header-based extraction happens in 01_convert.R
    return(NA_character_)

  } else if (format_type == "tim_preprocessed") {
    # Format B: first token of filename before underscore
    # e.g. "610110_left wrist_035056_2018-07-14 21-49-44.csv" -> "610110"
    id <- strsplit(fname, "_")[[1]][1]
    return(id)

  } else if (format_type == "raw_bin") {
    # Format C: same convention as Tim's preprocessed
    id <- strsplit(tools::file_path_sans_ext(fname), "_")[[1]][1]
    return(id)

  } else {
    stop("Unknown format_type: ", format_type)
  }
}

#' Load GGIR output files and bind into a single data.frame
#'
#' @param ggir_dir Path to GGIR output directory
#' @return data.frame with all pupils, including a pupil_id column
load_ggir_output <- function(ggir_dir) {
  if (!dir.exists(ggir_dir)) {
    stop("GGIR output directory not found: ", ggir_dir)
  }

  csv_files <- list.files(ggir_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(csv_files) == 0) {
    stop("No CSV files found in GGIR output directory: ", ggir_dir)
  }

  log_step(paste("Loading", length(csv_files), "GGIR output files from", ggir_dir))

  all_data <- lapply(csv_files, function(f) {
    df <- read.csv(f, stringsAsFactors = FALSE)
    # Derive pupil_id from the filename
    df$pupil_id <- tools::file_path_sans_ext(basename(f))
    df
  })

  result <- do.call(rbind, all_data)
  log_step(paste("Loaded", nrow(result), "rows for", length(csv_files), "pupils"))
  result
}

#' Write a validity report CSV
#'
#' @param validity data.frame with per-pupil validity flags
#' @param output_dir Directory to write the report
write_validity_report <- function(validity, output_dir) {
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  report_path <- file.path(output_dir, "validity_report.csv")
  write.csv(validity, report_path, row.names = FALSE)
  log_step(paste("Validity report written to", report_path))
  invisible(report_path)
}

#' Log a pipeline step with timestamp
#'
#' @param msg Message to log
log_step <- function(msg) {
  timestamp <- format(Sys.time(), "[%H:%M:%S]")
  message(timestamp, " ", msg)
}

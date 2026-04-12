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

#' Read optional SPSS .sav metadata files
#'
#' Looks for standard admin files in the specified directory:
#'   - Dataset_Scholen.sav (school schedules)
#'   - Dataset_Afwezigheden.sav (absences)
#'   - Databestand_Slaap.sav (sleep times)
#'   - Dataset_Leerlingen.sav (pupil non-wear)
#'
#' @param sav_dir Path to directory containing .sav files
#' @return Named list of data.frames, or NULL if haven is not installed
read_sav_metadata <- function(sav_dir) {
  if (!dir.exists(sav_dir)) {
    log_step(paste("SAV metadata directory not found:", sav_dir))
    return(NULL)
  }

  if (!requireNamespace("haven", quietly = TRUE)) {
    log_step("Package 'haven' not installed. Skipping .sav metadata.")
    return(NULL)
  }

  sav_files <- list(
    schools = "Dataset_Scholen.sav",
    absences = "Dataset_Afwezigheden.sav",
    sleep = "Databestand_Slaap.sav",
    pupils = "Dataset_Leerlingen.sav"
  )

  result <- list()
  for (name in names(sav_files)) {
    path <- file.path(sav_dir, sav_files[[name]])
    if (file.exists(path)) {
      result[[name]] <- as.data.frame(haven::read_spss(path))
      log_step(paste("Loaded", name, "metadata:", nrow(result[[name]]), "rows"))
    }
  }

  if (length(result) == 0) {
    log_step("No .sav files found in metadata directory")
    return(NULL)
  }

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

# utils_ggir.R
# ─────────────────────────────────────────────────────────────────────────────
# Version-tolerant GGIR output readers.
#
# Ported and adapted from project_1/R/pipeline/03_read_ggir_output.R.
#
# GGIR creates output like:
#   {outputdir}/output_{datadir_name}/results/
#     part2_daysummary.csv
#     part4_nightsummary_sleep_cleaned.csv  (or _full.csv, or part4_*.csv)
#     part5_daysummary_Segments_*.csv       (or part5_daysummary_WW_*.csv)
#     part5_personsummary_WW_*.csv
#   {outputdir}/output_{datadir_name}/config.csv
#
# These helpers are tolerant of filename variations across GGIR versions.
#
# Functions can be sourced from any working directory — they take absolute
# or relative paths as arguments.
# ─────────────────────────────────────────────────────────────────────────────

#' Convert "HH:MM" string to decimal hours
#'
#' @param hm Character string in "HH:MM" format.
#' @return Numeric scalar (e.g. "08:30" → 8.5).
hm_to_h <- function(hm) {
  parts <- as.integer(strsplit(hm, ":")[[1]])
  parts[1] + parts[2] / 60
}

#' Find the GGIR output subdirectory for a given meting
#'
#' GGIR creates a subdirectory named "output_<datadir_name>" inside the
#' outputdir that was passed to GGIR::GGIR(). This function locates it
#' without assuming the exact name.
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#'   E.g. "../data/processed/ggir/meting_1"
#' @return Path to the GGIR output subdirectory (the one that contains
#'   meta/ and results/), or NULL if not found.
find_ggir_output_subdir <- function(meting_output_dir) {
  if (!dir.exists(meting_output_dir)) return(NULL)

  subdirs <- list.dirs(meting_output_dir, full.names = TRUE, recursive = FALSE)
  ggir_subdirs <- subdirs[grepl("^output_", basename(subdirs))]

  if (length(ggir_subdirs) == 0) return(NULL)
  if (length(ggir_subdirs) > 1) {
    message("[utils_ggir] Multiple output_ subdirs; using: ", basename(ggir_subdirs[1]))
  }
  ggir_subdirs[1]
}

#' Find the results/ directory for a given meting output directory
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @return Path to results/, or NULL if not found.
find_ggir_results_dir <- function(meting_output_dir) {
  subdir <- find_ggir_output_subdir(meting_output_dir)
  if (is.null(subdir)) return(NULL)
  results <- file.path(subdir, "results")
  if (!dir.exists(results)) return(NULL)
  results
}

#' Load a GGIR CSV with meting and school columns added
#'
#' Drop-in replacement for the ad-hoc load_ggir() helper in 03_build_summaries.R
#' and global.R. Adds version-tolerant directory discovery.
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @param meting Character meting label (e.g. "meting_1").
#' @param filename Exact filename (e.g. "part2_daysummary.csv"). One of
#'   filename or pattern must be supplied.
#' @param pattern Regex pattern matching the file (e.g. "^part5_personsummary_").
#' @param extract_school_id_fn Function(ID) → school label. Defaults to the
#'   standard extract_school_id() if available in the calling environment.
#' @return data.table with meting and school columns, or NULL if file not found.
load_ggir_file <- function(meting_output_dir, meting,
                            filename = NULL, pattern = NULL,
                            extract_school_id_fn = NULL) {
  results_dir <- find_ggir_results_dir(meting_output_dir)
  if (is.null(results_dir)) return(NULL)

  if (!is.null(pattern)) {
    files <- list.files(results_dir, pattern = pattern, full.names = TRUE)
    if (length(files) == 0) return(NULL)
    path <- files[1]
  } else if (!is.null(filename)) {
    path <- file.path(results_dir, filename)
  } else {
    stop("load_ggir_file: supply filename or pattern")
  }

  if (!file.exists(path)) return(NULL)

  dt <- data.table::fread(path, data.table = TRUE)
  dt[, meting := meting]

  # Callers must supply extract_school_id_fn explicitly — no env auto-lookup.
  if (!is.null(extract_school_id_fn) && "ID" %in% names(dt)) {
    dt[, school := extract_school_id_fn(ID)]
  }

  dt
}

#' Read GGIR Part 4 sleep summary with multi-level fallback
#'
#' Tries: cleaned → full → any part4 CSV. Checked in both results/ and
#' results/QC/ — GGIR writes the "cleaned" (valid-nights-only) report to
#' results/ when at least one night passes validity criteria, but falls back
#' to only writing the unfiltered "full" report under results/QC/ when it
#' doesn't (observed with GGIR 3.3.6 on a small test set).
#'
#' @param results_dir Path to the GGIR results/ directory.
#' @return data.frame, or NULL if no Part 4 file found.
read_part4_sleep <- function(results_dir) {
  filenames <- c(
    "part4_nightsummary_sleep_cleaned.csv",
    "part4_nightsummary_sleep_full.csv",
    "part4_nightsummary.csv"
  )
  search_dirs <- c(results_dir, file.path(results_dir, "QC"))
  candidates  <- as.vector(outer(search_dirs, filenames, file.path))

  for (p in candidates) {
    if (file.exists(p)) {
      message("[utils_ggir] Part 4 sleep: ", basename(p),
              if (dirname(p) != results_dir) paste0(" (", basename(dirname(p)), "/)") else "")
      out <- read.csv(p, stringsAsFactors = FALSE)
      attr(out, "source_path") <- p
      return(out)
    }
  }

  # Last resort: any file matching part4*.csv, in results/ or results/QC/
  any_p4 <- unlist(lapply(search_dirs, list.files,
                          pattern = "^part4.*\\.csv$", full.names = TRUE))
  if (length(any_p4) > 0) {
    message("[utils_ggir] Part 4 sleep (fallback): ", basename(any_p4[1]))
    out <- read.csv(any_p4[1], stringsAsFactors = FALSE)
    attr(out, "source_path") <- any_p4[1]
    return(out)
  }

  message("[utils_ggir] No Part 4 sleep CSV found. Sleep data may be in Part 5.")
  NULL
}

#' Read GGIR Part 5 day summary — prefers Segments version
# Note: Part 5 files are read via load_ggir_file(pattern = "^part5_...") — use that API.

#' Read GGIR config.csv (parameter record)
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @return data.frame, or NULL if not found.
read_ggir_config <- function(meting_output_dir) {
  subdir <- find_ggir_output_subdir(meting_output_dir)
  if (is.null(subdir)) return(NULL)
  cfg_path <- file.path(subdir, "config.csv")
  if (!file.exists(cfg_path)) return(NULL)
  read.csv(cfg_path, stringsAsFactors = FALSE)
}

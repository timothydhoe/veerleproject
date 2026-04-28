# utils_input.R
# ─────────────────────────────────────────────────────────────────────────────
# Input detection and manifest utilities.
#
# Ported from project_1/R/pipeline/01_prepare_input.R and adapted for the
# r/ pipeline structure (no staging directory; GGIR reads raw dirs directly).
#
# Provides:
#   detect_format()           — classify a file as geneactiv_csv / _bin / preprocessed_csv
#   extract_pupil_id_from_file() — extract pupil ID from header or filename
#   get_school_from_pupil()   — first digit of pupil_id → school number
#   write_input_manifest()    — scan data dirs and write logs/input_manifest.csv
# ─────────────────────────────────────────────────────────────────────────────

#' Detect the format of a single input file
#'
#' @param filepath Path to the input file
#' @return One of "geneactiv_csv", "geneactiv_bin", "preprocessed_csv"
detect_format <- function(filepath) {
  ext <- tolower(tools::file_ext(filepath))

  if (ext == "bin") {
    return("geneactiv_bin")
  }

  if (ext == "cwa") {
    return("axivity_cwa")
  }

  if (ext != "csv") {
    stop("Unsupported file extension: .", ext,
         "\n  Expected .csv, .bin, or .cwa, got: ", basename(filepath))
  }

  first_line <- readLines(filepath, n = 1, warn = FALSE)
  first_cell <- trimws(strsplit(first_line, ",")[[1]][1])

  if (first_cell == "Device Type") {
    return("geneactiv_csv")
  } else {
    return("preprocessed_csv")
  }
}

#' Extract pupil ID from a file
#'
#' For GENEActiv CSVs: reads Subject Code from header row 21.
#' For .bin and pre-processed CSVs: uses the filename stem (first token before "_").
#'
#' @param filepath Path to the input file
#' @param format_type One of "geneactiv_csv", "geneactiv_bin", "preprocessed_csv"
#' @return Character pupil ID
extract_pupil_id_from_file <- function(filepath, format_type) {
  fname <- tools::file_path_sans_ext(basename(filepath))

  if (format_type == "geneactiv_csv") {
    header_lines <- readLines(filepath, n = 25, warn = FALSE)
    subject_line <- header_lines[21]
    pupil_id <- trimws(strsplit(subject_line, ",")[[1]][2])
    if (is.na(pupil_id) || pupil_id == "") {
      pupil_id <- strsplit(fname, "_")[[1]][1]
    }
    return(pupil_id)
  }

  # For .bin and preprocessed: use filename
  strsplit(fname, "_")[[1]][1]
}

#' Extract school ID from a pupil ID (first digit)
#'
#' @param pupil_id Character pupil ID (e.g. "2063")
#' @return Integer school ID (e.g. 2)
get_school_from_pupil <- function(pupil_id) {
  as.integer(substr(as.character(pupil_id), 1, 1))
}

#' Scan data directories and write an input manifest CSV
#'
#' Scans each measurement wave directory for .csv and .bin files, classifies
#' each file, and writes a manifest to logs/input_manifest.csv.
#'
#' @param data_dirs Named list of measurement wave directories.
#'   Example: list(meting_1 = "../data/raw/meting_1", meting_2 = "../data/raw/meting_2")
#' @param logs_dir Path to the logs directory (will be created if absent).
#' @return Invisibly returns the manifest data.frame.
write_input_manifest <- function(data_dirs, logs_dir = "logs") {
  rows <- list()

  for (meting in names(data_dirs)) {
    dir_path <- data_dirs[[meting]]

    if (!dir.exists(dir_path)) {
      message("[input] Skipping ", meting, " — directory not found: ", dir_path)
      next
    }

    files <- list.files(dir_path, pattern = "\\.(csv|bin|cwa)$",
                        full.names = TRUE, ignore.case = TRUE, recursive = FALSE)

    if (length(files) == 0) {
      message("[input] No .csv, .bin, or .cwa files in: ", dir_path)
      next
    }

    for (f in files) {
      fmt <- tryCatch(detect_format(f), error = function(e) "unknown")
      pid <- tryCatch(extract_pupil_id_from_file(f, fmt), error = function(e) NA_character_)
      sid <- tryCatch(get_school_from_pupil(pid), error = function(e) NA_integer_)

      rows[[length(rows) + 1]] <- data.frame(
        meting           = meting,
        filename         = basename(f),
        original_path    = f,
        format           = fmt,
        pupil_id         = pid,
        school_id        = sid,
        ggir_compatible  = fmt %in% c("geneactiv_csv", "geneactiv_bin", "axivity_cwa"),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) {
    message("[input] No input files found across all measurement wave directories.")
    return(invisible(NULL))
  }

  manifest <- do.call(rbind, rows)

  n_total  <- nrow(manifest)
  n_ggir   <- sum(manifest$ggir_compatible, na.rm = TRUE)
  n_bypass <- n_total - n_ggir
  n_bin    <- sum(manifest$format == "geneactiv_bin", na.rm = TRUE)

  message(sprintf("[input] Found %d files: %d GGIR-compatible (%d .bin), %d pre-processed",
                  n_total, n_ggir, n_bin, n_bypass))

  if (n_bypass > 0) {
    warning("[input] Pre-processed epoch files detected — these bypass GGIR (no calibration, no validated sleep):\n  ",
            paste(manifest$filename[!manifest$ggir_compatible], collapse = "\n  "))
  }

  dir.create(logs_dir, showWarnings = FALSE, recursive = TRUE)
  manifest_path <- file.path(logs_dir, "input_manifest.csv")
  write.csv(manifest, manifest_path, row.names = FALSE)
  message("[input] Manifest written to: ", manifest_path)

  invisible(manifest)
}

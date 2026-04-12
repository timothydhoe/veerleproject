# =============================================================================
# SchoolMoves Pipeline — Step 1: Prepare Input
# =============================================================================
# Scans the input directory, detects file formats, and organises files into
# a clean directory structure that GGIR can process directly.
#
# GGIR natively reads:
#   - GENEActiv .bin files
#   - GENEActiv .csv files (with 100-row metadata header)
#
# Files that GGIR cannot process (e.g. Tim's pre-processed epoch CSVs)
# are flagged for the legacy bypass path.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Detect the format of a single input file
#'
#' @param filepath Path to the input file
#' @return One of "geneactiv_csv", "preprocessed_csv", "geneactiv_bin"
detect_format <- function(filepath) {
  ext <- tolower(tools::file_ext(filepath))

  if (ext == "bin") {
    return("geneactiv_bin")
  }

  if (ext != "csv") {
    stop("Unsupported file extension: .", ext,
         "\n  Expected .csv or .bin, got: ", basename(filepath))
  }

  first_line <- readLines(filepath, n = 1, warn = FALSE)
  first_cell <- trimws(strsplit(first_line, ",")[[1]][1])

  if (first_cell == "Device Type") {
    return("geneactiv_csv")
  } else {
    return("preprocessed_csv")
  }
}

#' Extract pupil ID from a file path
#'
#' For GENEActiv CSVs: reads Subject Code from header row 21.
#' For .bin files: uses filename stem (first token before underscore).
#' For preprocessed CSVs: uses first token of filename before underscore.
#'
#' @param filepath Path to the input file
#' @param format_type One of "geneactiv_csv", "preprocessed_csv", "geneactiv_bin"
#' @return Character string with the pupil ID
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

#' Get school_id from a pupil_id (first digit)
#'
#' @param pupil_id Character pupil ID
#' @return Integer school ID
get_school_from_pupil <- function(pupil_id) {
  as.integer(substr(pupil_id, 1, 1))
}

#' Prepare input files for GGIR processing
#'
#' Scans the input directory, classifies each file, and creates a manifest.
#' Files that GGIR can process (.bin, GENEActiv CSV) are symlinked/copied
#' to a clean input directory. Preprocessed CSVs are flagged separately.
#'
#' @param input_dir Path to raw .bin or .csv files
#' @param output_dir Pipeline output directory (used to create subdirectories)
#' @param overwrite Re-process existing files. Default FALSE.
#' @return A list with:
#'   - manifest: data.frame with file info (path, format, pupil_id, school_id, ggir_compatible)
#'   - ggir_input_dir: path to directory containing GGIR-compatible files
#'   - bypass_files: paths to files requiring legacy bypass
prepare_input <- function(input_dir, output_dir, overwrite = FALSE) {
  if (!dir.exists(input_dir)) {
    stop("Input directory not found: ", input_dir)
  }

  all_files <- list.files(input_dir, pattern = "\\.(csv|bin)$",
                          full.names = TRUE, ignore.case = TRUE, recursive = TRUE)

  if (length(all_files) == 0) {
    stop("No .csv or .bin files found in: ", input_dir)
  }

  log_step(paste("Found", length(all_files), "input files in", input_dir))

  # Classify each file
  manifest <- do.call(rbind, lapply(all_files, function(f) {
    fmt <- tryCatch(detect_format(f), error = function(e) "unknown")
    pid <- tryCatch(extract_pupil_id_from_file(f, fmt), error = function(e) NA_character_)
    sid <- tryCatch(get_school_from_pupil(pid), error = function(e) NA_integer_)

    data.frame(
      original_path = f,
      filename = basename(f),
      format = fmt,
      pupil_id = pid,
      school_id = sid,
      ggir_compatible = fmt %in% c("geneactiv_csv", "geneactiv_bin"),
      stringsAsFactors = FALSE
    )
  }))

  n_ggir <- sum(manifest$ggir_compatible)
  n_bypass <- sum(!manifest$ggir_compatible)

  log_step(paste("GGIR-compatible:", n_ggir, "files | Legacy bypass:", n_bypass, "files"))

  # Create clean GGIR input directory with compatible files
  ggir_input_dir <- file.path(output_dir, "ggir_input")
  dir.create(ggir_input_dir, showWarnings = FALSE, recursive = TRUE)

  ggir_files <- manifest[manifest$ggir_compatible, ]
  for (i in seq_len(nrow(ggir_files))) {
    src <- ggir_files$original_path[i]
    dst <- file.path(ggir_input_dir, ggir_files$filename[i])
    if (!file.exists(dst) || overwrite) {
      file.copy(src, dst, overwrite = overwrite)
    }
  }

  bypass_files <- manifest$original_path[!manifest$ggir_compatible]
  if (length(bypass_files) > 0) {
    warning("The following files cannot be processed by GGIR (pre-processed epoch data):\n  ",
            paste(basename(bypass_files), collapse = "\n  "),
            "\n  These will use the legacy bypass path (no calibration, no validated sleep).")
  }

  # Write manifest
  manifest_path <- file.path(output_dir, "logs", "input_manifest.csv")
  dir.create(dirname(manifest_path), showWarnings = FALSE, recursive = TRUE)
  write.csv(manifest, manifest_path, row.names = FALSE)
  log_step(paste("Input manifest written to", manifest_path))

  list(
    manifest = manifest,
    ggir_input_dir = ggir_input_dir,
    bypass_files = bypass_files
  )
}

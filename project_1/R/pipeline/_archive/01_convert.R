# =============================================================================
# SchoolMoves Pipeline — Step 1: Format Detection & Conversion
# =============================================================================
# Detects the input file format (A, B, or C) and normalises to a standard
# column layout for downstream processing.
#
# Format A — GENEActiv direct export CSV
#   Detected by: .csv extension AND first cell == "Device Type"
#   100-row metadata header; data starts row 101
#   Pupil ID from header row 21 (Subject Code)
#
# Format B — Tim's pre-processed .bin->CSV
#   Detected by: .csv extension AND first cell != "Device Type"
#   No metadata header; first column is row index
#   Pupil ID from first token of filename (e.g. "610110" from "610110_left wrist_...csv")
#
# Format C — Raw .bin file
#   Detected by: .bin extension
#   Processed with GENEAread::read.bin(calibrate = TRUE)
#   Epoch-aggregated to 1 second
#   SVMg = abs(sqrt(x^2 + y^2 + z^2) - 1), summed per epoch
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

# Standard output columns after normalisation
STANDARD_COLUMNS <- c(
  "pupil_id", "timestamp", "x", "y", "z",
  "light", "temperature", "svmg", "x_std", "y_std", "z_std"
)

#' Detect the format of a single input file
#'
#' @param filepath Path to the input file
#' @return One of "geneactiv_export", "tim_preprocessed", "raw_bin"
detect_format <- function(filepath) {
  ext <- tolower(tools::file_ext(filepath))

  if (ext == "bin") {
    return("raw_bin")
  }

  if (ext != "csv") {
    stop("Unsupported file extension: .", ext,
         "\n  Expected .csv or .bin, got: ", basename(filepath))
  }

  # Read just the first line to check the header signature
  first_line <- readLines(filepath, n = 1, warn = FALSE)
  first_cell <- trimws(strsplit(first_line, ",")[[1]][1])

  if (first_cell == "Device Type") {
    return("geneactiv_export")
  } else {
    return("tim_preprocessed")
  }
}

#' Convert a single file to the standard format
#'
#' @param filepath Path to a single input file (.csv or .bin)
#' @param output_dir Directory to write the normalised CSV
#' @param overwrite If TRUE, re-convert existing files
#' @return A one-row data.frame with the conversion log entry
convert_single_file <- function(filepath, output_dir, overwrite = FALSE) {
  fname <- basename(filepath)
  log_entry <- data.frame(
    file = fname,
    detected_format = NA_character_,
    pupil_id = NA_character_,
    n_rows = NA_integer_,
    output_path = NA_character_,
    status = "error",
    message = "",
    stringsAsFactors = FALSE
  )

  tryCatch({
    fmt <- detect_format(filepath)
    log_entry$detected_format <- fmt

    if (fmt == "geneactiv_export") {
      result <- read_format_a(filepath)
    } else if (fmt == "tim_preprocessed") {
      result <- read_format_b(filepath)
    } else if (fmt == "raw_bin") {
      result <- read_format_c(filepath)
    }

    pupil_id <- result$pupil_id
    df <- result$data
    log_entry$pupil_id <- pupil_id
    log_entry$n_rows <- nrow(df)

    # Write normalised output
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
    out_path <- file.path(output_dir, paste0(pupil_id, ".csv"))

    if (file.exists(out_path) && !overwrite) {
      log_entry$status <- "skipped"
      log_entry$message <- "Output already exists"
      log_entry$output_path <- out_path
      return(log_entry)
    }

    write.csv(df, out_path, row.names = FALSE)
    log_entry$output_path <- out_path
    log_entry$status <- "success"
    log_entry$message <- paste("Converted", fmt, "->", nrow(df), "rows")

  }, error = function(e) {
    log_entry$status <<- "error"
    log_entry$message <<- conditionMessage(e)
  })

  log_entry
}

#' Read Format A: GENEActiv direct export CSV
#'
#' 100-row metadata header. Data starts at row 101.
#' Columns: timestamp, x, y, z, light, button, temperature, SVMgs,
#'          x_std, y_std, z_std, peak_lux
#' Pupil ID from header row 21 (Subject Code).
read_format_a <- function(filepath) {
  # Extract pupil_id from header row 21
  header_lines <- readLines(filepath, n = 25, warn = FALSE)
  subject_line <- header_lines[21]  # "Subject Code,4001"
  pupil_id <- trimws(strsplit(subject_line, ",")[[1]][2])

  if (is.na(pupil_id) || pupil_id == "") {
    stop("Could not extract pupil ID from header row 21 in: ", basename(filepath))
  }

  # Read data starting after the 100-row header
  df <- read.csv(filepath, skip = 100, header = FALSE, stringsAsFactors = FALSE)

  # Expected columns from GENEActiv export (no header row in data section)
  # timestamp, x, y, z, light, button, temperature, SVMgs, x_std, y_std, z_std, peak_lux
  if (ncol(df) < 11) {
    stop("Format A file has fewer than 11 data columns: ", basename(filepath))
  }

  result <- data.frame(
    pupil_id    = pupil_id,
    timestamp   = df[[1]],
    x           = as.numeric(df[[2]]),
    y           = as.numeric(df[[3]]),
    z           = as.numeric(df[[4]]),
    light       = as.numeric(df[[5]]),
    temperature = as.numeric(df[[7]]),  # column 6 = button, 7 = temperature
    svmg        = as.numeric(df[[8]]),  # SVMgs
    x_std       = as.numeric(df[[9]]),
    y_std       = as.numeric(df[[10]]),
    z_std       = as.numeric(df[[11]]),
    stringsAsFactors = FALSE
  )

  list(pupil_id = pupil_id, data = result)
}

#' Read Format B: Tim's pre-processed .bin->CSV
#'
#' No metadata header. First column is row index.
#' Columns: (idx), timestamp, xm, ym, zm, lightm, tempm, svmgsum, sdx, sdy, sdz, id
#' Pupil ID from first token of filename.
read_format_b <- function(filepath) {
  pupil_id <- extract_pupil_id(filepath, "tim_preprocessed")

  df <- read.csv(filepath, stringsAsFactors = FALSE)

  # Column mapping: the first column is the row index (named "X" or "")
  # Remaining: timestamp, xm, ym, zm, lightm, tempm, svmgsum, sdx, sdy, sdz, id
  result <- data.frame(
    pupil_id    = pupil_id,
    timestamp   = df$timestamp,
    x           = as.numeric(df$xm),
    y           = as.numeric(df$ym),
    z           = as.numeric(df$zm),
    light       = as.numeric(df$lightm),
    temperature = as.numeric(df$tempm),
    svmg        = as.numeric(df$svmgsum),
    x_std       = as.numeric(df$sdx),
    y_std       = as.numeric(df$sdy),
    z_std       = as.numeric(df$sdz),
    stringsAsFactors = FALSE
  )

  list(pupil_id = pupil_id, data = result)
}

#' Read Format C: Raw .bin file
#'
#' Uses GENEAread::read.bin() with auto-calibration, then aggregates
#' raw samples to 1-second epochs (mean x/y/z, sd x/y/z, sum svmg).
#'
#' SVMg computation:
#'   Per raw sample: svmg_sample = abs(sqrt(x^2 + y^2 + z^2) - 1)
#'   Per epoch:      svmg = sum(svmg_sample) across all samples in the epoch
#'
#' Reference: data/raw/GENEActiv/12615468/read_a_binFile_share.R
read_format_c <- function(filepath) {
  if (!requireNamespace("GENEAread", quietly = TRUE)) {
    stop("Package 'GENEAread' is required for .bin file processing.\n",
         "Install it with: install.packages('GENEAread')")
  }

  pupil_id <- extract_pupil_id(filepath, "raw_bin")
  log_step(paste("Reading .bin file:", basename(filepath)))

  # Read and calibrate
  content <- GENEAread::read.bin(filepath, calibrate = TRUE)
  raw_data <- as.data.frame(content$data.out)
  raw_data$button <- NULL  # not needed, save memory

  # Determine sampling frequency from the data
  record_freq <- as.numeric(content$header["Measurement_Frequency"])
  if (is.na(record_freq) || record_freq <= 0) {
    record_freq <- 100  # default GENEActiv frequency
    log_step(paste("Warning: could not determine frequency, assuming", record_freq, "Hz"))
  }

  epoch_seconds <- 1
  samples_per_epoch <- epoch_seconds * record_freq

  # Assign epoch group to each sample
  n_samples <- nrow(raw_data)
  n_epochs <- ceiling(n_samples / samples_per_epoch)
  epoch_group <- rep(seq_len(n_epochs), each = samples_per_epoch, length.out = n_samples)

  # Compute per-sample SVMg: abs(sqrt(x^2 + y^2 + z^2) - 1)
  # This is the Signal Vector Magnitude minus gravity
  svmg_sample <- abs(sqrt(raw_data$x^2 + raw_data$y^2 + raw_data$z^2) - 1)

  # Aggregate to 1-second epochs
  raw_data$epoch_group <- epoch_group
  raw_data$svmg_sample <- svmg_sample
  raw_data$ts <- as.POSIXct(raw_data$timestamp, origin = "1970-01-01", tz = "UTC")

  epoch_data <- raw_data |>
    dplyr::group_by(epoch_group) |>
    dplyr::summarise(
      timestamp = min(ts),
      x         = mean(x),
      y         = mean(y),
      z         = mean(z),
      light     = mean(light),
      temperature = mean(temperature),
      svmg      = sum(svmg_sample),
      x_std     = sd(x),
      y_std     = sd(y),
      z_std     = sd(z),
      .groups   = "drop"
    )

  result <- data.frame(
    pupil_id    = pupil_id,
    timestamp   = format(epoch_data$timestamp, "%Y-%m-%d %H:%M:%S"),
    x           = epoch_data$x,
    y           = epoch_data$y,
    z           = epoch_data$z,
    light       = epoch_data$light,
    temperature = epoch_data$temperature,
    svmg        = epoch_data$svmg,
    x_std       = epoch_data$x_std,
    y_std       = epoch_data$y_std,
    z_std       = epoch_data$z_std,
    stringsAsFactors = FALSE
  )

  # Free memory
  rm(content, raw_data, epoch_data, svmg_sample)
  gc()

  list(pupil_id = pupil_id, data = result)
}

#' Convert all files in a directory to the standard format
#'
#' @param input_dir Path to folder containing raw .bin or .csv files
#' @param output_dir Path to write normalised CSV files
#' @param overwrite If TRUE, re-convert existing files. Default FALSE.
#' @return Invisible data.frame with the full conversion log
convert_to_standard <- function(input_dir, output_dir, overwrite = FALSE) {
  if (!dir.exists(input_dir)) {
    stop("Input directory not found: ", input_dir,
         "\n  Check that the path exists and contains .csv or .bin files.")
  }

  # Find all input files
  all_files <- list.files(input_dir, pattern = "\\.(csv|bin)$",
                          full.names = TRUE, ignore.case = TRUE)

  # Exclude files that are clearly not data (e.g. R scripts, logs)
  all_files <- all_files[!grepl("\\.(R|r|py|txt|md|log)$", all_files)]

  if (length(all_files) == 0) {
    stop("No .csv or .bin files found in: ", input_dir)
  }

  log_step(paste("Found", length(all_files), "files to convert in", input_dir))

  # Process each file
  log_entries <- lapply(all_files, function(f) {
    log_step(paste("Processing:", basename(f)))
    convert_single_file(f, output_dir, overwrite = overwrite)
  })

  conversion_log <- do.call(rbind, log_entries)

  # Report summary
  n_ok <- sum(conversion_log$status == "success")
  n_skip <- sum(conversion_log$status == "skipped")
  n_err <- sum(conversion_log$status == "error")
  log_step(paste("Conversion complete:", n_ok, "converted,",
                 n_skip, "skipped,", n_err, "errors"))

  if (n_err > 0) {
    errors <- conversion_log[conversion_log$status == "error", ]
    message("\n  Errors:")
    for (i in seq_len(nrow(errors))) {
      message("    ", errors$file[i], ": ", errors$message[i])
    }
  }

  # Write the conversion log
  log_dir <- dirname(output_dir)
  log_dir <- file.path(log_dir, "logs")
  dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
  log_path <- file.path(log_dir, "conversion_log.csv")
  write.csv(conversion_log, log_path, row.names = FALSE)
  log_step(paste("Conversion log written to", log_path))

  invisible(conversion_log)
}

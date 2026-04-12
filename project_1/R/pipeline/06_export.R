# =============================================================================
# SchoolMoves Pipeline — Step 6: Export
# =============================================================================
# Writes processed data and GGIR summaries to the output directory.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Export processed epoch data (per-pupil files)
#'
#' @param epochs data.frame — full processed epoch dataset
#' @param output_dir Path to write output files (one per pupil)
#' @param format One of "csv" or "parquet". Default "csv".
#' @return Invisible character vector of output file paths
export_processed <- function(epochs, output_dir = "data/processed/", format = "csv") {
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  format <- tolower(format)
  if (!format %in% c("csv", "parquet")) {
    stop("Unsupported output format: '", format, "'. Use 'csv' or 'parquet'.")
  }
  if (format == "parquet" && !requireNamespace("arrow", quietly = TRUE)) {
    message("Package 'arrow' not installed. Falling back to CSV format.")
    format <- "csv"
  }

  pupil_ids <- unique(epochs$pupil_id)
  log_step(paste("Exporting", length(pupil_ids), "pupils to", output_dir,
                 "(format:", format, ")"))

  ext <- if (format == "parquet") ".parquet" else ".csv"
  output_paths <- character(length(pupil_ids))

  for (i in seq_along(pupil_ids)) {
    pid <- pupil_ids[i]
    pupil_data <- epochs[epochs$pupil_id == pid, ]
    out_path <- file.path(output_dir, paste0(pid, ext))

    if (format == "parquet") {
      arrow::write_parquet(pupil_data, out_path)
    } else {
      write.csv(pupil_data, out_path, row.names = FALSE)
    }
    output_paths[i] <- out_path
  }

  log_step(paste("Exported", length(output_paths), "files"))
  invisible(output_paths)
}

#' Export a summary table
#'
#' @param df data.frame to export
#' @param filepath Output file path (with extension)
#' @param format One of "csv" or "parquet". Inferred from filepath if not given.
export_summary <- function(df, filepath, format = NULL) {
  if (is.null(format)) {
    format <- if (grepl("\\.parquet$", filepath)) "parquet" else "csv"
  }

  dir.create(dirname(filepath), showWarnings = FALSE, recursive = TRUE)

  if (format == "parquet" && requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_parquet(df, filepath)
  } else {
    write.csv(df, filepath, row.names = FALSE)
  }

  log_step(paste("Exported summary:", filepath))
  invisible(filepath)
}

#' Copy GGIR native output files to the export directory
#'
#' @param ggir_dir Path to GGIR output directory
#' @param export_dir Path to write copies
export_ggir_summaries <- function(ggir_dir, export_dir) {
  dir.create(export_dir, showWarnings = FALSE, recursive = TRUE)

  results_dir <- file.path(ggir_dir, "results")
  if (!dir.exists(results_dir)) {
    log_step("No GGIR results directory to export")
    return(invisible(NULL))
  }

  csv_files <- list.files(results_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(csv_files) > 0) {
    file.copy(csv_files, file.path(export_dir, basename(csv_files)), overwrite = TRUE)
    log_step(paste("Copied", length(csv_files), "GGIR summary files to", export_dir))
  }

  # Copy config.csv for reproducibility
  config_csv <- file.path(ggir_dir, "config.csv")
  if (file.exists(config_csv)) {
    file.copy(config_csv, file.path(export_dir, "ggir_config.csv"), overwrite = TRUE)
  }

  invisible(export_dir)
}

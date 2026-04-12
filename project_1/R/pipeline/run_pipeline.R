# =============================================================================
# SchoolMoves Pipeline — Master Script
# =============================================================================
# Runs the full pipeline: prepare → GGIR → read output → label → validate → export.
#
# Usage:
#   Rscript R/pipeline/run_pipeline.R --input data/raw/ --output data/processed/
#   Rscript R/pipeline/run_pipeline.R --input data/raw/ --output data/processed/ --config config/pipeline_params.yaml
#
# Or call run_full_pipeline() directly from R.
# =============================================================================

# Source all pipeline modules
source("R/pipeline/utils.R", local = FALSE)
source("R/pipeline/01_prepare_input.R", local = FALSE)
source("R/pipeline/02_run_ggir.R", local = FALSE)
source("R/pipeline/03_read_ggir_output.R", local = FALSE)
source("R/pipeline/04_label_schedule.R", local = FALSE)
source("R/pipeline/05_filter_validity.R", local = FALSE)
source("R/pipeline/06_export.R", local = FALSE)

# Source analysis modules
source("R/analysis/activity_totals.R", local = FALSE)
source("R/analysis/sleep_analysis.R", local = FALSE)
source("R/analysis/sedentary_bouts.R", local = FALSE)

#' Run the full SchoolMoves pipeline
#'
#' @param input_dir Path to raw .bin or .csv files
#' @param output_dir Path for all pipeline output
#' @param config_path Path to pipeline_params.yaml
#' @param schedule_path Path to school_schedules.yaml
#' @param use_ggir If TRUE (default), run official GGIR pipeline.
#'   If FALSE, use legacy bypass for pre-processed CSVs.
#' @param n_cores Number of parallel cores for GGIR. Default 1.
#' @return Invisible list with pipeline results
run_full_pipeline <- function(input_dir,
                              output_dir,
                              config_path = "config/pipeline_params.yaml",
                              schedule_path = "config/school_schedules.yaml",
                              use_ggir = TRUE,
                              n_cores = 1) {

  start_time <- Sys.time()
  log_step("========================================")
  log_step("SchoolMoves Pipeline — Starting")
  log_step("========================================")
  log_step(paste("Input:   ", input_dir))
  log_step(paste("Output:  ", output_dir))
  log_step(paste("Config:  ", config_path))
  log_step(paste("Mode:    ", if (use_ggir) "Official GGIR (Parts 1-5)" else "Legacy bypass"))

  # --- Load configuration ---
  params <- read_pipeline_params(config_path)

  # --- Step 1: Prepare input ---
  log_step("--- Step 1: Prepare input ---")
  input_info <- prepare_input(input_dir, output_dir, overwrite = FALSE)

  n_ggir_files <- sum(input_info$manifest$ggir_compatible)
  n_bypass_files <- length(input_info$bypass_files)

  results <- list()

  # --- Step 2: Run GGIR on compatible files ---
  if (use_ggir && n_ggir_files > 0) {
    log_step("--- Step 2: GGIR processing (Parts 1-5) ---")
    ggir_output_dir <- file.path(output_dir, "ggir")
    run_ggir(input_info$ggir_input_dir, ggir_output_dir, params,
             schedule_path = schedule_path, n_cores = n_cores)

    # --- Step 3: Read GGIR output ---
    log_step("--- Step 3: Read GGIR output ---")
    ggir_data <- load_all_ggir_output(ggir_output_dir)
    results$ggir <- ggir_data

    # --- Step 4: Label school contexts ---
    log_step("--- Step 4: School schedule labelling ---")
    qwindow <- build_qwindow_from_schedules(schedule_path)
    context_map <- build_qwindow_context_map(schedule_path, qwindow)
    results$context_map <- context_map

    if (!is.null(ggir_data$part5_daysummary)) {
      results$activity_totals <- compute_activity_totals_ggir(
        ggir_data$part5_daysummary, context_map
      )
    }

    # --- Step 5: Assess validity ---
    log_step("--- Step 5: Validity assessment ---")
    if (!is.null(ggir_data$part2_daysummary)) {
      results$validity <- assess_validity_from_ggir(
        ggir_data$part2_daysummary, ggir_data$part4_sleep, params
      )
    }

    # --- Sleep analysis ---
    if (!is.null(ggir_data$part4_sleep)) {
      results$sleep <- summarise_sleep_ggir(ggir_data$part4_sleep)
    }

    # --- Step 6: Export ---
    log_step("--- Step 6: Export ---")
    analysis_dir <- file.path(output_dir, "analysis")
    dir.create(analysis_dir, showWarnings = FALSE, recursive = TRUE)

    if (!is.null(results$activity_totals)) {
      export_summary(results$activity_totals,
                     file.path(analysis_dir, "activity_totals.csv"))
    }
    if (!is.null(results$validity)) {
      write_validity_report(results$validity, output_dir)
    }
    if (!is.null(results$sleep)) {
      export_summary(results$sleep,
                     file.path(analysis_dir, "sleep_summary.csv"))
    }

  } else if (!use_ggir || n_ggir_files == 0) {
    # Legacy bypass for pre-processed files
    log_step("--- Step 2: Legacy bypass processing ---")
    all_bypass_files <- if (n_bypass_files > 0) input_info$bypass_files
                        else list.files(input_info$ggir_input_dir,
                                       pattern = "\\.csv$", full.names = TRUE)

    if (length(all_bypass_files) == 0) {
      stop("No files to process.")
    }

    epochs <- run_legacy_bypass(all_bypass_files, params)

    # Classify intensity (manual cut-points for bypass mode)
    epochs$intensity <- cut(
      epochs$enmo_mg,
      breaks = c(-Inf, params$threshold_lig, params$threshold_mod,
                 params$threshold_vig, Inf),
      labels = c("sedentary", "light", "moderate", "vigorous"),
      right = FALSE, ordered_result = TRUE
    )

    # Label school context
    log_step("--- Step 4: School schedule labelling ---")
    epochs <- label_school_context(epochs, schedule_config = schedule_path)

    # Assess validity
    log_step("--- Step 5: Validity assessment ---")
    validity <- assess_validity(epochs, params)
    results$validity <- validity

    # Export
    log_step("--- Step 6: Export ---")
    export_processed(epochs, file.path(output_dir, "epochs"), format = params$output_format)
    write_validity_report(validity, output_dir)
  }

  # Handle bypass files alongside GGIR (if both exist)
  if (use_ggir && n_bypass_files > 0) {
    log_step("--- Processing legacy bypass files ---")
    bypass_epochs <- run_legacy_bypass(input_info$bypass_files, params)
    results$bypass_epochs <- bypass_epochs
  }

  # --- Summary ---
  elapsed <- round(difftime(Sys.time(), start_time, units = "mins"), 1)
  log_step("========================================")
  log_step(paste("Pipeline complete in", elapsed, "minutes"))
  log_step(paste("GGIR files processed:", n_ggir_files))
  log_step(paste("Bypass files processed:", n_bypass_files))
  log_step(paste("Output:", output_dir))
  log_step("========================================")

  invisible(results)
}

# --- Command-line interface ---
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)

  input_dir <- NULL
  output_dir <- NULL
  config_path <- "config/pipeline_params.yaml"
  schedule_path <- "config/school_schedules.yaml"
  use_ggir <- TRUE  # GGIR is now the default
  n_cores <- 1

  i <- 1
  while (i <= length(args)) {
    if (args[i] == "--input" && i < length(args)) {
      input_dir <- args[i + 1]; i <- i + 2
    } else if (args[i] == "--output" && i < length(args)) {
      output_dir <- args[i + 1]; i <- i + 2
    } else if (args[i] == "--config" && i < length(args)) {
      config_path <- args[i + 1]; i <- i + 2
    } else if (args[i] == "--schedule" && i < length(args)) {
      schedule_path <- args[i + 1]; i <- i + 2
    } else if (args[i] == "--no-ggir") {
      use_ggir <- FALSE; i <- i + 1
    } else if (args[i] == "--cores" && i < length(args)) {
      n_cores <- as.integer(args[i + 1]); i <- i + 2
    } else {
      stop("Unknown argument: ", args[i],
           "\nUsage: Rscript run_pipeline.R --input <dir> --output <dir> [--config <yaml>] [--no-ggir] [--cores N]")
    }
  }

  if (is.null(input_dir) || is.null(output_dir)) {
    stop("Both --input and --output are required.\n",
         "Usage: Rscript R/pipeline/run_pipeline.R --input data/raw/ --output data/processed/")
  }

  run_full_pipeline(input_dir, output_dir, config_path, schedule_path, use_ggir, n_cores)
}

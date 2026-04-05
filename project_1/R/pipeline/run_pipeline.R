# =============================================================================
# SchoolMoves Pipeline — Master Script
# =============================================================================
# Runs the full pipeline: convert -> process -> classify -> label -> validate -> export.
#
# Usage:
#   Rscript R/pipeline/run_pipeline.R --input data/raw/ --output data/processed/
#   Rscript R/pipeline/run_pipeline.R --input data/raw/ --output data/processed/ --config config/pipeline_params.yaml
#
# Or call run_full_pipeline() directly from R.
# =============================================================================

# Source all pipeline modules
source("R/pipeline/utils.R", local = FALSE)
source("R/pipeline/01_convert.R", local = FALSE)
source("R/pipeline/02_ggir_process.R", local = FALSE)
source("R/pipeline/03_classify_activity.R", local = FALSE)
source("R/pipeline/04_label_schedule.R", local = FALSE)
source("R/pipeline/05_filter_validity.R", local = FALSE)
source("R/pipeline/06_export.R", local = FALSE)

#' Run the full SchoolMoves pipeline
#'
#' @param input_dir Path to raw .bin or .csv files
#' @param output_dir Path for all pipeline output
#' @param config_path Path to pipeline_params.yaml
#' @param schedule_path Path to school_schedules.yaml
#' @param use_ggir If TRUE, run full GGIR pipeline. If FALSE, use bypass mode
#'   for pre-processed CSVs. Default FALSE (bypass).
#' @return Invisible data.frame with validity results
run_full_pipeline <- function(input_dir,
                              output_dir,
                              config_path = "config/pipeline_params.yaml",
                              schedule_path = "config/school_schedules.yaml",
                              use_ggir = FALSE) {

  start_time <- Sys.time()
  log_step("========================================")
  log_step("SchoolMoves Pipeline — Starting")
  log_step("========================================")
  log_step(paste("Input:   ", input_dir))
  log_step(paste("Output:  ", output_dir))
  log_step(paste("Config:  ", config_path))
  log_step(paste("Mode:    ", if (use_ggir) "Full GGIR" else "Bypass (pre-processed)"))

  # --- Load configuration ---
  params <- read_pipeline_params(config_path)

  # --- Step 1: Convert to standard format ---
  log_step("--- Step 1: Format detection & conversion ---")
  converted_dir <- file.path(output_dir, "standardised")
  conversion_log <- convert_to_standard(input_dir, converted_dir, overwrite = FALSE)

  n_success <- sum(conversion_log$status == "success")
  if (n_success == 0) {
    stop("No files were successfully converted. Check the conversion log in logs/")
  }

  # --- Step 2: GGIR processing or bypass ---
  log_step("--- Step 2: Processing ---")
  if (use_ggir) {
    ggir_dir <- file.path(output_dir, "ggir")
    run_ggir(converted_dir, ggir_dir, params)
    epochs <- load_ggir_output(ggir_dir)
  } else {
    epochs <- run_bypass(converted_dir, params)
  }

  # --- Step 3: Classify intensity ---
  log_step("--- Step 3: Activity classification ---")
  thresholds <- build_thresholds(params)
  epochs <- classify_intensity(epochs, thresholds)

  # --- Step 4: Label school context ---
  log_step("--- Step 4: School schedule labelling ---")
  epochs <- label_school_context(epochs, schedule_path)

  # --- Step 5: Assess validity ---
  log_step("--- Step 5: Validity assessment ---")
  validity <- assess_validity(epochs, params)
  epochs <- merge(epochs, validity[, c("pupil_id", "pupil_valid_sedentary",
                                        "pupil_valid_sleep", "exclusion_reason")],
                  by = "pupil_id", all.x = TRUE)

  # --- Step 6: Export ---
  log_step("--- Step 6: Export ---")
  export_processed(epochs, output_dir, format = params$output_format)
  write_validity_report(validity, output_dir)

  # --- Summary ---
  elapsed <- round(difftime(Sys.time(), start_time, units = "mins"), 1)
  log_step("========================================")
  log_step(paste("Pipeline complete in", elapsed, "minutes"))
  log_step(paste("Pupils processed:", length(unique(epochs$pupil_id))))
  log_step(paste("Valid (waking):", sum(validity$pupil_valid_sedentary),
                 "/ Valid (sleep):", sum(validity$pupil_valid_sleep)))
  log_step(paste("Output:", output_dir))
  log_step("========================================")

  invisible(validity)
}

# --- Command-line interface ---
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)

  # Parse arguments
  input_dir <- NULL
  output_dir <- NULL
  config_path <- "config/pipeline_params.yaml"
  schedule_path <- "config/school_schedules.yaml"
  use_ggir <- FALSE

  i <- 1
  while (i <= length(args)) {
    if (args[i] == "--input" && i < length(args)) {
      input_dir <- args[i + 1]
      i <- i + 2
    } else if (args[i] == "--output" && i < length(args)) {
      output_dir <- args[i + 1]
      i <- i + 2
    } else if (args[i] == "--config" && i < length(args)) {
      config_path <- args[i + 1]
      i <- i + 2
    } else if (args[i] == "--schedule" && i < length(args)) {
      schedule_path <- args[i + 1]
      i <- i + 2
    } else if (args[i] == "--ggir") {
      use_ggir <- TRUE
      i <- i + 1
    } else {
      stop("Unknown argument: ", args[i],
           "\nUsage: Rscript run_pipeline.R --input <dir> --output <dir> [--config <yaml>] [--ggir]")
    }
  }

  if (is.null(input_dir) || is.null(output_dir)) {
    stop("Both --input and --output are required.\n",
         "Usage: Rscript R/pipeline/run_pipeline.R --input data/raw/ --output data/processed/")
  }

  run_full_pipeline(input_dir, output_dir, config_path, schedule_path, use_ggir)
}

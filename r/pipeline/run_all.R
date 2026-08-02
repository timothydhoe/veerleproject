# run_all.R
# ─────────────────────────────────────────────────────────────────────────────
# Full pipeline — runs all three steps in sequence.
#
# Steps:
#   01_run_ggir.R        GGIR processing (Parts 1–5) for both metingen
#   02_label_segments.R  Apply school schedule context labels
#   03_build_summaries.R Build analysis-ready tables + validity flags
#
# Before running:
#   1. Set dev.example_mode in config.yaml (true = dummy data, false = real data)
#   2. Confirm data folders exist (data/raw/meting_1, data/raw/meting_2)
#   3. Run from r/ directory (open SchoolMove.Rproj in RStudio)
#
# After running:
#   - Check outputs with:  source("qc/qc_01_ggir.R")
#                          source("qc/qc_02_segments.R")
#                          source("qc/qc_03_summaries.R")
#   - Launch dashboard with: shiny::runApp("shiny")
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)

`%||%` <- function(a, b) if (!is.null(a)) a else b

source("pipeline/validate_config.R", local = TRUE)
source("pipeline/utils_logging.R",   local = TRUE)

# Errors/warnings encountered anywhere below are additionally captured to
# this file (overwritten each run) — console output is unaffected, this is
# purely additive. See docs/test/feature_log.md #1.
PIPELINE_LOG <- file.path("logs", "pipeline_errors.txt")
init_pipeline_log(PIPELINE_LOG)

message("═══ SchoolMove Pipeline ══════════════════════════════════════════")
message("Starting at: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
message("")

t_start <- proc.time()

# ── Input manifest ─────────────────────────────────────────────────────────────
# Scans raw data directories, classifies each file, and writes logs/input_manifest.csv.
# This is a reproducibility record — does not change what GGIR receives.
source("pipeline/utils_input.R", local = TRUE)

cfg <- read_config_yaml("../config.yaml")
cfg <- apply_active_profile(cfg)
with_logged_conditions(validate_config(cfg), PIPELINE_LOG, "config validation")

if (isTRUE(cfg$dev$example_mode)) {
  raw_base <- file.path(cfg$paths$data_example, "dummy_data")
} else {
  raw_base <- cfg$paths$data_raw
}

with_logged_conditions({
  write_input_manifest(
    data_dirs = list(
      meting_1 = file.path(raw_base, "meting_1"),
      meting_2 = file.path(raw_base, "meting_2")
    ),
    logs_dir = "logs",
    valid_school_ids = suppressWarnings(as.integer(sub("^school_", "", names(cfg$schedules))))
  )
}, PIPELINE_LOG, "input manifest")

message("")

# ── Step 01: GGIR ─────────────────────────────────────────────────────────────
message("── Step 01: GGIR (Parts 1–5) ────────────────────────────────────")
with_logged_conditions(source("pipeline/01_run_ggir.R"), PIPELINE_LOG, "01_run_ggir.R")

# ── Archive GGIR config.csv for reproducibility ───────────────────────────────
# Copies GGIR's own parameter record into logs/ so every run is auditable.
ggir_processed_base <- cfg$paths$data_processed
for (meting in c("meting_1", "meting_2")) {
  ggir_out_pattern <- file.path(ggir_processed_base, meting)
  # GGIR creates output_<meting>/ inside the outputdir we gave it
  ggir_subdirs <- list.dirs(ggir_out_pattern, recursive = FALSE, full.names = TRUE)
  for (sd in ggir_subdirs) {
    cfg_src <- file.path(sd, "config.csv")
    if (file.exists(cfg_src)) {
      date_tag <- format(Sys.Date(), "%Y%m%d")
      dst_name <- paste0("ggir_config_", meting, "_", date_tag, ".csv")
      file.copy(cfg_src, file.path("logs", dst_name), overwrite = TRUE)
      message("[repro] Archived GGIR config: logs/", dst_name)
    }
  }
}

# ── Append run record to logs/pipeline_runs.csv ───────────────────────────────
run_record <- data.frame(
  timestamp    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  r_version    = paste(R.version$major, R.version$minor, sep = "."),
  ggir_version = as.character(utils::packageVersion("GGIR")),
  example_mode = isTRUE(cfg$dev$example_mode),
  active_profile = cfg$profiles$active %||% "default",
  stringsAsFactors = FALSE
)
runs_path <- file.path("logs", "pipeline_runs.csv")
if (file.exists(runs_path)) {
  existing <- read.csv(runs_path, stringsAsFactors = FALSE)
  run_record <- rbind(existing, run_record)
}
write.csv(run_record, runs_path, row.names = FALSE)
message("[repro] Run record appended to logs/pipeline_runs.csv")
message("")

# ── Step 02: Segment labels ───────────────────────────────────────────────────
message("── Step 02: Segment labels ──────────────────────────────────────")
with_logged_conditions(source("pipeline/02_label_segments.R"), PIPELINE_LOG, "02_label_segments.R")

# ── Step 02b: Epoch labels (opt-in, feature_log.md #2) ────────────────────────
# Only runs when config.yaml's bouts.enable_epoch_labeling is true — expensive
# at full study scale, and skipped by default. See 02b_label_epochs.R.
if (isTRUE(cfg$bouts$enable_epoch_labeling)) {
  message("── Step 02b: Epoch labels ───────────────────────────────────────")
  with_logged_conditions(source("pipeline/02b_label_epochs.R"), PIPELINE_LOG, "02b_label_epochs.R")
}

# ── Step 03: Build summaries ──────────────────────────────────────────────────
message("── Step 03: Build summaries ─────────────────────────────────────")
with_logged_conditions(source("pipeline/03_build_summaries.R"), PIPELINE_LOG, "03_build_summaries.R")

# ── Done ──────────────────────────────────────────────────────────────────────
t_elapsed <- proc.time() - t_start
message("")
message("═══ Pipeline complete ════════════════════════════════════════════")
message(sprintf("Total time: %.0f s", t_elapsed["elapsed"]))
message("")
message("Next steps:")
message("  Verify:   source('qc/qc_01_ggir.R')")
message("            source('qc/qc_02_segments.R')")
message("            source('qc/qc_03_summaries.R')")
message("  Dashboard: shiny::runApp('shiny')")

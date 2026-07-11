# run_example_pipeline.R
# ─────────────────────────────────────────────────────────────────────────────
# CI helper: temporarily switches config.yaml to dummy-data / quick-test mode,
# runs the full pipeline, then restores the original config.yaml exactly
# (byte-for-byte via readLines/writeLines) regardless of success or failure.
#
# Run from the r/ directory: Rscript ../scripts/ci/run_example_pipeline.R
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)

cfg_path <- "../config.yaml"
original_lines <- readLines(cfg_path, warn = FALSE)

# tryCatch(..., finally = ...) rather than on.exit(): on.exit() only attaches
# to a function's call frame, and this script runs at top level, so it would
# silently never fire. finally always runs, on success or error.
tryCatch({
  cfg <- yaml::read_yaml(cfg_path)
  cfg$dev$example_mode <- TRUE
  cfg$dev$quick_test_n <- 2
  yaml::write_yaml(cfg, cfg_path)
  message("[ci] config.yaml temporarily set to ",
          "example_mode: true, quick_test_n: 2")

  source("pipeline/run_all.R")
}, finally = {
  writeLines(original_lines, cfg_path)
  message("[ci] config.yaml restored to its original contents")
})

# smoke_test.R
# ─────────────────────────────────────────────────────────────────────────────
# Full pipeline smoke test — runs all three steps on example/dummy data and
# asserts the expected output files exist with the expected structure.
#
# Requires: dev.example_mode: true in config.yaml (the default)
# Run from r/ directory:  Rscript --vanilla tests/smoke_test.R
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

cfg <- yaml::read_yaml("../config.yaml")

if (!isTRUE(cfg$dev$example_mode)) {
  stop("smoke_test.R requires dev.example_mode: true in config.yaml.\n",
       "Set it before running this test to avoid processing real data.",
       call. = FALSE)
}

pass <- function(msg) cat(sprintf("  [PASS] %s\n", msg))
fail <- function(msg) { cat(sprintf("  [FAIL] %s\n", msg)); failures <<- failures + 1L }

failures <- 0L

cat("\n── SchoolMove Smoke Test ─────────────────────────────────────────────\n")
cat("Running full pipeline on dummy data...\n\n")

# ── Run pipeline ───────────────────────────────────────────────────────────────
t0 <- proc.time()
tryCatch(
  source("pipeline/run_all.R"),
  error = function(e) {
    cat(sprintf("  [FAIL] Pipeline aborted with error: %s\n", e$message))
    failures <<- failures + 1L
  }
)
elapsed <- (proc.time() - t0)["elapsed"]
cat(sprintf("\nPipeline finished in %.0f s\n\n", elapsed))

# ── Output file assertions ─────────────────────────────────────────────────────
out_dir <- file.path("..", cfg$paths$data_processed, "..")

cat("── Checking output files ──────────────────────────────────────────────\n")

# segment_summary.csv
seg_path <- file.path(out_dir, "segment_summary.csv")
if (!file.exists(seg_path)) {
  fail("segment_summary.csv not found")
} else {
  seg <- fread(seg_path)
  if (nrow(seg) >= 1) {
    pass(sprintf("segment_summary.csv — %d rows", nrow(seg)))
  } else {
    fail("segment_summary.csv exists but is empty")
  }
}

# analysis_ready.csv
ar_path <- file.path(out_dir, "analysis_ready.csv")
if (!file.exists(ar_path)) {
  fail("analysis_ready.csv not found")
} else {
  ar <- fread(ar_path)
  required_cols <- c("ID", "school", "meting", "n_valid_days")
  missing <- setdiff(required_cols, names(ar))
  if (length(missing) > 0) {
    fail(paste("analysis_ready.csv missing columns:", paste(missing, collapse = ", ")))
  } else {
    pass(sprintf("analysis_ready.csv — %d rows, required columns present", nrow(ar)))
  }
}

# validity_summary.csv
vs_path <- file.path(out_dir, "validity_summary.csv")
if (!file.exists(vs_path)) {
  fail("validity_summary.csv not found")
} else {
  vs <- fread(vs_path)
  if ("meets_sedentary_criteria" %in% names(vs)) {
    pass(sprintf("validity_summary.csv — %d participants, meets_sedentary_criteria column present", nrow(vs)))
  } else {
    fail("validity_summary.csv missing meets_sedentary_criteria column")
  }
}

# ── Summary ────────────────────────────────────────────────────────────────────
cat("\n── Smoke Test Summary ────────────────────────────────────────────────\n")
if (failures == 0L) {
  cat("  ALL CHECKS PASSED\n")
} else {
  cat(sprintf("  %d CHECK(S) FAILED — review output above\n", failures))
  quit(status = 1)
}

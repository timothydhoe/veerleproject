# check_outputs.R
# ─────────────────────────────────────────────────────────────────────────────
# Sanity checks on GGIR output. Run after 01_run_ggir.R to verify the pipeline
# completed correctly before opening the Shiny dashboard.
#
# Run from the r/ directory: Rscript validation/check_outputs.R
# Prints a summary of what passed / warned / failed to the console.
# ─────────────────────────────────────────────────────────────────────────────

library(data.table)
library(yaml)

cfg      <- yaml::read_yaml("../config.yaml")
base_dir <- cfg$paths$data_processed       # "../data/processed/ggir"
metingen <- c("meting_1", "meting_2")

pass <- function(msg) cat("[PASS]", msg, "\n")
fail <- function(msg) cat("[FAIL]", msg, "\n")
warn <- function(msg) cat("[WARN]", msg, "\n")

cat("── SchoolMove output checks ───────────────────────────────────────────\n\n")

# ── 1. For each meting: check key GGIR output files ──────────────────────────
for (meting in metingen) {
  results_dir <- file.path(base_dir, meting, paste0("output_", meting), "results")
  cat("  Checking", meting, "→", results_dir, "\n")

  if (!dir.exists(results_dir)) {
    fail(paste(meting, "— results directory not found (pipeline not yet run?)"))
    next
  }

  # Part 2 daily summary
  p2_path <- file.path(results_dir, "part2_daysummary.csv")
  if (file.exists(p2_path)) {
    dt2 <- fread(p2_path)
    pass(paste(meting, "— part2_daysummary.csv:", nrow(dt2), "rows"))
  } else {
    fail(paste(meting, "— part2_daysummary.csv missing"))
  }

  # Part 5 day summary (filename includes cut-point label)
  p5_files <- list.files(results_dir, pattern = "^part5_daysummary_WW_", full.names = TRUE)
  if (length(p5_files) > 0) {
    dt5 <- fread(p5_files[1])
    if (nrow(dt5) == 0) {
      warn(paste(meting, "— part5_daysummary is empty (too few valid days?)"))
    } else {
      pass(paste(meting, "— part5_daysummary:", nrow(dt5), "rows"))
    }

    # Check expected activity columns exist
    required_cols <- c("dur_day_total_IN_min", "dur_day_total_LIG_min",
                       "dur_day_total_MOD_min", "dur_day_total_VIG_min")
    missing_cols <- setdiff(required_cols, names(dt5))
    if (length(missing_cols) == 0) {
      pass(paste(meting, "— activity intensity columns present"))
    } else {
      fail(paste(meting, "— missing columns:", paste(missing_cols, collapse = ", ")))
    }
  } else {
    fail(paste(meting, "— part5_daysummary (WW) not found"))
  }

  cat("\n")
}

# ── 2. Fallback schedule warning ──────────────────────────────────────────────
fallback_schools <- Filter(
  function(s) isTRUE(cfg$schedules[[s]]$fallback),
  names(cfg$schedules)
)
if (length(fallback_schools) > 0) {
  warn(paste(
    "Schools using fallback (unconfirmed) schedules:",
    paste(fallback_schools, collapse = ", ")
  ))
} else {
  pass("All school schedules are confirmed (no fallbacks)")
}

# ── 3. Cut-points configured? ─────────────────────────────────────────────────
cp <- cfg$ggir$cut_points_mg
if (is.null(cp)) {
  warn("Cut-points not set in config.yaml — activity classification unavailable")
} else {
  pass(paste0(
    "Cut-points configured: SB <", cp$sedentary_to_light,
    " | LPA ", cp$sedentary_to_light, "–", cp$light_to_moderate,
    " | MPA ", cp$light_to_moderate, "–", cp$moderate_to_vigorous,
    " | VPA >", cp$moderate_to_vigorous, " mg"
  ))
}

cat("\n── Done ───────────────────────────────────────────────────────────────\n")

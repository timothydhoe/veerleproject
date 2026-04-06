# global.R
# ─────────────────────────────────────────────────────────────────────────────
# Loaded once when the Shiny app starts (before ui.R and server.R).
# ─────────────────────────────────────────────────────────────────────────────

library(shiny)
library(bslib)
library(DT)
library(ggplot2)
library(data.table)
library(yaml)

# Config -----------------------------------------------------------------------
cfg            <- yaml::read_yaml("../../config.yaml")
data_processed <- file.path("..", cfg$paths$data_processed)
schools        <- names(cfg$schedules)
n_schools      <- length(schools)
metingen       <- c("meting_1", "meting_2")

SCHOOL_LABELS  <- setNames(
  paste("School", seq_along(schools)),
  schools
)

# Helper: participant code → school ID ----------------------------------------
extract_school_id <- function(id) {
  code <- suppressWarnings(as.integer(sub("\\.csv$", "", basename(id))))
  paste0("school_", code %/% 1000L)
}

# Helper: load a GGIR results CSV for a given meting --------------------------
load_ggir_summary <- function(meting, filename = NULL, pattern = NULL) {
  results_dir <- file.path(
    data_processed, meting,
    paste0("output_", meting), "results"
  )

  if (!dir.exists(results_dir)) {
    message("GGIR results not found for ", meting,
            " — run pipeline/01_run_ggir.R first.")
    return(NULL)
  }

  if (!is.null(pattern)) {
    files <- list.files(results_dir, pattern = pattern, full.names = TRUE)
    if (length(files) == 0) {
      message("No files matching '", pattern, "' in ", results_dir)
      return(NULL)
    }
    path <- files[1]
  } else {
    path <- file.path(results_dir, filename)
  }

  if (!file.exists(path)) {
    message("File not found: ", path)
    return(NULL)
  }

  dt        <- fread(path, data.table = TRUE)
  dt[, meting := meting]
  dt[, school := extract_school_id(ID)]
  dt
}

# Load GGIR outputs for all metingen ------------------------------------------
part2_list      <- lapply(metingen, load_ggir_summary,
                          filename = "part2_daysummary.csv")
part5_day_list  <- lapply(metingen, load_ggir_summary,
                          pattern  = "^part5_daysummary_WW_")
part5_pers_list <- lapply(metingen, load_ggir_summary,
                          pattern  = "^part5_personsummary_WW_")

part2      <- rbindlist(Filter(Negate(is.null), part2_list),  fill = TRUE)
part5_day  <- rbindlist(Filter(Negate(is.null), part5_day_list),  fill = TRUE)
part5_pers <- rbindlist(Filter(Negate(is.null), part5_pers_list), fill = TRUE)

setnames(part2,
         old = c("N valid hours", "N hours"),
         new = c("n_valid_hours",  "n_hours"),
         skip_absent = TRUE)

# Validity flag per participant-day (Part 2) ----------------------------------
if (nrow(part2) > 0) {
  min_wear <- if (isTRUE(cfg$dev$example_mode) && !is.null(cfg$dev$includedaycrit)) {
    cfg$dev$includedaycrit
  } else {
    cfg$validity$min_wear_hours_per_day
  }
  part2[, valid_day := n_valid_hours >= min_wear]
}

# Participant-level validity summary ------------------------------------------
if (nrow(part2) > 0) {
  participant_validity <- part2[
    , .(
        n_days       = .N,
        n_valid_days = sum(valid_day, na.rm = TRUE),
        mean_wear_h  = round(mean(n_valid_hours, na.rm = TRUE), 1),
        has_weekend  = any(weekday %in% c("Saturday", "Sunday") & valid_day,
                           na.rm = TRUE)
      ),
    by = .(ID, school, meting)
  ]
  min_days  <- cfg$validity$min_valid_days
  need_wknd <- isTRUE(cfg$validity$require_weekend_day)
  participant_validity[,
    meets_criteria := n_valid_days >= min_days & (!need_wknd | has_weekend)
  ]
} else {
  participant_validity <- data.table()
}

# Segment summary (School Day tab) --------------------------------------------
seg_path <- file.path(data_processed, "segment_summary.csv")
if (file.exists(seg_path)) {
  segment_summary <- fread(seg_path, data.table = TRUE)
  segment_summary[, school_label := SCHOOL_LABELS[school]]
  segment_summary[, school_label := factor(
    school_label, levels = paste("School", 1:6)
  )]
  # Ordered factor for readable chart axis
  SEGMENT_LEVELS  <- c("before_school", "in_class", "recess", "lunch", "after_school")
  SEGMENT_LABELS  <- c("Before school", "In class", "Recess", "Lunch", "After school")
  segment_summary[, segment := factor(segment, levels = SEGMENT_LEVELS,
                                      labels = SEGMENT_LABELS)]
} else {
  message("segment_summary.csv not found — School Day tab will be empty.")
  message("Run pipeline/02_compute_segments.R to generate it.")
  segment_summary <- data.table()
}

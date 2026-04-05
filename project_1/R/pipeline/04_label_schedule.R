# =============================================================================
# SchoolMoves Pipeline — Step 4: School Schedule Labelling
# =============================================================================
# Adds 'context' and 'schedule_source' columns to epoch data by matching
# each epoch's timestamp against the school schedule configuration.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Load and parse the school schedule YAML
#'
#' @param config_path Path to school_schedules.yaml
#' @return List of school schedule definitions
load_school_schedules <- function(config_path = "config/school_schedules.yaml") {
  if (!file.exists(config_path)) {
    stop("School schedule config not found: ", config_path)
  }
  config <- yaml::read_yaml(config_path)
  config$schools
}

#' Extract school_id from a pupil_id
#'
#' Convention: for 4-digit IDs, first digit = school_id.
#' For longer IDs (Format B), first digit = school_id.
#'
#' @param pupil_id Character vector of pupil IDs
#' @return Integer vector of school IDs
get_school_id <- function(pupil_id) {
  as.integer(substr(pupil_id, 1, 1))
}

#' Label epochs with school context
#'
#' For each epoch, determines the context based on:
#'   1. Day of week: Saturday/Sunday -> "weekend"
#'   2. Time of day matched against the school's block schedule
#'   3. Gaps between blocks -> "unknown"
#'
#' @param epochs data.frame with columns: pupil_id, timestamp (POSIXct), date
#' @param schedule_config Path to school_schedules.yaml
#' @return Same data.frame with added columns: context, schedule_source, school_id
label_school_context <- function(epochs, schedule_config = "config/school_schedules.yaml") {
  schedules <- load_school_schedules(schedule_config)

  # Build a lookup: school_id -> schedule
  schedule_lookup <- list()
  for (sch in schedules) {
    schedule_lookup[[as.character(sch$school_id)]] <- sch
  }

  # Derive school_id from pupil_id
  epochs$school_id <- get_school_id(epochs$pupil_id)

  # Pre-allocate columns
  epochs$context <- "unknown"
  epochs$schedule_source <- NA_character_

  # Determine day of week (1=Monday in Belgian locale, but use wday for safety)
  if (!inherits(epochs$timestamp, "POSIXct")) {
    epochs$timestamp <- as.POSIXct(epochs$timestamp, tz = "Europe/Brussels")
  }
  day_of_week <- lubridate::wday(epochs$timestamp, week_start = 1)  # 1=Mon, 7=Sun

  # Weekend detection
  is_weekend <- day_of_week >= 6
  epochs$context[is_weekend] <- "weekend"

  # For weekdays, match against school schedule blocks
  weekday_idx <- which(!is_weekend)
  if (length(weekday_idx) == 0) {
    log_step("All epochs fall on weekends — no schedule labelling needed")
    return(epochs)
  }

  # Extract time-of-day as seconds since midnight for fast matching
  time_of_day <- as.numeric(format(epochs$timestamp[weekday_idx], "%H")) * 3600 +
                 as.numeric(format(epochs$timestamp[weekday_idx], "%M")) * 60 +
                 as.numeric(format(epochs$timestamp[weekday_idx], "%S"))

  school_ids <- epochs$school_id[weekday_idx]

  for (sid_char in names(schedule_lookup)) {
    sch <- schedule_lookup[[sid_char]]
    sid <- as.integer(sid_char)
    mask <- school_ids == sid

    if (!any(mask)) next

    epochs$schedule_source[weekday_idx[mask]] <- sch$schedule_source

    for (block in sch$blocks) {
      # Parse block times to seconds since midnight
      block_start <- time_str_to_seconds(block$start)
      block_end   <- time_str_to_seconds(block$end)

      in_block <- mask & (time_of_day >= block_start) & (time_of_day < block_end)
      epochs$context[weekday_idx[in_block]] <- block$context
    }
  }

  # Set schedule_source for weekends
  for (sid_char in names(schedule_lookup)) {
    sch <- schedule_lookup[[sid_char]]
    sid <- as.integer(sid_char)
    epochs$schedule_source[is_weekend & epochs$school_id == sid] <- sch$schedule_source
  }

  # Summary
  ctx_table <- table(epochs$context)
  log_step(paste("Context labels assigned:",
                 paste(names(ctx_table), ctx_table, sep = "=", collapse = ", ")))

  epochs
}

#' Convert "HH:MM" time string to seconds since midnight
#'
#' @param time_str Character like "08:30" or "15:00"
#' @return Numeric seconds since midnight
time_str_to_seconds <- function(time_str) {
  parts <- as.numeric(strsplit(time_str, ":")[[1]])
  parts[1] * 3600 + parts[2] * 60
}

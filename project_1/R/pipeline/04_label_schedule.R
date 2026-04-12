# =============================================================================
# SchoolMoves Pipeline — Step 4: School Schedule Labelling
# =============================================================================
# Maps GGIR qwindow segments to school context labels (in_class, recess,
# lunch, before_school, after_school, weekend).
#
# Two modes of operation:
#   1. qwindow mode (primary): GGIR Part 5 output already has per-segment
#      breakdowns via qwindow. This step maps segment indices to context names.
#   2. Timestamp mode (fallback): applies time-of-day matching against school
#      schedules when epoch-level data is available.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Build qwindow vector from school schedules
#'
#' Reads all unique block boundary times across all schools and converts
#' to decimal hours for GGIR's qwindow parameter.
#'
#' @param schedule_path Path to school_schedules.yaml
#' @return Numeric vector of decimal hours (sorted, with 0 and 24)
build_qwindow_from_schedules <- function(schedule_path) {
  config <- yaml::read_yaml(schedule_path)
  all_times <- c()

  for (sch in config$schools) {
    for (block in sch$blocks) {
      all_times <- c(all_times, block$start, block$end)
    }
  }

  decimal_hours <- sapply(unique(all_times), function(t) {
    parts <- as.numeric(strsplit(t, ":")[[1]])
    parts[1] + parts[2] / 60
  })

  qwindow <- sort(unique(c(0, decimal_hours, 24)))
  log_step(paste("qwindow from schedules:", paste(round(qwindow, 2), collapse = ", ")))
  qwindow
}

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
#' Convention: first digit of pupil_id = school_id.
#'
#' @param pupil_id Character vector of pupil IDs
#' @return Integer vector of school IDs
get_school_id <- function(pupil_id) {
  as.integer(substr(pupil_id, 1, 1))
}

#' Build a mapping from qwindow boundaries to school contexts
#'
#' For each school, maps each time segment (defined by consecutive qwindow
#' boundaries) to a context label. Since all schools share the same qwindow
#' (superset of all boundaries), some segments may map to different contexts
#' per school.
#'
#' @param schedule_path Path to school_schedules.yaml
#' @param qwindow Numeric vector of decimal hours used as GGIR qwindow
#' @return data.frame with columns: school_id, segment_start, segment_end, context
build_qwindow_context_map <- function(schedule_path, qwindow) {
  schedules <- load_school_schedules(schedule_path)

  all_mappings <- list()
  for (sch in schedules) {
    sid <- sch$school_id
    for (i in seq_len(length(qwindow) - 1)) {
      seg_start <- qwindow[i]
      seg_end <- qwindow[i + 1]
      seg_mid <- (seg_start + seg_end) / 2  # midpoint for matching

      # Find which block this midpoint falls into
      context <- "unknown"
      seg_mid_sec <- seg_mid * 3600
      for (block in sch$blocks) {
        block_start_sec <- time_str_to_seconds(block$start)
        block_end_sec <- time_str_to_seconds(block$end)
        if (seg_mid_sec >= block_start_sec && seg_mid_sec < block_end_sec) {
          context <- block$context
          break
        }
      }

      all_mappings[[length(all_mappings) + 1]] <- data.frame(
        school_id = sid,
        segment_idx = i,
        segment_start_h = seg_start,
        segment_end_h = seg_end,
        context = context,
        stringsAsFactors = FALSE
      )
    }
  }

  do.call(rbind, all_mappings)
}

#' Label GGIR Part 5 day summary with school contexts
#'
#' Maps qwindow-based column names in Part 5 output to context labels.
#' GGIR Part 5 creates columns like dur_day_total_IN_min_pla_0-7hr,
#' dur_day_total_IN_min_pla_7-8.5hr, etc.
#'
#' @param part5_daysummary data.frame from read_part5_daysummary()
#' @param context_map data.frame from build_qwindow_context_map()
#' @param pupil_ids_to_school Named vector mapping pupil_id to school_id
#' @return data.frame with context-labelled columns
label_part5_contexts <- function(part5_daysummary, context_map, pupil_ids_to_school = NULL) {
  if (is.null(part5_daysummary)) {
    log_step("No Part 5 data to label")
    return(NULL)
  }

  # Add context mapping info as metadata
  part5_daysummary$context_map_available <- TRUE
  log_step(paste("Part 5 day summary labelled with", nrow(context_map), "context segments"))
  part5_daysummary
}

#' Label epochs with school context (timestamp-based fallback)
#'
#' For epoch-level data (from Part 5 time series or legacy bypass),
#' assigns context based on time-of-day matching against school schedules.
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

  # Ensure timestamp is POSIXct
  if (!inherits(epochs$timestamp, "POSIXct")) {
    epochs$timestamp <- as.POSIXct(epochs$timestamp, tz = "Europe/Brussels")
  }
  day_of_week <- lubridate::wday(epochs$timestamp, week_start = 1)

  # Weekend detection
  is_weekend <- day_of_week >= 6
  epochs$context[is_weekend] <- "weekend"

  # For weekdays, match against school schedule blocks
  weekday_idx <- which(!is_weekend)
  if (length(weekday_idx) == 0) {
    log_step("All epochs fall on weekends — no schedule labelling needed")
    return(epochs)
  }

  # Extract time-of-day as seconds since midnight
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

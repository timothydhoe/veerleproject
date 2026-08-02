# utils_schedule.R
# ─────────────────────────────────────────────────────────────────────────────
# Shared school-schedule lookup logic, used by both 02_label_segments.R
# (day-level context labeling) and 02b_label_epochs.R (epoch-level context
# labeling, feature_log.md #2). Extracted out of 02_label_segments.R so both
# consumers stay in sync instead of drifting via copy-paste.
#
# Depends on hm_to_h() from utils_ggir.R and the %||% operator — callers must
# source utils_ggir.R before this file. %||% is defined here too (guarded) so
# this file also works if sourced standalone (e.g. from tests).
# ─────────────────────────────────────────────────────────────────────────────

if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

#' Get the school-day schedule for a school + weekday
#'
#' Returns a data.frame with columns: segment, start_h, end_h — one row per
#' school-day segment (before_school, in_class, recess/lunch/etc., after_school).
#'
#' @param school_id Character, e.g. "school_1".
#' @param wday_name Full weekday name (e.g. "Monday"). Case-insensitive.
#' @param schedules Named list — cfg$schedules.
#' @return data.table, or NULL if the school isn't configured.
get_schedule <- function(school_id, wday_name, schedules) {
  sch <- schedules[[school_id]]
  if (is.null(sch)) return(NULL)

  school_start <- hm_to_h(sch$school_start)

  wday_lower <- tolower(wday_name)
  if (wday_lower == "wednesday") {
    school_end <- hm_to_h(sch$school_end$wednesday %||% sch$school_end$mon_tue_thu_fri)
    breaks_key <- "wednesday"
  } else {
    school_end <- hm_to_h(
      sch$school_end[[wday_lower]] %||%
      sch$school_end$mon_tue_thu_fri %||%
      sch$school_end$mon_thu_fri
    )
    breaks_key <- "mon_tue_thu_fri"
  }

  segments <- list()

  segments <- c(segments, list(data.frame(
    segment = "before_school", start_h = 0, end_h = school_start
  )))

  breaks <- sch$breaks[[breaks_key]]
  if (is.null(breaks) || length(breaks) == 0) breaks <- list()

  if (length(breaks) > 0) {
    break_starts <- sapply(breaks, function(b) hm_to_h(b$start))
    breaks <- breaks[order(break_starts)]
  }

  cursor <- school_start
  for (brk in breaks) {
    brk_start <- hm_to_h(brk$start)
    brk_end   <- hm_to_h(brk$end)
    if (brk_start > cursor && brk_start < school_end) {
      segments <- c(segments, list(data.frame(
        segment = "in_class", start_h = cursor, end_h = brk_start
      )))
    }
    seg_label <- if (!is.null(brk$label)) brk$label else "recess"
    segments <- c(segments, list(data.frame(
      segment = seg_label, start_h = brk_start, end_h = min(brk_end, school_end)
    )))
    cursor <- min(brk_end, school_end)
  }

  if (cursor < school_end) {
    segments <- c(segments, list(data.frame(
      segment = "in_class", start_h = cursor, end_h = school_end
    )))
  }

  segments <- c(segments, list(data.frame(
    segment = "after_school", start_h = school_end, end_h = 24
  )))

  data.table::rbindlist(lapply(segments, data.table::as.data.table))
}

#' Extract school ID from participant code (4-digit, first digit = school 1-6)
#'
#' @param id Character or numeric participant ID / filename.
#' @return Character vector like "school_1", or "school_NA" when unparseable.
extract_school_id <- function(id) {
  code     <- suppressWarnings(as.integer(sub("\\.[^.]+$", "", basename(as.character(id)))))
  school_n <- code %/% 1000L
  school_n[is.na(school_n) | school_n < 1L | school_n > 6L] <- NA_integer_
  paste0("school_", school_n)
}

#' Build the pupil -> class-override map
#'
#' For schools with class_overrides: maps pupil_id (character) to a list with
#' $class (class name, e.g. "2Aa") and $overrides (named list: weekday_lower
#' -> override school_end, e.g. "16:25").
#'
#' @param cfg Full config list (cfg$schedules used).
#' @return Named list keyed by pupil_id.
build_pupil_override_map <- function(cfg) {
  pupil_override_map <- list()
  for (school_id in names(cfg$schedules)) {
    class_overrides <- cfg$schedules[[school_id]]$class_overrides
    if (is.null(class_overrides)) next
    for (class_name in names(class_overrides)) {
      co <- class_overrides[[class_name]]
      for (pupil in as.character(co$pupils)) {
        pupil_override_map[[pupil]] <- list(
          class     = class_name,
          overrides = co$school_end_override
        )
      }
    }
  }
  pupil_override_map
}

#' Build the school x weekday (x class-override variant) schedule cache
#'
#' @param cfg Full config list (cfg$schedules used).
#' @return Named list keyed by "school_weekday" (and "school_class_weekday"
#'   for class-override variants), each value a get_schedule() data.table.
build_schedule_cache <- function(cfg) {
  weekdays_list  <- c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
  schedule_cache <- list()

  for (school_id in names(cfg$schedules)) {
    for (wday in weekdays_list) {
      key <- paste(school_id, wday, sep = "_")
      sched <- tryCatch(
        get_schedule(school_id, wday, cfg$schedules),
        error = function(e) {
          warning(sprintf("Could not build schedule for %s %s: %s", school_id, wday, e$message))
          NULL
        }
      )
      if (!is.null(sched)) schedule_cache[[key]] <- sched
    }

    class_overrides <- cfg$schedules[[school_id]]$class_overrides
    if (is.null(class_overrides)) next
    for (class_name in names(class_overrides)) {
      co <- class_overrides[[class_name]]
      for (wday_lower in names(co$school_end_override)) {
        override_end <- co$school_end_override[[wday_lower]]
        wday_name    <- paste0(toupper(substring(wday_lower, 1, 1)),
                               substring(wday_lower, 2))
        sch_mod <- cfg$schedules[[school_id]]
        sch_mod$school_end[[wday_lower]] <- override_end
        sch_mod$class_overrides          <- NULL  # avoid recursion
        cache_key <- paste(school_id, class_name, wday_lower, sep = "_")
        sched <- tryCatch(
          get_schedule(school_id, wday_name, setNames(list(sch_mod), school_id)),
          error = function(e) {
            warning(sprintf("Could not build class schedule for %s %s %s: %s",
                            school_id, class_name, wday_lower, e$message))
            NULL
          }
        )
        if (!is.null(sched)) schedule_cache[[cache_key]] <- sched
      }
    }
  }

  schedule_cache
}

#' Resolve the schedule-cache key to use for a given participant/school/weekday
#'
#' Applies per-pupil class overrides (school_end_override) when applicable,
#' falling back to the plain school/weekday key otherwise.
#'
#' @param id Participant ID (raw, filename-shaped is fine — pupil_key is
#'   derived the same way 02_label_segments.R always has).
#' @param school school_id string, e.g. "school_3".
#' @param wday Full weekday name (e.g. "Tuesday").
#' @param schedule_cache From build_schedule_cache().
#' @param pupil_override_map From build_pupil_override_map().
#' @return Character cache key (may or may not exist in schedule_cache —
#'   caller must still check).
resolve_schedule_key <- function(id, school, wday, schedule_cache, pupil_override_map) {
  cache_key  <- paste(school, wday, sep = "_")
  pupil_key  <- sub("\\.[^.]+$", "", basename(as.character(id)))
  pupil_info <- pupil_override_map[[pupil_key]]
  if (!is.null(pupil_info)) {
    wday_lower   <- tolower(wday)
    override_end <- pupil_info$overrides[[wday_lower]]
    if (!is.null(override_end)) {
      class_key <- paste(school, pupil_info$class, wday_lower, sep = "_")
      if (class_key %in% names(schedule_cache))
        cache_key <- class_key
    }
  }
  cache_key
}

#' Read data/absences.csv (if present) as a lookup keyed by "ID date"
#'
#' Absences only overlay in_class/recess/lunch segments — before/after-school
#' time is unaffected (a pupil absent from school can still have worn the
#' device before/after school hours). This matches 02_label_segments.R's
#' original absence-overlay behavior exactly; kept as a shared function so
#' 02b_label_epochs.R can't silently drift from it.
#'
#' @param absences_path Path to absences.csv.
#' @return Character vector of "pupil_id date" keys, or character(0) if the
#'   file doesn't exist / has no rows.
read_absence_keys <- function(absences_path) {
  if (!file.exists(absences_path)) return(character(0))
  abs_dt <- tryCatch(
    data.table::fread(absences_path,
                      colClasses = c(pupil_id = "character", date = "character")),
    error = function(e) {
      message("[absences] Could not read absences.csv: ", e$message)
      NULL
    }
  )
  if (is.null(abs_dt) || nrow(abs_dt) == 0) return(character(0))
  paste(abs_dt$pupil_id, abs_dt$date)
}

#' Segments an absence overlay applies to (school-time segments only)
ABSENCE_OVERLAY_SEGMENTS <- c("in_class", "recess", "lunch")

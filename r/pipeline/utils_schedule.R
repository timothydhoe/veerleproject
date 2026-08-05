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

#' Strip a GGIR-style extension suffix (".cwa"/".csv"/etc.) from a participant ID
#'
#' GGIR's own ID column, and pupil_id as pasted into config.yaml, don't always
#' agree on whether an extension suffix is present (e.g. "2063" vs
#' "2063.cwa"). Every ID-matching call site in this pipeline needs to strip it
#' the same way before comparing — two real bugs (build order steps 3 and 7
#' of docs/test/plan_absences_config.md) came from a call site quietly
#' comparing an un-stripped ID against a stripped one. Centralized here so
#' that can't happen again.
#'
#' @param id Character or numeric participant ID / filename.
#' @return Character vector, extension suffix and any directory path removed.
strip_pupil_id <- function(id) {
  sub("\\.[^.]+$", "", basename(as.character(id)))
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
  code     <- suppressWarnings(as.integer(strip_pupil_id(id)))
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
  pupil_key  <- strip_pupil_id(id)
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

#' Parse cfg$afwezigheden into a clean (pupil_id, date) lookup table
#'
#' config.yaml is the single source of truth for absences (see
#' docs/test/plan_absences_config.md) — there is no absences.csv equivalent
#' read here; `data/absences.csv`, if present, is only a generated read-only
#' mirror written by 02_label_segments.R, never read back by pipeline code.
#' pupil_id is stripped to bare numeric form the same way
#' extract_school_id()/resolve_schedule_key() do, in case an entry was pasted
#' in with a ".cwa"-style suffix.
#'
#' @param cfg Full config list (cfg$afwezigheden used).
#' @return data.table with columns pupil_id (character), date (character,
#'   "YYYY-MM-DD"). Zero rows if cfg$afwezigheden is NULL/empty.
get_absence_entries <- function(cfg) {
  entries <- cfg$afwezigheden
  if (is.null(entries) || length(entries) == 0) {
    return(data.table::data.table(pupil_id = character(0), date = character(0)))
  }
  pupil_id <- vapply(entries, function(e) strip_pupil_id(e$pupil_id), character(1))
  date <- vapply(entries, function(e) as.character(e$date), character(1))
  data.table::data.table(pupil_id = pupil_id, date = date)
}

#' "pupil_id date" membership keys for an absence entries table
#'
#' Used by consumers that need a fast %in% lookup (e.g. "is this ID+date
#' combination absent?") rather than the raw table itself.
#'
#' @param absence_entries data.table from get_absence_entries().
#' @return Character vector of "pupil_id date" keys, or character(0).
absence_keys <- function(absence_entries) {
  if (is.null(absence_entries) || nrow(absence_entries) == 0) return(character(0))
  paste(absence_entries$pupil_id, absence_entries$date)
}

#' Drop rows matching a full-day absence entry from a day/segment-level table
#'
#' Shared by 02_label_segments.R's whole-day exclusion so the ID-matching
#' logic (and its strip_pupil_id() dependency) lives in exactly one place,
#' testable in isolation — see strip_pupil_id()'s docstring for why that
#' matters here specifically.
#'
#' @param dt data.table with ID and date columns (segment_summary-shaped).
#'   Not modified in place; a filtered copy is returned.
#' @param abs_entries data.table from get_absence_entries().
#' @return list(dt = filtered data.table, n_dropped = integer count of rows
#'   removed, unmatched_keys = character vector of "pupil_id date" entries
#'   from abs_entries that matched no row in dt at all — a likely typo).
apply_absence_drop <- function(dt, abs_entries) {
  if (is.null(abs_entries) || nrow(abs_entries) == 0) {
    return(list(dt = dt, n_dropped = 0L, unmatched_keys = character(0)))
  }
  keys    <- paste(abs_entries$pupil_id, abs_entries$date)
  dt_keys <- paste(strip_pupil_id(dt$ID), as.character(dt$date))

  unmatched_keys <- setdiff(keys, unique(dt_keys))
  kept <- dt[!(dt_keys %in% keys)]

  list(dt = kept, n_dropped = nrow(dt) - nrow(kept), unmatched_keys = unmatched_keys)
}

# 02_label_segments.R
# ─────────────────────────────────────────────────────────────────────────────
# Apply school schedule context labels to GGIR part2 day summaries.
#
# For each participant × day, assigns a label to each 15-minute qwindow slot
# based on the school's timetable from config.yaml. Then aggregates to
# per-participant × per-day × per-segment summaries.
#
# Note: GGIR's qwindow parameter splits the day into fixed time blocks, but
# those blocks don't align exactly with per-school bell times. This script
# maps GGIR's time-segment columns onto our 5 context labels using the
# school-specific schedule from config.yaml.
#
# Output: data/processed/summaries/segment_summary.csv
#
# Run from r/ directory. Requires 01_run_ggir.R to have completed first.
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

Sys.setlocale("LC_TIME", "C")  # force English weekday names regardless of OS locale

source("pipeline/validate_config.R", local = TRUE)

cfg         <- read_config_yaml("../config.yaml")
cfg         <- apply_active_profile(cfg)
validate_config(cfg)
base_out    <- cfg$paths$data_processed
metingen    <- c("meting_1", "meting_2")
tz          <- cfg$output$timezone

# ── Helper: extract school ID from participant code ───────────────────────────
# Participant code is a 4-digit number: first digit = school (1–6)
extract_school_id <- function(id) {
  code     <- suppressWarnings(as.integer(sub("\\.[^.]+$", "", basename(as.character(id)))))
  school_n <- code %/% 1000L
  school_n[is.na(school_n) | school_n < 1L | school_n > 6L] <- NA_integer_
  paste0("school_", school_n)
}

# ── Helper: get schedule for a school + weekday ───────────────────────────────
# Returns a data.frame with columns: segment, start_h, end_h
get_schedule <- function(school_id, wday_name, schedules) {
  sch <- schedules[[school_id]]
  if (is.null(sch)) return(NULL)

  school_start <- hm_to_h(sch$school_start)

  # School end depends on day
  wday_lower <- tolower(wday_name)
  if (wday_lower == "wednesday") {
    school_end <- hm_to_h(sch$school_end$wednesday %||% sch$school_end$mon_tue_thu_fri)
    breaks_key <- "wednesday"
  } else {
    # Try weekday-specific end time first (e.g. "tuesday"), then generic fallbacks
    school_end <- hm_to_h(
      sch$school_end[[wday_lower]] %||%
      sch$school_end$mon_tue_thu_fri %||%
      sch$school_end$mon_thu_fri
    )
    breaks_key <- "mon_tue_thu_fri"
  }

  # Build segment intervals
  segments <- list()

  # Before school
  segments <- c(segments, list(data.frame(
    segment = "before_school", start_h = 0, end_h = school_start
  )))

  # Breaks split the in-class time
  breaks <- sch$breaks[[breaks_key]]
  if (is.null(breaks) || length(breaks) == 0) breaks <- list()

  # Sort breaks by start time
  if (length(breaks) > 0) {
    break_starts <- sapply(breaks, function(b) hm_to_h(b$start))
    breaks <- breaks[order(break_starts)]
  }

  # Build in-class and break segments between school_start and school_end
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

  # Final in-class block before school ends
  if (cursor < school_end) {
    segments <- c(segments, list(data.frame(
      segment = "in_class", start_h = cursor, end_h = school_end
    )))
  }

  # After school
  segments <- c(segments, list(data.frame(
    segment = "after_school", start_h = school_end, end_h = 24
  )))

  rbindlist(lapply(segments, as.data.table))
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

source("pipeline/utils_ggir.R", local = TRUE)

# ── Load GGIR part2 for both metingen ─────────────────────────────────────────
all_data <- list()

for (meting in metingen) {
  results_dir <- find_ggir_results_dir(file.path(base_out, meting))
  if (is.null(results_dir)) {
    message("Skipping ", meting, " — GGIR results directory not found under: ",
            file.path(base_out, meting))
    message("  Run pipeline/01_run_ggir.R first.")
    next
  }
  fpath <- file.path(results_dir, "part2_daysummary.csv")
  if (!file.exists(fpath)) {
    message("Skipping ", meting, " — part2_daysummary.csv not found: ", fpath)
    message("  Run pipeline/01_run_ggir.R first.")
    next
  }

  dt <- fread(fpath, data.table = TRUE)
  dt[, meting := meting]
  dt[, school := extract_school_id(ID)]
  all_data[[meting]] <- dt
}

if (length(all_data) == 0) {
  stop("No GGIR output found. Run pipeline/01_run_ggir.R first.")
}

part2 <- rbindlist(all_data, fill = TRUE)

# Normalise wear-time column names
if ("N valid hours" %in% names(part2)) setnames(part2, "N valid hours", "n_valid_hours")
if ("N hours"       %in% names(part2)) setnames(part2, "N hours",       "n_hours")

# ── Identify GGIR time-segment columns in part2 ───────────────────────────────
# GGIR names these like "ACC_day_mg_0.8.75", "ACC_day_mg_8.75.10", etc.
# where the numbers are the qwindow boundaries (hours).
# We use the weekday column to determine which schedule to apply per row,
# then map each part2 row to the 5 context labels.

# Detect weekday column (GGIR names it "weekday" or "day")
wday_col <- intersect(c("weekday", "day"), names(part2))
if (length(wday_col) == 0) {
  # Try to derive from calendar date
  date_col <- intersect(c("calendar_date", "Date", "date"), names(part2))
  if (length(date_col) > 0) {
    part2[, weekday := weekdays(as.Date(get(date_col[1]), tz = tz))]
    wday_col <- "weekday"
    n_na_wday <- sum(is.na(part2$weekday))
    if (n_na_wday > 0)
      warning(sprintf("[02] %d rows have unparseable calendar_date — those days will be assigned 'outside_school'",
                      n_na_wday))
  } else {
    warning("No weekday column found — segment labeling will default to Mon–Fri schedule")
    part2[, weekday := "Monday"]
    wday_col <- "weekday"
  }
} else {
  wday_col <- wday_col[1]
  if (wday_col != "weekday") setnames(part2, wday_col, "weekday")
}

# ── Find activity intensity data for qwindow segments ─────────────────────────
# part2 never carries activity-intensity columns (SB/LIG/MOD/VIG) — GGIR only
# puts wear-time/valid-hours per qwindow there. True per-window activity
# intensity lives in part5_daysummary_Segments_*.csv instead: one row per
# participant x day x window, with "window" values like "segment1", "segment2"
# where segmentN = the Nth qwindow interval [qw_starts[N], qw_ends[N]).
# Column names below (dur_IN_min etc.) match what shiny/modules/mod_schoolday.R
# expects (grep("^dur_MOD", ...) etc.) — do not rename without updating that too.
intensity_cols <- c("dur_IN_min", "dur_LIG_min", "dur_MOD_min", "dur_VIG_min")
INTENSITY_SRC_COLS <- c(
  dur_IN_min  = "dur_day_total_IN_min",
  dur_LIG_min = "dur_day_total_LIG_min",
  dur_MOD_min = "dur_day_total_MOD_min",
  dur_VIG_min = "dur_day_total_VIG_min"
)

# ── Resolve the qwindow GGIR actually used (must agree across metingen) ──────
# Prefer GGIR's own recorded config.csv per meting over the literal
# config.yaml value, which may be stale (edited without a step-01 rerun) or
# irrelevant (qwindow_strategy: "auto" derives it from schedules instead).
resolved_qwindows <- list()
for (meting in metingen) {
  resolved <- resolve_ggir_qwindow(file.path(base_out, meting))
  if (!is.null(resolved)) resolved_qwindows[[meting]] <- resolved
}

if (length(resolved_qwindows) == 0) {
  warning("No GGIR config.csv found for either meting - falling back to config.yaml's ",
          "ggir.qwindow value. This may not reflect an actual GGIR run; rerun ",
          "pipeline/01_run_ggir.R to confirm the real boundaries.")
  qwindow <- as.numeric(cfg$ggir$qwindow)
} else {
  rounded <- lapply(resolved_qwindows, round, digits = 6)
  if (length(resolved_qwindows) == length(metingen) && !identical(rounded[[1]], rounded[[2]])) {
    stop(
      "meting_1 and meting_2 resolved to different qwindow values from their GGIR ",
      "config.csv files - this should never happen (both metingen must share the ",
      "same qwindow). meting_1: ", paste(resolved_qwindows[[metingen[1]]], collapse = ", "),
      " | meting_2: ", paste(resolved_qwindows[[metingen[2]]], collapse = ", "),
      ". Check whether one meting was re-run with a different config.yaml/schedule ",
      "and reconcile before continuing."
    )
  }
  qwindow <- resolved_qwindows[[1]]
  if (length(resolved_qwindows) < length(metingen)) {
    missing <- setdiff(metingen, names(resolved_qwindows))
    message("Note: GGIR config.csv not found for ", paste(missing, collapse = ", "),
            " - using the qwindow resolved from ", names(resolved_qwindows)[1],
            " for both.")
  }
  message("Using qwindow resolved from GGIR's own config.csv: ",
          paste(round(qwindow, 4), collapse = ", "))
}
use_qwindow   <- FALSE
qw_starts     <- qw_ends <- NULL
window_lookup <- NULL  # keyed by "ID date window_idx" -> one-row data.table of intensity cols

if (!is.null(qwindow) && length(qwindow) >= 2) {
  qw_starts <- head(qwindow, -1)
  qw_ends   <- tail(qwindow, -1)

  seg5_list <- lapply(metingen, function(m) {
    load_ggir_file(meting_output_dir = file.path(base_out, m), meting = m,
                   pattern = "^part5_daysummary_Segments_")
  })
  seg5 <- rbindlist(Filter(function(x) !is.null(x) && nrow(x) > 0, seg5_list), fill = TRUE)

  if (nrow(seg5) > 0 && "window" %in% names(seg5)) {
    seg5[, window_idx := suppressWarnings(as.integer(sub("^segment", "", window, ignore.case = TRUE)))]
    seg5 <- seg5[!is.na(window_idx) & window_idx >= 1 & window_idx <= length(qw_starts)]
    date5_col <- intersect(c("calendar_date", "Date", "date"), names(seg5))
    present_src <- INTENSITY_SRC_COLS[INTENSITY_SRC_COLS %in% names(seg5)]

    if (nrow(seg5) > 0 && length(date5_col) > 0 && length(present_src) > 0) {
      date5_col <- date5_col[1]
      seg5[, lookup_key := paste(as.character(ID), as.character(get(date5_col)), window_idx)]
      window_lookup <- split(seg5[, c(names(present_src)) := lapply(.SD, as.numeric), .SDcols = present_src][
        , c("lookup_key", names(present_src)), with = FALSE], by = "lookup_key", keep.by = FALSE)
      use_qwindow <- TRUE
      message(sprintf(
        "part5 Segments data loaded (%d window-rows, %d participants) — using true per-window activity for segment estimates",
        nrow(seg5), uniqueN(seg5$ID)
      ))
    }
  }

  if (!use_qwindow) {
    message("qwindow is set in config but part5_daysummary_Segments_*.csv not found or unusable.")
    message("  Falling back to wear-time-only segment estimates (no activity intensity).")
  }
}

# Helper: for a segment [start_h, end_h], accumulate part5-Segments intensity
# values (looked up by participant/date/qwindow-index) weighted by overlap
# with each qwindow interval. Modifies seg_row in place.
distribute_qwindow_cols <- function(seg_row, id, date_val, start_h, end_h) {
  for (qi in seq_along(qw_starts)) {
    qw_start <- qw_starts[qi]
    qw_end   <- qw_ends[qi]
    qw_dur   <- qw_end - qw_start
    overlap  <- max(0, min(end_h, qw_end) - max(start_h, qw_start))
    if (overlap <= 0 || qw_dur <= 0) next
    frac <- overlap / qw_dur

    key     <- paste(as.character(id), as.character(date_val), qi)
    win_row <- window_lookup[[key]]
    if (is.null(win_row) || nrow(win_row) == 0) next

    for (out_col in names(INTENSITY_SRC_COLS)) {
      # window_lookup rows are already renamed src->out (see construction
      # above) — look up by out_col, not the original GGIR src column name.
      if (!out_col %in% names(win_row)) next
      val <- win_row[[out_col]][1]
      if (!is.numeric(val) || is.na(val)) next
      cur <- if (out_col %in% names(seg_row)) seg_row[[out_col]] else 0
      set(seg_row, j = out_col, value = cur + val * frac)
    }
  }
  seg_row
}

# ── Build segment summary ─────────────────────────────────────────────────────
# For each participant × day, we can only assign a SINGLE dominant segment
# from part2 (it's already aggregated to day level).
# The segment_summary.csv will contain one row per participant × day × segment,
# with the proportion of that day belonging to each segment (from the schedule),
# multiplied by the day-level activity values as an approximation.
# This is a first-pass estimate; exact per-segment minutes require part5 timeseries.

message("\nBuilding segment schedule lookup...")

# ── Build pupil → class override map ─────────────────────────────────────────
# For schools with class_overrides: maps pupil_id (character) to a list with
#   $class     — class name (e.g. "2Aa")
#   $overrides — named list: weekday_lower → override school_end (e.g. "16:25")
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
if (length(pupil_override_map) > 0)
  message("Class overrides loaded for ", length(pupil_override_map), " pupils")

# Build all schedule lookups for all schools × weekdays
weekdays_list <- c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
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

  # ── Class-variant cache entries ───────────────────────────────────────────
  # For each (school, class, weekday) with a school_end_override, build a
  # modified schedule where that day's school_end is replaced by the override.
  class_overrides <- cfg$schedules[[school_id]]$class_overrides
  if (is.null(class_overrides)) next
  for (class_name in names(class_overrides)) {
    co <- class_overrides[[class_name]]
    for (wday_lower in names(co$school_end_override)) {
      override_end <- co$school_end_override[[wday_lower]]
      wday_name    <- paste0(toupper(substring(wday_lower, 1, 1)),
                             substring(wday_lower, 2))
      # Build a copy of the school config with the override injected
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

message("Schedule cache built for ", length(schedule_cache), " school × day combinations")

# ── Expand part2 rows into per-segment rows ────────────────────────────────────
message("Expanding part2 to segment-level summary...")

rows <- list()

for (i in seq_len(nrow(part2))) {
  row    <- part2[i]
  school <- row$school
  wday   <- row$weekday

  # Weekend: assign all time to "weekend"
  if (wday %in% c("Saturday", "Sunday")) {
    seg_row <- data.table(
      ID          = row$ID,
      school      = school,
      meting      = row$meting,
      date        = if ("calendar_date" %in% names(row)) row$calendar_date else NA_character_,
      weekday     = wday,
      segment     = "weekend",
      duration_h  = 24,
      n_valid_hours = if ("n_valid_hours" %in% names(row)) row$n_valid_hours else NA_real_
    )
    if (use_qwindow) {
      seg_row <- distribute_qwindow_cols(seg_row, row$ID, seg_row$date, 0, 24)
    } else {
      for (col in intensity_cols) seg_row[, (col) := row[[col]]]
    }
    rows[[length(rows) + 1]] <- seg_row
    next
  }

  # School day: look up schedule (with per-pupil class override if applicable)
  cache_key  <- paste(school, wday, sep = "_")
  pupil_key  <- sub("\\.[^.]+$", "", basename(as.character(row$ID)))
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
  sched     <- schedule_cache[[cache_key]]

  if (is.null(sched)) {
    # Unknown school or missing schedule — mark as outside_school
    seg_row <- data.table(
      ID          = row$ID,
      school      = school,
      meting      = row$meting,
      date        = if ("calendar_date" %in% names(row)) row$calendar_date else NA_character_,
      weekday     = wday,
      segment     = "outside_school",
      duration_h  = 24,
      n_valid_hours = if ("n_valid_hours" %in% names(row)) row$n_valid_hours else NA_real_
    )
    if (use_qwindow) {
      seg_row <- distribute_qwindow_cols(seg_row, row$ID, seg_row$date, 0, 24)
    } else {
      for (col in intensity_cols) {
        val <- row[[col]]
        if (is.numeric(val)) seg_row[, (col) := val]
      }
    }
    rows[[length(rows) + 1]] <- seg_row
    next
  }

  # Distribute day-level values proportionally across segments
  total_h <- sum(sched$end_h - sched$start_h)

  for (j in seq_len(nrow(sched))) {
    seg_dur   <- sched$end_h[j] - sched$start_h[j]
    prop      <- seg_dur / total_h

    seg_row <- data.table(
      ID          = row$ID,
      school      = school,
      meting      = row$meting,
      date        = if ("calendar_date" %in% names(row)) row$calendar_date else NA_character_,
      weekday     = wday,
      segment     = sched$segment[j],
      duration_h  = seg_dur,
      n_valid_hours = if ("n_valid_hours" %in% names(row)) row$n_valid_hours * prop else NA_real_
    )

    # Activity columns: use qwindow overlap aggregation if available,
    # otherwise distribute proportionally (day-level approximation)
    if (use_qwindow) {
      seg_row <- distribute_qwindow_cols(seg_row, row$ID, seg_row$date,
                                         sched$start_h[j], sched$end_h[j])
    } else {
      for (col in intensity_cols) {
        val <- row[[col]]
        if (is.numeric(val)) seg_row[, (col) := val * prop]
      }
    }

    rows[[length(rows) + 1]] <- seg_row
  }
}

segment_summary <- rbindlist(rows, fill = TRUE)

# ── Apply absence overlay ─────────────────────────────────────────────────────
# If data/absences.csv exists and has rows, mark school-context segments for
# absent pupils on those dates as "absent" and NA out activity values.
# Absence data is entered by the researcher via the Shiny dashboard.
absences_path <- cfg$paths$absences %||% "../data/absences.csv"
if (file.exists(absences_path)) {
  abs_dt <- tryCatch(
    fread(absences_path,
          colClasses = c(pupil_id = "character", date = "character")),
    error = function(e) { message("[absences] Could not read absences.csv: ", e$message); NULL }
  )
  if (!is.null(abs_dt) && nrow(abs_dt) > 0) {
    abs_keys    <- paste(abs_dt$pupil_id, abs_dt$date)
    school_segs <- c("in_class", "recess", "lunch")
    rows_before <- nrow(segment_summary[segment == "absent"])
    segment_summary[
      !is.na(ID) & !is.na(date) &
        paste(ID, date) %in% abs_keys & segment %in% school_segs,
      `:=`(segment = "absent", n_valid_hours = NA_real_)
    ]
    for (col in intensity_cols) {
      if (col %in% names(segment_summary))
        segment_summary[segment == "absent", (col) := NA_real_]
    }
    n_marked <- nrow(segment_summary[segment == "absent"]) - rows_before
    message(sprintf("[absences] %d absence records — %d segment rows marked as absent",
                    nrow(abs_dt), n_marked))
    if (n_marked == 0 && nrow(abs_dt) > 0)
      warning("[absences] No rows were marked absent despite ", nrow(abs_dt),
              " records in absences.csv — check that ID and date formats match.")
  }
}

# ── Flag fallback schools ──────────────────────────────────────────────────────
fallback_schools <- names(Filter(function(s) isTRUE(s$fallback), cfg$schedules))
segment_summary[, fallback_schedule := school %in% fallback_schools]

if (length(fallback_schools) > 0) {
  message("\nWARNING: Fallback (unconfirmed) schedules used for: ",
          paste(fallback_schools, collapse = ", "))
  message("  Results for these schools should be treated with caution.")
}

# ── Write output ──────────────────────────────────────────────────────────────
out_path <- file.path(base_out, "summaries", "segment_summary.csv")
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
backup_if_exists(out_path)
fwrite(segment_summary, out_path)

message(sprintf("\nSegment summary written: %s", normalizePath(out_path)))
message(sprintf("  %d rows | %d participants | %d metingen",
                nrow(segment_summary),
                uniqueN(segment_summary$ID),
                uniqueN(segment_summary$meting)))

message("\nStep 02 complete. Run qc/qc_02_segments.R to verify outputs.")

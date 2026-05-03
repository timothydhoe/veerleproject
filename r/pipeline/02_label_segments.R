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
# Output: data/processed/segment_summary.csv
#
# Run from r/ directory. Requires 01_run_ggir.R to have completed first.
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

Sys.setlocale("LC_TIME", "C")  # force English weekday names regardless of OS locale

cfg         <- yaml::read_yaml("../config.yaml")
base_out    <- cfg$paths$data_processed
metingen    <- c("meting_1", "meting_2")
tz          <- cfg$output$timezone

# ── Helper: extract school ID from participant code ───────────────────────────
# Participant code is a 4-digit number: first digit = school (1–6)
extract_school_id <- function(id) {
  code <- suppressWarnings(as.integer(sub("\\.csv$", "", basename(as.character(id)))))
  paste0("school_", code %/% 1000L)
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

# ── Find ENMO/activity columns per qwindow segment ───────────────────────────
# GGIR part2 has columns like:  ACC_day_mg_0.8.75 (ENMO mean for 0–8.75 h window)
# We also look for SB/LIG/MOD/VIG columns broken down by segment.
# For now, we use the total-day columns and distribute context labels from
# the schedule — a per-minute breakdown requires the part5 timeseries.

# Detect activity intensity columns (total-day level)
intensity_cols <- grep("^(SB|IN|LIG|MOD|VIG|MVPA)", names(part2),
                       value = TRUE, ignore.case = TRUE)

if (length(intensity_cols) == 0) {
  warning("No activity intensity columns found in part2 — segment_summary will only contain wear time")
}

# ── Detect qwindow columns in part2 ──────────────────────────────────────────
# If 01_run_ggir.R was run with qwindow set, part2 has per-window columns like
# dur_day_total_IN_min_8.5.10 or ACC_day_mg_12.13. Using these gives far better
# per-segment estimates than distributing day-level totals proportionally.
qwindow     <- cfg$ggir$qwindow
use_qwindow <- FALSE
qw_starts   <- qw_ends <- qw_suffixes <- NULL

if (!is.null(qwindow) && length(qwindow) >= 2) {
  qw_starts   <- head(qwindow, -1)
  qw_ends     <- tail(qwindow, -1)
  qw_suffixes <- paste0(qw_starts, ".", qw_ends)

  qw_suffix_pattern <- paste0("_(", paste(gsub("\\.", "\\\\.", qw_suffixes), collapse = "|"), ")$")
  qw_col_names      <- grep(qw_suffix_pattern, names(part2), value = TRUE)

  if (length(qw_col_names) > 0) {
    use_qwindow <- TRUE
    message(sprintf(
      "qwindow columns detected (%d columns) — using per-window aggregation for segment estimates",
      length(qw_col_names)
    ))
  } else {
    message("qwindow is set in config but per-window columns not found in part2.")
    message("  Re-run pipeline/01_run_ggir.R to generate qwindow-based columns.")
    message("  Falling back to proportional day-level approximation.")
  }
}

# Helper: for a segment [start_h, end_h], accumulate qwindow column values
# weighted by overlap with each qwindow interval. Modifies seg_row in place.
distribute_qwindow_cols <- function(seg_row, row, start_h, end_h) {
  for (qi in seq_along(qw_starts)) {
    qw_start <- qw_starts[qi]
    qw_end   <- qw_ends[qi]
    qw_suf   <- qw_suffixes[qi]
    qw_dur   <- qw_end - qw_start
    overlap  <- max(0, min(end_h, qw_end) - max(start_h, qw_start))
    if (overlap <= 0 || qw_dur <= 0) next
    frac <- overlap / qw_dur

    cols_this_qw <- grep(
      paste0("_", gsub("\\.", "\\\\.", qw_suf), "$"),
      names(row), value = TRUE
    )
    for (col in cols_this_qw) {
      val <- row[[col]]
      if (!is.numeric(val) || is.na(val)) next
      base_col <- sub(paste0("_", gsub("\\.", "\\\\.", qw_suf), "$"), "", col)
      cur <- if (base_col %in% names(seg_row)) seg_row[[base_col]] else 0
      set(seg_row, j = base_col, value = cur + val * frac)
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
      seg_row <- distribute_qwindow_cols(seg_row, row, 0, 24)
    } else {
      for (col in intensity_cols) seg_row[, (col) := row[[col]]]
    }
    rows[[length(rows) + 1]] <- seg_row
    next
  }

  # School day: look up schedule (with per-pupil class override if applicable)
  cache_key  <- paste(school, wday, sep = "_")
  pupil_info <- pupil_override_map[[as.character(row$ID)]]
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
      seg_row <- distribute_qwindow_cols(seg_row, row, 0, 24)
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
      seg_row <- distribute_qwindow_cols(seg_row, row,
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
out_path <- file.path(base_out, "..", "segment_summary.csv")
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
fwrite(segment_summary, out_path)

message(sprintf("\nSegment summary written: %s", normalizePath(out_path)))
message(sprintf("  %d rows | %d participants | %d metingen",
                nrow(segment_summary),
                uniqueN(segment_summary$ID),
                uniqueN(segment_summary$meting)))

message("\nStep 02 complete. Run qc/qc_02_segments.R to verify outputs.")

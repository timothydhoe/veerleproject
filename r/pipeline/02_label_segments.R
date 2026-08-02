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

`%||%` <- function(a, b) if (!is.null(a)) a else b

source("pipeline/utils_ggir.R",    local = TRUE)
source("pipeline/utils_schedule.R", local = TRUE)
# get_schedule(), extract_school_id(), build_pupil_override_map(),
# build_schedule_cache(), resolve_schedule_key(), read_absence_keys(),
# ABSENCE_OVERLAY_SEGMENTS now come from utils_schedule.R (shared with
# 02b_label_epochs.R, feature_log.md #2) instead of being defined inline here.

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

# Pupil → class override map, and the school × weekday (× class-override
# variant) schedule cache, now come from utils_schedule.R — shared with
# 02b_label_epochs.R so the two labeling steps can't drift apart.
pupil_override_map <- build_pupil_override_map(cfg)
if (length(pupil_override_map) > 0)
  message("Class overrides loaded for ", length(pupil_override_map), " pupils")

schedule_cache <- build_schedule_cache(cfg)
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
  cache_key <- resolve_schedule_key(row$ID, school, wday, schedule_cache, pupil_override_map)
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
# `part_of_day` (full/morning/afternoon) narrows a whole-day absence to only
# the segments before/after that day's lunch break — added after the original
# whole-day-only schema, so a missing/unrecognized value falls back to "full"
# and keeps pre-existing absences.csv rows behaving exactly as before.
absences_path <- cfg$paths$absences %||% "../data/absences.csv"
if (file.exists(absences_path)) {
  abs_dt <- tryCatch(
    fread(absences_path,
          colClasses = c(pupil_id = "character", date = "character")),
    error = function(e) { message("[absences] Could not read absences.csv: ", e$message); NULL }
  )
  if (!is.null(abs_dt) && nrow(abs_dt) > 0) {
    if (!"part_of_day" %in% names(abs_dt)) abs_dt[, part_of_day := "full"]
    abs_dt[!(part_of_day %in% c("full", "morning", "afternoon")), part_of_day := "full"]

    rows_before <- nrow(segment_summary[segment == "absent"])

    for (k in seq_len(nrow(abs_dt))) {
      pid  <- abs_dt$pupil_id[k]
      dt_k <- abs_dt$date[k]
      part <- abs_dt$part_of_day[k]

      match_idx <- which(!is.na(segment_summary$ID) & !is.na(segment_summary$date) &
                          segment_summary$ID == pid & segment_summary$date == dt_k &
                          segment_summary$segment %in% ABSENCE_OVERLAY_SEGMENTS)
      if (length(match_idx) == 0) next

      target_idx <- match_idx
      if (part != "full") {
        day_school  <- segment_summary$school[match_idx[1]]
        day_weekday <- segment_summary$weekday[match_idx[1]]
        sched <- tryCatch(get_schedule(day_school, day_weekday, cfg$schedules),
                           error = function(e) NULL)
        lunch_start <- if (!is.null(sched) && "lunch" %in% sched$segment)
          sched$start_h[sched$segment == "lunch"][1] else NA_real_

        # Positional alignment, not label matching: a school day has more than
        # one "in_class"/"recess" block (before and after lunch), so matching
        # by segment label alone would always resolve to the first one.
        # segment_summary rows for this ID+date were appended in the same
        # order sched's rows were built in, so filtering both to
        # ABSENCE_OVERLAY_SEGMENTS keeps them aligned row-for-row.
        sched_segs <- if (!is.null(sched)) sched[sched$segment %in% ABSENCE_OVERLAY_SEGMENTS] else NULL

        if (is.na(lunch_start) || is.null(sched_segs) || nrow(sched_segs) != length(match_idx)) {
          warning(sprintf(
            paste0("[absences] Could not resolve lunch split for %s on %s (school %s) ",
                   "-- applying '%s' absence as a full day instead."),
            pid, dt_k, day_school, part))
        } else {
          seg_starts <- sched_segs$start_h
          target_idx <- if (part == "morning") match_idx[seg_starts <  lunch_start]
                        else                    match_idx[seg_starts >= lunch_start]
        }
      }

      segment_summary[target_idx, `:=`(segment = "absent", n_valid_hours = NA_real_)]
      for (col in intensity_cols) {
        if (col %in% names(segment_summary))
          segment_summary[target_idx, (col) := NA_real_]
      }
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

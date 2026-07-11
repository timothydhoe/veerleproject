# 03_build_summaries.R
# ─────────────────────────────────────────────────────────────────────────────
# Build analysis-ready summary tables from GGIR + segment outputs.
#
# Joins part2, part4 (sleep), part5 person summaries, and segment_summary.
# Computes validity flags per participant per meting.
#
# Outputs:
#   data/processed/analysis_ready.csv   — one row per participant × meting
#   data/processed/validity_summary.csv — inclusion/exclusion per participant
#
# Run from r/ directory. Requires 01 and 02 to have completed first.
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

Sys.setlocale("LC_TIME", "C")  # force English weekday names regardless of OS locale

source("pipeline/utils_ggir.R",  local = TRUE)
source("pipeline/utils_bouts.R", local = TRUE)

source("pipeline/validate_config.R", local = TRUE)

cfg      <- read_config_yaml("../config.yaml")
base_out <- cfg$paths$data_processed
metingen <- c("meting_1", "meting_2")
val_cfg  <- cfg$validity

# Validity thresholds — dev overrides when in example mode
min_wear_h  <- if (isTRUE(cfg$dev$example_mode) && !is.null(cfg$dev$includedaycrit)) {
  cfg$dev$includedaycrit
} else {
  val_cfg$min_wear_hours_per_day
}
min_days    <- val_cfg$min_valid_days
need_wknd   <- isTRUE(val_cfg$require_weekend_day)

# ── Helper: extract school ID from participant code ───────────────────────────
extract_school_id <- function(id) {
  code     <- suppressWarnings(as.integer(sub("\\.[^.]+$", "", basename(as.character(id)))))
  school_n <- code %/% 1000L
  school_n[is.na(school_n) | school_n < 1L | school_n > 6L] <- NA_integer_
  paste0("school_", school_n)
}

# ── Helper: load a GGIR CSV for a given meting (version-tolerant) ─────────────
load_ggir <- function(meting, filename = NULL, pattern = NULL) {
  load_ggir_file(
    meting_output_dir    = file.path(base_out, meting),
    meting               = meting,
    filename             = filename,
    pattern              = pattern,
    extract_school_id_fn = extract_school_id
  )
}

# ── Load GGIR outputs ─────────────────────────────────────────────────────────
message("Loading GGIR outputs...")

part2_list <- lapply(metingen, load_ggir, filename = "part2_daysummary.csv")

# Part 4: version-tolerant (cleaned → full → any part4 CSV)
part4_list <- lapply(metingen, function(m) {
  results_dir <- find_ggir_results_dir(file.path(base_out, m))
  if (is.null(results_dir)) return(NULL)
  df <- read_part4_sleep(results_dir)
  if (is.null(df)) return(NULL)
  dt <- as.data.table(df)
  dt[, meting := m]
  if ("ID" %in% names(dt)) dt[, school := extract_school_id(ID)]
  dt
})

# Part 5: person summary (WW or Segments)
part5_list <- lapply(metingen, load_ggir, pattern  = "^part5_personsummary_")

part2 <- rbindlist(Filter(Negate(is.null), part2_list), fill = TRUE)
part4 <- rbindlist(Filter(Negate(is.null), part4_list), fill = TRUE)
part5 <- rbindlist(Filter(Negate(is.null), part5_list), fill = TRUE)

if (nrow(part2) == 0) stop("No part2 data found. Run pipeline/01_run_ggir.R first.")

# Normalise column names
if ("N valid hours" %in% names(part2)) setnames(part2, "N valid hours", "n_valid_hours")
if ("N hours"       %in% names(part2)) setnames(part2, "N hours",       "n_hours")

# Derive weekday if needed
if (!"weekday" %in% names(part2) && "calendar_date" %in% names(part2)) {
  part2[, weekday := weekdays(as.Date(calendar_date, tz = cfg$output$timezone %||% "Europe/Brussels"))]
}

# ── Load segment summary ──────────────────────────────────────────────────────
seg_path <- file.path(base_out, "..", "segment_summary.csv")
if (file.exists(seg_path)) {
  message("Loading segment summary...")
  seg <- fread(seg_path, data.table = TRUE)
} else {
  message("segment_summary.csv not found — segment columns will be empty in analysis_ready.csv")
  message("  Run pipeline/02_label_segments.R to add segment data.")
  seg <- NULL
}

# ── Participant-level validity (from part2) ────────────────────────────────────
message("Computing validity flags...")

participant_validity <- part2[
  , .(
      n_days       = .N,
      n_valid_days = sum(n_valid_hours >= min_wear_h, na.rm = TRUE),
      mean_wear_h  = round(mean(n_valid_hours, na.rm = TRUE), 1),
      has_weekend  = any(
        weekday %in% c("Saturday", "Sunday") & n_valid_hours >= min_wear_h,
        na.rm = TRUE
      )
    ),
  by = .(ID, school, meting)
]

participant_validity[,
  meets_sedentary_criteria := n_valid_days >= min_days & (!need_wknd | has_weekend)
]

# Exclusion reason (first failing criterion wins)
participant_validity[, exclusion_reason := fcase(
  n_valid_days < min_days,
    sprintf("Only %d valid days (need %d)", n_valid_days, min_days),
  need_wknd & !has_weekend,
    "No valid weekend day",
  default = NA_character_
)]

# ── Sleep validity (from part4 nightsummary) ──────────────────────────────────
min_nights    <- val_cfg$min_valid_nights_sleep %||% 5L
min_pct_valid <- val_cfg$min_pct_night_valid    %||% 50

if (nrow(part4) > 0) {
  seff_col <- grep("SleepEfficiencyInSpt|sleep_efficiency",
                   names(part4), value = TRUE, ignore.case = TRUE)
  if (length(seff_col) > 0) {
    # Efficiency reported as 0–1 fraction in some GGIR versions, 0–100 in others
    eff_vals <- part4[[seff_col[1]]]
    scale    <- if (all(is.na(eff_vals))) {
      message("[sleep] All efficiency values are NA — scale detection skipped, defaulting to 1.")
      1
    } else if (max(eff_vals, na.rm = TRUE) <= 1) 100 else 1
    sleep_nights_valid <- part4[
      !is.na(get(seff_col[1])) & get(seff_col[1]) * scale >= min_pct_valid,
      .(n_valid_nights = .N),
      by = .(ID, meting)
    ]
    participant_validity <- merge(participant_validity, sleep_nights_valid,
                                   by = c("ID", "meting"), all.x = TRUE)
    participant_validity[is.na(n_valid_nights), n_valid_nights := 0L]
    participant_validity[, meets_sleep_criteria := n_valid_nights >= min_nights]
    message(sprintf("Sleep validity: ≥%d%% efficiency threshold, ≥%d nights required",
                    min_pct_valid, min_nights))
  } else {
    participant_validity[, n_valid_nights := NA_integer_]
    participant_validity[, meets_sleep_criteria := NA]
    message("Sleep validity: efficiency column not found in part4 — meets_sleep_criteria set to NA")
  }
} else {
  participant_validity[, n_valid_nights := NA_integer_]
  participant_validity[, meets_sleep_criteria := NA]
  message("Sleep validity: no part4 data — meets_sleep_criteria set to NA")
}

# ── Per-participant MVPA, sleep, SB, and bout averages (from part5) ───────────
if (nrow(part5) > 0) {
  # When qwindow is set, GGIR produces a _Segments_ file with one row per
  # person per time window. Duration columns must be summed (not averaged) to
  # get whole-day totals. The _WW_ file has one row per person, so sum = value.
  is_segments_file <- "window" %in% names(part5) &&
    any(grepl("^segment", part5[["window"]], ignore.case = TRUE))

  # ── MVPA column ────────────────────────────────────────────────────────────
  # Prefer total MOD+VIG minutes — reliable across GGIR versions and file types.
  # Avoid broad grep("MVPA") which picks ACC columns (mg, not min) alphabetically first.
  mod_col <- grep("dur_day_total_MOD_min", names(part5), value = TRUE, ignore.case = TRUE)
  vig_col <- grep("dur_day_total_VIG_min", names(part5), value = TRUE, ignore.case = TRUE)
  if (length(mod_col) > 0 && length(vig_col) > 0) {
    part5[, mvpa_min_day := get(mod_col[1]) + get(vig_col[1])]
    mvpa_col <- "mvpa_min_day"
  } else {
    # Older GGIR: look for MVPA minutes columns specifically (not ACC or Nbouts)
    mvpa_col <- grep("dur_day.*MVPA.*_min_pla$", names(part5), value = TRUE, ignore.case = TRUE)
  }

  # ── Sedentary time (inactivity) ────────────────────────────────────────────
  sb_col <- grep("dur_day_total_IN_min|dur_day_IN_unbt_min", names(part5),
                 value = TRUE, ignore.case = TRUE)

  # ── Light activity ─────────────────────────────────────────────────────────
  lpa_col <- grep("dur_day_total_LIG_min", names(part5), value = TRUE, ignore.case = TRUE)

  # ── Sedentary bouts ────────────────────────────────────────────────────────
  bts30_col <- grep("dur_day_IN_bts_30_min_pla$", names(part5), value = TRUE, ignore.case = TRUE)
  bts10_col <- grep("dur_day_IN_bts_10_20_min_pla$", names(part5), value = TRUE, ignore.case = TRUE)

  # ── Sleep from part5 SPT (used when no part4 nightsummary available) ───────
  sleep5_col <- grep("dur_spt_sleep_min_pla$", names(part5), value = TRUE, ignore.case = TRUE)
  sleff5_col <- grep("sleep_efficiency_pla$",  names(part5), value = TRUE, ignore.case = TRUE)

} else {
  message("No part5 person summary found — MVPA and other averages will be missing.")
}

# ── Per-participant sleep averages ────────────────────────────────────────────
# Priority: part4 nightsummary > part5 SPT sleep estimate
if (nrow(part4) > 0) {
  dur_col <- grep("duration|SleepDurationInSpt|sleep_dur",
                  names(part4), value = TRUE, ignore.case = TRUE)
  eff_col <- grep("efficiency|SleepEfficiencyInSpt|sleep_eff",
                  names(part4), value = TRUE, ignore.case = TRUE)

  sleep_summary <- part4[
    , .(
        sleep_nights          = .N,
        sleep_duration_h      = if (length(dur_col) > 0) {
          raw_val <- mean(get(dur_col[1]), na.rm = TRUE)
          if (is.na(raw_val)) NA_real_
          else if (raw_val > 24) round(raw_val / 60, 2)   # minutes → hours
          else if (raw_val >= 1) round(raw_val, 2)          # already hours
          else { message("[sleep] Unexpected duration value: ", raw_val,
                         " in ", dur_col[1], " — set to NA"); NA_real_ }
        } else NA_real_,
        sleep_efficiency_pct  = if (length(eff_col) > 0)
          round(mean(get(eff_col[1]), na.rm = TRUE), 1)
        else NA_real_
      ),
    by = .(ID, school, meting)
  ]

} else if (nrow(part5) > 0 && length(sleep5_col) > 0) {
  # Fall back to SPT sleep estimate from part5 personsummary.
  # Aggregate across windows to avoid cartesian product on merge.
  sleep_summary <- part5[
    , .(
        sleep_nights         = NA_integer_,
        sleep_duration_h     = {
          raw_val <- mean(get(sleep5_col[1]), na.rm = TRUE)
          if (is.na(raw_val)) NA_real_
          else if (raw_val > 24) round(raw_val / 60, 2)
          else if (raw_val >= 1) round(raw_val, 2)
          else NA_real_
        },
        sleep_efficiency_pct = if (length(sleff5_col) > 0)
          round(mean(get(sleff5_col[1]), na.rm = TRUE), 1)
        else NA_real_
      ),
    by = .(ID, school, meting)
  ]

} else {
  sleep_summary <- data.table(ID = character(), school = character(),
                               meting = character(), sleep_nights = integer(),
                               sleep_duration_h = numeric(),
                               sleep_efficiency_pct = numeric())
}

# ── Segment averages (from segment_summary) ───────────────────────────────────
if (!is.null(seg) && nrow(seg) > 0) {
  # Absent days: count per participant before filtering
  if ("absent" %in% seg$segment) {
    absent_days <- seg[segment == "absent",
                       .(n_absent_school_days = uniqueN(date)),
                       by = .(ID, school, meting)]
  } else {
    absent_days <- NULL
  }

  # Exclude absent segments from activity averages
  seg_active <- seg[segment != "absent"]

  intensity_cols <- grep("^(SB|IN|LIG|MOD|VIG|MVPA)", names(seg_active),
                         value = TRUE, ignore.case = TRUE)

  if (length(intensity_cols) > 0) {
    seg_wide <- dcast(
      seg_active[, c("ID", "school", "meting", "segment", intensity_cols), with = FALSE][
        , lapply(.SD, mean, na.rm = TRUE),
        by = .(ID, school, meting, segment),
        .SDcols = intensity_cols
      ],
      ID + school + meting ~ segment,
      value.var = intensity_cols,
      fun.aggregate = mean
    )
  } else {
    seg_wide <- NULL
  }
} else {
  seg_wide    <- NULL
  absent_days <- NULL
}

# ── Context-aware sedentary bouts (from epoch-level data) ─────────────────────
# detect_activity_bouts() in utils_bouts.R requires epoch-level labeled data:
# one row per 1-second epoch with ID, date, context, intensity, wear columns.
#
# NOTE: labeled_epochs.csv is NOT currently produced by any pipeline step.
# 02_label_segments.R is a day-level script only — it does not emit per-epoch output.
# epochvalues2csv (in 01_run_ggir.R) controls raw GGIR epoch export, not school
# context labeling. Until an epoch-level labeling step is implemented, this block
# never fires and all bouts_30min_*_n columns in analysis_ready.csv will be NA.
#
# The labeled epoch file (if available) would live at:
#   data/processed/labeled_epochs.csv
#
# When it is absent, we skip this block and emit a warning.
context_bouts_wide <- NULL
labeled_epochs_path <- file.path(base_out, "..", "labeled_epochs.csv")

if (file.exists(labeled_epochs_path)) {
  message("Loading epoch-level labeled data for context-aware bout detection...")
  epoch_dt <- tryCatch(
    fread(labeled_epochs_path, data.table = FALSE),
    error = function(e) {
      message("  Could not load labeled_epochs.csv: ", e$message)
      NULL
    }
  )
  if (!is.null(epoch_dt)) {
    bout_cfg <- cfg$bouts %||% list(sedentary_min = 30, split_at_context_boundary = TRUE)
    context_bouts_wide <- compute_context_bout_summaries(epoch_dt, bout_cfg)
    if (!is.null(context_bouts_wide)) {
      key_cols <- intersect(c("ID", "meting"), names(context_bouts_wide))
      message("  Context-aware bout columns (key: ", paste(key_cols, collapse = "+"), "): ",
              paste(setdiff(names(context_bouts_wide), key_cols), collapse = ", "))
    }
  }
} else {
  message("[WARN] labeled_epochs.csv not found — context-aware bout columns will be NA.")
  message("  Epoch-level school context labeling is not yet implemented (see comment above).")
}

# ── Build analysis_ready table ────────────────────────────────────────────────
message("Joining tables...")

analysis_ready <- copy(participant_validity)

# Join sleep
if (nrow(sleep_summary) > 0) {
  analysis_ready <- merge(analysis_ready, sleep_summary,
                           by = c("ID", "school", "meting"), all.x = TRUE)
}

# Join part5 MVPA + SB + LPA + bouts
# part5 personsummary may have multiple rows per ID (one per qwindow segment).
# Aggregate across windows before merging to avoid cartesian product.
if (nrow(part5) > 0) {
  val_cols <- character()
  if (exists("mvpa_col") && length(mvpa_col) > 0) val_cols <- c(val_cols, mvpa_col[1])
  if (exists("sb_col")   && length(sb_col)   > 0) val_cols <- c(val_cols, sb_col[1])
  if (exists("lpa_col")  && length(lpa_col)  > 0) val_cols <- c(val_cols, lpa_col[1])
  if (exists("bts30_col") && length(bts30_col) > 0) val_cols <- c(val_cols, bts30_col[1])
  if (exists("bts10_col") && length(bts10_col) > 0) val_cols <- c(val_cols, bts10_col[1])

  val_cols <- intersect(val_cols, names(part5))
  if (length(val_cols) > 0) {
    # _Segments_ stores per-window totals → sum across windows for daily total.
    # _WW_ has one row per person → sum = mean = the value itself.
    agg_fn <- if (isTRUE(is_segments_file)) sum else mean
    part5_merge <- part5[,
      lapply(.SD, agg_fn, na.rm = TRUE),
      by = .(ID, school, meting),
      .SDcols = val_cols
    ]
  } else {
    part5_merge <- unique(part5[, .(ID, school, meting)])
  }

  rename_map <- c()
  if (exists("mvpa_col") && length(mvpa_col) > 0 && mvpa_col[1] %in% names(part5_merge))
    rename_map[mvpa_col[1]] <- "mvpa_min_day_avg"
  if (exists("sb_col") && length(sb_col) > 0 && sb_col[1] %in% names(part5_merge))
    rename_map[sb_col[1]] <- "sb_min_day"
  if (exists("lpa_col") && length(lpa_col) > 0 && lpa_col[1] %in% names(part5_merge))
    rename_map[lpa_col[1]] <- "lpa_min_day"
  if (exists("bts30_col") && length(bts30_col) > 0 && bts30_col[1] %in% names(part5_merge))
    rename_map[bts30_col[1]] <- "bouts_30min_day"
  if (exists("bts10_col") && length(bts10_col) > 0 && bts10_col[1] %in% names(part5_merge))
    rename_map[bts10_col[1]] <- "bouts_10min_day"

  for (old_nm in names(rename_map)) {
    if (old_nm %in% names(part5_merge))
      setnames(part5_merge, old_nm, rename_map[old_nm])
  }

  analysis_ready <- merge(analysis_ready, part5_merge,
                           by = c("ID", "school", "meting"), all.x = TRUE)
}

# Join segment-level averages
if (!is.null(seg_wide) && nrow(seg_wide) > 0) {
  analysis_ready <- merge(analysis_ready, seg_wide,
                           by = c("ID", "school", "meting"), all.x = TRUE)
}

# Join absent day counts
if (!is.null(absent_days) && nrow(absent_days) > 0) {
  analysis_ready <- merge(analysis_ready, absent_days,
                           by = c("ID", "school", "meting"), all.x = TRUE)
  analysis_ready[is.na(n_absent_school_days), n_absent_school_days := 0L]
}

# Join context-aware bout columns (only when epoch data was available)
if (!is.null(context_bouts_wide) && nrow(context_bouts_wide) > 0) {
  by_cols <- intersect(c("ID", "meting"), names(context_bouts_wide))
  analysis_ready <- merge(analysis_ready, context_bouts_wide,
                           by = by_cols, all.x = TRUE)
}

# ── Write outputs ─────────────────────────────────────────────────────────────
out_dir <- file.path(base_out, "..")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ready_path    <- file.path(out_dir, "analysis_ready.csv")
validity_path <- file.path(out_dir, "validity_summary.csv")

fwrite(analysis_ready, ready_path)
if (!is.null(absent_days) && nrow(absent_days) > 0) {
  participant_validity <- merge(participant_validity, absent_days,
                                 by = c("ID", "school", "meting"), all.x = TRUE)
  participant_validity[is.na(n_absent_school_days), n_absent_school_days := 0L]
}

validity_cols <- intersect(
  c("ID", "school", "meting", "n_days", "n_valid_days", "mean_wear_h", "has_weekend",
    "meets_sedentary_criteria", "exclusion_reason", "n_valid_nights", "meets_sleep_criteria",
    "n_absent_school_days"),
  names(participant_validity)
)
fwrite(participant_validity[, validity_cols, with = FALSE], validity_path)

message("\nOutputs written:")
message("  ", normalizePath(ready_path))
message("  ", normalizePath(validity_path))

n_total    <- nrow(participant_validity)
n_included <- sum(participant_validity$meets_sedentary_criteria, na.rm = TRUE)
message(sprintf("\nValidity summary: %d / %d participants meet sedentary criteria (%.0f%%)",
                n_included, n_total, 100 * n_included / max(n_total, 1)))

message("\nStep 03 complete. Run qc/qc_03_summaries.R to verify outputs.")
message("The Shiny dashboard is now ready: shiny::runApp('shiny')")

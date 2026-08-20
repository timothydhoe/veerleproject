# utils_epoch_labeling.R
# ─────────────────────────────────────────────────────────────────────────────
# Builds one participant's rows of labeled_epochs.csv (feature_log.md #2):
# GGIR's raw per-epoch export (meta/csv/*.RData.csv), joined against school-
# schedule context (reusing utils_schedule.R, shared with 02_label_segments.R)
# and GGIR's own per-epoch wear/non-wear flag (meta/ms2.out/*.RData).
#
# Consumed by 02b_label_epochs.R. Depends on utils_ggir.R (hm_to_h) and
# utils_schedule.R (get_schedule, resolve_schedule_key) — callers must
# source both before this file.
# ─────────────────────────────────────────────────────────────────────────────

if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

#' Derive the real epoch length (seconds) from a raw epoch CSV's own timestamps
#'
#' GGIR's epochvalues2csv export resolution is a GGIR-internal setting
#' (`windowsizes`, default 5s short epoch) — NOT the 1-second figure this
#' project's `config.yaml`/`dev.epoch_length_s` describes (that key is about
#' a different input path, pre-converted CSVs, and is already documented as
#' "informational, not read"). Rather than hardcode 5 (or misread that
#' unrelated key), this derives the real value directly from the data, so it
#' stays correct even if GGIR's default ever changes.
#'
#' @param timestamps POSIXct vector, already parsed and sorted.
#' @return Positive numeric scalar (seconds). Falls back to 5 with a warning
#'   if fewer than 2 timestamps are available or the derived value is outside
#'   a sane [0.1, 300] second range (e.g. all-duplicate or corrupt timestamps).
derive_epoch_length_s <- function(timestamps) {
  fallback <- 5
  if (length(timestamps) < 2) {
    warning("[epoch_labeling] Fewer than 2 timestamps — cannot derive epoch length, ",
            "falling back to ", fallback, "s.")
    return(fallback)
  }
  diffs <- as.numeric(diff(timestamps), units = "secs")
  diffs <- diffs[diffs > 0]
  if (length(diffs) == 0) {
    warning("[epoch_labeling] No positive timestamp deltas — falling back to ", fallback, "s.")
    return(fallback)
  }
  epoch_s <- stats::median(diffs)
  if (!is.finite(epoch_s) || epoch_s < 0.1 || epoch_s > 300) {
    warning("[epoch_labeling] Derived epoch length (", epoch_s, "s) is outside the ",
            "sane [0.1, 300]s range — falling back to ", fallback, "s.")
    return(fallback)
  }
  epoch_s
}

#' Classify ENMO (in g, as GGIR's epoch CSV export stores it) into an
#' intensity category using config's cut-points (which are expressed in mg)
#'
#' @param enmo_g Numeric vector, ENMO in g (raw epoch CSV units).
#' @param cut_points_mg List with sedentary_to_light, light_to_moderate,
#'   moderate_to_vigorous (all in mg — see config.yaml's ggir.cut_points_mg).
#' @return Character vector: "sedentary", "light", "moderate", or "vigorous".
classify_intensity <- function(enmo_g, cut_points_mg) {
  enmo_mg <- enmo_g * 1000
  as.character(cut(
    enmo_mg,
    breaks = c(-Inf, cut_points_mg$sedentary_to_light,
              cut_points_mg$light_to_moderate,
              cut_points_mg$moderate_to_vigorous, Inf),
    labels = c("sedentary", "light", "moderate", "vigorous"),
    right  = FALSE
  ))
}

#' Build labeled_epochs.csv rows for one participant
#'
#' @param epoch_csv_path Path to GGIR's raw per-epoch export
#'   (meta/csv/<file>.RData.csv — columns timestamp, anglez, ENMO).
#' @param ms2out_path Path to the matching meta/ms2.out/<file>.RData milestone
#'   (holds IMP$r5long, GGIR's own per-epoch invalid/imputed flag).
#' @param id Participant ID (as used elsewhere in the pipeline, e.g. row$ID
#'   from part2).
#' @param meting Character meting label (e.g. "meting_1").
#' @param school school_id string (e.g. "school_2"), from extract_school_id().
#' @param cfg Full config list (cut_points_mg, schedules, timezone, absences path).
#' @param schedule_cache From build_schedule_cache().
#' @param pupil_override_map From build_pupil_override_map().
#' @param part2_days data.table with (at least) calendar_date (Date),
#'   n_valid_hours for THIS participant/meting only — used only for the
#'   wear-polarity sanity check below. NULL skips the check (a missing part2
#'   day just means the check can't run for that day, not that wear is wrong).
#' @param abs_keys Character vector from read_absence_keys(), or character(0).
#' @param part4_nights data.table with (at least) calendar_date, sleeponset,
#'   wakeup for THIS participant only (same convention as
#'   `add_waking_valid_hours()`'s `part4_full` in utils_ggir.R — decimal hours
#'   from that night's calendar_date's own midnight, wakeup > 24 meaning the
#'   wake time falls on the next calendar day). Used to derive the `waking`
#'   column below. NULL (default) leaves `waking` as NA for every epoch — a
#'   missing sleep record means "unknown", not "awake" (see the `waking`
#'   block for why that matters).
#' @return data.table with columns ID, meting, school, date, context,
#'   intensity, wear, waking, epoch_length_s — or NULL if the epoch CSV is
#'   empty/unreadable.
build_labeled_epochs_for_participant <- function(epoch_csv_path, ms2out_path,
                                                  id, meting, school, cfg,
                                                  schedule_cache, pupil_override_map,
                                                  part2_days = NULL,
                                                  abs_keys = character(0),
                                                  part4_nights = NULL) {
  if (!file.exists(epoch_csv_path)) {
    warning("[epoch_labeling] Epoch CSV not found for ", id, ": ", epoch_csv_path)
    return(NULL)
  }

  raw <- tryCatch(
    data.table::fread(epoch_csv_path, data.table = TRUE),
    error = function(e) {
      warning("[epoch_labeling] Could not read epoch CSV for ", id, ": ", e$message)
      NULL
    }
  )
  if (is.null(raw) || nrow(raw) == 0) return(NULL)

  required_cols <- c("timestamp", "ENMO")
  if (!all(required_cols %in% names(raw))) {
    warning("[epoch_labeling] Epoch CSV for ", id, " missing required column(s): ",
            paste(setdiff(required_cols, names(raw)), collapse = ", "))
    return(NULL)
  }

  tz <- cfg$output$timezone %||% "Europe/Brussels"
  ts <- as.POSIXct(raw$timestamp, format = "%Y-%m-%dT%H:%M:%S%z", tz = tz)
  n_bad_ts <- sum(is.na(ts))
  if (n_bad_ts > 0) {
    warning("[epoch_labeling] ", n_bad_ts, " of ", length(ts),
            " timestamp(s) failed to parse for ", id, " — those epochs will be dropped.")
  }
  raw <- raw[!is.na(ts)]
  ts  <- ts[!is.na(ts)]
  if (nrow(raw) == 0) return(NULL)

  epoch_length_s <- derive_epoch_length_s(ts)

  # ── Wear/non-wear from GGIR's own per-epoch invalid/imputed flag ───────────
  # See utils_bouts.R / DEVELOPER.md for why this matters: epochs GGIR flagged
  # invalid (non-wear, clipping, protocol exclusion) have their ENMO/anglez
  # values IMPUTED (averaged from other days), not measured — without
  # excluding them, bout detection would count synthetic values as real
  # sedentary/active time.
  wear <- rep(NA, nrow(raw))
  if (file.exists(ms2out_path)) {
    e <- new.env()
    ok <- tryCatch({ load(ms2out_path, envir = e); TRUE },
                   error = function(err) {
                     warning("[epoch_labeling] Could not load ", ms2out_path, ": ", err$message)
                     FALSE
                   })
    if (ok) {
      r5long <- tryCatch(e$IMP$r5long, error = function(err) NULL)
      if (is.null(r5long)) {
        warning("[epoch_labeling] IMP$r5long not found in ", ms2out_path,
                " — wear flag set to NA for ", id, ".")
      } else {
        r5long <- as.numeric(r5long)
        # r5long is stored as a 1-column matrix in GGIR's IMP object.
        if (!is.null(dim(r5long))) r5long <- as.numeric(r5long[, 1])
        if (length(r5long) != nrow(raw)) {
          warning("[epoch_labeling] IMP$r5long length (", length(r5long),
                  ") does not match epoch CSV row count (", nrow(raw),
                  ") for ", id, " — this couples on GGIR's internal (undocumented) ",
                  "IMP$r5long structure, which may have changed; wear flag set to NA.")
        } else {
          wear <- r5long == 0
        }
      }
    }
  } else {
    warning("[epoch_labeling] ms2.out RData not found for ", id, ": ", ms2out_path,
            " — wear flag set to NA.")
  }

  # ── Sanity cross-check against part2's already-trusted n_valid_hours ───────
  # Guards against IMP$r5long's polarity silently flipping in a future GGIR
  # version (the length check above only catches structural drift, not a
  # meaning flip that preserves length).
  if (!is.null(part2_days) && nrow(part2_days) > 0 && !all(is.na(wear))) {
    epoch_date <- as.Date(ts, tz = tz)
    wear_hours_by_day <- data.table::data.table(date = epoch_date, wear = wear)[
      , .(wear_hours = sum(wear, na.rm = TRUE) * epoch_length_s / 3600), by = date
    ]
    cmp <- merge(wear_hours_by_day, part2_days,
                by.x = "date", by.y = "calendar_date", all.x = TRUE)
    cmp <- cmp[!is.na(n_valid_hours)]
    if (nrow(cmp) > 0) {
      cmp[, diff_h := abs(wear_hours - n_valid_hours)]
      bad <- cmp[diff_h > pmax(1, 0.25 * n_valid_hours)]
      if (nrow(bad) > 0) {
        warning("[epoch_labeling] ", id, ": epoch-derived wear hours diverge from ",
                "part2's n_valid_hours by >max(1h, 25%) on ", nrow(bad), " of ",
                nrow(cmp), " day(s) — IMP$r5long's polarity/meaning may not be what ",
                "this code assumes. Spot-check before trusting bout columns for this ",
                "participant.")
      }
    }
  }

  # ── Intensity classification ────────────────────────────────────────────────
  intensity <- classify_intensity(raw$ENMO, cfg$ggir$cut_points_mg)

  # ── Context labeling (weekday/schedule lookup, same logic as 02) ──────────
  date_val <- as.Date(ts, tz = tz)
  pl       <- as.POSIXlt(ts, tz = tz)
  hour_of_day <- pl$hour + pl$min / 60 + pl$sec / 3600
  weekday  <- weekdays(date_val)

  context <- character(nrow(raw))
  for (d in unique(date_val)) {
    idx  <- which(date_val == d)
    wday <- weekday[idx[1]]

    if (wday %in% c("Saturday", "Sunday")) {
      context[idx] <- "weekend"
      next
    }

    cache_key <- resolve_schedule_key(id, school, wday, schedule_cache, pupil_override_map)
    sched     <- schedule_cache[[cache_key]]

    if (is.null(sched)) {
      context[idx] <- "outside_school"
      next
    }

    seg_idx <- findInterval(hour_of_day[idx], sched$start_h)
    seg_idx[seg_idx < 1] <- 1L
    seg_idx[seg_idx > nrow(sched)] <- nrow(sched)
    context[idx] <- sched$segment[seg_idx]
  }

  # ── Waking-hours flag from Part 4 sleep-period-time (SPT) ──────────────────
  # "Waking hours" = 24h minus that night's GGIR-detected sleep period — same
  # definition add_waking_valid_hours() (utils_ggir.R) uses at the day level,
  # applied here per epoch via each night's actual clock-time onset/wakeup
  # instead of a duration subtraction. This matters because before_school and
  # after_school are NOT "early morning" / "evening" windows — by
  # construction (utils_schedule.R:get_schedule()) before_school spans
  # 00:00-school_start and after_school spans school_end-24:00, i.e. together
  # they cover the ENTIRE rest of the calendar day. Without this flag, a
  # full night's sleep would silently count as "before/after school
  # sedentary time" in any epoch-level aggregation that only filters on wear.
  #
  # NA (not TRUE/FALSE) when no Part 4 night record covers a given calendar
  # date — mirrors add_waking_valid_hours()'s "unknown sleep timing is
  # excluded, not assumed awake" rule.
  waking <- rep(NA, nrow(raw))
  if (!is.null(part4_nights) && nrow(part4_nights) > 0) {
    p4 <- part4_nights[!is.na(calendar_date) & !is.na(sleeponset) & !is.na(wakeup)]
    p4[, calendar_date := as.Date(calendar_date)]
    if (nrow(p4) > 0) {
      onset_dt <- unique(data.table::data.table(
        calendar_date = p4$calendar_date,
        onset_h       = pmin(p4$sleeponset, 24)
      ), by = "calendar_date")
      wake_dt <- unique(data.table::data.table(
        calendar_date = p4$calendar_date + 1,
        wake_h        = pmax(0, p4$wakeup - 24)
      )[wake_h > 0], by = "calendar_date")

      epoch_dt <- data.table::data.table(
        row_i         = seq_len(nrow(raw)),
        calendar_date = date_val,
        hour_of_day   = hour_of_day
      )
      epoch_dt <- merge(epoch_dt, onset_dt, by = "calendar_date", all.x = TRUE)
      epoch_dt <- merge(epoch_dt, wake_dt,  by = "calendar_date", all.x = TRUE)
      data.table::setorder(epoch_dt, row_i)

      covered <- !is.na(epoch_dt$onset_h) | !is.na(epoch_dt$wake_h)
      is_asleep <-
        (!is.na(epoch_dt$onset_h) & epoch_dt$hour_of_day >= epoch_dt$onset_h) |
        (!is.na(epoch_dt$wake_h)  & epoch_dt$hour_of_day <  epoch_dt$wake_h)

      waking[covered] <- !is_asleep[covered]
    }
  }

  # ── Absence overlay (whole day, same as 02_label_segments.R) ───────────────
  # Full-day exclusion (docs/test/plan_absences_config.md §4) — relabels
  # EVERY context on an absent date, not just school-hours segments, so
  # before_school/after_school epochs on an absent day no longer leak into
  # real-context bout columns either. Still only touches daytime context
  # labels — sleep-related epoch data is a separate part of GGIR's output
  # and is never touched.
  #
  # abs_keys is built from get_absence_entries()'s extension-stripped
  # pupil_id (e.g. "1901"), but `id` here is the raw participant ID as GGIR
  # records it (e.g. "1901.csv") — same mismatch Step 3 found and fixed in
  # 02_label_segments.R. strip_pupil_id() (utils_schedule.R) centralizes
  # this so it can't silently drift out of sync between call sites again.
  if (length(abs_keys) > 0) {
    is_absent <- paste(strip_pupil_id(id), date_val) %in% abs_keys
    context[is_absent] <- "absent"
  }

  data.table::data.table(
    ID             = id,
    meting         = meting,
    school         = school,
    date           = date_val,
    context        = context,
    intensity      = intensity,
    wear           = wear,
    waking         = waking,
    epoch_length_s = epoch_length_s
  )
}

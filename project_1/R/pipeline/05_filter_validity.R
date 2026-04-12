# =============================================================================
# SchoolMoves Pipeline — Step 5: Validity Filtering
# =============================================================================
# Assesses each pupil's data validity using GGIR Part 2 output when available,
# or epoch-level data as fallback (legacy bypass mode).
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Assess validity from GGIR Part 2 day summary
#'
#' Reads GGIR's own validity columns (N valid hours, N valid days, etc.)
#' and applies the configured thresholds.
#'
#' @param part2_daysummary data.frame from read_part2_daysummary()
#' @param params Named list from read_pipeline_params()
#' @return data.frame with one row per pupil:
#'   pupil_id, n_valid_days, n_valid_nights, pupil_valid_sedentary,
#'   pupil_valid_sleep, exclusion_reason
assess_validity_from_ggir <- function(part2_daysummary, part4_sleep = NULL, params = NULL) {
  min_days   <- if (!is.null(params)) params$min_valid_days_waking else 4
  min_hours  <- if (!is.null(params)) params$min_valid_hours_per_day else 9
  min_nights <- if (!is.null(params)) params$min_valid_nights_sleep else 5
  min_pct    <- if (!is.null(params)) params$min_pct_night_valid else 50

  log_step(paste("Validity criteria: >=", min_days, "days with >=",
                 min_hours, "h wear; >=", min_nights, "nights with >=",
                 min_pct, "% coverage"))

  # GGIR Part 2 has columns like N.valid.hours, N.hours
  # Find the filename/ID column (varies by GGIR version)
  id_col <- intersect(c("filename", "ID", "id"), names(part2_daysummary))[1]
  if (is.na(id_col)) {
    id_col <- names(part2_daysummary)[1]
  }

  # Find valid hours column
  hour_cols <- grep("valid.*hour|N\\.valid\\.hours|dur_day_valid", names(part2_daysummary),
                    value = TRUE, ignore.case = TRUE)
  if (length(hour_cols) == 0) {
    hour_cols <- grep("N\\.hours", names(part2_daysummary), value = TRUE)
  }

  # Extract pupil IDs from filenames
  part2_daysummary$pupil_id <- extract_pupil_from_ggir_col(part2_daysummary[[id_col]])

  # Count valid days per pupil
  if (length(hour_cols) > 0) {
    valid_hours_col <- hour_cols[1]
    part2_daysummary$valid_day <- !is.na(part2_daysummary[[valid_hours_col]]) &
                                   part2_daysummary[[valid_hours_col]] >= min_hours
  } else {
    # Fallback: count all days as valid
    log_step("Warning: Could not find valid hours column in Part 2 output. Counting all days as valid.")
    part2_daysummary$valid_day <- TRUE
  }

  day_validity <- part2_daysummary |>
    dplyr::group_by(pupil_id) |>
    dplyr::summarise(
      n_valid_days = sum(valid_day, na.rm = TRUE),
      n_total_days = dplyr::n(),
      .groups = "drop"
    )

  # Sleep validity from Part 4
  if (!is.null(part4_sleep) && nrow(part4_sleep) > 0) {
    sleep_id_col <- intersect(c("filename", "ID", "id"), names(part4_sleep))[1]
    if (!is.na(sleep_id_col)) {
      part4_sleep$pupil_id <- extract_pupil_from_ggir_col(part4_sleep[[sleep_id_col]])

      night_validity <- part4_sleep |>
        dplyr::group_by(pupil_id) |>
        dplyr::summarise(
          n_valid_nights = sum(!is.na(pupil_id)),  # count non-NA rows
          .groups = "drop"
        )
      day_validity <- merge(day_validity, night_validity, by = "pupil_id", all.x = TRUE)
    }
  }

  if (!"n_valid_nights" %in% names(day_validity)) {
    day_validity$n_valid_nights <- 0L
  }
  day_validity$n_valid_nights[is.na(day_validity$n_valid_nights)] <- 0L

  # Apply criteria
  day_validity$pupil_valid_sedentary <- day_validity$n_valid_days >= min_days
  day_validity$pupil_valid_sleep <- day_validity$n_valid_nights >= min_nights

  day_validity$exclusion_reason <- apply(day_validity, 1, function(row) {
    reasons <- character(0)
    if (!as.logical(row["pupil_valid_sedentary"])) {
      reasons <- c(reasons, paste0("Only ", row["n_valid_days"], " valid waking days (need ", min_days, ")"))
    }
    if (!as.logical(row["pupil_valid_sleep"])) {
      reasons <- c(reasons, paste0("Only ", row["n_valid_nights"], " valid nights (need ", min_nights, ")"))
    }
    if (length(reasons) == 0) NA_character_ else paste(reasons, collapse = "; ")
  })

  n_valid_both <- sum(day_validity$pupil_valid_sedentary & day_validity$pupil_valid_sleep)
  log_step(paste("Validity:", nrow(day_validity), "pupils assessed,",
                 n_valid_both, "pass both criteria"))

  as.data.frame(day_validity)
}

#' Assess validity from epoch data (legacy fallback)
#'
#' @param epochs data.frame with columns: pupil_id, timestamp, date, wear
#' @param params Named list from read_pipeline_params()
#' @return data.frame with validity flags
assess_validity <- function(epochs, params = NULL) {
  min_days   <- if (!is.null(params)) params$min_valid_days_waking else 4
  min_hours  <- if (!is.null(params)) params$min_valid_hours_per_day else 9
  min_nights <- if (!is.null(params)) params$min_valid_nights_sleep else 5
  min_pct    <- if (!is.null(params)) params$min_pct_night_valid else 50

  log_step(paste("Validity criteria (epoch mode): >=", min_days, "days with >=",
                 min_hours, "h wear; >=", min_nights, "nights with >=",
                 min_pct, "% coverage"))

  pupils <- unique(epochs$pupil_id)
  results <- lapply(pupils, function(pid) {
    pdata <- epochs[epochs$pupil_id == pid, ]
    assess_single_pupil(pdata, min_hours, min_days, min_nights, min_pct)
  })

  validity <- do.call(rbind, results)
  n_valid_both <- sum(validity$pupil_valid_sedentary & validity$pupil_valid_sleep)
  log_step(paste("Validity:", nrow(validity), "pupils assessed,",
                 n_valid_both, "pass both criteria"))
  validity
}

#' Assess validity for a single pupil (epoch-level)
assess_single_pupil <- function(pdata, min_hours, min_days, min_nights, min_pct) {
  pid <- pdata$pupil_id[1]

  if (inherits(pdata$timestamp, "POSIXct")) {
    hour_of_day <- as.numeric(format(pdata$timestamp, "%H"))
  } else {
    ts <- as.POSIXct(pdata$timestamp, tz = "Europe/Brussels")
    hour_of_day <- as.numeric(format(ts, "%H"))
  }
  is_waking <- hour_of_day >= 6 & hour_of_day < 23

  waking_wear <- pdata[is_waking & pdata$wear, ]
  if (nrow(waking_wear) > 0) {
    daily_wear_seconds <- tapply(rep(1, nrow(waking_wear)), waking_wear$date, sum)
    daily_wear_hours <- daily_wear_seconds / 3600
    n_valid_days <- sum(daily_wear_hours >= min_hours)
  } else {
    n_valid_days <- 0L
  }

  is_night <- hour_of_day >= 23 | hour_of_day < 6
  night_data <- pdata[is_night, ]
  if (nrow(night_data) > 0) {
    night_date <- as.Date(night_data$timestamp, tz = "Europe/Brussels")
    night_hour <- as.numeric(format(
      if (inherits(night_data$timestamp, "POSIXct")) night_data$timestamp
      else as.POSIXct(night_data$timestamp, tz = "Europe/Brussels"), "%H"))
    night_date[night_hour < 6] <- night_date[night_hour < 6] - 1
    night_total_epochs <- 7 * 3600
    night_counts <- tapply(rep(1, nrow(night_data)), night_date, sum)
    night_pct <- (night_counts / night_total_epochs) * 100
    n_valid_nights <- sum(night_pct >= min_pct)
  } else {
    n_valid_nights <- 0L
  }

  valid_sed <- n_valid_days >= min_days
  valid_sleep <- n_valid_nights >= min_nights

  reasons <- character(0)
  if (!valid_sed) reasons <- c(reasons, paste0("Only ", n_valid_days, " valid waking days (need ", min_days, ")"))
  if (!valid_sleep) reasons <- c(reasons, paste0("Only ", n_valid_nights, " valid nights (need ", min_nights, ")"))

  data.frame(
    pupil_id = pid, n_valid_days = n_valid_days, n_valid_nights = n_valid_nights,
    pupil_valid_sedentary = valid_sed, pupil_valid_sleep = valid_sleep,
    exclusion_reason = if (length(reasons) == 0) NA_character_ else paste(reasons, collapse = "; "),
    stringsAsFactors = FALSE
  )
}

#' Extract pupil ID from GGIR filename column values
extract_pupil_from_ggir_col <- function(filenames) {
  fname <- tools::file_path_sans_ext(basename(filenames))
  sapply(strsplit(fname, "[_ ]"), `[`, 1)
}

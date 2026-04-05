# =============================================================================
# SchoolMoves Pipeline — Step 5: Validity Filtering
# =============================================================================
# Assesses each pupil's data validity against configurable criteria.
# Pupils must meet BOTH waking and sleep thresholds to be fully valid.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Assess validity per pupil
#'
#' For each pupil, counts:
#'   - Valid waking days: days with >= min_valid_hours_waking of wear time
#'   - Valid nights: nights with >= min_pct_night_valid of data coverage
#'
#' A pupil passes waking validity if n_valid_days >= min_valid_days_waking.
#' A pupil passes sleep validity if n_valid_nights >= min_valid_nights_sleep.
#'
#' @param epochs data.frame with columns: pupil_id, timestamp, date, wear
#' @param params Named list from read_pipeline_params(). If NULL, uses defaults.
#' @return data.frame with one row per pupil:
#'   pupil_id, n_valid_days, n_valid_nights, pupil_valid_sedentary,
#'   pupil_valid_sleep, exclusion_reason
assess_validity <- function(epochs, params = NULL) {
  # Extract parameters (use defaults if not provided)
  min_days   <- if (!is.null(params)) params$min_valid_days_waking else 4
  min_hours  <- if (!is.null(params)) params$min_valid_hours_per_day else 9
  min_nights <- if (!is.null(params)) params$min_valid_nights_sleep else 5
  min_pct    <- if (!is.null(params)) params$min_pct_night_valid else 50

  log_step(paste("Validity criteria: >=", min_days, "days with >=",
                 min_hours, "h wear; >=", min_nights, "nights with >=",
                 min_pct, "% coverage"))

  pupils <- unique(epochs$pupil_id)
  results <- lapply(pupils, function(pid) {
    pdata <- epochs[epochs$pupil_id == pid, ]
    assess_single_pupil(pdata, min_hours, min_days, min_nights, min_pct)
  })

  validity <- do.call(rbind, results)

  n_valid_both <- sum(validity$pupil_valid_sedentary & validity$pupil_valid_sleep)
  log_step(paste("Validity: ", nrow(validity), "pupils assessed,",
                 n_valid_both, "pass both criteria"))

  validity
}

#' Assess validity for a single pupil
#'
#' @param pdata data.frame — all epochs for one pupil
#' @param min_hours Minimum wear hours per valid day
#' @param min_days Minimum valid days for waking analysis
#' @param min_nights Minimum valid nights for sleep analysis
#' @param min_pct Minimum % night coverage for valid night
#' @return One-row data.frame with validity flags
assess_single_pupil <- function(pdata, min_hours, min_days, min_nights, min_pct) {
  pid <- pdata$pupil_id[1]

  # --- Waking validity ---
  # Count wear hours per day (waking hours roughly 06:00-23:00)
  if (inherits(pdata$timestamp, "POSIXct")) {
    hour_of_day <- as.numeric(format(pdata$timestamp, "%H"))
  } else {
    ts <- as.POSIXct(pdata$timestamp, tz = "Europe/Brussels")
    hour_of_day <- as.numeric(format(ts, "%H"))
  }
  is_waking <- hour_of_day >= 6 & hour_of_day < 23

  # Wear hours per day during waking time
  waking_wear <- pdata[is_waking & pdata$wear, ]
  if (nrow(waking_wear) > 0) {
    daily_wear_seconds <- tapply(rep(1, nrow(waking_wear)),
                                  waking_wear$date, sum)
    daily_wear_hours <- daily_wear_seconds / 3600
    n_valid_days <- sum(daily_wear_hours >= min_hours)
  } else {
    n_valid_days <- 0L
  }

  # --- Sleep validity ---
  # Night = 23:00 to 06:00 next day
  is_night <- hour_of_day >= 23 | hour_of_day < 6
  night_data <- pdata[is_night, ]

  if (nrow(night_data) > 0) {
    # Group nights: hours 23-24 belong to that date's night,
    # hours 0-6 belong to the previous date's night
    night_date <- as.Date(night_data$timestamp, tz = "Europe/Brussels")
    if (inherits(night_data$timestamp, "POSIXct")) {
      night_hour <- as.numeric(format(night_data$timestamp, "%H"))
    } else {
      night_hour <- as.numeric(format(as.POSIXct(night_data$timestamp,
                                                  tz = "Europe/Brussels"), "%H"))
    }
    # Hours 0-5 belong to previous night
    night_date[night_hour < 6] <- night_date[night_hour < 6] - 1

    # Total possible night epochs = 7 hours * 3600 seconds = 25200
    night_total_epochs <- 7 * 3600
    night_counts <- tapply(rep(1, nrow(night_data)), night_date, sum)
    night_pct <- (night_counts / night_total_epochs) * 100
    n_valid_nights <- sum(night_pct >= min_pct)
  } else {
    n_valid_nights <- 0L
  }

  # --- Build result ---
  valid_sed <- n_valid_days >= min_days
  valid_sleep <- n_valid_nights >= min_nights

  reasons <- character(0)
  if (!valid_sed) {
    reasons <- c(reasons, paste0("Only ", n_valid_days, " valid waking days (need ", min_days, ")"))
  }
  if (!valid_sleep) {
    reasons <- c(reasons, paste0("Only ", n_valid_nights, " valid nights (need ", min_nights, ")"))
  }

  data.frame(
    pupil_id             = pid,
    n_valid_days         = n_valid_days,
    n_valid_nights       = n_valid_nights,
    pupil_valid_sedentary = valid_sed,
    pupil_valid_sleep     = valid_sleep,
    exclusion_reason     = if (length(reasons) == 0) NA_character_
                           else paste(reasons, collapse = "; "),
    stringsAsFactors     = FALSE
  )
}

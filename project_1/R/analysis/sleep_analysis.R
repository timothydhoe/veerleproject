# =============================================================================
# SchoolMoves Analysis — Sleep Analysis (RQ3)
# =============================================================================
# Summarises GGIR Part 4 sleep output per pupil per night.
# =============================================================================

#' Summarise sleep data per pupil per night
#'
#' Wraps GGIR Part 4 output (or simulated sleep data from bypass mode).
#' Returns one row per pupil per night with sleep onset, offset, duration,
#' and validity flags.
#'
#' @param sleep_output data.frame — GGIR Part 4 output with columns:
#'   pupil_id, date, sleep_onset (POSIXct), sleep_offset (POSIXct)
#'   OR if from bypass mode: pupil_id, date, timestamp, wear
#' @param validity_data data.frame — per-pupil validity flags from assess_validity()
#' @return data.frame with columns:
#'   pupil_id, date, sleep_onset, sleep_offset,
#'   sleep_duration_h, pct_night_valid, valid_night
summarise_sleep <- function(sleep_output, validity_data = NULL) {

  # If sleep_output has explicit onset/offset (from GGIR Part 4)
  if (all(c("sleep_onset", "sleep_offset") %in% names(sleep_output))) {
    result <- sleep_output |>
      dplyr::mutate(
        sleep_duration_h = as.numeric(difftime(sleep_offset, sleep_onset, units = "hours"))
      )

    # Calculate pct_night_valid if not already present
    if (!"pct_night_valid" %in% names(result)) {
      # Assume 100% for GGIR-detected sleep (GGIR already validates internally)
      result$pct_night_valid <- 100
    }

    result$valid_night <- result$pct_night_valid >= 50

  } else if (all(c("timestamp", "wear") %in% names(sleep_output))) {
    # Bypass mode: estimate sleep from epoch data
    # Night window: 21:00 to 08:00
    result <- estimate_sleep_from_epochs(sleep_output)

  } else {
    stop("sleep_output must contain either (sleep_onset, sleep_offset) or (timestamp, wear) columns.\n",
         "  Available: ", paste(names(sleep_output), collapse = ", "))
  }

  # Merge validity data if provided
  if (!is.null(validity_data) && "pupil_valid_sleep" %in% names(validity_data)) {
    result <- merge(result,
                    validity_data[, c("pupil_id", "pupil_valid_sleep")],
                    by = "pupil_id", all.x = TRUE)
  }

  as.data.frame(result)
}

#' Estimate sleep from epoch data (bypass mode)
#'
#' When GGIR Part 4 output is not available, estimates sleep from
#' low-activity periods during nighttime hours. This is approximate.
#'
#' @param epochs data.frame with columns: pupil_id, timestamp, wear, enmo_mg
#' @return data.frame with sleep summary per night
estimate_sleep_from_epochs <- function(epochs) {
  if (!inherits(epochs$timestamp, "POSIXct")) {
    epochs$timestamp <- as.POSIXct(epochs$timestamp, tz = "Europe/Brussels")
  }

  hour <- as.numeric(format(epochs$timestamp, "%H"))

  # Night window: 21:00 to 08:00 next day
  is_night <- hour >= 21 | hour < 8
  night_epochs <- epochs[is_night, ]

  if (nrow(night_epochs) == 0) {
    return(data.frame(
      pupil_id = character(), date = as.Date(character()),
      sleep_onset = as.POSIXct(character()), sleep_offset = as.POSIXct(character()),
      sleep_duration_h = numeric(), pct_night_valid = numeric(),
      valid_night = logical(), stringsAsFactors = FALSE
    ))
  }

  # Assign each night epoch to a night date (hours 0-7 belong to previous night)
  night_date <- as.Date(night_epochs$timestamp, tz = "Europe/Brussels")
  night_hour <- as.numeric(format(night_epochs$timestamp, "%H"))
  night_date[night_hour < 8] <- night_date[night_hour < 8] - 1

  night_epochs$night_date <- night_date

  # Total possible night epochs = 11 hours * 3600 = 39600
  total_night_seconds <- 11 * 3600

  # Summarise per pupil per night
  summary <- night_epochs |>
    dplyr::group_by(pupil_id, night_date) |>
    dplyr::summarise(
      sleep_onset     = min(timestamp),
      sleep_offset    = max(timestamp),
      n_epochs        = dplyr::n(),
      n_wear          = sum(wear, na.rm = TRUE),
      pct_night_valid = (n_wear / total_night_seconds) * 100,
      .groups = "drop"
    ) |>
    dplyr::mutate(
      date = night_date,
      sleep_duration_h = as.numeric(difftime(sleep_offset, sleep_onset, units = "hours")),
      valid_night = pct_night_valid >= 50
    ) |>
    dplyr::select(pupil_id, date, sleep_onset, sleep_offset,
                  sleep_duration_h, pct_night_valid, valid_night)

  as.data.frame(summary)
}

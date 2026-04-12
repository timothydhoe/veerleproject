# =============================================================================
# SchoolMoves Analysis — Sleep Analysis (RQ3)
# =============================================================================
# Summarises sleep data from GGIR Part 4 output.
# =============================================================================

#' Summarise sleep from GGIR Part 4 output
#'
#' Reads Part 4 nightsummary and returns per-pupil per-night sleep metrics.
#'
#' @param part4_sleep data.frame from read_part4_sleep()
#' @return data.frame with columns:
#'   pupil_id, date, sleep_onset, sleep_offset,
#'   sleep_duration_h, sleeponset, wakeup
summarise_sleep_ggir <- function(part4_sleep) {
  if (is.null(part4_sleep) || nrow(part4_sleep) == 0) {
    message("No Part 4 sleep data available.")
    return(data.frame(
      pupil_id = character(), date = as.Date(character()),
      sleep_onset = character(), sleep_offset = character(),
      sleep_duration_h = numeric(), stringsAsFactors = FALSE
    ))
  }

  # Extract pupil IDs
  id_col <- intersect(c("filename", "ID", "id"), names(part4_sleep))[1]
  if (is.na(id_col)) id_col <- names(part4_sleep)[1]
  part4_sleep$pupil_id <- sapply(
    strsplit(tools::file_path_sans_ext(basename(part4_sleep[[id_col]])), "[_ ]"),
    `[`, 1
  )

  # Find sleep onset/offset columns (GGIR naming varies)
  onset_col <- grep("sleeponset|sleep_onset|onset", names(part4_sleep),
                    value = TRUE, ignore.case = TRUE)
  offset_col <- grep("wakeup|sleep_offset|offset", names(part4_sleep),
                     value = TRUE, ignore.case = TRUE)
  dur_col <- grep("SleepDuration|sleep_duration|dur.*sleep", names(part4_sleep),
                  value = TRUE, ignore.case = TRUE)
  date_col <- grep("calendar_date|night|date", names(part4_sleep),
                   value = TRUE, ignore.case = TRUE)

  result <- data.frame(
    pupil_id = part4_sleep$pupil_id,
    stringsAsFactors = FALSE
  )

  if (length(date_col) > 0) result$date <- part4_sleep[[date_col[1]]]
  if (length(onset_col) > 0) result$sleep_onset <- part4_sleep[[onset_col[1]]]
  if (length(offset_col) > 0) result$sleep_offset <- part4_sleep[[offset_col[1]]]
  if (length(dur_col) > 0) {
    result$sleep_duration_h <- as.numeric(part4_sleep[[dur_col[1]]])
  }

  result
}

#' Legacy: summarise sleep from epoch data (bypass mode)
#'
#' @param sleep_output data.frame with sleep_onset/sleep_offset OR timestamp/wear
#' @param validity_data Optional validity data
#' @return data.frame with sleep summary
summarise_sleep <- function(sleep_output, validity_data = NULL) {
  if (all(c("sleep_onset", "sleep_offset") %in% names(sleep_output))) {
    result <- sleep_output |>
      dplyr::mutate(
        sleep_duration_h = as.numeric(difftime(sleep_offset, sleep_onset, units = "hours"))
      )
    if (!"pct_night_valid" %in% names(result)) result$pct_night_valid <- 100
    result$valid_night <- result$pct_night_valid >= 50

  } else if (all(c("timestamp", "wear") %in% names(sleep_output))) {
    result <- estimate_sleep_from_epochs(sleep_output)
  } else {
    stop("sleep_output must contain either (sleep_onset, sleep_offset) or (timestamp, wear) columns.")
  }

  if (!is.null(validity_data) && "pupil_valid_sleep" %in% names(validity_data)) {
    result <- merge(result, validity_data[, c("pupil_id", "pupil_valid_sleep")],
                    by = "pupil_id", all.x = TRUE)
  }
  as.data.frame(result)
}

#' Estimate sleep from epoch data (legacy bypass)
estimate_sleep_from_epochs <- function(epochs) {
  if (!inherits(epochs$timestamp, "POSIXct")) {
    epochs$timestamp <- as.POSIXct(epochs$timestamp, tz = "Europe/Brussels")
  }
  hour <- as.numeric(format(epochs$timestamp, "%H"))
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

  night_date <- as.Date(night_epochs$timestamp, tz = "Europe/Brussels")
  night_hour <- as.numeric(format(night_epochs$timestamp, "%H"))
  night_date[night_hour < 8] <- night_date[night_hour < 8] - 1
  night_epochs$night_date <- night_date
  total_night_seconds <- 11 * 3600

  summary <- night_epochs |>
    dplyr::group_by(pupil_id, night_date) |>
    dplyr::summarise(
      sleep_onset = min(timestamp), sleep_offset = max(timestamp),
      n_wear = sum(wear, na.rm = TRUE),
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

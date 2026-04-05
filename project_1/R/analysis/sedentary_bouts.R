# =============================================================================
# SchoolMoves Analysis — Activity Bouts (RQ2)
# =============================================================================
# Detects sustained bouts of any intensity level using run-length encoding.
# Bouts spanning context boundaries are split.
# =============================================================================

#' Detect bouts of a specific activity intensity
#'
#' Uses run-length encoding (rle) on the intensity column to find consecutive
#' epochs at the target intensity. Bouts spanning a context change are split
#' at the boundary.
#'
#' @param epochs data.frame with columns: pupil_id, date, context, intensity, wear
#' @param min_bout_min Minimum bout duration in minutes. Default 30.
#' @param target_intensity One of "sedentary", "light", "moderate", "vigorous"
#' @param valid_only If TRUE, exclude non-wear epochs. Default TRUE.
#' @return data.frame with columns:
#'   pupil_id, date, context, intensity, n_bouts, mean_bout_min, total_bout_min
detect_activity_bouts <- function(epochs,
                                  min_bout_min = 30,
                                  target_intensity = "sedentary",
                                  valid_only = TRUE) {
  df <- epochs
  if (valid_only && "wear" %in% names(df)) {
    df <- df[df$wear == TRUE, ]
  }

  df <- df[!is.na(df$intensity), ]
  min_bout_epochs <- min_bout_min * 60  # convert minutes to 1-second epochs

  all_results <- list()
  pupil_ids <- unique(df$pupil_id)

  for (pid in pupil_ids) {
    pdata <- df[df$pupil_id == pid, ]
    dates <- unique(pdata$date)

    for (d in dates) {
      ddata <- pdata[pdata$date == d, ]
      if (nrow(ddata) == 0) next

      # Create a combined key of intensity + context for rle
      # This ensures bouts are split at context boundaries
      is_target <- as.character(ddata$intensity) == target_intensity
      context_vec <- ddata$context

      # Run-length encode: a "bout" is a run of TRUE in is_target
      # that stays within the same context
      bout_key <- paste(is_target, context_vec, sep = "|")
      runs <- rle(bout_key)

      # Identify qualifying bouts
      run_end <- cumsum(runs$lengths)
      run_start <- c(1, run_end[-length(run_end)] + 1)

      for (j in seq_along(runs$values)) {
        val_parts <- strsplit(runs$values[j], "\\|")[[1]]
        is_match <- val_parts[1] == "TRUE"
        ctx <- val_parts[2]

        if (!is_match) next
        if (runs$lengths[j] < min_bout_epochs) next

        bout_duration_min <- runs$lengths[j] / 60
        bout_row <- data.frame(
          pupil_id  = pid,
          date      = d,
          context   = ctx,
          intensity = target_intensity,
          bout_duration_min = bout_duration_min,
          stringsAsFactors = FALSE
        )
        all_results[[length(all_results) + 1]] <- bout_row
      }
    }
  }

  if (length(all_results) == 0) {
    return(data.frame(
      pupil_id = character(), date = as.Date(character()),
      context = character(), intensity = character(),
      n_bouts = integer(), mean_bout_min = numeric(),
      total_bout_min = numeric(), stringsAsFactors = FALSE
    ))
  }

  bout_data <- do.call(rbind, all_results)

  # Aggregate: n_bouts, mean_bout_min, total_bout_min per pupil/date/context
  summary <- bout_data |>
    dplyr::group_by(pupil_id, date, context, intensity) |>
    dplyr::summarise(
      n_bouts        = dplyr::n(),
      mean_bout_min  = mean(bout_duration_min),
      total_bout_min = sum(bout_duration_min),
      .groups = "drop"
    )

  as.data.frame(summary)
}

#' Convenience wrapper for sedentary bout detection
#'
#' @param epochs data.frame
#' @param min_bout_min Minimum sedentary bout in minutes. Default 30.
#' @param valid_only Exclude non-wear. Default TRUE.
#' @return data.frame with bout summary
detect_sedentary_bouts <- function(epochs, min_bout_min = 30, valid_only = TRUE) {
  detect_activity_bouts(epochs, min_bout_min, "sedentary", valid_only)
}

#' Detect bouts for all intensity levels
#'
#' Runs detect_activity_bouts() for each intensity with its own minimum
#' bout duration, then combines the results.
#'
#' @param epochs data.frame
#' @param bout_configs Named list: intensity -> min_bout_min.
#'   Default: list(sedentary=30, light=10, moderate=5, vigorous=5)
#' @param valid_only Exclude non-wear. Default TRUE.
#' @return data.frame with combined bout summaries across all intensities
detect_all_bouts <- function(epochs,
                             bout_configs = NULL,
                             valid_only = TRUE) {
  if (is.null(bout_configs)) {
    bout_configs <- list(sedentary = 30, light = 10, moderate = 5, vigorous = 5)
  }

  results <- lapply(names(bout_configs), function(intensity) {
    detect_activity_bouts(epochs, bout_configs[[intensity]], intensity, valid_only)
  })

  do.call(rbind, results)
}

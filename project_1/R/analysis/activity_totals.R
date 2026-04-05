# =============================================================================
# SchoolMoves Analysis — Activity Totals (RQ1)
# =============================================================================
# Daily minutes per intensity level per context per pupil.
# =============================================================================

#' Compute daily activity totals per pupil per context
#'
#' Groups epoch data by pupil_id, date, and context, then counts epochs
#' per intensity level and converts to minutes (1 epoch = 1 second).
#'
#' @param epochs data.frame with columns: pupil_id, date, context, intensity, wear
#' @param valid_only If TRUE, exclude non-wear epochs. Default TRUE.
#' @return data.frame with columns:
#'   pupil_id, school_id, date, context,
#'   sedentary_min, light_min, moderate_min, vigorous_min, total_wear_min
compute_activity_totals <- function(epochs, valid_only = TRUE) {
  df <- epochs

  if (valid_only && "wear" %in% names(df)) {
    df <- df[df$wear == TRUE, ]
  }

  # Remove epochs with missing intensity
  df <- df[!is.na(df$intensity), ]

  # Group and count
  totals <- df |>
    dplyr::group_by(pupil_id, school_id, date, context) |>
    dplyr::summarise(
      sedentary_min = sum(intensity == "sedentary") / 60,
      light_min     = sum(intensity == "light") / 60,
      moderate_min  = sum(intensity == "moderate") / 60,
      vigorous_min  = sum(intensity == "vigorous") / 60,
      total_wear_min = dplyr::n() / 60,
      .groups = "drop"
    )

  as.data.frame(totals)
}


# =============================================================================
# SchoolMoves Analysis — Activity Totals (RQ1)
# =============================================================================
# Daily minutes per intensity level per context per pupil.
# Reads from GGIR Part 5 day summaries when available, or from epoch data
# as fallback for legacy bypass mode.
# =============================================================================

#' Compute activity totals from GGIR Part 5 day summary
#'
#' GGIR Part 5 already contains minutes in SB/LPA/MPA/VPA per day per qwindow
#' segment. This function reshapes and labels them with school contexts.
#'
#' @param part5_daysummary data.frame from read_part5_daysummary()
#' @param context_map data.frame from build_qwindow_context_map() (optional)
#' @return data.frame with per-pupil per-day per-context activity minutes
compute_activity_totals_ggir <- function(part5_daysummary, context_map = NULL) {
  if (is.null(part5_daysummary) || nrow(part5_daysummary) == 0) {
    message("No Part 5 day summary available.")
    return(NULL)
  }

  # Extract pupil IDs from filename column
  id_col <- intersect(c("filename", "ID", "id"), names(part5_daysummary))[1]
  if (is.na(id_col)) id_col <- names(part5_daysummary)[1]
  part5_daysummary$pupil_id <- sapply(
    strsplit(tools::file_path_sans_ext(basename(part5_daysummary[[id_col]])), "[_ ]"),
    `[`, 1
  )
  part5_daysummary$school_id <- as.integer(substr(part5_daysummary$pupil_id, 1, 1))

  # Return the GGIR Part 5 data with pupil metadata
  # The column names contain the segment and intensity info
  part5_daysummary
}

#' Compute daily activity totals from epoch data (legacy fallback)
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

  df <- df[!is.na(df$intensity), ]

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

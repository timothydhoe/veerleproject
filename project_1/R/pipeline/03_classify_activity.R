# =============================================================================
# SchoolMoves Pipeline — Step 3: Activity Intensity Classification
# =============================================================================
# Adds an 'intensity' column to epoch data based on ENMO cut-points.
# =============================================================================

source("R/pipeline/utils.R", local = TRUE)

#' Build thresholds from pipeline parameters
#'
#' @param params Named list from read_pipeline_params()
#' @return Named numeric vector: c(sedentary, light, moderate)
build_thresholds <- function(params) {
  c(
    sedentary = params$threshold_lig,
    light     = params$threshold_mod,
    moderate  = params$threshold_vig
  )
}

#' Classify ENMO values into activity intensity levels
#'
#' Applies cut-points to the enmo_mg column and adds an ordered factor
#' column 'intensity' with levels: sedentary, light, moderate, vigorous.
#'
#' Cut-points (default Hildebrand et al. wrist, children):
#'   sedentary:  ENMO < 56.3 mg
#'   light:      56.3 <= ENMO < 191.6 mg
#'   moderate:   191.6 <= ENMO < 695.8 mg
#'   vigorous:   ENMO >= 695.8 mg
#'
#' @param epochs data.frame with at least column: enmo_mg
#' @param thresholds Named numeric vector with elements: sedentary, light, moderate.
#'   Values represent the UPPER boundary of sedentary, light, and moderate.
#' @return Same data.frame with added column 'intensity' (ordered factor)
classify_intensity <- function(epochs, thresholds = NULL) {
  if (is.null(thresholds)) {
    thresholds <- c(sedentary = 56.3, light = 191.6, moderate = 695.8)
  }

  if (!"enmo_mg" %in% names(epochs)) {
    stop("Column 'enmo_mg' not found in epochs data.\n",
         "  Available columns: ", paste(names(epochs), collapse = ", "))
  }

  epochs$intensity <- cut(
    epochs$enmo_mg,
    breaks = c(-Inf, thresholds["sedentary"], thresholds["light"],
               thresholds["moderate"], Inf),
    labels = c("sedentary", "light", "moderate", "vigorous"),
    right  = FALSE,
    ordered_result = TRUE
  )

  n_total <- nrow(epochs)
  n_sed <- sum(epochs$intensity == "sedentary", na.rm = TRUE)
  n_vig <- sum(epochs$intensity == "vigorous", na.rm = TRUE)
  log_step(paste("Classified", n_total, "epochs:",
                 round(n_sed / n_total * 100, 1), "% sedentary,",
                 round(n_vig / n_total * 100, 1), "% vigorous"))

  epochs
}

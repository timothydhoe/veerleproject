# util_filters.R
# ─────────────────────────────────────────────────────────────────────────────
# Pure filter and label utilities: no reactive context, no Shiny input
# dependencies. Sourced by global.R so everything here is available in
# server.R and modules.
# ─────────────────────────────────────────────────────────────────────────────

#' Canonical school ID extractor (defined once — pipeline scripts have local
#' copies that will be retired when they source this file).
#'
#' @param id  Participant ID string (e.g. "2063.csv" or "2063").
#' @return    School key string, e.g. "school_2".
extract_school_id <- function(id) {
  code     <- suppressWarnings(as.integer(sub("\\.[^.]+$", "", basename(as.character(id)))))
  school_n <- code %/% 1000L
  # Only school_1..school_6 exist. A filename that doesn't follow the 4-digit
  # convention (e.g. a raw device serial number) would otherwise silently
  # produce a plausible-looking but wrong label like "school_73".
  school_n[is.na(school_n) | school_n < 1L | school_n > 6L] <- NA_integer_
  paste0("school_", school_n)
}

#' Apply global school/meting selectors to any data.table.
#'
#' Pure version: school and meting values are explicit arguments, not read
#' from Shiny input directly. server.R wraps this in apply_filters() which
#' injects input$global_school and safe_meting().
#'
#' @param dt         data.table to filter (modified by reference via data.table
#'                   subset — pass copy() if the original must be preserved).
#' @param school_val Resolved school filter value ("all" or a display label).
#' @param meting_val Resolved meting filter value ("all", "meting_1", "meting_2").
#' @param school_col Column name for school in dt (default "school").
#' @param meting_col Column name for meting in dt (default "meting").
apply_global_filters_pure <- function(dt, school_val, meting_val,
                                      school_col = "school",
                                      meting_col = "meting") {
  if (is.null(dt) || nrow(dt) == 0) return(dt)
  if (!is.null(school_val) && school_val != "all") {
    dt <- dt[get(school_col) == school_val]
  }
  if (!is.null(meting_val) && meting_val != "all") {
    dt <- dt[get(meting_col) == meting_val]
  }
  dt
}

#' Resolve a metric selector string to a column name in a data.table.
#'
#' Pure version: mvpa_col is passed explicitly (not read reactively).
#' server.R provides a local wrapper metric_col() that injects mvpa_col_name().
#'
#' @param metric   Selector string: "mvpa", "sb", "lpa", "bouts30", or "sleep".
#' @param dt       data.table to check column existence against.
#' @param mvpa_col Resolved MVPA column name (character or NULL).
metric_col_pure <- function(metric, dt, mvpa_col = NULL) {
  switch(metric,
    mvpa    = mvpa_col,
    sb      = if ("sb_min_day"       %in% names(dt)) "sb_min_day"       else NULL,
    lpa     = if ("lpa_min_day"      %in% names(dt)) "lpa_min_day"      else NULL,
    bouts30 = if ("bouts_30min_day"  %in% names(dt)) "bouts_30min_day"  else NULL,
    sleep   = if ("sleep_duration_h" %in% names(dt)) "sleep_duration_h" else NULL
  )
}

#' Dutch display label for a metric selector string.
metric_label <- function(metric) {
  switch(metric,
    mvpa    = "MVPA (min/dag)",
    sb      = "Sedentair (min/dag)",
    lpa     = "Licht actief (min/dag)",
    bouts30 = "SB bouts ≥30 min/dag",
    sleep   = "Slaap (h/nacht)",
    metric
  )
}

#' Verbal label for a rank-biserial effect size value.
rb_effect_label <- function(r) {
  abs_r <- abs(as.numeric(r))
  if (is.na(abs_r)) return("—")
  if (abs_r >= 0.5) paste0(r, " (groot)")
  else if (abs_r >= 0.1) paste0(r, " (middel)")
  else paste0(r, " (klein)")
}

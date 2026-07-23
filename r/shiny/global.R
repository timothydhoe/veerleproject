# global.R
# ─────────────────────────────────────────────────────────────────────────────
# Loaded once when the Shiny app starts (before ui.R and server.R).
# Reads config, loads all processed data, defines shared helpers.
# ─────────────────────────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Resolve a config-file path relative to r/ (global.R runs from r/shiny/, one
# level deeper) — unless the path is already absolute (Windows drive letter,
# UNC, or POSIX), in which case it's used as-is. config.yaml explicitly allows
# absolute paths for paths.data_raw / data_processed / etc.
resolve_cfg_path <- function(p) {
  if (grepl("^([A-Za-z]:[\\\\/]|\\\\\\\\|/)", p)) p else file.path("..", p)
}

library(shiny)
library(bslib)
library(DT)
library(ggplot2)
library(ggrepel)
library(plotly)
library(data.table)
library(yaml)

# ── Utilities (pure functions, no reactive context) ───────────────────────────
source("../utils/util_plots.R",   local = TRUE)
source("../utils/util_filters.R", local = TRUE)

# ── Config ────────────────────────────────────────────────────────────────────
source("../pipeline/validate_config.R", local = TRUE)

cfg <- read_config_yaml("../../config.yaml")

# Load the active configuration profile and merge it over the base config
# *before* validating — validation must check the values actually in effect,
# not the pre-merge base (otherwise an invalid active profile would ship to
# the dashboard completely unchecked). Profiles live in r/profiles/ and are
# managed via Tab 7 "Instellingen". Shared with the pipeline scripts via
# apply_active_profile() in validate_config.R, so the dashboard and real runs
# agree on effective values.
profiles_dir <- resolve_cfg_path(cfg$profiles$directory %||% "profiles/")
cfg <- apply_active_profile(cfg, profiles_dir)

CONFIG_VALID <- tryCatch({
  validate_config(cfg)
  TRUE
}, error = function(e) {
  message("[config] Validation errors — dashboard may show incomplete data:\n", e$message)
  FALSE
})
base_out       <- resolve_cfg_path(cfg$paths$data_processed)
metingen       <- c("meting_1", "meting_2")
METINGEN_LABELS <- c(meting_1 = "Meting 1", meting_2 = "Meting 2")
schools        <- names(cfg$schedules)
SCHOOL_LABELS  <- setNames(paste("School", seq_along(schools)), schools)

# Validity threshold (dev override when in example mode)
MIN_WEAR_H <- if (isTRUE(cfg$dev$example_mode) && !is.null(cfg$dev$includedaycrit)) {
  cfg$dev$includedaycrit
} else {
  cfg$validity$min_wear_hours_per_day
}
MIN_DAYS   <- cfg$validity$min_valid_days
NEED_WKND  <- isTRUE(cfg$validity$require_weekend_day)

# Fallback schools
FALLBACK_SCHOOLS <- names(Filter(function(s) isTRUE(s$fallback), cfg$schedules))

# ── Helpers ───────────────────────────────────────────────────────────────────
source("../pipeline/utils_ggir.R", local = TRUE)
# extract_school_id() is defined in ../utils/util_filters.R (sourced above)

# Wrapper that calls load_ggir_file() with the school ID extractor injected.
load_ggir <- function(meting, filename = NULL, pattern = NULL) {
  load_ggir_file(
    meting_output_dir    = file.path(base_out, meting),
    meting               = meting,
    filename             = filename,
    pattern              = pattern,
    extract_school_id_fn = extract_school_id
  )
}

# ── Load processed data ───────────────────────────────────────────────────────
# analysis_ready + validity (output of 03_build_summaries.R)
analysis_ready <- tryCatch(
  fread(file.path(base_out, "summaries", "analysis_ready.csv"),   data.table = TRUE, encoding = "UTF-8"),
  error = function(e) { message("analysis_ready.csv not found — run pipeline first"); NULL }
)
validity_summary <- tryCatch(
  fread(file.path(base_out, "summaries", "validity_summary.csv"), data.table = TRUE, encoding = "UTF-8"),
  error = function(e) NULL
)

# part2 day summaries (for heatmap and day-level views)
part2_list <- lapply(metingen, load_ggir, filename = "part2_daysummary.csv")
part2      <- rbindlist(Filter(Negate(is.null), part2_list), fill = TRUE)
if (nrow(part2) > 0) {
  if ("N valid hours" %in% names(part2)) setnames(part2, "N valid hours", "n_valid_hours")
  if ("N hours"       %in% names(part2)) setnames(part2, "N hours",       "n_hours")
  if (!"weekday" %in% names(part2) && "calendar_date" %in% names(part2)) {
    # Force English day names so Saturday/Sunday filters work on Dutch-locale machines.
    old_lc <- Sys.getlocale("LC_TIME")
    Sys.setlocale("LC_TIME", "C")
    part2[, weekday := weekdays(as.Date(calendar_date))]
    Sys.setlocale("LC_TIME", old_lc)
  }
  part2[, valid_day := !is.na(n_valid_hours) & n_valid_hours >= MIN_WEAR_H]
  part2[, school_label := SCHOOL_LABELS[school]]
}

# part4 night summaries (sleep) — uses version-tolerant reader
part4_list <- lapply(metingen, function(m) {
  results_dir <- find_ggir_results_dir(file.path(base_out, m))
  if (is.null(results_dir)) return(NULL)
  df <- read_part4_sleep(results_dir)
  if (is.null(df)) return(NULL)
  dt <- data.table::as.data.table(df)
  dt[, meting := m]
  if ("ID" %in% names(dt)) dt[, school := extract_school_id(ID)]
  dt
})
part4 <- rbindlist(Filter(Negate(is.null), part4_list), fill = TRUE)

# segment summary (output of 02_label_segments.R)
seg_path <- file.path(base_out, "summaries", "segment_summary.csv")
if (file.exists(seg_path)) {
  segment_summary <- fread(seg_path, data.table = TRUE, encoding = "UTF-8")
  segment_summary[, school_label := SCHOOL_LABELS[school]]
  SEGMENT_LEVELS <- c("before_school", "in_class", "recess", "lunch", "after_school")
  SEGMENT_LABELS <- c("Voor school", "Les", "Speeltijd", "Middagpauze", "Na school")
  segment_summary[, segment_label := factor(
    segment,
    levels = c(SEGMENT_LEVELS, "absent", "weekend", "outside_school"),
    labels = c(SEGMENT_LABELS, "Afwezig", "Weekend", "Buiten school")
  )]
} else {
  segment_summary <- NULL
  message("segment_summary.csv not found — School Day tab will be empty.")
}

# ── WHO references ────────────────────────────────────────────────────────────
WHO_MVPA_MIN   <- 60   # WHO recommendation: ≥60 min/day MVPA for children (5–17 yr)
WHO_SLEEP_MIN_H <- 8   # WHO/AAP minimum sleep: ≥8h/night for children 6–12 yr

# ZONE_COLORS and theme_schoolmove() live in ../utils/util_plots.R (sourced above)

# Atlassian categorical palette — 6 distinct, accessible schools (config-derived)
SCHOOL_COLORS <- setNames(
  c("#2684FF", "#00B8D9", "#36B37E", "#FF991F", "#6554C0", "#FF5630")[seq_along(schools)],
  SCHOOL_LABELS
)

# ── UI helper functions (needed by modules; defined before module sources) ─────
# BUG FIX (UX review): these helpers are also defined in ui.R (original location).
# They must be available here so module UI functions can call them at definition time.
# See UX_REVIEW.md → U0 for the full writeup.

chart_card <- function(header, plot_id, dl_id = NULL, height = "460px",
                       subtitle = NULL, full_screen = TRUE, plotly = FALSE) {
  footer <- if (!is.null(dl_id)) {
    card_footer(
      class = "d-flex justify-content-end py-1",
      downloadButton(dl_id, "PNG opslaan",
                     icon  = icon("download"),
                     class = "btn-outline-secondary btn-sm")
    )
  }
  plot_widget <- if (plotly) plotlyOutput(plot_id, height = height) else plotOutput(plot_id, height = height)
  card(
    class       = "shadow-sm",
    full_screen = full_screen,
    card_header(header),
    card_body(
      class = "p-3",
      if (!is.null(subtitle)) p(class = "text-muted small mb-2", subtitle),
      plot_widget
    ),
    footer
  )
}

tip <- function(label, text) {
  tagList(
    label,
    tooltip(
      span(icon("circle-info"), style = "color:#94a3b8; margin-left:4px; font-size:0.8em;"),
      text
    )
  )
}

kpi_strip_card <- function(icon_nm, title_ui, value_id) {
  div(
    class = "card kpi-strip",
    div(
      class = "card-body",
      div(class = "kpi-strip-icon", icon(icon_nm)),
      div(
        class = "kpi-strip-text",
        div(class = "kpi-strip-title", title_ui),
        div(class = "kpi-strip-value", textOutput(value_id))
      )
    )
  )
}

fallback_banner <- function() {
  if (length(FALLBACK_SCHOOLS) == 0) return(NULL)
  school_names <- paste(SCHOOL_LABELS[FALLBACK_SCHOOLS], collapse = ", ")
  div(
    class = "readiness-strip",
    style = "background:#fff3cd; border-bottom-color:#ffc107;",
    tags$span(class = "check-warn",
      icon("triangle-exclamation"),
      paste0(" Geschat rooster: ", school_names,
             " — segmentresultaten zijn benaderingen.")
    )
  )
}

# ── Module UI/server definitions ──────────────────────────────────────────────
# BUG FIX (UX review): modules were only sourced in server.R with local = TRUE,
# making their UI functions invisible to ui.R (which runs before server.R).
# Sourced here (global env) so both ui.R and server.R can find them.
# See UX_REVIEW.md → U0 for the full writeup.
source("modules/mod_overview.R",      local = FALSE)
source("modules/mod_participants.R",  local = FALSE)
source("modules/mod_schoolday.R",     local = FALSE)
source("modules/mod_sleep.R",         local = FALSE)
source("modules/mod_comparison.R",    local = FALSE)
source("modules/mod_export.R",        local = FALSE)
source("modules/mod_settings.R",      local = FALSE)

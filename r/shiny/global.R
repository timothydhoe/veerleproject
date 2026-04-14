# global.R
# ─────────────────────────────────────────────────────────────────────────────
# Loaded once when the Shiny app starts (before ui.R and server.R).
# Reads config, loads all processed data, defines shared helpers.
# ─────────────────────────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (!is.null(a)) a else b

library(shiny)
library(bslib)
library(DT)
library(ggplot2)
library(ggrepel)
library(plotly)
library(data.table)
library(yaml)

# ── Config ────────────────────────────────────────────────────────────────────
source("../pipeline/validate_config.R", local = TRUE)

cfg <- yaml::read_yaml("../../config.yaml")

CONFIG_VALID <- tryCatch({
  validate_config(cfg)
  TRUE
}, error = function(e) {
  message("[config] Validation errors — dashboard may show incomplete data:\n", e$message)
  FALSE
})

# Load the active configuration profile and merge it over the base config.
# Profiles live in r/profiles/ and are managed via Tab 7 "Instellingen".
active_profile_name <- cfg$profiles$active %||% "default"
profiles_dir        <- file.path("..", cfg$profiles$directory %||% "profiles/")
profile_path        <- file.path(profiles_dir, paste0(active_profile_name, ".yaml"))

if (file.exists(profile_path)) {
  profile <- yaml::read_yaml(profile_path)
  # Merge profile sections over base config (profile values take precedence)
  for (section in c("validity", "bouts")) {
    if (!is.null(profile[[section]])) {
      cfg[[section]] <- modifyList(
        cfg[[section]] %||% list(),
        profile[[section]]
      )
    }
  }
  if (!is.null(profile$ggir$cut_points_mg)) {
    cfg$ggir$cut_points_mg <- modifyList(
      cfg$ggir$cut_points_mg %||% list(),
      profile$ggir$cut_points_mg
    )
  }
  message("[profile] Loaded: '", active_profile_name, "' from ", profile_path)
} else {
  message("[profile] Profile not found: '", profile_path, "' — using base config.yaml values.")
}
base_out       <- file.path("..", cfg$paths$data_processed)
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

extract_school_id <- function(id) {
  code <- suppressWarnings(as.integer(sub("\\.csv$", "", basename(as.character(id)))))
  paste0("school_", code %/% 1000L)
}

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
  fread(file.path(base_out, "..", "analysis_ready.csv"),   data.table = TRUE),
  error = function(e) { message("analysis_ready.csv not found — run pipeline first"); NULL }
)
validity_summary <- tryCatch(
  fread(file.path(base_out, "..", "validity_summary.csv"), data.table = TRUE),
  error = function(e) NULL
)

# part2 day summaries (for heatmap and day-level views)
part2_list <- lapply(metingen, load_ggir, filename = "part2_daysummary.csv")
part2      <- rbindlist(Filter(Negate(is.null), part2_list), fill = TRUE)
if (nrow(part2) > 0) {
  if ("N valid hours" %in% names(part2)) setnames(part2, "N valid hours", "n_valid_hours")
  if ("N hours"       %in% names(part2)) setnames(part2, "N hours",       "n_hours")
  if (!"weekday" %in% names(part2) && "calendar_date" %in% names(part2)) {
    part2[, weekday := weekdays(as.Date(calendar_date))]
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
seg_path <- file.path(base_out, "..", "segment_summary.csv")
if (file.exists(seg_path)) {
  segment_summary <- fread(seg_path, data.table = TRUE)
  segment_summary[, school_label := SCHOOL_LABELS[school]]
  SEGMENT_LEVELS <- c("before_school", "in_class", "recess", "lunch", "after_school")
  SEGMENT_LABELS <- c("Voor school", "Les", "Speeltijd", "Middagpauze", "Na school")
  segment_summary[, segment_label := factor(
    segment,
    levels = SEGMENT_LEVELS,
    labels = SEGMENT_LABELS
  )]
} else {
  segment_summary <- NULL
  message("segment_summary.csv not found — School Day tab will be empty.")
}

# ── WHO references ────────────────────────────────────────────────────────────
WHO_MVPA_MIN   <- 60   # WHO recommendation: ≥60 min/day MVPA for children (5–17 yr)
WHO_SLEEP_MIN_H <- 8   # WHO/AAP minimum sleep: ≥8h/night for children 6–12 yr

# ── Activity intensity zone colours ───────────────────────────────────────────
# Atlassian-inspired: SB de-emphasised (grey), LPA cyan, MVPA bold blue (hero)
ZONE_COLORS <- c(
  SB   = "#DFE1E6",   # neutral grey  — sedentary / inactivity (de-emphasised)
  LPA  = "#79E2F2",   # light cyan    — light physical activity
  MVPA = "#0052CC"    # bold blue     — moderate-to-vigorous (hero metric)
)

# ── Shared plot theme (Atlassian neutrals) ────────────────────────────────────
theme_schoolmove <- function(legend_pos = "bottom") {
  theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(face = "bold", size = 13, colour = "#172B4D",
                                      margin = margin(b = 2)),
      plot.subtitle    = element_text(colour = "#6B778C", size = 10.5,
                                      margin = margin(b = 8)),
      plot.background  = element_rect(fill = "white", colour = NA),
      plot.margin      = margin(10, 14, 10, 14),
      panel.grid.major = element_line(colour = "#F4F5F7", linewidth = 0.8),
      panel.grid.minor = element_blank(),
      axis.title       = element_text(size = 10, colour = "#6B778C"),
      axis.text        = element_text(colour = "#5E6C84", size = 9.5),
      axis.ticks       = element_blank(),
      legend.position  = legend_pos,
      legend.title     = element_blank(),
      legend.text      = element_text(size = 10, colour = "#5E6C84"),
      strip.text       = element_text(face = "bold", size = 10.5, colour = "#172B4D"),
      strip.background = element_rect(fill = "#F4F5F7", colour = NA)
    )
}

# Atlassian categorical palette — 6 distinct, accessible schools
SCHOOL_COLORS <- setNames(
  c("#2684FF", "#00B8D9", "#36B37E", "#FF991F", "#6554C0", "#FF5630")[seq_along(schools)],
  SCHOOL_LABELS
)

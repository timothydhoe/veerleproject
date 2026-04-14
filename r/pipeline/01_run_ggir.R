# 01_run_ggir.R
# ─────────────────────────────────────────────────────────────────────────────
# GGIR pipeline — Parts 1–5.
#
# Reads all parameters from config.yaml. Processes meting_1 and meting_2
# independently. Output lands in:
#   data/processed/ggir/meting_1/
#   data/processed/ggir/meting_2/
#
# Set dev.example_mode: true in config.yaml to run on dummy data.
# Run from r/ directory (open SchoolMove.Rproj in RStudio first).
# ─────────────────────────────────────────────────────────────────────────────

library(GGIR)
library(yaml)

Sys.setlocale("LC_TIME", "C")  # force English weekday names regardless of OS locale

cfg <- yaml::read_yaml("../config.yaml")
cp  <- cfg$ggir$cut_points_mg
dev <- cfg$dev

`%||%` <- function(a, b) if (!is.null(a)) a else b

max_cores <- cfg$ggir$maxNcores %||% 1L

# ── qwindow: auto or manual ────────────────────────────────────────────────────
# Helper: gather all unique bell-time boundaries from config$schedules
source("pipeline/utils_ggir.R", local = TRUE)

build_qwindow_from_schedules <- function(schedules_cfg) {
  all_times <- c()
  for (sch in schedules_cfg) {
    # School start (same across days)
    all_times <- c(all_times, sch$school_start)
    # School end variants (mon_tue_thu_fri, wednesday, tuesday, etc.)
    for (end_val in unlist(sch$school_end)) {
      all_times <- c(all_times, end_val)
    }
    # All break boundaries
    for (day_breaks in sch$breaks) {
      for (brk in day_breaks) {
        if (!is.null(brk$start)) all_times <- c(all_times, brk$start)
        if (!is.null(brk$end))   all_times <- c(all_times, brk$end)
      }
    }
  }

  decimal_h <- sapply(unique(all_times), hm_to_h)
  qw <- sort(unique(c(0, decimal_h, 24)))
  message("Auto qwindow (", length(qw), " boundaries): ",
          paste(round(qw, 4), collapse = ", "))
  qw
}

qwindow_strategy <- cfg$ggir$qwindow_strategy %||% "manual"
if (qwindow_strategy == "auto") {
  qwindow_val <- build_qwindow_from_schedules(cfg$schedules)
  message("Using AUTO qwindow derived from school schedules.")
} else {
  qwindow_val <- cfg$ggir$qwindow
  message("Using MANUAL qwindow from config.")
}

# ── Data source ───────────────────────────────────────────────────────────────
if (isTRUE(dev$example_mode)) {
  base_dir <- file.path(cfg$paths$data_example, "dummy_data")
  message("Running in EXAMPLE MODE — using dummy data from: ", base_dir)
} else {
  base_dir <- cfg$paths$data_raw
  message("Running on REAL DATA from: ", base_dir)
}

# ── Dev overrides (only active with dummy data) ───────────────────────────────
nonwear_approach     <- dev$nonwear_approach     %||% "2023"
includedaycrit       <- dev$includedaycrit       %||% cfg$validity$min_wear_hours_per_day
includedaycrit_part5 <- dev$includedaycrit_part5 %||% (2 / 3)

if (isTRUE(dev$example_mode) && (!is.null(dev$nonwear_approach) || !is.null(dev$includedaycrit))) {
  message("Dev overrides active: nonwear_approach=", nonwear_approach,
          " | includedaycrit=", includedaycrit,
          " | includedaycrit.part5=", round(includedaycrit_part5, 2))
}

# ── Run GGIR for each meting ──────────────────────────────────────────────────
for (meting in c("meting_1", "meting_2")) {

  data_dir   <- file.path(base_dir, meting)
  output_dir <- file.path(cfg$paths$data_processed, meting)

  if (!dir.exists(data_dir)) {
    message("Skipping ", meting, " — directory not found: ", data_dir)
    next
  }

  n_files <- length(list.files(data_dir, pattern = "\\.csv$", ignore.case = TRUE))
  if (n_files == 0) {
    message("Skipping ", meting, " — no CSV files found in: ", data_dir)
    next
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  message("\n── GGIR: ", meting, " (", n_files, " files) ─────────────────────────")
  message("   input:  ", data_dir)
  message("   output: ", output_dir)

  GGIR(
    # ── Scope ─────────────────────────────────────────────────────────────────
    mode      = 1:5,           # Parts 1–5 (Part 6 is out of scope for this study)
    datadir   = data_dir,
    outputdir = output_dir,
    overwrite = isTRUE(cfg$ggir$overwrite),

    # ── Part 1: CSV reading ────────────────────────────────────────────────────
    # GENEActiv native CSV reading was deprecated in GGIR 2.6-4. We use
    # read.myacc.csv with explicit column mappings for the GENEActiv CSV format.
    # do.cal = FALSE: autocalibration requires raw .bin files.
    do.cal            = FALSE,
    epochvalues2csv   = TRUE,
    rmc.firstrow.acc  = 101,                    # 100-row metadata header
    rmc.col.acc       = 2:4,                    # x, y, z columns
    rmc.col.time      = 1,                      # timestamp column
    rmc.col.temp      = 7,                      # temperature column
    rmc.unit.acc      = "g",
    rmc.unit.time     = "POSIX",
    rmc.format.time   = "%Y-%m-%d %H:%M:%OS",  # e.g. "2026-02-22 17:00:00:000"
    rmc.unit.temp     = "C",
    rmc.sf            = 1,                      # 1 Hz: CSV stores 1-second epoch means

    # ── Parts 3–4: Sleep detection ─────────────────────────────────────────────
    # HDCZA is the wrist-validated algorithm for children (van Hees 2015).
    # anglethreshold/timethreshold come from Veerle's protocol.
    HASPT.algo     = "HDCZA",
    anglethreshold = 5,   # arm angle change < 5 degrees = sustained stillness
    timethreshold  = 5,   # must hold ≥ 5 min to count as sleep candidate

    # ── Part 5: Activity cut-points ────────────────────────────────────────────
    # Hildebrand et al. 2014/2017, wrist-worn GENEActiv, children.
    threshold.lig = cp$sedentary_to_light,    #  56.3 mg
    threshold.mod = cp$light_to_moderate,     # 191.6 mg
    threshold.vig = cp$moderate_to_vigorous,  # 695.8 mg

    # Sedentary bout lengths to extract separately (minutes).
    boutdur.in = c(10, 20, 30),

    # ── Part 2: Time-of-day segment windows ───────────────────────────────────
    # GGIR splits each day into these windows and produces separate activity
    # columns per window in part2_daysummary (e.g. dur_day_total_IN_min_8.5.10).
    # 02_label_segments.R maps these windows onto school-specific context labels.
    qwindow = qwindow_val,

    # ── Non-wear & validity ────────────────────────────────────────────────────
    nonwear_approach     = nonwear_approach,
    includedaycrit       = includedaycrit,
    includedaycrit.part5 = includedaycrit_part5,

    # ── General ───────────────────────────────────────────────────────────────
    idloc      = 2,                        # ID = full filename (4-digit pupil code)
    desiredtz  = cfg$output$timezone,      # "Europe/Brussels"
    do.report  = c(2, 5),
    do.parallel = max_cores > 1,
    maxNcores   = max_cores
  )

  message("── Done: ", meting, " ───────────────────────────────────────────────\n")
}

message("Step 01 complete. Run qc/qc_01_ggir.R to verify outputs.")

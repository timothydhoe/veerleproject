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

source("pipeline/validate_config.R", local = TRUE)

cfg <- read_config_yaml("../config.yaml")
cfg <- apply_active_profile(cfg)
validate_config(cfg)
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
    # Class-level overrides (e.g. school_3's late-dismissal exceptions) — pool
    # any HH:MM-shaped value found anywhere under class_overrides, not just
    # school_end_override by name, so a future override type is picked up too.
    if (!is.null(sch$class_overrides)) {
      override_vals <- unlist(sch$class_overrides, use.names = FALSE)
      is_hm <- grepl("^\\d{1,2}:\\d{2}$", override_vals)
      all_times <- c(all_times, override_vals[is_hm])
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
  qwindow_val <- as.numeric(cfg$ggir$qwindow)
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
# Gated on example_mode so a value left in config.yaml from a dummy-data test
# session (e.g. nonwear_approach: "2013") can never silently affect a real run.
if (isTRUE(dev$example_mode)) {
  nonwear_approach     <- dev$nonwear_approach     %||% "2023"
  includedaycrit       <- dev$includedaycrit       %||%
    cfg$validity$min_wear_hours_per_day
  includedaycrit_part5 <- dev$includedaycrit_part5 %||% (2 / 3)

  if (!is.null(dev$nonwear_approach) || !is.null(dev$includedaycrit)) {
    message("Dev overrides active: nonwear_approach=", nonwear_approach,
            " | includedaycrit=", includedaycrit,
            " | includedaycrit.part5=", round(includedaycrit_part5, 2))
  }
} else {
  nonwear_approach     <- "2023"
  includedaycrit       <- cfg$validity$min_wear_hours_per_day
  includedaycrit_part5 <- 2 / 3
}

# ── Run GGIR for each meting ──────────────────────────────────────────────────
for (meting in c("meting_1", "meting_2")) {

  data_dir   <- file.path(base_dir, meting)
  output_dir <- file.path(cfg$paths$data_processed, meting)

  if (!dir.exists(data_dir)) {
    message("Skipping ", meting, " — directory not found: ", data_dir)
    next
  }

  n_files <- length(list.files(data_dir, pattern = "\\.(csv|bin|cwa)$", ignore.case = TRUE))
  if (n_files == 0) {
    message("Skipping ", meting, " — no data files found in: ", data_dir)
    next
  }

  quick_n <- dev$quick_test_n
  if (!is.null(quick_n) && !is.na(quick_n)) {
    quick_n <- as.integer(quick_n)
    if (quick_n < n_files) {
      message("⚡ QUICK TEST MODE: processing first ", quick_n, " of ", n_files, " files.")
    }
  } else {
    quick_n <- NULL
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  message("\n── GGIR: ", meting, " (", if (!is.null(quick_n)) paste0(quick_n, "/") else "", n_files, " files) ─────────────────────────")
  message("   input:  ", data_dir)
  message("   output: ", output_dir)

  # ── Detect input format ───────────────────────────────────────────────────
  # .bin and .cwa files use GGIR's native reader (with autocalibration).
  # .csv files need rmc.* parameters for read.myacc.csv (no autocalibration).
  has_native <- length(list.files(data_dir, pattern = "\\.(bin|cwa)$", ignore.case = TRUE)) > 0

  # ── Shared GGIR arguments (all formats) ─────────────────────────────────
  shared_args <- list(
    mode      = 1:5,
    datadir   = data_dir,
    outputdir = output_dir,
    overwrite = isTRUE(cfg$ggir$overwrite),
    epochvalues2csv = TRUE,

    # Parts 3–4: Sleep detection (HDCZA, wrist-validated for children)
    HASPT.algo     = "HDCZA",
    anglethreshold = 5,
    timethreshold  = 5,

    # Part 5: Activity cut-points (Hildebrand et al. 2014/2017, wrist, children)
    threshold.lig = cp$sedentary_to_light,
    threshold.mod = cp$light_to_moderate,
    threshold.vig = cp$moderate_to_vigorous,
    boutdur.in    = c(10, 20, 30),

    # Part 2: Time-of-day segment windows
    qwindow = qwindow_val,

    # Non-wear & validity
    nonwear_approach     = nonwear_approach,
    includedaycrit       = includedaycrit,
    includedaycrit.part5 = includedaycrit_part5,

    # General
    idloc       = 2,
    desiredtz   = cfg$output$timezone,
    do.report   = c(2, 4, 5),
    do.parallel = max_cores > 1,
    maxNcores   = max_cores,

    # Quick-test: limit to first N files (f0 defaults to 1 in GGIR)
    f1          = if (!is.null(quick_n)) min(quick_n, n_files) else n_files
  )

  if (has_native) {
    # ── Native path (.bin / .cwa) ────────────────────────────────────────────
    # GGIR auto-detects format per file via GGIRread. Autocalibration enabled
    # because raw multi-Hz data supports sphere-fitting.
    message("   format: native (.bin/.cwa) — autocalibration ON")
    ggir_args <- c(shared_args, list(do.cal = TRUE))

    # ── Guard: clear a stale CSV-format config.csv before a native run ──────
    # GGIR persists rmc.* parameters to config.csv per output directory and
    # reuses them whenever overwrite: false. If an earlier run against this
    # output directory used CSV input, a leftover rmc.firstrow.acc value
    # makes GGIR route every file through its CSV reader regardless of
    # actual extension - hard crash on native .bin/.cwa input. Native is the
    # only supported format going forward, so any such leftover is
    # unambiguously stale.
    stale_configs <- list.files(output_dir, pattern = "^config\\.csv$",
                                recursive = TRUE, full.names = TRUE)
    for (stale_cfg in stale_configs) {
      old <- tryCatch(read.csv(stale_cfg, stringsAsFactors = FALSE),
                      error = function(e) NULL)
      if (is.null(old)) {
        warning("Could not read ", stale_cfg, " - leaving in place.")
      } else if (all(c("argument", "value") %in% names(old))) {
        rmc_val <- old$value[old$argument == "rmc.firstrow.acc"]
        if (length(rmc_val) > 0 && nzchar(trimws(rmc_val[1])) &&
              !identical(trimws(rmc_val[1]), "c()")) {
          message("   Clearing stale CSV-format config.csv (rmc.firstrow.acc=",
                  rmc_val[1], ") before native run: ", stale_cfg)
          removed <- file.remove(stale_cfg)
          if (!removed) {
            warning("Could not remove ", stale_cfg)
          }
        }
      }
    }
  } else {
    # ── CSV path (GENEActiv 100-row header) ──────────────────────────────────
    # Autocalibration disabled: CSV is pre-epoched at 1 Hz.
    message("   format: GENEActiv CSV — using rmc.* parameters, autocalibration OFF")
    csv_args <- list(
      do.cal           = FALSE,
      rmc.firstrow.acc = 101,
      rmc.col.acc      = 2:4,
      rmc.col.time     = 1,
      rmc.col.temp     = 7,
      rmc.unit.acc     = "g",
      rmc.unit.time    = "POSIX",
      rmc.format.time  = "%Y-%m-%d %H:%M:%OS",
      rmc.unit.temp    = "C",
      rmc.sf           = 1      # CSVs are pre-aggregated 1-second epochs, not raw 100 Hz samples
    )
    ggir_args <- c(shared_args, csv_args)
  }

  do.call(GGIR, ggir_args)

  message("── Done: ", meting, " ───────────────────────────────────────────────\n")
}

message("Step 01 complete. Run qc/qc_01_ggir.R to verify outputs.")

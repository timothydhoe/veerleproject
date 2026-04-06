# 01_run_ggir.R
# ─────────────────────────────────────────────────────────────────────────────
# Run the full GGIR pipeline (Parts 1–6) on all accelerometer CSV files.
#
# All parameters are read from config.yaml — do not hard-code values here.
# Run this script from the r/ directory (or open SchoolMove.Rproj in RStudio).
#
# Each meting is processed independently. Output lands in:
#   data/processed/ggir/meting_1/
#   data/processed/ggir/meting_2/
#
# Set dev.example_mode: true in config.yaml to run on dummy data instead of
# the real participant files.
# ─────────────────────────────────────────────────────────────────────────────

library(GGIR)
library(yaml)

# Load config ------------------------------------------------------------------
cfg <- yaml::read_yaml("../config.yaml")

cp  <- cfg$ggir$cut_points_mg
dev <- cfg$dev

base <- if (isTRUE(dev$example_mode)) {
  file.path(cfg$paths$data_example, "dummy_data")
} else {
  cfg$paths$data_raw
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

# GGIR parameters — use dev overrides when present, else production defaults
nonwear_approach     <- dev$nonwear_approach     %||% "2023"
includedaycrit       <- dev$includedaycrit       %||% 16
includedaycrit_part5 <- dev$includedaycrit_part5 %||% (2/3)

message("example_mode = ", isTRUE(dev$example_mode), " | data base: ", base)
if (!is.null(dev$nonwear_approach) || !is.null(dev$includedaycrit)) {
  message("  ⚠ Dev overrides active:",
          " nonwear_approach=", nonwear_approach,
          " | includedaycrit=", includedaycrit,
          " | includedaycrit.part5=", round(includedaycrit_part5, 2))
}

# Run GGIR for each meting -----------------------------------------------------
for (meting in c("meting_1", "meting_2")) {

  data_dir   <- file.path(base, meting)
  output_dir <- file.path(cfg$paths$data_processed, meting)

  if (!dir.exists(data_dir)) {
    message("Skipping ", meting, " — directory not found: ", data_dir)
    next
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  message("\n── Running GGIR: ", meting, " ──────────────────────────────────────")
  message("   input:  ", data_dir)
  message("   output: ", output_dir)

  GGIR(
    mode      = cfg$ggir$parts,
    datadir   = data_dir,
    outputdir = output_dir,
    overwrite = cfg$ggir$overwrite,

    # ── Part 1: CSV reading via read.myacc.csv ─────────────────────────────────
    # GENEActiv native CSV reading was deprecated in GGIR 2.6-4.
    # We use read.myacc.csv with explicit column mappings instead.
    # do.cal = FALSE: autocalibration requires raw .bin files; not applicable here.
    do.cal          = FALSE,
    epochvalues2csv = TRUE,

    # Column mapping for GENEActiv CSV format:
    #   col 1: timestamp | 2-4: x/y/z (g) | 5: light | 6: button |
    #   7: temp (°C) | 8: SVMgs | 9-11: sdx/y/z | 12: peak_lux
    rmc.firstrow.acc  = 101,                 # Data rows start after 100-line header
    rmc.col.acc       = 2:4,                 # x, y, z acceleration columns
    rmc.col.time      = 1,                   # Timestamp column
    rmc.col.temp      = 7,                   # Temperature column
    rmc.unit.acc      = "g",                 # Acceleration in g
    rmc.unit.time     = "POSIX",             # Timestamps are ISO strings
    rmc.format.time   = "%Y-%m-%d %H:%M:%OS", # e.g. "2026-02-22 17:00:00:000"
    rmc.unit.temp     = "C",
    rmc.sf            = 1,                   # 1 Hz — CSV stores 1-second epoch means

    # ── Part 5: Activity classification ───────────────────────────────────────
    # Wrist-worn GENEActiv cut-points (Hildebrand et al. 2014), confirmed in
    # Veerle's protocol. Units: mg (milli-g).
    threshold.lig = cp$sedentary_to_light,    #  56.3 mg — SB  | LPA
    threshold.mod = cp$light_to_moderate,     # 191.6 mg — LPA | MPA
    threshold.vig = cp$moderate_to_vigorous,  # 695.8 mg — MPA | VPA

    # ── Non-wear & validity ────────────────────────────────────────────────────
    # Production: 2023 non-wear algorithm; 16 h/day; 0.667 waking-window fraction.
    # Dev overrides (config.yaml dev.*) used when working with 1 Hz dummy data:
    #   nonwear_approach = "2013" — avoids internal 5 Hz resampling that kills 1 Hz signals
    #   includedaycrit = 5 — lower min valid hours per day
    #   includedaycrit.part5 = 0.3 — lower waking-window fraction for Part 5
    nonwear_approach     = nonwear_approach,
    includedaycrit       = includedaycrit,
    includedaycrit.part5 = includedaycrit_part5,

    # ── General ───────────────────────────────────────────────────────────────
    idloc     = 2,                  # Participant ID = full filename (4-digit code)
    desiredtz = cfg$output$timezone,
    do.report = c(2, 5)
  )

  message("── Done: ", meting, " ────────────────────────────────────────────────\n")
}

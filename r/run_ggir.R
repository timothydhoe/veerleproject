library(GGIR)

# Configuration ---------------------------------------------------------------
# TODO: replace placeholders with values confirmed by Veerle
DATA_DIR    <- file.path("..", "data", "raw")
OUTPUT_DIR  <- file.path("..", "data", "processed", "ggir")

# GGIR::GGIR() runs all requested parts in sequence.
# Parts 1+2 are always required; Part 5 produces the physical-activity summaries
# we need. Part 6 (population-level) is out of scope for this study.
GGIR(
  mode        = c(1, 2, 5),       # parts to run
  datadir     = DATA_DIR,
  outputdir   = OUTPUT_DIR,
  overwrite   = FALSE,

  # Part 1 – autocalibration + metric calculation
  do.cal      = TRUE,             # sphere-fit autocalibration
  epochvalues2csv = TRUE,

  # Part 2 – data quality / non-wear detection
  # (defaults are reasonable; revisit after seeing actual data)

  # Part 5 – activity classification
  # TODO: set threshold_lig, threshold_mod, threshold_vig once Veerle
  #       provides cut-point values (current blocker)
  # threshold_lig = ,
  # threshold_mod = ,
  # threshold_vig = ,

  idloc       = 2,                # subject ID from filename (4-digit code)
  do.report   = c(2, 5)
)

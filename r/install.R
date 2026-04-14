# install.R
# ─────────────────────────────────────────────────────────────────────────────
# Bootstrap script — run this ONCE to set up the R environment.
# After running, renv.lock pins all package versions for reproducibility.
# Colleagues can restore the exact same environment with: renv::restore()
# ─────────────────────────────────────────────────────────────────────────────

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}

renv::init(bare = TRUE)

renv::install(c(
  # Core pipeline
  "GGIR",
  "yaml",        # Read config.yaml
  "data.table",  # Fast tabular data manipulation

  # Shiny dashboard
  "shiny",
  "bslib",       # Modern Bootstrap-based Shiny themes
  "DT",          # Interactive tables in Shiny

  # Visualisation
  "ggplot2",
  "ggrepel",     # Non-overlapping text labels in ggplot2
  "plotly",      # Interactive charts
  "scales",
  "patchwork",   # Combine ggplot panels

  # Testing
  "testthat"     # Unit testing framework
))

renv::snapshot()

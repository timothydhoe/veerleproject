# Run this once to bootstrap the R environment.
# After running, renv.lock will pin all package versions for reproducibility.

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

renv::init(bare = TRUE)

renv::install(c(
  "GGIR",
  "data.table",
  "ggplot2"
))

renv::snapshot()

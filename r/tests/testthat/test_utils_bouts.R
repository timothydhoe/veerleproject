# test_utils_bouts.R
# Run with: testthat::test_file("tests/testthat/test_utils_bouts.R")

library(testthat)

source("../../pipeline/utils_bouts.R", local = TRUE)

# ── Helper: build minimal epoch data.frame ─────────────────────────────────────
make_epochs <- function(n_minutes, intensity, context = "in_class",
                        id = "P001", date = "2026-02-25", wear = TRUE) {
  n_epochs <- n_minutes * 60L
  data.frame(
    ID        = id,
    date      = date,
    context   = context,
    intensity = intensity,
    wear      = wear,
    stringsAsFactors = FALSE
  )[rep(1, n_epochs), ]
}

# ── detect_activity_bouts ──────────────────────────────────────────────────────

test_that("empty input returns empty data.frame with correct columns", {
  result <- detect_activity_bouts(data.frame(
    ID = character(), date = character(), context = character(),
    intensity = character(), wear = logical(), stringsAsFactors = FALSE
  ))
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true("n_bouts" %in% names(result))
  expect_true("total_bout_min" %in% names(result))
})

test_that("single 30-min sedentary run → 1 bout", {
  epochs <- make_epochs(30, "sedentary")
  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE)
  expect_equal(nrow(result), 1)
  expect_equal(result$n_bouts, 1)
  expect_equal(result$total_bout_min, 30)
})

test_that("run shorter than threshold → 0 bouts", {
  epochs <- make_epochs(29, "sedentary")
  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE)
  expect_equal(nrow(result), 0)
})

test_that("sedentary run that crosses context boundary → 2 separate bouts", {
  part1 <- make_epochs(30, "sedentary", context = "in_class")
  part2 <- make_epochs(30, "sedentary", context = "recess")
  epochs <- rbind(part1, part2)
  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE)
  expect_equal(nrow(result), 2)
  expect_equal(sort(result$context), c("in_class", "recess"))
})

test_that("non-wear epochs excluded when valid_only = TRUE", {
  wear    <- make_epochs(30, "sedentary", wear = TRUE)
  nonwear <- make_epochs(30, "sedentary", wear = FALSE)
  nonwear$date <- "2026-02-26"
  epochs  <- rbind(wear, nonwear)
  result  <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                   valid_only = TRUE)
  expect_equal(nrow(result), 1)
  expect_equal(result$date, "2026-02-25")
})

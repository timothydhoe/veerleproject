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

# ── epoch_length_s (feature_log.md #2 — real GGIR epoch export is 5s, not 1s) ──

test_that("5-second epochs: 30-min threshold uses real elapsed time, not row count", {
  # 30 minutes at 5s/epoch = 360 rows (NOT 1800, which is what the old
  # hardcoded `* 60L` assumed regardless of actual epoch length).
  n_epochs <- 30 * 60 / 5
  epochs <- data.frame(
    ID = "P001", date = "2026-02-25", context = "in_class",
    intensity = "sedentary", wear = TRUE, stringsAsFactors = FALSE
  )[rep(1, n_epochs), ]

  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE, epoch_length_s = 5)
  expect_equal(nrow(result), 1)
  expect_equal(result$total_bout_min, 30)
})

test_that("5-second epochs: a run just under the row-count-as-1s threshold still counts as a bout", {
  # 360 rows at 5s/epoch = 30 real minutes. Under the old (buggy) 1s
  # assumption this would have needed 1800 rows to register as a bout at
  # all — with the fix, 360 rows already clears the 30-min threshold.
  n_epochs <- 360
  epochs <- data.frame(
    ID = "P001", date = "2026-02-25", context = "in_class",
    intensity = "sedentary", wear = TRUE, stringsAsFactors = FALSE
  )[rep(1, n_epochs), ]

  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE, epoch_length_s = 5)
  expect_equal(nrow(result), 1)
})

test_that("epoch_length_s is read from an `epoch_length_s` column when the parameter is omitted", {
  n_epochs <- 360
  epochs <- data.frame(
    ID = "P001", date = "2026-02-25", context = "in_class",
    intensity = "sedentary", wear = TRUE, epoch_length_s = 5,
    stringsAsFactors = FALSE
  )[rep(1, n_epochs), ]

  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE)
  expect_equal(nrow(result), 1)
  expect_equal(result$total_bout_min, 30)
})

test_that("epoch_length_s defaults to 1 when neither parameter nor column is supplied (legacy behavior)", {
  epochs <- make_epochs(30, "sedentary")
  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE)
  expect_equal(result$total_bout_min, 30)
})

test_that("invalid epoch_length_s errors clearly", {
  epochs <- make_epochs(30, "sedentary")
  expect_error(
    detect_activity_bouts(epochs, epoch_length_s = 0),
    "epoch_length_s"
  )
  expect_error(
    detect_activity_bouts(epochs, epoch_length_s = -5),
    "epoch_length_s"
  )
})

# ── split_at_context_boundary ──────────────────────────────────────────────

test_that("split_at_context_boundary = FALSE merges a run across a context change", {
  part1 <- make_epochs(20, "sedentary", context = "in_class")
  part2 <- make_epochs(15, "sedentary", context = "recess")
  epochs <- rbind(part1, part2)
  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE, split_at_context_boundary = FALSE)
  expect_equal(nrow(result), 1)
  expect_equal(result$total_bout_min, 35)
  expect_equal(result$context, "in_class")  # labeled with the run's starting context
})

test_that("split_at_context_boundary = TRUE (default) still splits at the boundary", {
  part1 <- make_epochs(30, "sedentary", context = "in_class")
  part2 <- make_epochs(30, "sedentary", context = "recess")
  epochs <- rbind(part1, part2)
  result <- detect_activity_bouts(epochs, min_bout_min = 30, target_intensity = "sedentary",
                                  valid_only = FALSE)
  expect_equal(nrow(result), 2)
})

# ── compute_wear_waking_sedentary_pct ────────────────────────────────────────

test_that("computes sedentary % restricted to wear == TRUE & waking == TRUE epochs", {
  epochs <- data.frame(
    ID        = "P001",
    meting    = "meting_1",
    intensity = c("sedentary", "sedentary", "light", "sedentary", "moderate"),
    # 4th/5th rows must be excluded: non-wear and asleep respectively.
    wear      = c(TRUE, TRUE, TRUE, FALSE, TRUE),
    waking    = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    epoch_length_s = 5,
    stringsAsFactors = FALSE
  )
  result <- compute_wear_waking_sedentary_pct(epochs)
  expect_equal(nrow(result), 1)
  expect_equal(result$n_wear_waking_epochs, 3)      # rows 1-3 only
  expect_equal(result$sb_min_wear_waking, 2 * 5 / 60)  # 2 sedentary epochs
  expect_equal(result$wear_waking_min, 3 * 5 / 60)
  expect_equal(result$sb_pct_wear_waking, round(100 * (2 / 3), 2))
})

test_that("NA waking epochs are excluded from both numerator and denominator", {
  epochs <- data.frame(
    ID        = "P001",
    intensity = c("sedentary", "sedentary"),
    wear      = c(TRUE, TRUE),
    waking    = c(TRUE, NA),
    epoch_length_s = 5,
    stringsAsFactors = FALSE
  )
  result <- compute_wear_waking_sedentary_pct(epochs)
  expect_equal(result$n_wear_waking_epochs, 1)
  expect_equal(result$sb_pct_wear_waking, 100)
})

test_that("returns NULL when the epoch data has no `waking` column", {
  epochs <- data.frame(
    ID = "P001", intensity = "sedentary", wear = TRUE,
    stringsAsFactors = FALSE
  )
  expect_null(compute_wear_waking_sedentary_pct(epochs))
})

test_that("returns NULL when no epoch is both wear == TRUE and waking == TRUE", {
  epochs <- data.frame(
    ID = "P001", intensity = "sedentary", wear = c(TRUE, FALSE),
    waking = c(FALSE, TRUE), stringsAsFactors = FALSE
  )
  expect_null(compute_wear_waking_sedentary_pct(epochs))
})

test_that("groups by ID x meting when meting is present", {
  epochs <- data.frame(
    ID        = c("P001", "P001", "P002"),
    meting    = c("meting_1", "meting_2", "meting_1"),
    intensity = c("sedentary", "light", "sedentary"),
    wear      = TRUE,
    waking    = TRUE,
    epoch_length_s = 5,
    stringsAsFactors = FALSE
  )
  result <- compute_wear_waking_sedentary_pct(epochs)
  expect_equal(nrow(result), 3)
  expect_setequal(result$meting, c("meting_1", "meting_2", "meting_1"))
})

# test_schedule.R
# Tests for get_schedule() logic from 02_label_segments.R
# Run with: testthat::test_file("tests/testthat/test_schedule.R")

library(testthat)
library(data.table)

# ── Dependencies ───────────────────────────────────────────────────────────────
source("../../pipeline/utils_ggir.R", local = TRUE)  # provides hm_to_h

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Inline get_schedule — pure function, no file I/O side-effects
get_schedule <- function(school_id, wday_name, schedules) {
  sch <- schedules[[school_id]]
  if (is.null(sch)) return(NULL)

  school_start <- hm_to_h(sch$school_start)

  wday_lower <- tolower(wday_name)
  if (wday_lower == "wednesday") {
    school_end <- hm_to_h(sch$school_end$wednesday %||% sch$school_end$mon_tue_thu_fri)
    breaks_key <- "wednesday"
  } else {
    school_end <- hm_to_h(
      sch$school_end[[wday_lower]] %||%
      sch$school_end$mon_tue_thu_fri %||%
      sch$school_end$mon_thu_fri
    )
    breaks_key <- "mon_tue_thu_fri"
  }

  segments <- list()
  segments <- c(segments, list(data.frame(
    segment = "before_school", start_h = 0, end_h = school_start
  )))

  breaks <- sch$breaks[[breaks_key]]
  if (is.null(breaks) || length(breaks) == 0) breaks <- list()

  if (length(breaks) > 0) {
    break_starts <- sapply(breaks, function(b) hm_to_h(b$start))
    breaks <- breaks[order(break_starts)]
  }

  cursor <- school_start
  for (brk in breaks) {
    brk_start <- hm_to_h(brk$start)
    brk_end   <- hm_to_h(brk$end)
    if (brk_start > cursor && brk_start < school_end) {
      segments <- c(segments, list(data.frame(
        segment = "in_class", start_h = cursor, end_h = brk_start
      )))
    }
    seg_label <- if (!is.null(brk$label)) brk$label else "recess"
    segments <- c(segments, list(data.frame(
      segment = seg_label, start_h = brk_start, end_h = min(brk_end, school_end)
    )))
    cursor <- min(brk_end, school_end)
  }

  if (cursor < school_end) {
    segments <- c(segments, list(data.frame(
      segment = "in_class", start_h = cursor, end_h = school_end
    )))
  }

  segments <- c(segments, list(data.frame(
    segment = "after_school", start_h = school_end, end_h = 24
  )))

  data.table::rbindlist(lapply(segments, data.table::as.data.table))
}

# ── Minimal schedules fixture (school_1 from config.yaml) ─────────────────────
test_schedules <- list(
  school_1 = list(
    fallback     = FALSE,
    school_start = "08:25",
    school_end   = list(
      mon_thu_fri = "15:40",
      tuesday     = "16:30",
      wednesday   = "11:55"
    ),
    breaks = list(
      mon_tue_thu_fri = list(
        list(label = "recess", start = "10:05", end = "10:20"),
        list(label = "lunch",  start = "12:00", end = "13:00"),
        list(label = "recess", start = "14:40", end = "14:50")
      ),
      wednesday = list(
        list(label = "recess", start = "10:05", end = "10:15")
      )
    )
  )
)

# ── Tests ──────────────────────────────────────────────────────────────────────

test_that("Monday: schedule returns a data.frame with expected segments", {
  result <- as.data.frame(get_schedule("school_1", "Monday", test_schedules))
  expect_true("segment" %in% names(result))
  expect_true("before_school" %in% result$segment)
  expect_true("in_class"      %in% result$segment)
  expect_true("recess"        %in% result$segment)
  expect_true("lunch"         %in% result$segment)
  expect_true("after_school"  %in% result$segment)
})

test_that("Wednesday: school ends at 11:55", {
  result <- as.data.frame(get_schedule("school_1", "Wednesday", test_schedules))
  after  <- result[result$segment == "after_school", ]
  expect_equal(after$start_h, 11 + 55/60, tolerance = 1e-4)
})

test_that("Tuesday: school ends at 16:30", {
  result <- as.data.frame(get_schedule("school_1", "Tuesday", test_schedules))
  after  <- result[result$segment == "after_school", ]
  expect_equal(after$start_h, 16.5, tolerance = 1e-4)
})

test_that("Missing school → NULL (no crash)", {
  result <- get_schedule("school_99", "Monday", test_schedules)
  expect_null(result)
})

test_that("Segments cover full 24-hour day without gaps or overlaps", {
  result        <- as.data.frame(get_schedule("school_1", "Monday", test_schedules))
  result_sorted <- result[order(result$start_h), ]
  for (i in seq_len(nrow(result_sorted) - 1)) {
    expect_equal(result_sorted$end_h[i], result_sorted$start_h[i + 1],
                 tolerance = 1e-6,
                 label = paste("gap/overlap between row", i, "and", i + 1))
  }
  expect_equal(result_sorted$start_h[1], 0)
  expect_equal(result_sorted$end_h[nrow(result_sorted)], 24)
})

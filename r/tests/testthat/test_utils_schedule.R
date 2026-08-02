# test_utils_schedule.R
# Run with: testthat::test_file("tests/testthat/test_utils_schedule.R")

library(testthat)
library(data.table)

source("../../pipeline/utils_ggir.R",     local = TRUE)
source("../../pipeline/utils_schedule.R", local = TRUE)

make_cfg <- function() {
  list(
    schedules = list(
      school_1 = list(
        school_start = "08:30",
        school_end   = list(mon_tue_thu_fri = "15:30", wednesday = "12:00"),
        breaks = list(
          mon_tue_thu_fri = list(
            list(start = "10:00", end = "10:15", label = "recess"),
            list(start = "12:00", end = "13:00", label = "lunch")
          ),
          wednesday = list()
        )
      )
    )
  )
}

test_that("get_schedule builds contiguous segments covering the full day", {
  cfg <- make_cfg()
  sched <- get_schedule("school_1", "Monday", cfg$schedules)
  expect_equal(sched$start_h[1], 0)
  expect_equal(tail(sched$end_h, 1), 24)
  # contiguous: each segment's start == previous segment's end
  expect_equal(sched$start_h[-1], sched$end_h[-nrow(sched)])
  expect_true(all(c("before_school", "in_class", "recess", "lunch", "after_school") %in% sched$segment))
})

test_that("get_schedule returns NULL for an unconfigured school", {
  cfg <- make_cfg()
  expect_null(get_schedule("school_99", "Monday", cfg$schedules))
})

test_that("build_schedule_cache builds a cache entry for every school x weekday", {
  cfg <- make_cfg()
  cache <- build_schedule_cache(cfg)
  expect_true("school_1_Monday" %in% names(cache))
  expect_true("school_1_Wednesday" %in% names(cache))
  expect_equal(length(cache), 5)  # Mon-Fri, no class overrides in this fixture
})

test_that("build_pupil_override_map returns empty list when no class_overrides exist", {
  cfg <- make_cfg()
  expect_equal(build_pupil_override_map(cfg), list())
})

test_that("build_pupil_override_map + resolve_schedule_key route an overridden pupil to the class-variant cache entry", {
  cfg <- make_cfg()
  cfg$schedules$school_1$class_overrides <- list(
    "2Aa" = list(pupils = list("101"), school_end_override = list(monday = "16:25"))
  )
  pupil_override_map <- build_pupil_override_map(cfg)
  schedule_cache      <- build_schedule_cache(cfg)

  expect_true("school_1_2Aa_monday" %in% names(schedule_cache))

  key <- resolve_schedule_key("101", "school_1", "Monday", schedule_cache, pupil_override_map)
  expect_equal(key, "school_1_2Aa_monday")

  # A non-overridden pupil at the same school still gets the plain key
  key2 <- resolve_schedule_key("102", "school_1", "Monday", schedule_cache, pupil_override_map)
  expect_equal(key2, "school_1_Monday")
})

test_that("extract_school_id parses the school digit and handles bad input", {
  expect_equal(extract_school_id("2063"), "school_2")
  expect_equal(extract_school_id("2063.csv"), "school_2")
  expect_equal(extract_school_id("not-a-code"), "school_NA")
})

test_that("read_absence_keys returns character(0) when the file doesn't exist", {
  expect_equal(read_absence_keys(tempfile()), character(0))
})

test_that("read_absence_keys reads pupil_id/date pairs", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("pupil_id,date", "101,2026-02-25", "102,2026-02-26"), tmp)
  keys <- read_absence_keys(tmp)
  expect_equal(keys, c("101 2026-02-25", "102 2026-02-26"))
  unlink(tmp)
})

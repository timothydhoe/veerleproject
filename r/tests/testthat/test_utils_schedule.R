# test_utils_schedule.R
# Run with: testthat::test_file("tests/testthat/test_utils_schedule.R")
#
# Absence-rework coverage (docs/test/plan_absences_config.md §11): config
# parsing, ID-matching, and the whole-day drop are unit-tested below via
# apply_absence_drop() — the same function 02_label_segments.R calls. Two
# properties from §11 are architectural rather than unit-testable (03 and
# 02b/utils_epoch_labeling.R are procedural scripts, not pure functions) and
# were instead verified live against real pipeline output during build:
# (1) an absence entry leaves n_valid_days/mean_wear_h/has_weekend/sleep
# validity completely unchanged (03_build_summaries.R, build order step 4),
# and (2) n_absent_school_days lands on the correct meting (same step, same
# live run).

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

test_that("get_absence_entries/absence_keys return character(0) when afwezigheden is unset", {
  expect_equal(nrow(get_absence_entries(list())), 0)
  expect_equal(absence_keys(get_absence_entries(list())), character(0))
  expect_equal(absence_keys(get_absence_entries(list(afwezigheden = list()))), character(0))
})

test_that("get_absence_entries/absence_keys read pupil_id/date pairs from config", {
  cfg <- list(afwezigheden = list(
    list(pupil_id = "101", date = "2026-02-25"),
    list(pupil_id = "102", date = "2026-02-26")
  ))
  entries <- get_absence_entries(cfg)
  expect_equal(entries$pupil_id, c("101", "102"))
  expect_equal(entries$date, c("2026-02-25", "2026-02-26"))
  expect_equal(absence_keys(entries), c("101 2026-02-25", "102 2026-02-26"))
})

test_that("get_absence_entries skips entries missing pupil_id or date entirely, instead of erroring", {
  cfg <- list(afwezigheden = list(
    list(pupil_id = "2063"),                     # date key entirely absent
    list(date = "2026-02-25"),                    # pupil_id key entirely absent
    list(pupil_id = "2064", date = "2026-02-26")  # well-formed, kept
  ))
  entries <- get_absence_entries(cfg)
  expect_equal(entries$pupil_id, "2064")
  expect_equal(entries$date, "2026-02-26")
})

test_that("get_absence_entries skips entries with empty-string pupil_id or date", {
  cfg <- list(afwezigheden = list(
    list(pupil_id = "",     date = "2026-02-25"),
    list(pupil_id = "2064", date = ""),
    list(pupil_id = "2065", date = "2026-02-27")
  ))
  expect_equal(get_absence_entries(cfg)$pupil_id, "2065")
})

test_that("get_absence_entries returns zero rows when every entry is malformed", {
  cfg <- list(afwezigheden = list(list(pupil_id = "2063"), list(date = "2026-02-25")))
  expect_equal(nrow(get_absence_entries(cfg)), 0)
})

test_that("get_absence_entries strips a .cwa-style suffix from pupil_id", {
  cfg <- list(afwezigheden = list(list(pupil_id = "2063.cwa", date = "2026-03-01")))
  expect_equal(get_absence_entries(cfg)$pupil_id, "2063")
})

test_that("strip_pupil_id removes extension suffixes and directory paths", {
  expect_equal(strip_pupil_id("2063"), "2063")
  expect_equal(strip_pupil_id("2063.csv"), "2063")
  expect_equal(strip_pupil_id("2063.cwa"), "2063")
  expect_equal(strip_pupil_id("some/dir/2063.bin"), "2063")
})

make_segment_summary <- function() {
  data.table(
    ID      = c(rep("1901.csv", 5), rep("1902.csv", 5)),
    school  = "school_1",
    meting  = "meting_1",
    date    = "2026-02-22",  # both pupils recorded on the same date
    segment = c("before_school", "in_class", "recess", "lunch", "after_school",
                "before_school", "in_class", "recess", "lunch", "after_school")
  )
}

test_that("apply_absence_drop removes the whole day (all daytime segments), not just school hours", {
  seg <- make_segment_summary()
  abs_entries <- get_absence_entries(list(afwezigheden = list(
    list(pupil_id = "1901", date = "2026-02-22")
  )))

  result <- apply_absence_drop(seg, abs_entries)

  # All 5 segments (before_school, in_class, recess, lunch, after_school)
  # for pupil 1901 on the absent date are gone — not just school-hours ones.
  expect_equal(nrow(result$dt[ID == "1901.csv"]), 0)
  expect_equal(result$n_dropped, 5L)
  # The other pupil, same date, is untouched.
  expect_equal(nrow(result$dt[ID == "1902.csv"]), 5)
  expect_equal(result$unmatched_keys, character(0))
})

test_that("apply_absence_drop matches despite a GGIR extension suffix on the ID column", {
  seg <- data.table(ID = "1901.csv", school = "school_1", meting = "meting_1",
                    date = "2026-02-22", segment = "in_class")
  abs_entries <- get_absence_entries(list(afwezigheden = list(
    list(pupil_id = "1901", date = "2026-02-22")  # bare, config-style pupil_id
  )))
  result <- apply_absence_drop(seg, abs_entries)
  expect_equal(nrow(result$dt), 0)
  expect_equal(result$n_dropped, 1L)
})

test_that("apply_absence_drop reports unmatched entries as likely typos without erroring", {
  seg <- data.table(ID = "1901.csv", school = "school_1", meting = "meting_1",
                    date = "2026-02-22", segment = "in_class")
  abs_entries <- get_absence_entries(list(afwezigheden = list(
    list(pupil_id = "1901", date = "2026-02-22"),   # matches
    list(pupil_id = "9999", date = "2026-01-01")    # typo — no such pupil/date recorded
  )))
  result <- apply_absence_drop(seg, abs_entries)
  expect_equal(result$n_dropped, 1L)
  expect_equal(result$unmatched_keys, "9999 2026-01-01")
})

test_that("apply_absence_drop is a no-op when there are no absence entries", {
  seg <- make_segment_summary()
  result <- apply_absence_drop(seg, get_absence_entries(list()))
  expect_equal(nrow(result$dt), nrow(seg))
  expect_equal(result$n_dropped, 0L)
  expect_equal(result$unmatched_keys, character(0))
})

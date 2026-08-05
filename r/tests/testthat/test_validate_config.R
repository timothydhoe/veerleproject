# test_validate_config.R
# Run with: testthat::test_file("tests/testthat/test_validate_config.R")
#
# Deliberately sources ONLY pipeline/validate_config.R (not utils_schedule.R)
# to exercise its standalone strip_pupil_id() fallback guard — see that
# guard's comment in validate_config.R, and utils_schedule.R's %||% guard
# for the precedent this mirrors.

library(testthat)

source("../../pipeline/validate_config.R", local = TRUE)

test_that("strip_pupil_id fallback is defined when utils_schedule.R isn't sourced", {
  expect_true(exists("strip_pupil_id"))
  expect_equal(strip_pupil_id("2063.cwa"), "2063")
})

test_that("validate_config flags an extension-suffix duplicate in afwezigheden", {
  cfg <- list(afwezigheden = list(
    list(pupil_id = "2063",     date = "2026-02-25"),
    list(pupil_id = "2063.cwa", date = "2026-02-25")
  ))
  msgs <- capture_messages(tryCatch(validate_config(cfg), error = function(e) invisible(NULL)))
  expect_true(any(grepl("duplicate entry for pupil_id 2063.cwa on 2026-02-25", msgs, fixed = TRUE)))
})

test_that("validate_config does not flag genuinely different pupils as duplicates", {
  cfg <- list(afwezigheden = list(
    list(pupil_id = "2063", date = "2026-02-25"),
    list(pupil_id = "2064", date = "2026-02-25")
  ))
  msgs <- capture_messages(tryCatch(validate_config(cfg), error = function(e) invisible(NULL)))
  expect_false(any(grepl("duplicate entry", msgs)))
})

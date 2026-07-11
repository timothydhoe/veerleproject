# test_utils_ggir.R
# Run with: testthat::test_file("tests/testthat/test_utils_ggir.R")

library(testthat)

source("../../pipeline/utils_ggir.R", local = TRUE)

# ── hm_to_h ───────────────────────────────────────────────────────────────────

test_that("hm_to_h: 08:30 → 8.5", {
  expect_equal(hm_to_h("08:30"), 8.5)
})

test_that("hm_to_h: 00:00 → 0", {
  expect_equal(hm_to_h("00:00"), 0)
})

test_that("hm_to_h: 23:59 → correct decimal", {
  expect_equal(hm_to_h("23:59"), 23 + 59/60)
})

test_that("hm_to_h: 12:00 → 12", {
  expect_equal(hm_to_h("12:00"), 12)
})

# ── extract_school_id (canonical version, from util_filters.R) ─────────────────
source("../../utils/util_filters.R", local = TRUE)

test_that("extract_school_id: '2063' → 'school_2'", {
  expect_equal(extract_school_id("2063"), "school_2")
})

test_that("extract_school_id: '2063.csv' → 'school_2'", {
  expect_equal(extract_school_id("2063.csv"), "school_2")
})

test_that("extract_school_id: '1001' → 'school_1'", {
  expect_equal(extract_school_id("1001"), "school_1")
})

test_that("extract_school_id: non-numeric → 'school_NA' (not a crash)", {
  result <- extract_school_id("abc")
  expect_true(grepl("NA", result))
})

test_that("extract_school_id: strips non-.csv extensions (.bin, .cwa)", {
  # GGIR's own ID column is already cleaned to the leading numeric code
  # (e.g. "1001") before extract_school_id() ever sees it — it does not
  # receive the full raw device filename.
  expect_equal(extract_school_id("1001.bin"), "school_1")
  expect_equal(extract_school_id("2063.cwa"), "school_2")
})

test_that("extract_school_id: out-of-range code (e.g. raw device serial) → 'school_NA', not a wrong school", {
  result <- extract_school_id("73044")
  expect_true(grepl("NA", result))
})

test_that("extract_school_id: vectorized input (as used on a data.table column)", {
  result <- extract_school_id(c("1001", "2063.csv", "73044", "abc"))
  expect_equal(result, c("school_1", "school_2", "school_NA", "school_NA"))
})

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

# ── extract_school_id (inline version matching global.R logic) ─────────────────
extract_school_id_local <- function(id) {
  code <- suppressWarnings(as.integer(sub("\\.csv$", "", basename(as.character(id)))))
  paste0("school_", code %/% 1000L)
}

test_that("extract_school_id: '2063' → 'school_2'", {
  expect_equal(extract_school_id_local("2063"), "school_2")
})

test_that("extract_school_id: '2063.csv' → 'school_2'", {
  expect_equal(extract_school_id_local("2063.csv"), "school_2")
})

test_that("extract_school_id: '1001' → 'school_1'", {
  expect_equal(extract_school_id_local("1001"), "school_1")
})

test_that("extract_school_id: non-numeric → 'school_NA' (not a crash)", {
  result <- extract_school_id_local("abc")
  expect_true(grepl("NA", result))
})

# test_utils_epoch_labeling.R
# Run with: testthat::test_file("tests/testthat/test_utils_epoch_labeling.R")

library(testthat)
library(data.table)

source("../../pipeline/utils_ggir.R",           local = TRUE)
source("../../pipeline/utils_schedule.R",       local = TRUE)
source("../../pipeline/utils_epoch_labeling.R", local = TRUE)

# ── derive_epoch_length_s ──────────────────────────────────────────────────

test_that("derive_epoch_length_s reads the real (5s) gap from timestamps", {
  ts <- as.POSIXct("2026-02-25 08:00:00", tz = "UTC") + seq(0, by = 5, length.out = 100)
  expect_equal(derive_epoch_length_s(ts), 5)
})

test_that("derive_epoch_length_s is robust to a single missing/duplicated reading", {
  ts <- as.POSIXct("2026-02-25 08:00:00", tz = "UTC") + seq(0, by = 5, length.out = 100)
  ts[50] <- ts[49]  # duplicate timestamp -> a zero delta, should be filtered out
  expect_equal(derive_epoch_length_s(ts), 5)
})

test_that("derive_epoch_length_s falls back to 5s with a warning on too few timestamps", {
  expect_warning(result <- derive_epoch_length_s(as.POSIXct("2026-02-25 08:00:00", tz = "UTC")))
  expect_equal(result, 5)
})

test_that("derive_epoch_length_s falls back to 5s with a warning outside the sane range", {
  # A single huge gap (e.g. corrupted timestamps) should trigger the fallback,
  # not silently produce a nonsense epoch length.
  ts <- as.POSIXct(c("2026-02-25 08:00:00", "2027-02-25 08:00:00"), tz = "UTC")
  expect_warning(result <- derive_epoch_length_s(ts))
  expect_equal(result, 5)
})

# ── classify_intensity ──────────────────────────────────────────────────────

test_that("classify_intensity applies mg cut-points to g-unit ENMO correctly", {
  cp <- list(sedentary_to_light = 56.3, light_to_moderate = 191.6, moderate_to_vigorous = 695.8)
  # ENMO column is in g; cut-points are in mg -- 0.0054g = 5.4mg (sedentary),
  # 0.1455g = 145.5mg (light), 0.3g = 300mg (moderate), 0.8g = 800mg (vigorous).
  enmo_g <- c(0.0054, 0.1455, 0.3, 0.8)
  expect_equal(classify_intensity(enmo_g, cp),
              c("sedentary", "light", "moderate", "vigorous"))
})

test_that("classify_intensity boundary values fall on the lower (inclusive) side", {
  cp <- list(sedentary_to_light = 56.3, light_to_moderate = 191.6, moderate_to_vigorous = 695.8)
  # Exactly at a cut-point boundary (in mg, converted to g) should classify
  # into the HIGHER category (right = FALSE in cut(), matching Hildebrand's
  # own convention of half-open intervals [lower, upper)).
  enmo_g <- c(0.0563, 0.1916, 0.6958)
  expect_equal(classify_intensity(enmo_g, cp),
              c("light", "moderate", "vigorous"))
})

# ── build_labeled_epochs_for_participant ────────────────────────────────────

make_test_cfg <- function() {
  list(
    output = list(timezone = "Europe/Brussels"),
    ggir   = list(cut_points_mg = list(
      sedentary_to_light = 56.3, light_to_moderate = 191.6, moderate_to_vigorous = 695.8
    )),
    schedules = list(
      school_1 = list(
        school_start = "08:30",
        school_end   = list(mon_tue_thu_fri = "15:30", wednesday = "12:00"),
        breaks = list(
          mon_tue_thu_fri = list(list(start = "12:00", end = "13:00", label = "lunch")),
          wednesday = list()
        )
      )
    )
  )
}

write_epoch_csv <- function(path, n = 20, start = "2026-02-25T08:00:00+0100", enmo = 0.01) {
  ts <- format(as.POSIXct(start, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC") + seq(0, by = 5, length.out = n),
              "%Y-%m-%dT%H:%M:%S+0100")
  fwrite(data.table(timestamp = ts, anglez = 0, ENMO = enmo), path)
}

write_ms2out <- function(path, r5long) {
  IMP <- list(r5long = matrix(r5long, ncol = 1))
  save(IMP, file = path)
}

test_that("build_labeled_epochs_for_participant labels context, intensity, and wear correctly", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  # Monday 08:00-08:00+95s -- all "before_school" (school starts 08:30), sedentary ENMO
  write_epoch_csv(tmp_csv, n = 20, start = "2026-02-23T08:00:00+0100", enmo = 0.01)
  write_ms2out(tmp_rdata, r5long = rep(0, 20))  # all worn

  cfg <- make_test_cfg()
  schedule_cache      <- build_schedule_cache(cfg)
  pupil_override_map  <- build_pupil_override_map(cfg)

  result <- build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map
  )

  expect_equal(nrow(result), 20)
  expect_true(all(result$context == "before_school"))
  expect_true(all(result$intensity == "sedentary"))
  expect_true(all(result$wear == TRUE))
  expect_equal(result$epoch_length_s[1], 5)
})

test_that("r5long length mismatch degrades to wear = NA with a warning, not a crash", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  write_epoch_csv(tmp_csv, n = 20, start = "2026-02-23T08:00:00+0100")
  write_ms2out(tmp_rdata, r5long = rep(0, 10))  # WRONG length on purpose

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  expect_warning(
    result <- build_labeled_epochs_for_participant(
      epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
      id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
      schedule_cache = schedule_cache, pupil_override_map = pupil_override_map
    ),
    "does not match"
  )
  expect_equal(nrow(result), 20)
  expect_true(all(is.na(result$wear)))
})

test_that("missing ms2.out file degrades to wear = NA with a warning, not a crash", {
  tmp_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp_csv))
  write_epoch_csv(tmp_csv, n = 10, start = "2026-02-23T08:00:00+0100")

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  expect_warning(
    result <- build_labeled_epochs_for_participant(
      epoch_csv_path = tmp_csv, ms2out_path = tempfile(fileext = ".RData"),  # doesn't exist
      id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
      schedule_cache = schedule_cache, pupil_override_map = pupil_override_map
    ),
    "not found"
  )
  expect_true(all(is.na(result$wear)))
})

test_that("weekend epochs are labeled 'weekend' regardless of school schedule", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  # 2026-02-22 is a Sunday
  write_epoch_csv(tmp_csv, n = 10, start = "2026-02-22T10:00:00+0100")
  write_ms2out(tmp_rdata, r5long = rep(0, 10))

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  result <- build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map
  )
  expect_true(all(result$context == "weekend"))
})

test_that("timestamps spanning a DST transition are parsed without dropped/NA rows", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  # Europe/Brussels DST spring-forward: 2026-03-29 02:00 CET -> 03:00 CEST.
  # Straddle it with mixed +0100/+0200 offsets, as the real epoch CSV would have.
  ts <- c(
    paste0("2026-03-29T01:", sprintf("%02d", seq(50, 59, 5)), ":00+0100"),
    paste0("2026-03-29T03:", sprintf("%02d", seq(0, 9, 5)), ":00+0200")
  )
  fwrite(data.table(timestamp = ts, anglez = 0, ENMO = 0.01), tmp_csv)
  write_ms2out(tmp_rdata, r5long = rep(0, length(ts)))

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  result <- build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map
  )
  expect_equal(nrow(result), length(ts))
  expect_false(any(is.na(result$context)))
  expect_true(all(result$date == as.Date("2026-03-29")))
})

# ── waking flag (Part 4 sleep-period-time) ──────────────────────────────────

test_that("epochs during the night's SPT window are marked waking = FALSE", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  # Monday: epochs at 02:00 (asleep) and 06:00 (asleep, strictly before the
  # 07:00 wakeup) and 08:00 (awake, before_school) -- sleeponset 22.0 the
  # PREVIOUS night (Sunday, hence date - 1), wakeup 31.0 (= 07:00 Monday).
  # wakeup itself is the half-open boundary (hour < wake_h => asleep, same
  # convention as classify_intensity()'s right = FALSE cut-points), so the
  # exact wakeup minute is intentionally NOT used as a test point here.
  ts <- c("2026-02-23T02:00:00+0100", "2026-02-23T06:00:00+0100",
          "2026-02-23T08:00:00+0100")
  fwrite(data.table(timestamp = ts, anglez = 0, ENMO = 0.01), tmp_csv)
  write_ms2out(tmp_rdata, r5long = rep(0, length(ts)))

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  part4_nights <- data.table(
    calendar_date = as.Date("2026-02-22"),  # Sunday night
    sleeponset    = 22.0,                   # 22:00 Sunday
    wakeup        = 31.0                    # 07:00 Monday
  )

  result <- suppressWarnings(build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map,
    part4_nights = part4_nights
  ))
  expect_equal(result$waking, c(FALSE, FALSE, TRUE))
})

test_that("waking is NA (not TRUE) for a calendar date with no matching Part 4 night record", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  write_epoch_csv(tmp_csv, n = 5, start = "2026-02-23T08:00:00+0100")
  write_ms2out(tmp_rdata, r5long = rep(0, 5))

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  # part4_nights covers a completely different date -> no coverage for 2026-02-23
  part4_nights <- data.table(
    calendar_date = as.Date("2026-01-01"), sleeponset = 22.0, wakeup = 30.0
  )

  result <- build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map,
    part4_nights = part4_nights
  )
  expect_true(all(is.na(result$waking)))
})

test_that("waking defaults to NA for every epoch when part4_nights is NULL", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  write_epoch_csv(tmp_csv, n = 5, start = "2026-02-23T08:00:00+0100")
  write_ms2out(tmp_rdata, r5long = rep(0, 5))

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  result <- build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map
  )
  expect_true(all(is.na(result$waking)))
})

test_that("absence overlay marks in_class/recess/lunch as 'absent' but not before/after school", {
  tmp_csv <- tempfile(fileext = ".csv")
  tmp_rdata <- tempfile(fileext = ".RData")
  on.exit(unlink(c(tmp_csv, tmp_rdata)))

  # Spans before_school (08:00) through in_class (09:00) on a Monday.
  ts <- c("2026-02-23T08:00:00+0100", "2026-02-23T09:00:00+0100")
  fwrite(data.table(timestamp = ts, anglez = 0, ENMO = 0.01), tmp_csv)
  write_ms2out(tmp_rdata, r5long = rep(0, length(ts)))

  cfg <- make_test_cfg()
  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)

  result <- build_labeled_epochs_for_participant(
    epoch_csv_path = tmp_csv, ms2out_path = tmp_rdata,
    id = "1001", meting = "meting_1", school = "school_1", cfg = cfg,
    schedule_cache = schedule_cache, pupil_override_map = pupil_override_map,
    abs_keys = c("1001 2026-02-23")
  )
  expect_equal(result$context[result$context != "absent"], "before_school")
  expect_equal(sum(result$context == "absent"), 1)  # only the in_class epoch
})

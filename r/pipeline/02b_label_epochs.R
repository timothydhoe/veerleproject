# 02b_label_epochs.R
# ─────────────────────────────────────────────────────────────────────────────
# Builds data/processed/labeled_epochs.csv: one row per 5-second GGIR epoch,
# labeled with school context and wear/non-wear, for context-aware bout
# detection (utils_bouts.R). See docs/test/feature_log.md #2.
#
# Opt-in: only runs when config.yaml's bouts.enable_epoch_labeling is true
# (expensive at full study scale — ~96M rows for 400 participants). Requires
# 01_run_ggir.R to have been run WITH bouts.enable_epoch_labeling: true (that
# flag also controls whether GGIR's epochvalues2csv export is produced in the
# first place — see 01_run_ggir.R).
#
# Run from r/ directory. Requires 01_run_ggir.R to have completed first.
# ─────────────────────────────────────────────────────────────────────────────

library(yaml)
library(data.table)

Sys.setlocale("LC_TIME", "C")  # force English weekday names regardless of OS locale

source("pipeline/validate_config.R",      local = TRUE)
source("pipeline/utils_ggir.R",           local = TRUE)
source("pipeline/utils_schedule.R",       local = TRUE)
source("pipeline/utils_epoch_labeling.R", local = TRUE)

cfg      <- read_config_yaml("../config.yaml")
cfg      <- apply_active_profile(cfg)
validate_config(cfg)
base_out <- cfg$paths$data_processed
metingen <- c("meting_1", "meting_2")

if (!isTRUE(cfg$bouts$enable_epoch_labeling)) {
  message("bouts.enable_epoch_labeling is not true in config.yaml — skipping ",
          "02b_label_epochs.R (labeled_epochs.csv will not be built/updated).")
} else {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  schedule_cache     <- build_schedule_cache(cfg)
  pupil_override_map <- build_pupil_override_map(cfg)
  abs_keys           <- absence_keys(get_absence_entries(cfg))

  out_path <- file.path(base_out, "labeled_epochs.csv")
  tmp_path <- paste0(out_path, ".tmp")
  if (file.exists(tmp_path)) file.remove(tmp_path)  # stale leftover from a prior crashed run

  n_written     <- 0L
  n_skipped     <- 0L
  n_participants_total <- 0L
  row_i         <- 0L

  for (meting in metingen) {
    part2 <- load_ggir_file(
      meting_output_dir    = file.path(base_out, meting),
      meting               = meting,
      filename             = "part2_daysummary.csv",
      extract_school_id_fn = extract_school_id
    )
    if (is.null(part2) || nrow(part2) == 0) {
      message("Skipping ", meting, " — part2_daysummary.csv not found. Run pipeline/01_run_ggir.R first.")
      next
    }
    if ("N valid hours" %in% names(part2)) setnames(part2, "N valid hours", "n_valid_hours")

    date_col <- intersect(c("calendar_date", "Date", "date"), names(part2))
    date_col <- if (length(date_col) > 0) date_col[1] else NA_character_

    ggir_subdir <- find_ggir_output_subdir(file.path(base_out, meting))
    if (is.null(ggir_subdir)) {
      message("Skipping ", meting, " — no GGIR output_* subdirectory found.")
      next
    }

    participants <- unique(part2[, .(ID, filename, school)])
    n_participants_total <- n_participants_total + nrow(participants)
    message(sprintf("── %s: %d participant(s) ──────────────────────────", meting, nrow(participants)))

    for (p in seq_len(nrow(participants))) {
      id     <- participants$ID[p]
      fname  <- participants$filename[p]
      school <- participants$school[p]

      epoch_csv_path <- file.path(ggir_subdir, "meta", "csv",    paste0(fname, ".RData.csv"))
      ms2out_path    <- file.path(ggir_subdir, "meta", "ms2.out", paste0(fname, ".RData"))

      if (!file.exists(epoch_csv_path)) {
        message("  [", id, "] epoch CSV not found (", epoch_csv_path, ") — skipping. ",
                "If bouts.enable_epoch_labeling was only just turned on and this study's ",
                "GGIR output already existed with overwrite: false, GGIR's milestone ",
                "caching may have skipped re-running Part 1/2 and never produced this ",
                "export — rerun pipeline/01_run_ggir.R with ggir.overwrite: true once to fix.")
        n_skipped <- n_skipped + 1L
        next
      }

      part2_days <- if (!is.na(date_col)) {
        part2[ID == id, .(calendar_date = as.Date(get(date_col)), n_valid_hours)]
      } else {
        NULL
      }

      labeled <- tryCatch(
        build_labeled_epochs_for_participant(
          epoch_csv_path = epoch_csv_path, ms2out_path = ms2out_path,
          id = id, meting = meting, school = school, cfg = cfg,
          schedule_cache = schedule_cache, pupil_override_map = pupil_override_map,
          part2_days = part2_days, abs_keys = abs_keys
        ),
        error = function(e) {
          message("  [", id, "] Error building labeled epochs: ", e$message, " — skipping.")
          NULL
        }
      )

      if (is.null(labeled) || nrow(labeled) == 0) {
        n_skipped <- n_skipped + 1L
        next
      }

      row_i <- row_i + 1L
      fwrite(labeled, tmp_path, append = (row_i > 1L))
      n_written <- n_written + 1L
      message(sprintf("  [%s] %d epoch-rows written (%s)", id, nrow(labeled), meting))
    }
  }

  if (n_written == 0L) {
    message("\nNo participants produced labeled epoch data — labeled_epochs.csv NOT written ",
            "(", n_skipped, " of ", n_participants_total, " participant(s) skipped). ",
            "Existing labeled_epochs.csv (if any) is left untouched.")
    if (file.exists(tmp_path)) file.remove(tmp_path)
  } else {
    backup_if_exists(out_path)
    file.rename(tmp_path, out_path)
    message(sprintf(
      "\nlabeled_epochs.csv written: %s\n  %d participant(s) written, %d skipped (of %d total)",
      normalizePath(out_path), n_written, n_skipped, n_participants_total
    ))
  }

  message("\nStep 02b complete.")
}

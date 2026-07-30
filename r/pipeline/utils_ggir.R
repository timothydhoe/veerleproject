# utils_ggir.R
# ─────────────────────────────────────────────────────────────────────────────
# Version-tolerant GGIR output readers.
#
# Ported and adapted from project_1/R/pipeline/03_read_ggir_output.R.
#
# GGIR creates output like:
#   {outputdir}/output_{datadir_name}/results/
#     part2_daysummary.csv
#     part4_nightsummary_sleep_cleaned.csv  (or _full.csv, or part4_*.csv)
#     part5_daysummary_Segments_*.csv       (or part5_daysummary_WW_*.csv)
#     part5_personsummary_WW_*.csv
#   {outputdir}/output_{datadir_name}/config.csv
#
# These helpers are tolerant of filename variations across GGIR versions.
#
# Functions can be sourced from any working directory — they take absolute
# or relative paths as arguments.
# ─────────────────────────────────────────────────────────────────────────────

#' Convert "HH:MM" string to decimal hours
#'
#' @param hm Character string in "HH:MM" format.
#' @return Numeric scalar (e.g. "08:30" → 8.5).
hm_to_h <- function(hm) {
  parts <- as.integer(strsplit(hm, ":")[[1]])
  parts[1] + parts[2] / 60
}

#' Find the GGIR output subdirectory for a given meting
#'
#' GGIR creates a subdirectory named "output_<datadir_name>" inside the
#' outputdir that was passed to GGIR::GGIR(). This function locates it
#' without assuming the exact name.
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#'   E.g. "../data/processed/ggir/meting_1"
#' @return Path to the GGIR output subdirectory (the one that contains
#'   meta/ and results/), or NULL if not found.
find_ggir_output_subdir <- function(meting_output_dir) {
  if (!dir.exists(meting_output_dir)) return(NULL)

  subdirs <- list.dirs(meting_output_dir, full.names = TRUE, recursive = FALSE)
  ggir_subdirs <- subdirs[grepl("^output_", basename(subdirs))]

  if (length(ggir_subdirs) == 0) return(NULL)
  if (length(ggir_subdirs) == 1) return(ggir_subdirs[1])

  # More than one output_ subdir (e.g. a partial re-run under a renamed
  # datadir) — list.dirs()'s order isn't guaranteed stable or chronological
  # across filesystems, so picking ggir_subdirs[1] used to be a silent guess.
  # Sort by modification time instead (most recently written = most likely
  # the current, intended output) and warn loudly, since this is genuinely
  # unusual and every downstream reader (part4/part5 loaders,
  # resolve_ggir_qwindow()) is affected by which one gets picked.
  mtimes  <- file.info(ggir_subdirs)$mtime
  ordered <- ggir_subdirs[order(mtimes, decreasing = TRUE)]
  warning("[utils_ggir] Multiple output_ subdirs found in ", meting_output_dir, ":\n  ",
          paste(basename(ordered), collapse = "\n  "),
          "\nUsing the most recently modified: ", basename(ordered[1]),
          ". If this isn't the intended run, remove the stale output_* directory.",
          call. = FALSE)
  ordered[1]
}

#' Find the results/ directory for a given meting output directory
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @return Path to results/, or NULL if not found.
find_ggir_results_dir <- function(meting_output_dir) {
  subdir <- find_ggir_output_subdir(meting_output_dir)
  if (is.null(subdir)) return(NULL)
  results <- file.path(subdir, "results")
  if (!dir.exists(results)) return(NULL)
  results
}

#' Load a GGIR CSV with meting and school columns added
#'
#' Drop-in replacement for the ad-hoc load_ggir() helper in 03_build_summaries.R
#' and global.R. Adds version-tolerant directory discovery.
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @param meting Character meting label (e.g. "meting_1").
#' @param filename Exact filename (e.g. "part2_daysummary.csv"). One of
#'   filename or pattern must be supplied.
#' @param pattern Regex pattern matching the file (e.g. "^part5_personsummary_").
#' @param extract_school_id_fn Function(ID) → school label. Defaults to the
#'   standard extract_school_id() if available in the calling environment.
#' @return data.table with meting and school columns, or NULL if file not found.
load_ggir_file <- function(meting_output_dir, meting,
                            filename = NULL, pattern = NULL,
                            extract_school_id_fn = NULL) {
  results_dir <- find_ggir_results_dir(meting_output_dir)
  if (is.null(results_dir)) return(NULL)

  if (!is.null(pattern)) {
    files <- list.files(results_dir, pattern = pattern, full.names = TRUE)
    if (length(files) == 0) return(NULL)
    path <- pick_ggir_variant_file(files)
  } else if (!is.null(filename)) {
    path <- file.path(results_dir, filename)
  } else {
    stop("load_ggir_file: supply filename or pattern")
  }

  if (!file.exists(path)) return(NULL)

  dt <- data.table::fread(path, data.table = TRUE)
  dt[, meting := meting]

  # Callers must supply extract_school_id_fn explicitly — no env auto-lookup.
  if (!is.null(extract_school_id_fn) && "ID" %in% names(dt)) {
    dt[, school := extract_school_id_fn(ID)]
  }

  dt
}

#' Read GGIR Part 4 sleep summary with multi-level fallback
#'
#' Tries: cleaned → full → any part4 CSV. Checked in both results/ and
#' results/QC/ — GGIR writes the "cleaned" (valid-nights-only) report to
#' results/ when at least one night passes validity criteria, but falls back
#' to only writing the unfiltered "full" report under results/QC/ when it
#' doesn't (observed with GGIR 3.3.6 on a small test set).
#'
#' @param results_dir Path to the GGIR results/ directory.
#' @param prefer_full When TRUE, tries the unfiltered "full" report before
#'   "cleaned". Needed by add_waking_valid_hours(): computing how many hours
#'   a participant slept on a given calendar day requires every attempted
#'   night's sleeponset/wakeup, including nights GGIR's own per-night 50%-
#'   valid-data check excludes from "cleaned" — those nights still have real
#'   detected sleep timing, and silently treating them as "no sleep" would
#'   inflate that day's computed waking hours. The sleep *validity gate*
#'   (a separate criterion, "was this night's own data good enough to use")
#'   should keep using the default cleaned-first priority.
#' @return data.frame, or NULL if no Part 4 file found.
read_part4_sleep <- function(results_dir, prefer_full = FALSE) {
  filenames <- c(
    "part4_nightsummary_sleep_cleaned.csv",
    "part4_nightsummary_sleep_full.csv",
    "part4_nightsummary.csv"
  )
  if (isTRUE(prefer_full)) {
    filenames <- c(
      "part4_nightsummary_sleep_full.csv",
      "part4_nightsummary_sleep_cleaned.csv",
      "part4_nightsummary.csv"
    )
  }
  search_dirs <- c(results_dir, file.path(results_dir, "QC"))
  candidates  <- as.vector(outer(search_dirs, filenames, file.path))

  for (p in candidates) {
    if (file.exists(p)) {
      message("[utils_ggir] Part 4 sleep: ", basename(p),
              if (dirname(p) != results_dir) paste0(" (", basename(dirname(p)), "/)") else "")
      out <- read.csv(p, stringsAsFactors = FALSE)
      attr(out, "source_path") <- p
      return(out)
    }
  }

  # Last resort: any file matching part4*.csv, in results/ or results/QC/
  any_p4 <- unlist(lapply(search_dirs, list.files,
                          pattern = "^part4.*\\.csv$", full.names = TRUE))
  if (length(any_p4) > 0) {
    message("[utils_ggir] Part 4 sleep (fallback): ", basename(any_p4[1]))
    out <- read.csv(any_p4[1], stringsAsFactors = FALSE)
    attr(out, "source_path") <- any_p4[1]
    return(out)
  }

  message("[utils_ggir] No Part 4 sleep CSV found. Sleep data may be in Part 5.")
  NULL
}

#' Pick the preferred file when a pattern matches multiple GGIR report variants
#'
#' GGIR can emit several part5 report variants side by side in the same
#' results/ directory (WW = waking-window, MM = midnight-to-midnight,
#' Segments = qwindow-based) whenever more than one succeeds for a given run.
#' They are not interchangeable: each defines "a day" differently, and their
#' participant coverage can differ drastically — e.g. MM requires a full
#' clean midnight-to-midnight day and can silently cover only a fraction of
#' the participants that Segments or WW cover. Taking list.files()'s first
#' (alphabetical) match ignores all of this and can silently drop most
#' participants' activity data with no warning (confirmed live: a real test
#' run produced part5_personsummary_MM_*.csv covering 1 of 10 participants,
#' part5_personsummary_Segments_*.csv covering 7 of 10 — MM sorts first
#' alphabetically and was being picked unconditionally).
#'
#' Segments is preferred by default because this study's whole design is
#' built around qwindow/school-day segments (02_label_segments.R already
#' hard-requires the Segments daysummary file for the same reason).
#'
#' @param files Character vector of candidate file paths already filtered by
#'   a pattern (e.g. "^part5_personsummary_").
#' @param prefer Character vector of variant tokens in priority order.
#' @return The chosen file path, or NULL if `files` is empty.
pick_ggir_variant_file <- function(files, prefer = c("Segments", "WW", "MM")) {
  if (length(files) == 0) return(NULL)
  if (length(files) == 1) return(files[1])

  variants <- sub("^part5_(?:personsummary|daysummary)_([A-Za-z]+)_.*", "\\1",
                   basename(files), perl = TRUE)

  # Participant coverage per candidate — read once so a silent under-coverage
  # pick is caught even if the "preferred" variant happens to be present.
  n_ids <- vapply(files, function(f) {
    tryCatch({
      length(unique(data.table::fread(f, select = "ID")[["ID"]]))
    }, error = function(e) NA_integer_)
  }, integer(1))

  chosen_idx <- NA_integer_
  for (v in prefer) {
    hit <- which(variants == v)
    if (length(hit) > 0) { chosen_idx <- hit[1]; break }
  }
  if (is.na(chosen_idx)) chosen_idx <- 1L

  message("[ggir] Multiple part5 report variants found (",
          paste(paste0(variants, "=", n_ids, "p"), collapse = ", "),
          ") — using '", variants[chosen_idx], "': ", basename(files[chosen_idx]))

  best_idx <- which.max(n_ids)
  if (!is.na(n_ids[chosen_idx]) && !is.na(n_ids[best_idx]) &&
      n_ids[best_idx] > n_ids[chosen_idx]) {
    warning("[ggir] Chosen variant '", variants[chosen_idx], "' covers ",
            n_ids[chosen_idx], " participant(s), but '", variants[best_idx],
            "' covers ", n_ids[best_idx], " for the same run — participants ",
            "may be silently missing from this meting's activity summary.",
            call. = FALSE)
  }
  files[chosen_idx]
}

#' Back up a file before it gets overwritten
#'
#' segment_summary.csv / analysis_ready.csv / validity_summary.csv live under
#' paths.data_processed/summaries/ (file.path(base_out, "summaries", ...)),
#' so a test run that redirects data_processed to a scratch folder naturally
#' redirects these summaries too — no separate escape hatch to worry about.
#' This used to not be true: these files previously landed at a fixed path
#' derived from data_processed's *parent* directory, regardless of what
#' data_processed itself pointed at, which meant a deliberately redirected
#' test run could silently overwrite the real files if the scratch folder's
#' parent happened to match — confirmed to have happened once. Backing up
#' whatever was there before every write remains in place as a second safety
#' net, since these files are gitignored and have no git history to recover
#' from otherwise.
#'
#' Keeps only the 5 most recent backups per file to avoid unbounded growth
#' from routine dev/test iteration.
#'
#' Backups live in a `backups/` subfolder next to `path` rather than as
#' siblings of the live file, so the output folder doesn't visibly fill up
#' with `.bak.*` files over repeated pipeline runs.
#'
#' @param path Path to the file about to be overwritten.
backup_if_exists <- function(path) {
  if (!file.exists(path)) return(invisible(NULL))

  backup_dir <- file.path(dirname(path), "backups")
  dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)

  ts          <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_path <- file.path(backup_dir, paste0(basename(path), ".bak.", ts))
  file.copy(path, backup_path, overwrite = TRUE)
  message("[backup] Existing ", basename(path), " backed up to ", file.path("backups", basename(backup_path)))

  existing <- sort(list.files(backup_dir,
                              pattern = paste0("^", basename(path), "\\.bak\\."),
                              full.names = TRUE))
  if (length(existing) > 5) {
    file.remove(existing[seq_len(length(existing) - 5)])
  }
  invisible(backup_path)
}

#' Read GGIR Part 5 day summary — prefers Segments version
# Note: Part 5 files are read via load_ggir_file(pattern = "^part5_...") — use that API.

#' Read GGIR config.csv (parameter record)
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @return data.frame, or NULL if not found.
read_ggir_config <- function(meting_output_dir) {
  subdir <- find_ggir_output_subdir(meting_output_dir)
  if (is.null(subdir)) return(NULL)
  cfg_path <- file.path(subdir, "config.csv")
  if (!file.exists(cfg_path)) return(NULL)
  read.csv(cfg_path, stringsAsFactors = FALSE)
}

#' Compute per-day "waking valid wear hours" by subtracting overnight sleep
#'
#' Veerle's protocol (docs/info/info studie.docx, citing Antczak et al. 2021)
#' defines the sedentary-analysis validity criterion as "≥9 valid hours of
#' valid WAKING wear time" — 24h minus the time a pupil is asleep — not the
#' full calendar day. GGIR's own `includedaycrit` (used in 01_run_ggir.R for
#' GGIR's internal Part 2/5 processing) measures the full calendar day; this
#' function corrects that for the pipeline's own validity gate by subtracting
#' each night's sleep-period-time (SPT) window from the calendar day(s) it
#' overlaps. This mirrors how GGIR itself defines "waking hours" internally
#' for its own includedaycrit.part5 parameter (both are built on GGIR's
#' detected SleepPeriodTime) — see docs/test/bug_log.md #31 for the source-
#' level investigation that established this.
#'
#' Approximation, documented rather than hidden: a night's SPT clock-time
#' duration is treated as fully "valid wear" time (GGIR's sleep detection
#' needs wear data to run in the first place, so this is a reasonable but not
#' epoch-exact assumption — true epoch-level accounting is the deferred
#' labeled_epochs.csv feature, bug_log.md #10). GGIR expresses sleeponset/
#' wakeup as decimal hours counted from that night's calendar_date's
#' midnight, e.g. wakeup = 26.25 means 02:15 on the *next* calendar day — the
#' SPT window is split across both days accordingly. Subtraction is capped so
#' a day's waking hours can never go negative.
#'
#' Calendar days with no matching Part 4 night data (e.g. non-wear overnight,
#' or GGIR simply never produced any Part 4 output) get n_valid_waking_hours
#' = NA rather than an assumed zero-sleep subtraction — silently assuming no
#' sleep would inflate that day's waking hours and could wrongly count it as
#' valid. NA days are excluded from validity counts by the caller (any
#' na.rm = TRUE aggregation naturally drops them), matching how the sleep
#' validity gate already treats unknown/missing nights.
#'
#' @param part2 data.table with (at least) ID, calendar_date, n_valid_hours —
#'   one row per participant per calendar day (GGIR Part 2 daysummary).
#' @param part4_full data.table with (at least) ID, calendar_date,
#'   sleeponset, wakeup — one row per participant per night. Should be the
#'   UNFILTERED variant (read_part4_sleep(..., prefer_full = TRUE)), not the
#'   cleaned/valid-nights-only one.
#' @return part2 (copy), with calendar_date coerced to Date and a new
#'   n_valid_waking_hours column added.
add_waking_valid_hours <- function(part2, part4_full) {
  part2 <- data.table::copy(part2)
  part2[, calendar_date := as.Date(calendar_date)]

  required <- c("ID", "calendar_date", "sleeponset", "wakeup")
  if (is.null(part4_full) || nrow(part4_full) == 0 ||
      !all(required %in% names(part4_full))) {
    part2[, n_valid_waking_hours := NA_real_]
    return(part2)
  }

  key_cols <- intersect(c("ID", "school", "meting"), names(part4_full))
  key_cols <- intersect(key_cols, names(part2))

  spt <- part4_full[!is.na(calendar_date) & !is.na(sleeponset) & !is.na(wakeup)]
  spt[, calendar_date := as.Date(calendar_date)]

  # Portion of each night's sleep window falling on the onset day vs. the
  # next calendar day (see decimal-hour convention in the docstring above).
  spt[, today_h    := pmax(0, pmin(wakeup, 24) - pmin(sleeponset, 24))]
  spt[, tomorrow_h := pmax(0, wakeup - 24)]

  sleep_by_day <- data.table::rbindlist(list(
    spt[, c(key_cols, "calendar_date", "today_h"), with = FALSE][
      , .(sleep_h = today_h), by = c(key_cols, "calendar_date")],
    spt[tomorrow_h > 0][
      , calendar_date := calendar_date + 1][
      , c(key_cols, "calendar_date", "tomorrow_h"), with = FALSE][
      , .(sleep_h = tomorrow_h), by = c(key_cols, "calendar_date")]
  ))
  sleep_by_day <- sleep_by_day[
    , .(sleep_h = sum(sleep_h, na.rm = TRUE)), by = c(key_cols, "calendar_date")
  ]

  part2 <- merge(part2, sleep_by_day, by = c(key_cols, "calendar_date"), all.x = TRUE)

  n_missing <- part2[is.na(sleep_h), .N]
  if (n_missing > 0) {
    message(sprintf(
      "[validity] %d participant-day(s) have no matching Part 4 sleep record — waking valid hours cannot be computed and these will not count toward n_valid_days.",
      n_missing
    ))
  }

  part2[, n_valid_waking_hours := ifelse(
    is.na(sleep_h), NA_real_, pmax(0, n_valid_hours - sleep_h)
  )]
  part2[, sleep_h := NULL]
  part2[]
}

#' Resolve the qwindow actually used by GGIR for a given meting output
#'
#' Reads GGIR's own persisted config.csv (via read_ggir_config()) and parses
#' the qwindow argument's value string (e.g. "c(0,8.5,10,12,13,15.5,24)")
#' into a numeric vector. This is the ground truth of what GGIR actually used
#' for this run — independent of whatever config.yaml currently says, which
#' may be stale (edited without a step-01 rerun) or irrelevant
#' (qwindow_strategy: "auto" derives boundaries from schedules instead).
#'
#' @param meting_output_dir The outputdir passed to GGIR for this meting.
#' @return Numeric vector of qwindow boundaries, or NULL if config.csv is
#'   missing, has no qwindow row, or the value can't be parsed.
resolve_ggir_qwindow <- function(meting_output_dir) {
  ggir_cfg <- read_ggir_config(meting_output_dir)
  if (is.null(ggir_cfg) || !"argument" %in% names(ggir_cfg)) return(NULL)
  row <- ggir_cfg[ggir_cfg$argument == "qwindow", ]
  if (nrow(row) == 0) return(NULL)
  # Defensive: GGIR writes one config.csv per run, so this should never have
  # more than one qwindow row — but take the last one if it ever does.
  val_str <- tail(row$value, 1)
  val_str <- gsub("^c\\(|\\)$", "", val_str)
  parsed  <- suppressWarnings(as.numeric(strsplit(val_str, ",")[[1]]))
  if (length(parsed) == 0 || anyNA(parsed)) return(NULL)
  parsed
}

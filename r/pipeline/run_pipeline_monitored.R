# run_pipeline_monitored.R
# ─────────────────────────────────────────────────────────────────────────────
# Launches pipeline/run_all.R as a background process fully detached from
# whatever window started it, and shows a live text progress line while it
# runs — see docs/test/bug_log.md #29. On Windows, a process launched as a
# direct blocking child of a console (the old behaviour: Rscript run inline
# in the .bat) is killed if that console window is closed, which could lose
# up to 30-60 minutes of an in-progress real run. Detaching via
# `windows_detached_process = TRUE` (processx) survives the launching window
# being closed — verified empirically (not just from docs) during this
# session: a detached child process stayed alive after its launching console
# window was force-killed.
#
# If a pipeline run is already in progress (checked via logs/pipeline_run_status.txt
# and a live-process verification, not just PID-number reuse), this script
# reattaches to it and resumes showing progress instead of starting a second,
# overlapping run — two concurrent runs against the same output directory
# would race on GGIR's shared milestone/CSV files (GGIR's own resume logic
# via `overwrite: false` is file-existence-based, not process-aware, so it
# has no locking of its own).
#
# 01_run_ggir.R / 02_label_segments.R / 03_build_summaries.R are NOT modified
# by this change — progress is derived entirely from externally polling the
# milestone files GGIR already writes incrementally per participant per part,
# not from any hook inside the pipeline scripts themselves.
#
# Run from r/ (same convention as run_all.R itself).
# ─────────────────────────────────────────────────────────────────────────────

library(processx)
library(ps)
library(yaml)

`%||%` <- function(a, b) if (!is.null(a)) a else b

LOGS_DIR    <- "logs"
STATUS_PATH <- file.path(LOGS_DIR, "pipeline_run_status.txt")
LOCK_DIR    <- file.path(LOGS_DIR, "pipeline_run.lock")
STDOUT_PATH <- file.path(LOGS_DIR, "pipeline_run_stdout.txt")

# Guarded independently of run_all.R's own logging init (utils_logging.R's
# init_pipeline_log() only creates logs/ once the detached child itself
# starts) -- this script writes logs/pipeline_run_status.txt *before* that,
# so a completely fresh bundle extraction needs its own guard here.
dir.create(LOGS_DIR, showWarnings = FALSE, recursive = TRUE)

source("pipeline/validate_config.R", local = TRUE)

# ── Status file helpers ────────────────────────────────────────────────────

read_status <- function(path) {
  if (!file.exists(path)) return(NULL)
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
  if (is.null(lines) || length(lines) == 0) return(NULL)
  kv <- strsplit(lines, "=", fixed = TRUE)
  kv <- kv[lengths(kv) == 2]
  if (length(kv) == 0) return(NULL)
  setNames(as.list(vapply(kv, `[`, character(1), 2)),
           vapply(kv, `[`, character(1), 1))
}

write_status <- function(path, pid, expected_total) {
  writeLines(c(
    paste0("pid=", pid),
    paste0("expected_total=", expected_total),
    paste0("started=", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ), path)
}

#' Is the recorded PID genuinely our still-running run_all.R process?
#'
#' Checking only that *a* process with that PID exists and is named
#' Rscript.exe is not enough -- the dashboard, RStudio, or anything else can
#' also spawn Rscript.exe processes, and PIDs get reused by Windows over
#' time. Match on the full command line actually containing run_all.R
#' instead (per independent review of this design).
is_our_pipeline_process <- function(pid) {
  pid <- suppressWarnings(as.integer(pid))
  if (is.na(pid)) return(FALSE)
  handle <- tryCatch(ps::ps_handle(pid = pid), error = function(e) NULL)
  if (is.null(handle)) return(FALSE)
  alive <- tryCatch(ps::ps_is_running(handle), error = function(e) FALSE)
  if (!isTRUE(alive)) return(FALSE)
  cmdline <- tryCatch(paste(ps::ps_cmdline(handle), collapse = " "),
                       error = function(e) "")
  grepl("run_all.R", cmdline, fixed = TRUE)
}

# ── Progress helpers ───────────────────────────────────────────────────────

#' Expected milestone-unit total: participants x 5 GGIR parts, per meting.
#' Mirrors 01_run_ggir.R's own file-count + quick_test_n capping exactly, so
#' the denominator reflects what will actually run, not a theoretical max.
#' Not a guaranteed-reachable ceiling -- GGIR can legitimately skip a stage
#' for a specific participant (e.g. Part 4 sleep detection with insufficient
#' data), confirmed empirically this session, so the displayed percentage is
#' capped below 100% while still running (see render_progress()) rather than
#' promising a number it may never exactly reach.
compute_expected_total <- function(cfg) {
  dev <- cfg$dev
  base_dir <- if (isTRUE(dev$example_mode)) {
    file.path(cfg$paths$data_example, "dummy_data")
  } else {
    cfg$paths$data_raw
  }
  quick_n <- dev$quick_test_n
  total <- 0L
  for (meting in c("meting_1", "meting_2")) {
    data_dir <- file.path(base_dir, meting)
    if (!dir.exists(data_dir)) next
    n_files <- length(list.files(data_dir, pattern = "\\.(csv|bin|cwa)$", ignore.case = TRUE))
    if (!is.null(quick_n) && !is.na(quick_n)) {
      n_files <- min(as.integer(quick_n), n_files)
    }
    total <- total + n_files
  }
  total * 5L
}

MILESTONE_SUBFOLDERS <- c(
  "meta/basic"    = 1L,
  "meta/ms2.out"  = 2L,
  "meta/ms3.out"  = 3L,
  "meta/ms4.out"  = 4L,
  "meta/ms5.out"  = 5L
)

#' Count milestone files written so far, and the most recently active part.
#' @return list(done = integer, current_part = integer or NA)
count_progress <- function(cfg) {
  out_base <- cfg$paths$data_processed
  done <- 0L
  latest_mtime <- as.POSIXct(NA)
  latest_part  <- NA_integer_

  for (meting in c("meting_1", "meting_2")) {
    meting_dir <- file.path(out_base, meting)
    out_subdir <- find_ggir_output_subdir(meting_dir)
    if (is.null(out_subdir)) next

    for (sf in names(MILESTONE_SUBFOLDERS)) {
      p <- file.path(out_subdir, sf)
      if (!dir.exists(p)) next
      files <- list.files(p, pattern = "\\.RData$", full.names = TRUE)
      done <- done + length(files)
      if (length(files) > 0) {
        mt <- max(file.info(files)$mtime, na.rm = TRUE)
        if (is.na(latest_mtime) || mt > latest_mtime) {
          latest_mtime <- mt
          latest_part  <- MILESTONE_SUBFOLDERS[[sf]]
        }
      }
    }
  }
  list(done = done, current_part = latest_part)
}

render_progress <- function(done, expected_total, current_part) {
  pct <- if (expected_total > 0) round(100 * done / expected_total) else 0
  # Never claim 100% while still polling -- the denominator can overestimate
  # (GGIR can legitimately skip a stage for a participant), and "done" is
  # only ever reported once the process has actually exited (see main loop).
  pct <- min(pct, 99L)
  part_txt <- if (!is.na(current_part)) sprintf(" (Deel %d van 5)", current_part) else ""
  line <- sprintf("\rVerwerkt: %d van %d onderdelen%s -- %d%%   ",
                   done, expected_total, part_txt, pct)
  cat(line)
  utils::flush.console()
}

# ── Main ────────────────────────────────────────────────────────────────────

cfg <- read_config_yaml("../config.yaml")
cfg <- apply_active_profile(cfg)
source("pipeline/utils_ggir.R", local = TRUE)

existing <- read_status(STATUS_PATH)
reattaching <- FALSE

if (!is.null(existing) && is_our_pipeline_process(existing$pid)) {
  reattaching <- TRUE
  message("Er is al een pipeline-run bezig (PID ", existing$pid, ") -- hierop aansluiten...")
  pid            <- as.integer(existing$pid)
  expected_total <- suppressWarnings(as.integer(existing$expected_total)) %||% compute_expected_total(cfg)
} else {
  # Acquire a short-lived lock via atomic directory creation (dir.create()
  # either succeeds or fails atomically at the OS level -- no two concurrent
  # launches can both succeed) to close the race between "no run currently
  # recorded" and "write the new status file" that a bare PID-file check
  # alone would leave open (per independent review of this design).
  got_lock <- dir.create(LOCK_DIR, showWarnings = FALSE)
  if (!got_lock) {
    # Lock dir already exists -- either a genuine concurrent launch race, or
    # a stale leftover from a process that crashed before cleaning up.
    lock_age <- tryCatch(difftime(Sys.time(), file.info(LOCK_DIR)$mtime, units = "secs"),
                          error = function(e) Inf)
    if (!is.na(lock_age) && lock_age < 30) {
      stop("Een andere pipeline-start lijkt net bezig te zijn. Wacht even en probeer opnieuw.")
    }
    unlink(LOCK_DIR, recursive = TRUE, force = TRUE)
    dir.create(LOCK_DIR, showWarnings = FALSE)
  }

  message("Pipeline wordt gestart op de achtergrond...")
  expected_total <- compute_expected_total(cfg)

  rscript_path <- file.path(R.home("bin"), "Rscript.exe")
  proc <- processx::process$new(
    command = rscript_path,
    args = c("-e", "source('pipeline/run_all.R')"),
    wd = getwd(),
    stdout = STDOUT_PATH,
    stderr = STDOUT_PATH,
    windows_detached_process = TRUE,
    supervise = FALSE
  )
  pid <- proc$get_pid()
  write_status(STATUS_PATH, pid, expected_total)
  unlink(LOCK_DIR, recursive = TRUE, force = TRUE)

  message("Gestart (PID ", pid, "). Dit venster kan gesloten worden zonder de run te onderbreken --")
  message("open opnieuw '1 - Pipeline uitvoeren.bat' om de voortgang terug te zien.")
}

# ── Monitor loop ────────────────────────────────────────────────────────────

message("")
repeat {
  still_running <- is_our_pipeline_process(pid)
  progress <- count_progress(cfg)
  render_progress(progress$done, expected_total, progress$current_part)
  if (!still_running) break
  Sys.sleep(3)
}
cat("\n")

# ── Completion check ─────────────────────────────────────────────────────────
summaries_dir <- file.path(cfg$paths$data_processed, "summaries")
expected_outputs <- c("analysis_ready.csv", "segment_summary.csv", "validity_summary.csv")
all_present <- all(file.exists(file.path(summaries_dir, expected_outputs)))

if (all_present) {
  message("============================================================")
  message(" Klaar. Start nu \"2 - Dashboard starten.bat\" om de")
  message(" resultaten te bekijken.")
  message("============================================================")
} else {
  message("============================================================")
  message(" FOUT: de pipeline lijkt niet volledig afgerond te zijn.")
  message(" Zie logs/pipeline_errors.txt en logs/pipeline_run_stdout.txt voor details.")
  message("============================================================")
  quit(status = 1, save = "no")
}

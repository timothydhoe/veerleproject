# utils_logging.R
# ─────────────────────────────────────────────────────────────────────────────
# Shared error/warning-to-file logging. Sourced by both the pipeline
# (run_all.R) and the Shiny dashboard (global.R) — one implementation, so the
# two entry points can't silently drift the way part2's validity logic once
# did (see docs/test/bug_log.md #31).
#
# Captures warnings/errors only, not a full console transcript. Anything a
# called package (e.g. GGIR) suppresses internally via its own
# suppressWarnings()/message() calls never reaches R's condition system and
# is out of scope here, no matter how the call is wrapped.
#
# Consecutive identical (level, context, message) entries are collapsed into
# a single line with a "(xN)" suffix rather than repeated verbatim — GGIR's
# own Part 1 processing was observed (live run against real device data,
# 2026-07-27) to emit the same coercion warning ~1000 times in under a
# second, which without this would make the log unusable as the "small,
# scannable" file requested (feature_log.md #1).
# ─────────────────────────────────────────────────────────────────────────────

.log_dedup_state <- new.env(parent = emptyenv())

.log_dedup_key <- function(level, context, msg) {
  paste(level, if (!is.null(context)) context else "", msg, sep = "\x1f")
}

#' Flush any buffered repeated-entry for `path` to disk.
.log_flush_pending <- function(path) {
  pending <- .log_dedup_state[[path]]
  if (is.null(pending)) return(invisible())
  line <- if (pending$count > 1) {
    paste0(pending$line, sprintf(" (x%d)", pending$count))
  } else {
    pending$line
  }
  cat(line, file = path, sep = "\n", append = TRUE)
  rm(list = path, envir = .log_dedup_state)
  invisible()
}

#' Append a timestamped condition line, collapsing consecutive duplicates.
.log_append <- function(path, level, msg, context = NULL) {
  key  <- .log_dedup_key(level, context, msg)
  line <- sprintf(
    "[%s] %s%s: %s",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level,
    if (!is.null(context)) paste0(" (", context, ")") else "",
    msg
  )
  pending <- .log_dedup_state[[path]]
  if (!is.null(pending) && identical(pending$key, key)) {
    pending$count <- pending$count + 1
    .log_dedup_state[[path]] <- pending
  } else {
    .log_flush_pending(path)
    .log_dedup_state[[path]] <- list(key = key, count = 1, line = line)
  }
  invisible()
}

#' Create/truncate a log file and write its header.
#'
#' @param path Path to the log file. Parent directory is created if missing.
#' @return path, invisibly.
init_pipeline_log <- function(path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  writeLines(
    sprintf("SchoolMove log — started %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    path
  )
  if (exists(path, envir = .log_dedup_state, inherits = FALSE)) {
    rm(list = path, envir = .log_dedup_state)
  }
  invisible(path)
}

#' Append a timestamped WARNING line to a log file (deduplicated — see file header).
#'
#' @param path    Path to an already-initialized log file.
#' @param msg     Warning message text.
#' @param context Optional label identifying the step/context (e.g. "01_run_ggir.R").
log_warning <- function(path, msg, context = NULL) {
  .log_append(path, "WARNING", msg, context)
}

#' Append a timestamped ERROR line to a log file (deduplicated — see file header).
#'
#' Flushes any pending buffered warning for `path` first, since an error means
#' execution is about to stop and nothing else will trigger that flush.
#'
#' @param path    Path to an already-initialized log file.
#' @param msg     Error message text.
#' @param context Optional label identifying the step/context.
log_error <- function(path, msg, context = NULL) {
  .log_flush_pending(path)
  .log_append(path, "ERROR", msg, context)
  .log_flush_pending(path)
}

#' Evaluate `expr`, logging any warnings/errors raised during evaluation.
#'
#' Warnings are logged and then left to propagate normally — console output
#' is unaffected, this is purely additive (no `invokeRestart("muffleWarning")`
#' is called). Errors are logged and then re-thrown, so callers see exactly
#' the same failure behaviour as an unwrapped call (e.g. run_all.R's existing
#' errorlevel-based `.bat` failure messaging is untouched). Any buffered
#' repeated warning is flushed to disk once `expr` finishes (successfully or
#' not), so nothing is left unwritten at the end of this call.
#'
#' @param expr     Expression to evaluate (e.g. a source() call).
#' @param log_path Path to an already-initialized log file (see
#'                 init_pipeline_log()).
#' @param context  Optional label identifying the step/context.
with_logged_conditions <- function(expr, log_path, context = NULL) {
  on.exit(.log_flush_pending(log_path), add = TRUE)
  withCallingHandlers(
    tryCatch(
      expr,
      error = function(e) {
        log_error(log_path, conditionMessage(e), context)
        stop(e)
      }
    ),
    warning = function(w) {
      log_warning(log_path, conditionMessage(w), context)
    }
  )
}

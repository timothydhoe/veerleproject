# utils_bouts.R
# ─────────────────────────────────────────────────────────────────────────────
# Context-aware bout detection using run-length encoding.
#
# Ported and adapted from project_1/R/analysis/sedentary_bouts.R.
#
# KEY REQUIREMENT: These functions operate on epoch-level data — one row per
# 1-second epoch with columns: ID, date, context, intensity, wear.
#
# Epoch-level data is available when GGIR is run with epochvalues2csv = TRUE
# AND 02_label_segments.R has applied school context labels to each epoch.
#
# If epoch-level data is not available, 03_build_summaries.R falls back to
# GGIR-native bout columns from part5 (total-day level, no context split).
# ─────────────────────────────────────────────────────────────────────────────

#' Detect bouts of a specific activity intensity, split at context boundaries
#'
#' Uses run-length encoding on intensity × context to find consecutive epochs
#' at the target intensity within a school context window. Bouts that span
#' a context change are split at the boundary.
#'
#' @param epochs data.frame with columns:
#'   ID (or pupil_id), date, context, intensity, wear. May optionally include
#'   an `epoch_length_s` column (constant per participant) — see
#'   `epoch_length_s` param below.
#' @param min_bout_min Minimum bout duration in minutes.
#' @param target_intensity One of "sedentary", "light", "moderate", "vigorous".
#' @param valid_only If TRUE, exclude non-wear epochs. Default TRUE.
#' @param id_col Name of the participant ID column. Default "ID".
#' @param epoch_length_s Seconds spanned by one row of `epochs`. If NULL
#'   (default), taken from an `epoch_length_s` column in `epochs` if present
#'   (this is how `02b_label_epochs.R`/`labeled_epochs.csv` supply it — the
#'   real value is 5s for this study's GGIR export, NOT the 1s this function
#'   used to hardcode via `* 60L`/`/ 60`, which silently required 5x the real
#'   elapsed time to reach a nominal bout threshold). Falls back to 1 when
#'   neither is supplied, preserving old behavior for callers/tests that
#'   don't carry real epoch-length information.
#' @param split_at_context_boundary If TRUE (default — Veerle's confirmed
#'   methodology), a bout is split wherever the school-context label changes
#'   mid-run. If FALSE, context changes are ignored for bout detection and
#'   the reported context is simply the context of the run's first epoch.
#'   Not currently exercised in production (config.yaml's
#'   bouts.split_at_context_boundary defaults to TRUE), kept so the config
#'   flag actually controls behavior instead of being silently ignored.
#' @return data.frame with columns:
#'   ID, date, context, intensity, n_bouts, mean_bout_min, total_bout_min
detect_activity_bouts <- function(epochs,
                                  min_bout_min     = 30,
                                  target_intensity  = "sedentary",
                                  valid_only        = TRUE,
                                  id_col            = "ID",
                                  epoch_length_s    = NULL,
                                  split_at_context_boundary = TRUE) {
  df <- as.data.frame(epochs)

  # Normalise ID column name
  if (id_col != "ID" && id_col %in% names(df)) {
    names(df)[names(df) == id_col] <- "ID"
  }

  required <- c("ID", "date", "context", "intensity")
  missing  <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop("detect_activity_bouts: missing columns: ", paste(missing, collapse = ", "))
  }

  if (is.null(epoch_length_s)) {
    epoch_length_s <- if ("epoch_length_s" %in% names(df) && nrow(df) > 0) {
      df$epoch_length_s[1]
    } else {
      1
    }
  }
  if (!is.numeric(epoch_length_s) || length(epoch_length_s) != 1 ||
      is.na(epoch_length_s) || epoch_length_s <= 0) {
    stop("detect_activity_bouts: epoch_length_s must be a single positive number, got: ",
         epoch_length_s)
  }

  if (valid_only && "wear" %in% names(df)) {
    df <- df[df$wear == TRUE, ]
  }
  df <- df[!is.na(df$intensity), ]

  # min_bout_min minutes, expressed as a count of epoch_length_s-second epochs.
  min_bout_epochs <- (min_bout_min * 60) / epoch_length_s

  all_results <- list()

  for (pid in unique(df$ID)) {
    pdata <- df[df$ID == pid, ]

    for (d in unique(pdata$date)) {
      ddata <- pdata[pdata$date == d, ]
      if (nrow(ddata) == 0) next

      # RLE key: "TRUE|context" marks the start of a qualifying bout run,
      # splitting at context boundaries (unless split_at_context_boundary is
      # FALSE, in which case context is dropped from the key and only
      # intensity-run boundaries matter).
      is_target <- as.character(ddata$intensity) == target_intensity
      bout_key  <- if (isTRUE(split_at_context_boundary)) {
        paste(is_target, ddata$context, sep = "|")
      } else {
        as.character(is_target)
      }
      runs      <- rle(bout_key)

      run_end   <- cumsum(runs$lengths)
      run_start <- c(1L, run_end[-length(run_end)] + 1L)

      for (j in seq_along(runs$values)) {
        if (isTRUE(split_at_context_boundary)) {
          parts    <- strsplit(runs$values[j], "\\|")[[1]]
          is_match <- parts[1] == "TRUE"
          ctx      <- parts[2]
        } else {
          is_match <- runs$values[j] == "TRUE"
          ctx      <- ddata$context[run_start[j]]
        }

        if (!is_match || runs$lengths[j] < min_bout_epochs) next

        all_results[[length(all_results) + 1]] <- data.frame(
          ID                = pid,
          date              = d,
          context           = ctx,
          intensity         = target_intensity,
          bout_duration_min = runs$lengths[j] * epoch_length_s / 60,
          stringsAsFactors  = FALSE
        )
      }
    }
  }

  empty <- data.frame(
    ID = character(), date = as.Date(character()), context = character(),
    intensity = character(), n_bouts = integer(),
    mean_bout_min = numeric(), total_bout_min = numeric(),
    stringsAsFactors = FALSE
  )

  if (length(all_results) == 0) return(empty)

  bout_data <- do.call(rbind, all_results)

  # Aggregate per ID / date / context
  agg <- aggregate(
    bout_duration_min ~ ID + date + context + intensity,
    data = bout_data,
    FUN  = function(x) c(n = length(x), mean = mean(x), total = sum(x))
  )
  result <- data.frame(
    ID             = agg$ID,
    date           = agg$date,
    context        = agg$context,
    intensity      = agg$intensity,
    n_bouts        = agg$bout_duration_min[, "n"],
    mean_bout_min  = agg$bout_duration_min[, "mean"],
    total_bout_min = agg$bout_duration_min[, "total"],
    stringsAsFactors = FALSE
  )

  result
}

#' Detect sedentary bouts (convenience wrapper)
#'
#' @param epochs data.frame with epoch-level data.
#' @param min_bout_min Minimum sedentary bout in minutes. Default 30.
#' @param valid_only Exclude non-wear. Default TRUE.
#' @return data.frame with bout summary.
detect_sedentary_bouts <- function(epochs, min_bout_min = 30, valid_only = TRUE) {
  detect_activity_bouts(epochs, min_bout_min, "sedentary", valid_only)
}

#' Compute per-context sedentary bout averages from epoch data
#'
#' Aggregates `detect_activity_bouts()` results to per-participant level,
#' producing one value per school-context segment (to merge into analysis_ready).
#'
#' @param epochs Epoch-level data.frame.
#' @param bout_cfg Named list from config$bouts (sedentary_min, split_at_context_boundary).
#' @return Wide data.table: one row per ID × meting, columns like
#'   bouts_30min_inclass_n, bouts_30min_recess_n, etc.
#'   Returns NULL if epoch data is not available.
compute_context_bout_summaries <- function(epochs, bout_cfg) {
  if (is.null(epochs) || nrow(epochs) == 0) return(NULL)

  min_sb      <- bout_cfg$sedentary_min %||% 30L
  split_ctx   <- isTRUE(bout_cfg$split_at_context_boundary %||% TRUE)
  has_meting  <- "meting" %in% names(epochs)

  if (!has_meting) {
    warning("[bouts] 'meting' column absent from epoch data — grouping by ID only (fallback)")
  }

  raw <- tryCatch(
    detect_activity_bouts(epochs, min_bout_min = min_sb, target_intensity = "sedentary",
                          split_at_context_boundary = split_ctx),
    error = function(e) {
      message("[bouts] Error in bout detection: ", e$message)
      NULL
    }
  )
  if (is.null(raw) || nrow(raw) == 0) return(NULL)

  # Average per participant × meting × context (across days)
  group_vars <- if (has_meting && "meting" %in% names(raw)) {
    cbind(n_bouts, total_bout_min) ~ ID + meting + context
  } else {
    cbind(n_bouts, total_bout_min) ~ ID + context
  }

  avg <- aggregate(group_vars, data = raw, FUN = mean)

  # Pivot to wide: one column per context
  contexts <- unique(avg$context)
  id_cols  <- if (has_meting && "meting" %in% names(avg)) c("ID", "meting") else "ID"
  result   <- unique(avg[, id_cols, drop = FALSE])

  for (ctx in contexts) {
    safe_ctx <- gsub("[^a-zA-Z0-9]", "_", ctx)
    sub_df   <- avg[avg$context == ctx, ]
    col_n    <- paste0("bouts_", min_sb, "min_", safe_ctx, "_n")
    col_min  <- paste0("bouts_", min_sb, "min_", safe_ctx, "_total_min")
    if (has_meting && "meting" %in% names(avg)) {
      idx <- match(paste(result$ID, result$meting), paste(sub_df$ID, sub_df$meting))
    } else {
      idx <- match(result$ID, sub_df$ID)
    }
    result[[col_n]]   <- sub_df$n_bouts[idx]
    result[[col_min]] <- sub_df$total_bout_min[idx]
  }

  result
}

# Allow %||% to be used here if not already defined in the calling environment
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

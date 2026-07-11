# validate_config.R
# ─────────────────────────────────────────────────────────────────────────────
# Config schema validation for SchoolMove.
#
# Call validate_config(cfg) early in run_all.R and shiny/global.R.
# Stops with a clear message on hard failures. Warns on soft issues.
# Does NOT require interactive input — safe to call in batch/Shiny context.
# ─────────────────────────────────────────────────────────────────────────────

#' Read config.yaml with a friendlier error for a common Windows mistake
#'
#' Windows users routinely paste backslash paths (e.g. "C:\Users\...") into
#' a double-quoted YAML scalar. YAML then tries to parse the backslash as an
#' escape sequence (e.g. \\U as a broken unicode escape), producing a cryptic
#' "did not find expected hexdecimal number" scanner error (libyaml's own
#' spelling, not a typo introduced here). Detect that specific failure and
#' re-throw a clear, actionable Dutch message instead.
#'
#' @param path Path to the YAML file to read.
#' @return Named list produced by yaml::read_yaml().
read_config_yaml <- function(path) {
  tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      if (grepl("did not find expected hexdecimal number", conditionMessage(e), fixed = TRUE)) {
        stop(
          "Kon ", path, " niet lezen: het pad bevat waarschijnlijk backslashes (\\), ",
          "die YAML als een ongeldig escape-teken interpreteert.\n",
          "  Gebruik forward slashes (/) in plaats daarvan, bv.: \"C:/Data/SchoolMove\" ",
          "i.p.v. \"C:\\Data\\SchoolMove\".",
          call. = FALSE
        )
      }
      stop(e)
    }
  )
}

#' Validate the SchoolMove config list
#'
#' @param cfg Named list produced by yaml::read_yaml("config.yaml").
#' @return Invisibly TRUE on success. Stops with a single-line message on failure.
validate_config <- function(cfg) {

  errors   <- character(0)
  warnings <- character(0)

  add_err  <- function(msg) errors   <<- c(errors, msg)
  add_warn <- function(msg) warnings <<- c(warnings, msg)

  # ── 1. Required top-level sections ──────────────────────────────────────────
  required_sections <- c("paths", "ggir", "validity", "schedules", "dev", "output")
  missing_sections  <- setdiff(required_sections, names(cfg))
  if (length(missing_sections) > 0) {
    add_err(paste("Missing required config sections:", paste(missing_sections, collapse = ", ")))
  }

  # ── 2. Numeric range checks ──────────────────────────────────────────────────
  cp <- cfg$ggir$cut_points_mg
  if (!is.null(cp)) {
    vals <- c(cp$sedentary_to_light, cp$light_to_moderate, cp$moderate_to_vigorous)
    if (any(is.na(suppressWarnings(as.numeric(vals))))) {
      add_err("ggir.cut_points_mg: all three values must be numeric")
    } else {
      vals <- as.numeric(vals)
      if (any(vals <= 0)) {
        add_err("ggir.cut_points_mg: all values must be positive")
      }
      if (!all(diff(vals) > 0)) {
        add_err("ggir.cut_points_mg: values must be in strictly increasing order (SB < LPA < MPA)")
      }
    }
  } else {
    add_err("ggir.cut_points_mg: section missing — activity classification will fail")
  }

  val <- cfg$validity
  if (!is.null(val)) {
    min_h <- suppressWarnings(as.numeric(val$min_wear_hours_per_day))
    if (is.na(min_h) || min_h < 1 || min_h > 24) {
      add_err(paste0("validity.min_wear_hours_per_day must be a number between 1 and 24",
                     " (got: ", val$min_wear_hours_per_day, ")"))
    }
    min_d <- suppressWarnings(as.integer(val$min_valid_days))
    if (is.na(min_d) || min_d < 1) {
      add_err(paste0("validity.min_valid_days must be an integer ≥ 1 (got: ", val$min_valid_days, ")"))
    }
  }

  # ── 3. Schedule validation ───────────────────────────────────────────────────
  is_valid_hhmm <- function(x) {
    !is.null(x) && grepl("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", as.character(x))
  }

  if (!is.null(cfg$schedules)) {
    for (school_id in names(cfg$schedules)) {
      sch <- cfg$schedules[[school_id]]

      if (isTRUE(sch$fallback)) {
        add_warn(paste0(school_id, ": fallback schedule — confirm timetable with Veerle"))
      }

      if (!is_valid_hhmm(sch$school_start)) {
        add_err(paste0(school_id, ": school_start '", sch$school_start, "' is not a valid HH:MM time"))
      }

      school_start_h <- tryCatch(
        { parts <- as.integer(strsplit(sch$school_start, ":")[[1]]); parts[1] + parts[2] / 60 },
        error = function(e) NA_real_
      )

      for (day_key in names(sch$school_end)) {
        end_val <- sch$school_end[[day_key]]
        if (!is_valid_hhmm(end_val)) {
          add_err(paste0(school_id, ": school_end.", day_key, " '", end_val, "' is not a valid HH:MM time"))
        }
      }

      # Check break start < end
      for (day_key in names(sch$breaks)) {
        day_breaks <- sch$breaks[[day_key]]
        for (brk in day_breaks) {
          if (!is_valid_hhmm(brk$start) || !is_valid_hhmm(brk$end)) {
            add_err(paste0(school_id, ": break in ", day_key, " has invalid start/end time"))
            next
          }
          to_h <- function(hm) {
            p <- as.integer(strsplit(hm, ":")[[1]]); p[1] + p[2] / 60
          }
          if (!is.na(school_start_h) && to_h(brk$start) < school_start_h) {
            add_warn(paste0(school_id, ": break starts (", brk$start, ") before school_start (", sch$school_start, ")"))
          }
          if (to_h(brk$start) >= to_h(brk$end)) {
            add_err(paste0(school_id, ": break start (", brk$start, ") must be before end (", brk$end, ")"))
          }
        }
      }
    }
  }

  # ── 4. Report ────────────────────────────────────────────────────────────────
  if (length(warnings) > 0) {
    for (w in warnings) message("[config] WARN: ", w)
  }

  if (length(errors) > 0) {
    stop(
      "config.yaml validation failed (", length(errors), " error(s)):\n",
      paste0("  - ", errors, collapse = "\n"),
      call. = FALSE
    )
  }

  message("[config] Validation OK",
          if (length(warnings) > 0) paste0(" (", length(warnings), " warning(s) — see above)") else "")
  invisible(TRUE)
}

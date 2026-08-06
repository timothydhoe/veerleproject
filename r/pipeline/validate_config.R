# validate_config.R
# ─────────────────────────────────────────────────────────────────────────────
# Config schema validation for SchoolMove.
#
# Call validate_config(cfg) early in run_all.R and shiny/global.R.
# Stops with a clear message on hard failures. Warns on soft issues.
# Does NOT require interactive input — safe to call in batch/Shiny context.
# ─────────────────────────────────────────────────────────────────────────────

# strip_pupil_id() lives in pipeline/utils_schedule.R and isn't always
# sourced ahead of this file (02_label_segments.R sources this file first;
# shiny/global.R never sources utils_schedule.R at all). Guarded like
# utils_schedule.R's own %||% guard: define a fallback only if the canonical
# version isn't already in scope. Keep this in sync with utils_schedule.R's
# strip_pupil_id() if that one is ever changed — they must stay identical.
if (!exists("strip_pupil_id")) {
  strip_pupil_id <- function(id) sub("\\.[^.]+$", "", basename(as.character(id)))
}

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

#' Merge the active configuration profile over cfg
#'
#' Profiles let a researcher save named parameter presets (validity, bouts,
#' cut-points) as YAML files in the profiles directory and apply them without
#' editing config.yaml directly. Only overrides keys the profile actually
#' specifies (via modifyList) — config.yaml's own values remain the base for
#' anything a profile omits, so partial profiles (e.g. saved profiles that
#' only cover some bouts fields) work correctly.
#'
#' @param cfg Named list produced by read_config_yaml().
#' @param profiles_dir Path to the profiles directory. If NULL, resolved
#'   from cfg$profiles$directory (default "profiles"), relative to the
#'   caller's own working directory — correct for scripts run from r/.
#'   Callers running from a different working directory (e.g. shiny/global.R,
#'   which runs from r/shiny/) must pass an already-resolved path explicitly.
#' @return cfg, with validity/bouts/ggir.cut_points_mg overridden by the
#'   active profile's values where present. Unchanged if profiles.active is
#'   unset or "none" — config.yaml's own values are the default and are never
#'   silently overridden unless a profile is deliberately activated.
apply_active_profile <- function(cfg, profiles_dir = NULL) {
  active_name <- cfg$profiles$active
  no_profile  <- is.null(active_name) ||
    (is.character(active_name) &&
      tolower(trimws(active_name)) %in% c("", "none"))
  if (no_profile) {
    message("[profile] No active profile (profiles.active: none) — using config.yaml values directly.")
    return(cfg)
  }

  if (is.null(profiles_dir)) {
    profiles_dir <- cfg$profiles$directory
    if (is.null(profiles_dir)) profiles_dir <- "profiles"
  }
  profile_path <- file.path(profiles_dir, paste0(active_name, ".yaml"))

  if (!file.exists(profile_path)) {
    message("[profile] Profile not found: '", profile_path,
            "' — using base config.yaml values.")
    return(cfg)
  }

  profile <- yaml::read_yaml(profile_path)
  for (section in c("validity", "bouts")) {
    if (!is.null(profile[[section]])) {
      base <- cfg[[section]]
      if (is.null(base)) base <- list()
      cfg[[section]] <- modifyList(base, profile[[section]])
    }
  }
  if (!is.null(profile$ggir$cut_points_mg)) {
    base_cp <- cfg$ggir$cut_points_mg
    if (is.null(base_cp)) base_cp <- list()
    cfg$ggir$cut_points_mg <- modifyList(base_cp, profile$ggir$cut_points_mg)
  }
  message("[profile] Loaded: '", active_name, "' from ", profile_path)
  cfg
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

  bouts_cfg <- cfg$bouts
  if (!is.null(bouts_cfg) && !is.null(bouts_cfg$enable_epoch_labeling) &&
      !is.logical(bouts_cfg$enable_epoch_labeling)) {
    add_err(paste0("bouts.enable_epoch_labeling must be true or false (got: ",
                   bouts_cfg$enable_epoch_labeling, ")"))
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

  # ── 3. Path length (Windows 260-char MAX_PATH) ───────────────────────────────
  # GGIR creates deeply nested output folders and long filenames on top of
  # whatever data_raw/data_processed already resolves to — a data folder deep
  # on a network/shared drive can silently exceed Windows' path limit well
  # before GGIR's own additions are even factored in. Warn early and clearly
  # rather than let this fail deep inside GGIR's internals. mustWork = FALSE
  # since the directory may not exist yet (e.g. data_processed pre-run).
  path_len_threshold <- 140
  for (path_field in c("data_raw", "data_processed")) {
    p <- cfg$paths[[path_field]]
    if (!is.null(p)) {
      resolved_len <- nchar(normalizePath(p, mustWork = FALSE))
      if (resolved_len > path_len_threshold) {
        add_warn(sprintf(
          paste0("paths.%s resolves to a %d-character path — Windows has a ",
                 "260-character limit, and GGIR adds nested subfolders and ",
                 "long filenames on top. If this is on a network/shared ",
                 "drive, copy the data to a short local path instead ",
                 "(e.g. C:/SchoolMove/data/raw/) to avoid failures partway ",
                 "through a run."),
          path_field, resolved_len
        ))
      }
    }
  }

  # ── 4. Schedule validation ───────────────────────────────────────────────────
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

  # ── 5. Absence validation ─────────────────────────────────────────────────────
  # Warn, not error: pupil existence can't be checked before step 01 has run, and
  # a typo here shouldn't block the whole pipeline — just get flagged so it's not
  # silently ignored either.
  afw <- cfg$afwezigheden
  if (!is.null(afw) && length(afw) > 0) {
    seen_keys <- character(0)
    for (i in seq_along(afw)) {
      entry <- afw[[i]]
      pid   <- entry$pupil_id
      dt    <- entry$date

      if (is.null(pid) || !nzchar(trimws(as.character(pid)))) {
        add_warn(sprintf("afwezigheden[%d]: missing or empty pupil_id", i))
        next
      }
      dt_chr <- if (is.null(dt)) "" else as.character(dt)
      if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", dt_chr) ||
          is.na(as.Date(dt_chr, format = "%Y-%m-%d", tryFormats = "%Y-%m-%d"))) {
        add_warn(sprintf("afwezigheden[%d]: '%s' is not a valid YYYY-MM-DD date (pupil_id: %s)",
                         i, dt_chr, pid))
        next
      }

      # Normalize the same way get_absence_entries()/apply_absence_drop()
      # (utils_schedule.R) do at runtime — "2063" and "2063.cwa" collapse to
      # the same effective drop there, so they must collapse here too or a
      # config mistake goes undetected.
      key <- paste(strip_pupil_id(pid), dt_chr)
      if (key %in% seen_keys) {
        add_warn(sprintf("afwezigheden: duplicate entry for pupil_id %s on %s", pid, dt_chr))
      }
      seen_keys <- c(seen_keys, key)
    }
  }

  # ── 6. Report ────────────────────────────────────────────────────────────────
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

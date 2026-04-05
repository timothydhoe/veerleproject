# =============================================================================
# SchoolMoves Analysis — School Correlations (RQ4)
# =============================================================================
# Correlates lesson block duration with in-class sedentary minutes.
# N=6 schools — this analysis is EXPLORATORY ONLY.
# =============================================================================

suppressPackageStartupMessages(library(yaml))

#' Analyse correlations between school-day structure and activity
#'
#' Computes mean lesson block duration per school from the schedule config,
#' then correlates with mean in-class sedentary minutes from activity totals.
#'
#' NOTE: With only N=6 schools, this is exploratory — do not over-interpret
#' p-values or treat as confirmatory evidence.
#'
#' @param activity_totals data.frame — output of compute_activity_totals()
#' @param schedule_config Path to school_schedules.yaml
#' @return Named list with:
#'   - correlation_table: data.frame with school_id, mean_lesson_min, mean_sed_min
#'   - model_summary: summary of lm(mean_sed_min ~ mean_lesson_min)
#'   - correlation: Pearson r and p-value
analyse_school_correlations <- function(activity_totals,
                                        schedule_config = "config/school_schedules.yaml") {

  # --- Compute mean lesson block duration per school ---
  config <- yaml::read_yaml(schedule_config)
  school_lessons <- lapply(config$schools, function(sch) {
    in_class_blocks <- Filter(function(b) b$context == "in_class", sch$blocks)
    durations <- sapply(in_class_blocks, function(b) {
      start <- time_str_to_minutes(b$start)
      end   <- time_str_to_minutes(b$end)
      end - start
    })
    data.frame(
      school_id        = sch$school_id,
      n_blocks         = length(durations),
      mean_lesson_min  = mean(durations),
      total_lesson_min = sum(durations),
      schedule_source  = sch$schedule_source,
      stringsAsFactors = FALSE
    )
  })
  lesson_summary <- do.call(rbind, school_lessons)

  # --- Compute mean in-class sedentary minutes per school ---
  in_class <- activity_totals[activity_totals$context == "in_class", ]
  if (nrow(in_class) == 0) {
    message("No in-class data found in activity totals. Cannot compute correlations.")
    return(list(correlation_table = lesson_summary, model_summary = NULL, correlation = NULL))
  }

  sed_by_school <- in_class |>
    dplyr::group_by(school_id) |>
    dplyr::summarise(
      mean_sed_min = mean(sedentary_min, na.rm = TRUE),
      n_pupils     = dplyr::n_distinct(pupil_id),
      .groups = "drop"
    )

  # --- Merge ---
  corr_table <- merge(lesson_summary, sed_by_school, by = "school_id", all.x = TRUE)

  # --- Correlation and model ---
  # N=6 schools — exploratory only
  if (sum(!is.na(corr_table$mean_sed_min)) < 3) {
    message("Fewer than 3 schools with sedentary data — skipping correlation.")
    return(list(correlation_table = corr_table, model_summary = NULL, correlation = NULL))
  }

  valid <- corr_table[!is.na(corr_table$mean_sed_min), ]
  cor_test <- cor.test(valid$mean_lesson_min, valid$mean_sed_min, method = "pearson")

  model <- lm(mean_sed_min ~ mean_lesson_min, data = valid)

  list(
    correlation_table = corr_table,
    model_summary     = summary(model),
    correlation       = list(r = cor_test$estimate, p = cor_test$p.value,
                             n = nrow(valid), method = "pearson")
  )
}

#' Convert "HH:MM" to minutes since midnight
time_str_to_minutes <- function(time_str) {
  parts <- as.numeric(strsplit(time_str, ":")[[1]])
  parts[1] * 60 + parts[2]
}

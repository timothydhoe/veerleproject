# mod_overview.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 1 "Overzicht"
# KPI ribbon, MVPA dumbbell chart, school overview table, rapport accordion.
#
# NOTE: data_readiness_strip, btn_run_pipeline, pipeline_status_inline are
# root-level outputs/inputs (global pipeline concerns) — they remain in
# server.R and appear in ui.R as bare references above modOverviewUI().
#
# shared list keys used:
#   apply_filters     — session-scoped filter function
#   mvpa_col          — reactive returning MVPA column name (character or NULL)
#   global_school_val — reactive for input$global_school
#   safe_meting_val   — reactive for safe_meting()
#
# Global objects accessed directly (defined in global.R):
#   analysis_ready, validity_summary, SCHOOL_LABELS, SCHOOL_COLORS,
#   METINGEN_LABELS, WHO_MVPA_MIN, WHO_SLEEP_MIN_H, ZONE_COLORS,
#   FALLBACK_SCHOOLS
#   no_data_plot(), png_dl(), theme_schoolmove() — util_plots.R
# ─────────────────────────────────────────────────────────────────────────────

#' Overview tab UI
modOverviewUI <- function(id) {
  ns <- NS(id)
  tagList(
    # KPI ribbon
    layout_columns(
      fill = FALSE,
      col_widths = c(2, 2, 3, 2, 3),
      gap = "0.75rem",
      tags$div(class = "kpi-nav-card",
        onclick = "Shiny.setInputValue('kpi_click','Deelnemers',{priority:'event'})",
        kpi_strip_card("users", "Deelnemers", ns("n_participants"))
      ),
      tags$div(class = "kpi-nav-card",
        onclick = "Shiny.setInputValue('kpi_click','Deelnemers',{priority:'event'})",
        kpi_strip_card("circle-check",
          tip("Geldig voor analyse",
              "Voldoet aan draagduurcriteria (minimaal geldige dagen incl. 1 weekend)"),
          ns("pct_valid"))
      ),
      tags$div(class = "kpi-nav-card",
        onclick = "Shiny.setInputValue('kpi_click','Schooldag',{priority:'event'})",
        kpi_strip_card("person-running",
          tip("Gem. MVPA",
              "Matig-tot-intensieve beweging per dag · enkel geldige deelnemers"),
          ns("avg_mvpa"))
      ),
      tags$div(class = "kpi-nav-card",
        onclick = "Shiny.setInputValue('kpi_click','Vergelijking',{priority:'event'})",
        kpi_strip_card("award",
          tip("WHO-richtlijn gehaald", "% deelnemers met ≥60 min MVPA/dag"),
          ns("pct_who"))
      ),
      tags$div(class = "kpi-nav-card",
        onclick = "Shiny.setInputValue('kpi_click','Slaap',{priority:'event'})",
        kpi_strip_card("moon",
          tip("Gem. slaap", "Geschatte slaapduur per nacht (SPT)"),
          ns("avg_sleep"))
      )
    ),

    layout_columns(
      col_widths = c(8, 4),
      chart_card(
        header   = "MVPA verandering per school: Meting 1 → Meting 2",
        plot_id  = ns("plot_activity_stacked"),
        dl_id    = ns("dl_plot_overview"),
        height   = "500px"
      ),
      card(
        class       = "shadow-sm",
        full_screen = TRUE,
        card_header(tip("Schooloverzicht",
          "Gem. MVPA, % WHO-norm en slaap per school · enkel geldige deelnemers")),
        card_body(
          p(class = "text-muted small mb-2",
            "Gecombineerd over beide metingen · enkel geldige deelnemers."),
          DTOutput(ns("table_school_overview"))
        )
      )
    ),

    accordion(
      id   = ns("rapport_accordion"),
      open = FALSE,
      accordion_panel(
        title = tagList(icon("file-lines"), " Samenvatting voor rapport"),
        value = "rapport",
        uiOutput(ns("rapport_samenvatting_ui"))
      )
    )
  )
}

#' Overview tab server
mod_overview_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Rapport text reactive ─────────────────────────────────────────────────
    rapport_text_reactive <- reactive({
      req(shared$global_school_val())
      mc <- shared$mvpa_col()
      if (is.null(analysis_ready) || is.null(validity_summary))
        return("Geen data beschikbaar — voer de pipeline eerst uit.")

      school_val   <- shared$global_school_val()
      school_scope <- if (school_val == "all") "alle scholen"
                      else SCHOOL_LABELS[names(SCHOOL_LABELS)[SCHOOL_LABELS == school_val]]
      mv           <- shared$safe_meting_val()
      meting_scope <- if (mv != "all") METINGEN_LABELS[mv] else "beide metingen"

      filt_val <- shared$apply_filters(copy(validity_summary))
      filt_ar  <- if (!is.null(mc))
        shared$apply_filters(copy(analysis_ready[meets_sedentary_criteria == TRUE]))
      else NULL

      n_total        <- nrow(filt_val)
      n_valid        <- sum(filt_val$meets_sedentary_criteria, na.rm = TRUE)
      pct_valid_r    <- round(100 * n_valid / max(n_total, 1))
      n_participants <- uniqueN(filt_val$ID)

      mvpa_line <- who_line <- school_line <- sleep_line <- ""

      if (!is.null(filt_ar) && !is.null(mc) && mc %in% names(filt_ar) && nrow(filt_ar) > 0) {
        filt_ar[, mvpa_val     := get(mc)]
        filt_ar[, school_label := SCHOOL_LABELS[school]]

        avg_mvpa  <- round(mean(filt_ar$mvpa_val, na.rm = TRUE))
        pct_who_r <- round(100 * mean(filt_ar$mvpa_val >= WHO_MVPA_MIN, na.rm = TRUE))
        mvpa_line <- sprintf("Het cohort haalt gemiddeld %d min/dag MVPA.", avg_mvpa)
        who_line  <- sprintf("%d%% van de deelnemers bereikt de WHO-richtlijn van ≥60 min/dag.", pct_who_r)

        school_agg <- filt_ar[, .(m = mean(mvpa_val, na.rm = TRUE)), by = school_label]
        if (nrow(school_agg) > 1) {
          best  <- school_agg[which.max(m)]
          worst <- school_agg[which.min(m)]
          school_line <- sprintf(
            "%s scoort het hoogst (%d min/dag); %s het laagst (%d min/dag).",
            best$school_label,  round(best$m),
            worst$school_label, round(worst$m)
          )
        }
      }

      if (!is.null(filt_ar) && "sleep_duration_h" %in% names(filt_ar) && nrow(filt_ar) > 0) {
        avg_sleep  <- round(mean(filt_ar$sleep_duration_h, na.rm = TRUE), 1)
        pct_short  <- round(100 * mean(filt_ar$sleep_duration_h < WHO_SLEEP_MIN_H, na.rm = TRUE))
        sleep_line <- sprintf(
          "Gemiddelde slaapduur: %.1f uur/nacht. %d%% slaapt korter dan de WHO-aanbeveling van %d uur.",
          avg_sleep, pct_short, WHO_SLEEP_MIN_H
        )
      }

      lines <- c(
        sprintf("SchoolMove — %s / %s", school_scope, meting_scope),
        "",
        sprintf("Cohort: %d deelnemers · %d metingen · %d%% van de metingen geldig voor analyse.",
                n_participants, n_total, pct_valid_r),
        if (nzchar(mvpa_line))   mvpa_line,
        if (nzchar(school_line)) school_line,
        if (nzchar(who_line))    who_line,
        if (nzchar(sleep_line))  sleep_line
      )
      paste(Filter(Negate(is.null), lines), collapse = "\n")
    })

    output$rapport_samenvatting_ui <- renderUI({
      txt      <- rapport_text_reactive()
      btn_id   <- ns("btn_copy_rapport")
      pre_id   <- "rapport_text_out"
      conf_id  <- "rapport_copy_confirm"
      tagList(
        tags$pre(id = pre_id, txt),
        tags$div(
          style = "margin-top:8px; display:flex; gap:8px; align-items:center;",
          actionButton(btn_id, "Kopieer naar klembord",
                       icon  = icon("copy"),
                       class = "btn-outline-secondary btn-sm"),
          tags$span(id = conf_id,
                    style = "font-size:0.8rem; color:#198754; display:none;",
                    "✓ Gekopieerd")
        ),
        tags$script(HTML(sprintf("
          document.getElementById('%s').addEventListener('click', function() {
            var txt = document.getElementById('%s').innerText;
            navigator.clipboard.writeText(txt).then(function() {
              var conf = document.getElementById('%s');
              conf.style.display = 'inline';
              setTimeout(function(){ conf.style.display = 'none'; }, 2000);
            });
          });
        ", btn_id, pre_id, conf_id)))
      )
    })

    # ── KPI cards (whole-cohort, unfiltered) ──────────────────────────────────
    output$n_participants <- renderText({
      if (is.null(validity_summary)) return("—")
      uniqueN(validity_summary$ID)
    })

    output$pct_valid <- renderText({
      if (is.null(validity_summary)) return("—")
      sprintf("%.0f%%", 100 * mean(validity_summary$meets_sedentary_criteria, na.rm = TRUE))
    })

    output$avg_mvpa <- renderText({
      mc <- shared$mvpa_col()
      if (is.null(analysis_ready) || is.null(mc)) return("—")
      valid <- analysis_ready[meets_sedentary_criteria == TRUE & !is.na(get(mc))]
      if (nrow(valid) == 0) return("—")
      sprintf("%.0f min/dag", mean(valid[[mc]], na.rm = TRUE))
    })

    output$pct_who <- renderText({
      mc <- shared$mvpa_col()
      if (is.null(analysis_ready) || is.null(mc)) return("—")
      valid <- analysis_ready[meets_sedentary_criteria == TRUE & !is.na(get(mc))]
      if (nrow(valid) == 0) return("—")
      sprintf("%.0f%%", 100 * mean(valid[[mc]] >= WHO_MVPA_MIN, na.rm = TRUE))
    })

    output$avg_sleep <- renderText({
      if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready)) return("—")
      valid <- analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)]
      if (nrow(valid) == 0) return("—")
      sprintf("%.1f u/nacht", mean(valid$sleep_duration_h, na.rm = TRUE))
    })

    # ── MVPA dumbbell chart ───────────────────────────────────────────────────
    overview_plot <- reactive({
      mc <- shared$mvpa_col()
      if (is.null(analysis_ready)) return(no_data_plot())
      if (is.null(mc) || !mc %in% names(analysis_ready))
        return(no_data_plot("MVPA-kolom niet gevonden — herrun stap 03."))

      dt <- analysis_ready[meets_sedentary_criteria == TRUE & !is.na(get(mc))]
      if (nrow(dt) == 0) return(no_data_plot())
      dt[, school_label := SCHOOL_LABELS[school]]
      dt[, mvpa_val     := get(mc)]

      agg <- dt[, {
        n  <- .N
        mu <- mean(mvpa_val, na.rm = TRUE)
        ci <- qt(0.975, n - 1) * sd(mvpa_val, na.rm = TRUE) / sqrt(n)
        .(mean_mvpa = mu, ci95 = ci, n = n)
      }, by = .(school_label, meting)]

      wide <- dcast(agg, school_label ~ meting, value.var = c("mean_mvpa", "ci95", "n"))
      # dcast() only creates a "_meting_2" (or "_meting_1") column suffix if at
      # least one row of agg actually has that meting value — e.g. if zero
      # participants meet validity criteria for meting_2 in the current
      # filter, mean_mvpa_meting_2 simply doesn't exist, and referencing it
      # directly would error instead of falling back to the single-meting view.
      has_both_metingen <- all(c("mean_mvpa_meting_1", "mean_mvpa_meting_2") %in% names(wide))
      if (has_both_metingen) {
        n_schools_total <- nrow(wide)
        wide <- wide[!is.na(mean_mvpa_meting_1) & !is.na(mean_mvpa_meting_2)]
        n_excl_schools  <- n_schools_total - nrow(wide)
      } else {
        wide <- wide[0]
        n_excl_schools  <- 0
      }

      if (nrow(wide) == 0) {
        ggplot(agg, aes(y = reorder(school_label, mean_mvpa), x = mean_mvpa,
                        colour = school_label)) +
          geom_pointrange(aes(xmin = mean_mvpa - ci95, xmax = mean_mvpa + ci95),
                          size = 0.7, linewidth = 1.0) +
          geom_vline(xintercept = WHO_MVPA_MIN, linetype = "dashed",
                     colour = UGENT_REFERENCE_LINE, linewidth = 0.6) +
          scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
          labs(x = "Gem. MVPA (min/dag)", y = NULL,
               subtitle = "Enkel geldige deelnemers · lijnen = 95% BI") +
          theme_schoolmove(legend_pos = "none")
      } else {
        wide[, delta     := mean_mvpa_meting_2 - mean_mvpa_meting_1]
        wide[, direction := ifelse(delta >= 0, "Toename", "Afname")]
        wide[, lbl_m1    := paste0(round(mean_mvpa_meting_1, 0), " min")]
        wide[, lbl_m2    := paste0(round(mean_mvpa_meting_2, 0), " min")]
        wide[, lbl_delta := paste0(ifelse(delta >= 0, "+", ""), round(delta, 1))]

        ggplot(wide, aes(y = reorder(school_label, mean_mvpa_meting_1))) +
          annotate("rect", xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = Inf,
                   fill = "white", colour = NA) +
          geom_vline(xintercept = WHO_MVPA_MIN, linetype = "dashed",
                     colour = UGENT_REFERENCE_LINE, linewidth = 0.55, alpha = 0.7) +
          annotate("text", x = WHO_MVPA_MIN + 0.5, y = Inf,
                   label = "WHO (60 min)", hjust = 0, vjust = 1.8,
                   colour = UGENT_REFERENCE_LINE, size = 2.8, fontface = "italic") +
          geom_segment(aes(x = mean_mvpa_meting_1, xend = mean_mvpa_meting_2,
                           y = reorder(school_label, mean_mvpa_meting_1),
                           yend = reorder(school_label, mean_mvpa_meting_1),
                           colour = direction),
                       linewidth = 2.0, alpha = 0.80, lineend = "round") +
          geom_errorbar(aes(xmin = mean_mvpa_meting_1 - ci95_meting_1,
                            xmax = mean_mvpa_meting_1 + ci95_meting_1),
                        orientation = "y", width = 0.18,
                        colour = UGENT_TEXT_GRAY, linewidth = 0.55) +
          geom_errorbar(aes(xmin = mean_mvpa_meting_2 - ci95_meting_2,
                            xmax = mean_mvpa_meting_2 + ci95_meting_2),
                        orientation = "y", width = 0.18,
                        colour = UGENT_BLACK, linewidth = 0.55) +
          geom_point(aes(x = mean_mvpa_meting_1), colour = UGENT_TEXT_GRAY, size = 5, shape = 16) +
          geom_point(aes(x = mean_mvpa_meting_2, colour = direction), size = 5, shape = 16) +
          geom_text(aes(x = mean_mvpa_meting_1, label = lbl_m1),
                    nudge_y = 0.35, hjust = 0.5, size = 2.6, colour = UGENT_TEXT_GRAY) +
          geom_text(aes(x = mean_mvpa_meting_2, label = lbl_m2),
                    nudge_y = 0.35, hjust = 0.5, size = 2.6, colour = UGENT_BLACK,
                    fontface = "bold") +
          geom_text(aes(x = (mean_mvpa_meting_1 + mean_mvpa_meting_2) / 2,
                        label = lbl_delta, colour = direction),
                    nudge_y = -0.38, hjust = 0.5, size = 2.5, fontface = "bold") +
          scale_colour_manual(
            values = c("Toename" = UGENT_POSITIVE, "Afname" = UGENT_NEGATIVE),
            name   = "Verandering M1 → M2"
          ) +
          scale_x_continuous(expand = expansion(add = c(6, 6))) +
          labs(x = "Gem. MVPA (min/dag)", y = NULL,
               subtitle = paste0(
                 "Enkel geldige deelnemers · foutbalken = 95% BI",
                 if (n_excl_schools > 0)
                   paste0(" · ", n_excl_schools, " school(s) uitgesloten (ontbreekt ≥1 meting)")
                 else "")) +
          theme_schoolmove(legend_pos = "top") +
          theme(panel.grid.major.y = element_blank(),
                panel.grid.major.x = element_line(colour = UGENT_BORDER_LIGHTER))
      }
    })

    output$plot_activity_stacked <- renderPlot(overview_plot())
    output$dl_plot_overview      <- png_dl(overview_plot, "activiteitsprofiel", width = 2200)

    # ── School overview table ─────────────────────────────────────────────────
    output$table_school_overview <- renderDT({
      mc <- shared$mvpa_col()
      if (is.null(analysis_ready)) return(datatable(data.frame(Bericht = "Geen data")))
      dt <- shared$apply_filters(copy(analysis_ready[meets_sedentary_criteria == TRUE]))
      if (nrow(dt) == 0)
        return(datatable(data.frame(
          Bericht = "Geen geldige deelnemers voor huidige filter.")))
      dt[, school_label := SCHOOL_LABELS[school]]
      has_mvpa  <- !is.null(mc) && mc %in% names(dt)
      has_sleep <- "sleep_duration_h" %in% names(dt)
      if (has_mvpa) dt[, mvpa_val := get(mc)]

      agg <- dt[, {
        mvpa_m  <- if (has_mvpa && "mvpa_val" %in% names(.SD))
                     round(mean(mvpa_val, na.rm = TRUE), 1) else NA_real_
        who_pct <- if (has_mvpa && "mvpa_val" %in% names(.SD))
                     round(100 * mean(mvpa_val >= WHO_MVPA_MIN, na.rm = TRUE)) else NA_integer_
        slaap_m <- if (has_sleep) round(mean(sleep_duration_h, na.rm = TRUE), 1) else NA_real_
        .(
          `N`                   = uniqueN(ID),
          `Gem. MVPA (min/dag)` = mvpa_m,
          `WHO % (num)`         = if (!is.na(who_pct)) who_pct else NA_real_,
          `Gem. slaap (h)`      = if (!is.na(slaap_m)) slaap_m else NA_real_
        )
      }, by = .(School = school_label)]
      agg <- agg[order(School)]

      mvpa_range <- range(agg[["Gem. MVPA (min/dag)"]], na.rm = TRUE)
      if (diff(mvpa_range) == 0) mvpa_range <- c(0, max(mvpa_range, 1))

      datatable(
        agg, rownames = FALSE,
        options = list(dom = "t", pageLength = 10),
        colnames = c("School", "N", "Gem. MVPA (min/dag)", "WHO-norm (%)", "Gem. slaap (h)")
      ) |>
        formatStyle(
          "Gem. MVPA (min/dag)",
          background = styleColorBar(mvpa_range, paste0(ZONE_COLORS["MVPA"], "33")),
          backgroundSize = "98% 65%", backgroundRepeat = "no-repeat",
          backgroundPosition = "left center"
        ) |>
        formatStyle(
          "WHO % (num)",
          color = styleInterval(50, c(UGENT_NEGATIVE, UGENT_POSITIVE)),
          fontWeight = "bold"
        )
    })
  })
}

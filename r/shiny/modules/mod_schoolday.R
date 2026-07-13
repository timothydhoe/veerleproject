# mod_schoolday.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 3 "Schooldag"
# Segment activity charts (single-zone + budget), recess MVPA, weekday profile,
# sedentary bouts dumbbell, segment detail table.
#
# shared list keys used:
#   apply_filters    — session-scoped filter function from server.R
#   safe_meting_val  — reactive returning safe_meting() (meting-only filter
#                      needed for weekday_plot which always shows all schools)
#
# Global objects accessed directly (defined in global.R):
#   segment_summary, analysis_ready, SCHOOL_LABELS, SCHOOL_COLORS,
#   METINGEN_LABELS, WHO_MVPA_MIN, ZONE_COLORS
#   no_data_plot(), png_dl(), theme_schoolmove() — util_plots.R
#   apply_global_filters_pure()                  — util_filters.R
# ─────────────────────────────────────────────────────────────────────────────

#' Schoolday tab UI
modSchooldayUI <- function(id) {
  ns <- NS(id)
  tagList(
    fallback_banner(),
    layout_sidebar(
      sidebar = sidebar(
        width = 230,
        radioButtons(ns("seg_view"), "Hoofdgrafiek",
                     choices  = c("Één zone" = "single", "Alle zones" = "budget"),
                     selected = "single"),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'single'", ns("seg_view")),
          selectInput(ns("seg_metric"), "Zone",
                      choices = c(
                        "MVPA (min/dag)"         = "mvpa",
                        "Licht actief (min/dag)" = "lig",
                        "Sedentair (min/dag)"    = "sb"
                      ))
        )
      ),
      layout_columns(
        col_widths = c(7, 5),
        chart_card(
          header   = "Activiteit per schooldagsegment",
          plot_id  = ns("plot_segment_activity"),
          dl_id    = ns("dl_plot_segment"),
          height   = "480px",
          subtitle = "Gem. min/dag per activiteitszone voor elk deel van de schooldag (Ma–Vr) · enkel geldige deelnemers"
        ),
        chart_card(
          header   = "MVPA tijdens pauze per school",
          plot_id  = ns("plot_recess_mvpa"),
          dl_id    = ns("dl_plot_recess"),
          height   = "320px",
          subtitle = "Matig-tot-intensieve beweging specifiek tijdens de pauze"
        )
      ),
      card(
        class       = "shadow-sm",
        full_screen = TRUE,
        card_header(
          div(
            style = "display:flex; justify-content:space-between; align-items:center;",
            span("Weekdag activiteitsprofiel"),
            radioButtons(ns("seg_weekday"), NULL, inline = TRUE,
                         choices  = c("Schooldagen (Ma–Vr)" = "schooldays",
                                      "Weekend (Za & Zo)"   = "weekend"),
                         selected = "schooldays")
          )
        ),
        card_body(
          class = "p-3",
          p(class = "text-muted small mb-2",
            "Gem. MVPA per dag per school · lijn = gem., band = 95% BI"),
          plotOutput(ns("plot_weekday"), height = "320px")
        ),
        card_footer(
          class = "d-flex justify-content-end py-1",
          downloadButton(ns("dl_plot_weekday"), "PNG opslaan",
                         icon  = icon("download"),
                         class = "btn-outline-secondary btn-sm")
        )
      ),
      card(
        class       = "shadow-sm",
        full_screen = TRUE,
        card_header(
          tip("Sedentaire bouten",
              "Aaneengesloten perioden van inactiviteit. Langdurig zitten (≥30 min) is een onafhankelijke gezondheidsrisicofactor.")
        ),
        card_body(
          p(class = "text-muted small mb-2",
            "Gem. aantal aaneengesloten sedentaire perioden (≥30 min) per dag · foutbalken = 95% BI"),
          plotOutput(ns("plot_bouts"), height = "280px")
        )
      ),
      card(
        class       = "shadow-sm",
        full_screen = TRUE,
        card_header("Detailtabel per segment"),
        card_body(DTOutput(ns("table_segment_detail")))
      )
    )
  )
}

#' Schoolday tab server
mod_schoolday_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    # ── Filtered segment data ─────────────────────────────────────────────────
    seg_filtered <- reactive({
      if (is.null(segment_summary)) return(NULL)
      shared$apply_filters(copy(segment_summary))
    })

    # ── Segment activity bar chart ────────────────────────────────────────────
    seg_plot <- reactive({
      dt <- seg_filtered()
      if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())

      metric_col_name <- switch(input$seg_metric,
        mvpa = grep("^dur_MOD|^dur_VIG", names(dt), value = TRUE, ignore.case = TRUE)[1],
        lig  = grep("^dur_LIG",          names(dt), value = TRUE, ignore.case = TRUE)[1],
        sb   = grep("^dur_IN",           names(dt), value = TRUE, ignore.case = TRUE)[1]
      )
      if (input$seg_metric == "mvpa") {
        mod_c <- grep("^dur_MOD", names(dt), value = TRUE)[1]
        vig_c <- grep("^dur_VIG", names(dt), value = TRUE)[1]
        if (!is.na(mod_c) && !is.na(vig_c)) {
          dt[, mvpa_seg := get(mod_c) + get(vig_c)]
          metric_col_name <- "mvpa_seg"
        }
      }
      if (is.null(metric_col_name) || is.na(metric_col_name))
        return(no_data_plot("Activiteitskolom niet gevonden — voer de volledige pipeline opnieuw uit."))

      school_day_segs <- c("before_school","in_class","recess","lunch","after_school")
      agg <- dt[segment %in% school_day_segs, {
        n    <- .N
        mu   <- mean(get(metric_col_name), na.rm = TRUE)
        ci95 <- qt(0.975, n - 1) * sd(get(metric_col_name), na.rm = TRUE) / sqrt(n)
        .(mean_val = mu, ci95 = ci95, n = n)
      }, by = .(school_label, segment_label)]
      if (nrow(agg) == 0) return(no_data_plot())

      y_label <- switch(input$seg_metric,
        mvpa = "Gem. MVPA (min/dag)", lig = "Gem. LPA (min/dag)",
        sb   = "Gem. sedentair (min/dag)")
      mv         <- shared$safe_meting_val()
      meting_sub <- if (mv == "all") "alle metingen gecombineerd" else METINGEN_LABELS[mv]

      p <- ggplot(agg, aes(x = segment_label, y = mean_val, fill = school_label)) +
        geom_col(position = position_dodge(0.75), width = 0.7) +
        geom_errorbar(aes(ymin = mean_val - ci95, ymax = mean_val + ci95),
                      position = position_dodge(0.75), width = 0.25,
                      colour = "grey25", linewidth = 0.55) +
        scale_fill_manual(values = SCHOOL_COLORS) +
        scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
        labs(x = NULL, y = y_label, fill = NULL,
             subtitle = paste(meting_sub, "· foutbalken = 95% BI")) +
        theme_schoolmove() +
        theme(axis.text.x = element_text(angle = 0, hjust = 0.5))

      if (input$seg_metric == "mvpa")
        p <- p +
          geom_hline(yintercept = WHO_MVPA_MIN, linetype = "dashed",
                     colour = "#E74C3C", linewidth = 0.7) +
          annotate("text", x = Inf, y = WHO_MVPA_MIN + 1,
                   label = "WHO: 60 min/dag", hjust = 1.05, colour = "#E74C3C", size = 3.2)
      p
    })

    # ── Activity budget stacked chart ─────────────────────────────────────────
    budget_plot <- reactive({
      if (is.null(segment_summary)) return(no_data_plot("Geen segmentdata."))
      school_day_segs <- c("before_school","in_class","recess","lunch","after_school")
      dt <- shared$apply_filters(copy(segment_summary[segment %in% school_day_segs]))
      if (nrow(dt) == 0) return(no_data_plot())

      mod_c <- grep("^dur_MOD", names(dt), value = TRUE)[1]
      vig_c <- grep("^dur_VIG", names(dt), value = TRUE)[1]
      lpa_c <- grep("^dur_LIG", names(dt), value = TRUE)[1]
      sb_c  <- grep("^dur_IN",  names(dt), value = TRUE)[1]

      if (any(is.na(c(mod_c, vig_c, lpa_c, sb_c))))
        return(no_data_plot("Activiteitszones niet gevonden in segmentdata."))

      dt[, mvpa_val := get(mod_c) + get(vig_c)]

      agg <- dt[, .(
        SB   = mean(get(sb_c),  na.rm = TRUE),
        LPA  = mean(get(lpa_c), na.rm = TRUE),
        MVPA = mean(mvpa_val,   na.rm = TRUE)
      ), by = .(school_label, segment_label, meting)]
      agg[, meting_label := METINGEN_LABELS[meting]]

      long <- melt(agg[, .(school_label, segment_label, meting_label, SB, LPA, MVPA)],
                   id.vars = c("school_label","segment_label","meting_label"),
                   variable.name = "zone", value.name = "min_dag")
      long[, zone := factor(zone, levels = c("SB","LPA","MVPA"))]

      ggplot(long, aes(x = school_label, y = min_dag, fill = zone)) +
        geom_col(position = "stack", width = 0.75) +
        scale_fill_manual(values = ZONE_COLORS,
                          labels = c(SB = "Sedentair", LPA = "Licht actief", MVPA = "MVPA")) +
        scale_y_continuous(expand = expansion(mult = c(0, 0.06))) +
        facet_grid(segment_label ~ meting_label) +
        labs(x = NULL, y = "Gem. min/dag", fill = NULL,
             subtitle = "SB / LPA / MVPA per segment · rijen = segment, kolommen = meting") +
        theme_schoolmove() +
        theme(axis.text.x  = element_text(angle = 30, hjust = 1, size = 7),
              strip.text.y = element_text(size = 8, face = "bold", angle = 0),
              strip.text.x = element_text(size = 9, face = "bold"),
              legend.position = "top")
    })

    # ── Weekday profile (all schools, meting filter only) ─────────────────────
    weekday_plot <- reactive({
      if (is.null(segment_summary)) return(no_data_plot("Geen segmentdata."))
      dt <- copy(segment_summary)

      mod_c <- grep("^dur_MOD", names(dt), value = TRUE)[1]
      vig_c <- grep("^dur_VIG", names(dt), value = TRUE)[1]
      if (is.na(mod_c) || is.na(vig_c)) return(no_data_plot())
      if (!all(c("date", "weekday") %in% names(dt))) return(no_data_plot())
      dt[, mvpa_val := get(mod_c) + get(vig_c)]

      daily <- dt[, .(mvpa_day = sum(mvpa_val, na.rm = TRUE)),
                  by = .(ID, school_label, meting, date, weekday)]

      if (isTRUE(input$seg_weekday == "weekend")) {
        wd_order <- c("Saturday","Sunday")
        wd_nl    <- c(Saturday = "Za", Sunday = "Zo")
      } else {
        wd_order <- c("Monday","Tuesday","Wednesday","Thursday","Friday")
        wd_nl    <- c(Monday = "Ma", Tuesday = "Di", Wednesday = "Wo",
                      Thursday = "Do", Friday = "Vr")
      }

      # Apply meting filter only (school filter intentionally skipped — all schools shown)
      mv <- shared$safe_meting_val()
      daily <- apply_global_filters_pure(daily, "all", mv)

      agg <- daily[weekday %in% wd_order,
                   .(mean_mvpa = mean(mvpa_day, na.rm = TRUE),
                     ci95 = qt(0.975, max(.N - 1, 1)) * sd(mvpa_day, na.rm = TRUE) / sqrt(.N)),
                   by = .(school_label, meting, weekday)]
      agg[, meting_label := METINGEN_LABELS[meting]]
      agg <- agg[weekday %in% wd_order]
      agg[, weekday_f := factor(wd_nl[weekday], levels = wd_nl)]

      if (nrow(agg) == 0) return(no_data_plot("Geen data voor geselecteerd dagtype."))

      dag_type <- if (isTRUE(input$seg_weekday == "weekend")) "weekenddagen"
                  else "schooldagen (Ma–Vr)"

      ggplot(agg, aes(x = weekday_f, y = mean_mvpa, colour = school_label,
                      group = school_label)) +
        geom_ribbon(aes(ymin = mean_mvpa - ci95, ymax = mean_mvpa + ci95,
                        fill = school_label),
                    alpha = 0.12, colour = NA) +
        geom_line(linewidth = 1.2) +
        geom_point(size = 2.5) +
        scale_colour_manual(values = SCHOOL_COLORS) +
        scale_fill_manual(values = SCHOOL_COLORS, guide = "none") +
        scale_y_continuous(expand = expansion(mult = c(0.02, 0.1))) +
        facet_wrap(~ meting_label) +
        labs(x = NULL, y = "Gem. MVPA (min/dag)", colour = NULL,
             subtitle = paste0("Totale MVPA per dag (", dag_type, ") · lint = 95% BI")) +
        theme_schoolmove() +
        theme(strip.text = element_text(face = "bold", size = 11))
    })

    # ── Recess MVPA bar chart ─────────────────────────────────────────────────
    recess_plot <- reactive({
      dt <- seg_filtered()
      if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())
      recess_dt <- dt[segment == "recess"]
      if (nrow(recess_dt) == 0) return(no_data_plot("Geen pauzedata gevonden."))

      mod_c <- grep("^dur_MOD", names(recess_dt), value = TRUE)[1]
      vig_c <- grep("^dur_VIG", names(recess_dt), value = TRUE)[1]
      if (!is.na(mod_c) && !is.na(vig_c)) {
        recess_dt[, mvpa_seg := get(mod_c) + get(vig_c)]
        mvpa_col_s <- "mvpa_seg"
      } else {
        mvpa_col_s <- grep("^(dur_MOD|dur_VIG|MVPA)", names(recess_dt),
                           value = TRUE, ignore.case = TRUE)[1]
      }
      if (is.null(mvpa_col_s) || is.na(mvpa_col_s)) return(no_data_plot())

      agg <- recess_dt[, {
        n  <- .N
        mu <- mean(get(mvpa_col_s), na.rm = TRUE)
        ci <- qt(0.975, n - 1) * sd(get(mvpa_col_s), na.rm = TRUE) / sqrt(n)
        .(mean_mvpa = mu, ci95 = ci, n = n)
      }, by = school_label]

      ggplot(agg, aes(x = reorder(school_label, mean_mvpa), y = mean_mvpa,
                      fill = school_label)) +
        geom_col(show.legend = FALSE) +
        geom_errorbar(aes(ymin = mean_mvpa - ci95, ymax = mean_mvpa + ci95),
                      width = 0.25, colour = "grey30") +
        geom_text(aes(y = mean_mvpa + ci95 + 0.3, label = paste0("n=", n)),
                  size = 3, colour = "grey40", hjust = 0) +
        scale_fill_manual(values = SCHOOL_COLORS) +
        scale_y_continuous(expand = expansion(mult = c(0, 0.28))) +
        coord_flip() +
        labs(x = NULL, y = "Gem. MVPA (min)",
             subtitle = "Beweging tijdens pauze · foutbalken = 95% BI") +
        theme_schoolmove(legend_pos = "none")
    })

    # ── Sedentary bouts dumbbell ──────────────────────────────────────────────
    bouts_plot <- reactive({
      if (is.null(analysis_ready) || !"bouts_30min_day" %in% names(analysis_ready))
        return(no_data_plot("Sedentaire boutdata niet beschikbaar — voer de volledige pipeline opnieuw uit."))
      dt <- copy(analysis_ready[meets_sedentary_criteria == TRUE & !is.na(bouts_30min_day)])
      dt <- shared$apply_filters(dt)
      if (nrow(dt) == 0) return(no_data_plot("Geen data voor huidige filter."))
      dt[, school_label := SCHOOL_LABELS[school]]

      agg <- dt[, {
        n  <- .N
        mu <- mean(bouts_30min_day, na.rm = TRUE)
        ci <- qt(0.975, n - 1) * sd(bouts_30min_day, na.rm = TRUE) / sqrt(n)
        .(mean_bouts = mu, ci95 = ci, n = n)
      }, by = .(school_label, meting)]

      wide <- dcast(agg, school_label ~ meting, value.var = c("mean_bouts", "ci95", "n"))

      if (!all(c("mean_bouts_meting_1", "mean_bouts_meting_2") %in% names(wide))) {
        ggplot(agg, aes(y = reorder(school_label, mean_bouts), x = mean_bouts,
                        colour = school_label)) +
          geom_pointrange(aes(xmin = mean_bouts - ci95, xmax = mean_bouts + ci95),
                          size = 0.6, linewidth = 0.9) +
          scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
          labs(x = "Gem. bouten per dag (≥30 min)", y = NULL,
               subtitle = "Aaneengesloten sedentaire perioden · lijnen = 95% BI") +
          theme_schoolmove(legend_pos = "none")
      } else {
        wide <- wide[!is.na(mean_bouts_meting_1) & !is.na(mean_bouts_meting_2)]
        wide[, delta     := mean_bouts_meting_2 - mean_bouts_meting_1]
        wide[, direction := ifelse(delta <= 0, "Afname (positief)", "Toename")]

        ggplot(wide, aes(y = reorder(school_label, -mean_bouts_meting_1))) +
          geom_segment(aes(x = mean_bouts_meting_1, xend = mean_bouts_meting_2,
                           y = reorder(school_label, -mean_bouts_meting_1),
                           yend = reorder(school_label, -mean_bouts_meting_1)),
                       colour = "#DFE1E6", linewidth = 2.0, lineend = "round") +
          geom_point(aes(x = mean_bouts_meting_1), colour = "#97A0AF", size = 5, shape = 16) +
          geom_point(aes(x = mean_bouts_meting_2, colour = direction), size = 5, shape = 16) +
          geom_text(aes(x = mean_bouts_meting_2,
                        label = paste0(ifelse(delta <= 0, "", "+"), round(delta, 1))),
                    nudge_y = 0.32, hjust = 0.5, size = 2.6,
                    colour = "#172B4D", fontface = "bold") +
          scale_colour_manual(
            values = c("Afname (positief)" = "#36B37E", "Toename" = "#FF5630"),
            name   = NULL
          ) +
          scale_x_continuous(expand = expansion(add = c(0.5, 0.8))) +
          labs(x = "Gem. bouten per dag (≥30 min)", y = NULL,
               subtitle = "Grijs = M1 · kleur = M2 · afname sedentaire bouten = gezondheidswinst") +
          theme_schoolmove(legend_pos = "top") +
          theme(panel.grid.major.y = element_blank())
      }
    })

    # ── Render outputs ────────────────────────────────────────────────────────
    output$plot_segment_activity <- renderPlot({
      if (isTRUE(input$seg_view == "budget")) budget_plot() else seg_plot()
    })
    output$plot_recess_mvpa <- renderPlot(recess_plot())
    output$plot_weekday     <- renderPlot(weekday_plot())
    output$plot_bouts       <- renderPlot(bouts_plot())

    output$dl_plot_segment <- png_dl(
      function() if (isTRUE(input$seg_view == "budget")) budget_plot() else seg_plot(),
      "schooldag_activiteit", width = 2200, height = 1100)
    output$dl_plot_recess  <- png_dl(recess_plot, "pauze_mvpa")
    output$dl_plot_weekday <- png_dl(weekday_plot, "weekdag_profiel", width = 2000)

    # ── Segment detail table ──────────────────────────────────────────────────
    output$table_segment_detail <- renderDT({
      dt <- seg_filtered()
      if (is.null(dt) || nrow(dt) == 0) return(datatable(data.frame(Bericht = "Geen data")))
      intensity_cols <- grep("^(dur_IN|dur_LIG|dur_MOD|dur_VIG)", names(dt),
                             value = TRUE, ignore.case = TRUE)
      agg <- dt[, c(list(n_dagen = .N),
                    lapply(.SD, function(x) round(mean(x, na.rm = TRUE), 1))),
                 by = .(School = school_label, Segment = segment_label,
                        Meting = METINGEN_LABELS[meting]), .SDcols = intensity_cols]
      col_rename <- c(
        dur_IN_min  = "Sedentair (min)", dur_IN_sec  = "Sedentair (s)",
        dur_LIG_min = "Licht actief (min)", dur_LIG_sec = "Licht actief (s)",
        dur_MOD_min = "Matig actief (min)", dur_MOD_sec = "Matig actief (s)",
        dur_VIG_min = "Intensief actief (min)", dur_VIG_sec = "Intensief actief (s)"
      )
      for (raw in intersect(names(col_rename), names(agg)))
        setnames(agg, raw, col_rename[raw])
      datatable(agg, rownames = FALSE,
                options = list(pageLength = 20, dom = "frtip", scrollX = TRUE),
                filter = "top")
    })
  })
}

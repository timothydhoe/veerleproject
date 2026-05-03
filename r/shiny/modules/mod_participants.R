# mod_participants.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 2 "Deelnemers"
# Participant explorer dropdown, wear heatmap, individual MVPA + segment plots,
# inclusion/exclusion table with row-click → explorer sync.
#
# shared list keys used:
#   apply_filters     — session-scoped filter function from server.R
#   mvpa_col          — reactive returning MVPA column name (character or NULL)
#   global_school_val — reactive for input$global_school
#
# Global objects accessed directly (defined in global.R):
#   analysis_ready, validity_summary, segment_summary, part2,
#   SCHOOL_LABELS, METINGEN_LABELS, ZONE_COLORS,
#   WHO_MVPA_MIN, MIN_WEAR_H, MIN_DAYS, NEED_WKND
#   no_data_plot(), png_dl(), theme_schoolmove() — util_plots.R
# ─────────────────────────────────────────────────────────────────────────────

#' Participants tab UI
modParticipantsUI <- function(id) {
  ns <- NS(id)
  layout_sidebar(
    sidebar = sidebar(
      width = 240,
      p(class = "text-muted small fw-semibold mb-1", "Deelnemer bekijken"),
      selectInput(ns("explorer_id"), NULL,
                  choices = c("Kies een deelnemer..." = ""),
                  width   = "100%"),
      helpText(class = "text-muted", style = "font-size:0.75rem;",
               "Of klik een rij in de inclusietabel hieronder.")
    ),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(header  = "MVPA per dag",
                 plot_id = ns("plot_explorer_mvpa"),
                 dl_id   = ns("dl_plot_explorer_mvpa"),
                 height  = "380px"),
      chart_card(header  = "Activiteit per segment (M1 vs M2)",
                 plot_id = ns("plot_explorer_segments"),
                 dl_id   = ns("dl_plot_explorer_segments"),
                 height  = "380px")
    ),
    chart_card(
      header   = "Draagduuroverzicht",
      plot_id  = ns("plot_wear_heatmap"),
      dl_id    = ns("dl_plot_wear"),
      height   = "500px",
      subtitle = paste0("Groen = geldig (≥", MIN_WEAR_H,
                        "h draagduur) · rood = onvoldoende of niet gedragen")
    ),
    card(
      class       = "shadow-sm",
      full_screen = TRUE,
      card_header("Inclusie / exclusie"),
      card_body(
        div(
          style = "display:flex; align-items:center; gap:16px; margin-bottom:10px; flex-wrap:wrap;",
          div(style = "font-size:0.82rem; font-weight:600; color:#475569;", "Filter:"),
          radioButtons(
            ns("incl_status_filter"), NULL,
            choices  = c("Alle" = "all", "Inbegrepen" = "included",
                         "Uitgesloten" = "excluded"),
            selected = "all",
            inline   = TRUE
          )
        ),
        p(class = "text-muted small",
          "Deelnemers die niet voldoen aan het minimumaantal geldige draagdagen",
          "worden uitgesloten van de sedentaire analyse.",
          strong(" Klik een rij om die deelnemer te bekijken.")),
        DTOutput(ns("table_inclusion"))
      )
    )
  )
}

#' Participants tab server
mod_participants_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    # ── Wear heatmap ──────────────────────────────────────────────────────────
    part2_filtered <- reactive({
      if (nrow(part2) == 0) return(part2)
      shared$apply_filters(copy(part2))
    })

    wear_plot <- reactive({
      dt <- part2_filtered()
      if (nrow(dt) == 0) return(no_data_plot())

      selected_pid <- input$explorer_id
      if (!is.null(selected_pid) && nchar(selected_pid) > 0) {
        pid_clean <- sub("\\.csv$", "", selected_pid)
        dt_pid    <- dt[sub("\\.csv$", "", as.character(ID)) == pid_clean]
        if (nrow(dt_pid) > 0) dt <- dt_pid
      }

      school_val   <- shared$global_school_val()
      single_school <- school_val != "all" || (!is.null(selected_pid) && nchar(selected_pid) > 0)

      date_col <- intersect(c("calendar_date","Date","date"), names(dt))
      if (length(date_col) > 0) {
        dt[, day_label := as.character(as.Date(get(date_col[1])))]
      } else {
        dt[, day_label := paste0("Dag ", formatC(seq_len(.N), width = 2, flag = "0")),
           by = ID]
      }
      dt[, school_label := SCHOOL_LABELS[school]]

      if (!single_school) {
        agg <- dt[, .(pct_valid = round(100 * mean(valid_day, na.rm = TRUE)),
                       n_pupils  = uniqueN(ID)),
                   by = .(school_label, day_label, meting)]
        agg[, meting_label := METINGEN_LABELS[meting]]

        ggplot(agg, aes(x = day_label, y = school_label, fill = pct_valid,
                         text = paste0(school_label, "\nDatum: ", day_label,
                                       "\n% geldig: ", pct_valid, "%\nn leerlingen: ", n_pupils))) +
          geom_tile(colour = "white", linewidth = 0.5) +
          scale_fill_gradient(low = "#F5B7B1", high = "#27AE60",
                              limits = c(0, 100), name = "% geldig") +
          facet_wrap(~ meting_label, scales = "free_x") +
          labs(x = "Datum", y = NULL,
               title = "Draagduur overzicht — alle scholen",
               subtitle = paste0("% geldige dagen per school (drempelwaarde: ≥", MIN_WEAR_H, "h)")) +
          theme_schoolmove() +
          theme(axis.text.x  = element_text(angle = 45, hjust = 1, size = 8),
                panel.grid   = element_blank(),
                legend.position = "right")
      } else {
        id_order <- dt[order(school_label, ID), unique(ID)]
        dt[, ID_f := factor(ID, levels = rev(id_order))]

        ggplot(dt, aes(x = day_label, y = ID_f, fill = valid_day)) +
          geom_tile(colour = "white", linewidth = 0.3) +
          scale_fill_manual(
            values = c("TRUE" = "#27AE60", "FALSE" = "#E74C3C"),
            labels = c("TRUE" = "Geldig", "FALSE" = "Ongeldig/niet-dragen"),
            name   = NULL
          ) +
          facet_wrap(~ meting, scales = "free_x", labeller = as_labeller(METINGEN_LABELS)) +
          labs(x = "Datum", y = NULL,
               title = paste("Draagduur —", SCHOOL_LABELS[school_val]),
               subtitle = paste0("Groen = geldige dag (≥", MIN_WEAR_H, "h)")) +
          theme_schoolmove() +
          theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
                axis.text.y = element_text(size = 7),
                panel.grid  = element_blank())
      }
    })

    output$plot_wear_heatmap <- renderPlot(wear_plot())

    # Height depends on filter at download time, so written as direct downloadHandler
    output$dl_plot_wear <- downloadHandler(
      filename = function() paste0("draagduur_heatmap_", format(Sys.Date(), "%Y%m%d"), ".png"),
      content  = function(f) {
        h <- if (shared$global_school_val() == "all") 700 else 1200
        png(f, width = 2000, height = h, res = 180)
        print(wear_plot())
        dev.off()
      }
    )

    # ── Individual explorer ───────────────────────────────────────────────────
    explorer_day_data <- reactive({
      req(input$explorer_id, nchar(input$explorer_id) > 0)
      if (is.null(segment_summary)) return(NULL)
      dt <- segment_summary[as.character(ID) == input$explorer_id]
      if (nrow(dt) == 0) return(NULL)
      mod_c <- grep("^dur_MOD", names(dt), value = TRUE)[1]
      vig_c <- grep("^dur_VIG", names(dt), value = TRUE)[1]
      if (is.na(mod_c) || is.na(vig_c)) return(NULL)
      dt[, mvpa_seg := get(mod_c) + get(vig_c)]
      dt
    })

    explorer_mvpa_plot <- reactive({
      dt <- explorer_day_data()
      if (is.null(dt)) return(no_data_plot("Selecteer een deelnemer."))
      daily <- dt[, .(mvpa_day = sum(mvpa_seg, na.rm = TRUE)),
                  by = .(calendar_date, meting)]
      daily[, meting_label := METINGEN_LABELS[meting]]
      daily[, date_f := as.Date(calendar_date)]
      if (nrow(daily) == 0) return(no_data_plot("Geen dagdata beschikbaar."))
      ggplot(daily, aes(x = date_f, y = mvpa_day, colour = meting_label, group = meting_label)) +
        geom_line(linewidth = 0.9) +
        geom_point(size = 2) +
        geom_hline(yintercept = WHO_MVPA_MIN, linetype = "dashed",
                   colour = "#E74C3C", linewidth = 0.6) +
        scale_colour_manual(values = c("Meting 1" = "#3498DB", "Meting 2" = "#E67E22")) +
        scale_y_continuous(expand = expansion(mult = c(0.02, 0.1))) +
        labs(x = NULL, y = "MVPA (min/dag)", colour = NULL,
             subtitle = paste0("ID: ", input$explorer_id,
                               " · rode lijn = WHO-norm (60 min/dag)")) +
        theme_schoolmove(legend_pos = "top") +
        theme(axis.text.x = element_text(angle = 30, hjust = 1, size = 8))
    })

    explorer_seg_plot <- reactive({
      dt <- explorer_day_data()
      if (is.null(dt)) return(no_data_plot("Selecteer een deelnemer."))
      school_day_segs <- c("before_school","in_class","recess","lunch","after_school")
      dt_s <- dt[segment %in% school_day_segs]
      if (nrow(dt_s) == 0) return(no_data_plot("Geen segmentdata beschikbaar."))
      sb_c  <- grep("^dur_IN",  names(dt_s), value = TRUE)[1]
      lpa_c <- grep("^dur_LIG", names(dt_s), value = TRUE)[1]
      if (is.na(sb_c) || is.na(lpa_c))
        return(no_data_plot("SB/LPA-kolommen niet gevonden in segmentdata."))
      agg <- dt_s[, .(
        SB   = mean(get(sb_c),  na.rm = TRUE),
        LPA  = mean(get(lpa_c), na.rm = TRUE),
        MVPA = mean(mvpa_seg,   na.rm = TRUE)
      ), by = .(segment_label, meting)]
      agg[, meting_label := METINGEN_LABELS[meting]]
      long <- melt(agg, id.vars = c("segment_label", "meting_label"),
                   measure.vars = c("SB", "LPA", "MVPA"),
                   variable.name = "zone", value.name = "min_seg")
      long[, zone := factor(zone, levels = c("SB","LPA","MVPA"))]
      ggplot(long, aes(x = segment_label, y = min_seg, fill = zone)) +
        geom_col(position = "stack", width = 0.7) +
        facet_wrap(~ meting_label) +
        scale_fill_manual(values = ZONE_COLORS,
                          labels = c(SB = "Sedentair", LPA = "Licht", MVPA = "MVPA")) +
        scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
        labs(x = NULL, y = "Gem. min/segment", fill = NULL,
             subtitle = "Gem. over alle geldige schooldagen") +
        theme_schoolmove(legend_pos = "top") +
        theme(axis.text.x = element_text(angle = 20, hjust = 1, size = 8))
    })

    output$plot_explorer_mvpa       <- renderPlot(explorer_mvpa_plot())
    output$plot_explorer_segments   <- renderPlot(explorer_seg_plot())
    output$dl_plot_explorer_mvpa    <- png_dl(explorer_mvpa_plot,  "deelnemer_mvpa")
    output$dl_plot_explorer_segments <- png_dl(explorer_seg_plot, "deelnemer_segmenten")

    # ── Inclusion table ───────────────────────────────────────────────────────
    output$table_inclusion <- renderDT({
      if (is.null(validity_summary)) return(datatable(data.frame(Bericht = "Geen data")))
      dt <- shared$apply_filters(copy(validity_summary))
      dt[, school_label := SCHOOL_LABELS[school]]
      dt[, meting_label := METINGEN_LABELS[meting]]
      dt[, status := ifelse(meets_sedentary_criteria, "Inbegrepen", "Uitgesloten")]
      dt[, reden  := fifelse(is.na(exclusion_reason), "—", exclusion_reason)]

      sf <- input$incl_status_filter
      if (!is.null(sf) && sf == "included") dt <- dt[meets_sedentary_criteria == TRUE]
      if (!is.null(sf) && sf == "excluded") dt <- dt[meets_sedentary_criteria == FALSE]

      if (!is.null(analysis_ready)) {
        mc <- shared$mvpa_col()
        ar_cols <- c("ID", "school", "meting")
        if (!is.null(mc) && mc %in% names(analysis_ready)) ar_cols <- c(ar_cols, mc)
        if ("sleep_duration_h" %in% names(analysis_ready))  ar_cols <- c(ar_cols, "sleep_duration_h")
        ar_sub <- analysis_ready[, ar_cols, with = FALSE]
        if (!is.null(mc) && mc %in% names(ar_sub)) setnames(ar_sub, mc, "mvpa_avg")
        dt <- merge(dt, ar_sub, by = c("ID", "school", "meting"), all.x = TRUE)
        if ("mvpa_avg" %in% names(dt))          dt[, mvpa_avg := round(mvpa_avg, 1)]
        if ("sleep_duration_h" %in% names(dt))  dt[, sleep_duration_h := round(sleep_duration_h, 1)]
      }

      setnames(dt,
        c("ID","school_label","meting_label","n_valid_days","mean_wear_h","status","reden"),
        c("ID","School","Meting","Geldige dagen","Gem. draagduur (h)","Status","Reden"),
        skip_absent = TRUE)
      base_cols  <- c("ID","School","Meting","Geldige dagen","Gem. draagduur (h)")
      extra_cols <- character(0)
      if ("mvpa_avg" %in% names(dt)) {
        setnames(dt, "mvpa_avg", "MVPA (min/dag)", skip_absent = TRUE)
        extra_cols <- c(extra_cols, "MVPA (min/dag)")
      }
      if ("sleep_duration_h" %in% names(dt)) {
        setnames(dt, "sleep_duration_h", "Slaap (h/nacht)", skip_absent = TRUE)
        extra_cols <- c(extra_cols, "Slaap (h/nacht)")
      }
      all_cols <- intersect(c(base_cols, extra_cols, "Status","Reden"), names(dt))
      wknd_txt    <- if (NEED_WKND) "incl. 1 weekenddag" else "geen weekendvereiste"
      caption_txt <- htmltools::tags$caption(
        style = "caption-side:bottom; font-size:0.78rem; color:#64748b; padding:4px 0;",
        sprintf(
          "Inclusiecriterium: ≥%g geldige draagdagen (%s) · ≥%g uur/dag draagduur",
          MIN_DAYS, wknd_txt, MIN_WEAR_H
        )
      )
      datatable(dt[, ..all_cols], rownames = FALSE,
                caption   = caption_txt,
                selection = "single",
                options   = list(pageLength = 15, dom = "frtip", scrollX = TRUE),
                filter    = "top") |>
        formatStyle("Status",
          backgroundColor = styleEqual(c("Inbegrepen","Uitgesloten"),
                                       c("#d4edda","#f8d7da")))
    })

    # ── Populate explorer dropdown from filtered analysis_ready ───────────────
    observe({
      choices <- if (is.null(analysis_ready)) character(0) else {
        dt <- shared$apply_filters(copy(analysis_ready))
        sort(unique(as.character(dt$ID)))
      }
      updateSelectInput(session, "explorer_id",
                        choices = c("Kies een deelnemer..." = "", choices))
    })

    # ── Row click in inclusion table → pre-fill explorer_id ──────────────────
    observeEvent(input$table_inclusion_rows_selected, {
      row_idx <- input$table_inclusion_rows_selected
      if (length(row_idx) == 0 || is.null(validity_summary)) return()
      dt <- shared$apply_filters(copy(validity_summary))
      if (row_idx > nrow(dt)) return()
      selected_id <- as.character(dt$ID[row_idx])
      updateSelectInput(session, "explorer_id", selected = selected_id)
    })
  })
}

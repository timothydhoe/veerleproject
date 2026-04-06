# server.R
# ─────────────────────────────────────────────────────────────────────────────
# Reactive logic for the SchoolMove dashboard.
# ─────────────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ── Shared constants ──────────────────────────────────────────────────────────
  INT_PERS <- c(SB  = "dur_day_total_IN_min_pla",
                LPA = "dur_day_total_LIG_min_pla",
                MPA = "dur_day_total_MOD_min_pla",
                VPA = "dur_day_total_VIG_min_pla")

  INT_COLOURS <- c(SB = "#d1e5f0", LPA = "#92c5de",
                   MPA = "#f4a582", VPA = "#ca0020")

  SCHOOL_COLOURS <- c(
    school_1 = "#4e79a7", school_2 = "#f28e2b", school_3 = "#e15759",
    school_4 = "#76b7b2", school_5 = "#59a14f", school_6 = "#b07aa1"
  )

  no_data_plot <- function(msg = "No data available for this selection.") {
    ggplot() +
      annotate("text", x = 0.5, y = 0.5, label = msg,
               size = 4.5, hjust = 0.5, vjust = 0.5) +
      theme_void()
  }

  filter_dt <- function(dt, school_input, meting_input) {
    if (is.null(dt) || nrow(dt) == 0) return(dt)
    out <- copy(dt)
    if (!is.null(school_input) && school_input != "All schools")
      out <- out[school == school_input]
    if (!is.null(meting_input) && meting_input != "Both")
      out <- out[meting == meting_input]
    out
  }

  intensity_long <- function(dt, col_map, id_cols) {
    avail <- col_map[col_map %in% names(dt)]
    if (length(avail) == 0) return(NULL)
    long <- melt(dt[, c(id_cols, avail), with = FALSE],
                 id.vars = id_cols,
                 variable.name = "col", value.name = "minutes")
    inv  <- setNames(names(avail), avail)
    long[, intensity := factor(inv[as.character(col)], levels = names(INT_COLOURS))]
    long[, col := NULL]
    long
  }

  # ── Overview tab ─────────────────────────────────────────────────────────────
  output$overview_cards <- renderUI({
    if (nrow(participant_validity) == 0)
      return(p("No pipeline output found. Run pipeline/01_run_ggir.R first."))

    summary <- participant_validity[
      , .(n = uniqueN(ID), valid = sum(meets_criteria, na.rm = TRUE)),
      by = school
    ]

    cards <- lapply(seq_len(nrow(summary)), function(i) {
      row   <- summary[i]
      dates <- cfg$measurements[[row$school]]
      date_str <- if (!is.null(dates))
        paste0("M1: ", dates$meting_1$start, " – ", dates$meting_1$end,
               "  |  M2: ", dates$meting_2$start, " – ", dates$meting_2$end)
      else ""
      layout_columns(
        col_widths = 2,
        value_box(
          title = SCHOOL_LABELS[[row$school]],
          value = paste0(row$valid, " / ", row$n, " valid"),
          p(date_str, class = "small text-muted")
        )
      )
    })
    tagList(cards)
  })

  output$plot_overview_mvpa <- renderPlot({
    if (nrow(part5_pers) == 0)
      return(no_data_plot("No Part 5 data yet — run the pipeline first."))

    mvpa_col <- "dur_day_total_MOD_min_pla"
    vpa_col  <- "dur_day_total_VIG_min_pla"
    if (!mvpa_col %in% names(part5_pers))
      return(no_data_plot("Activity columns not found."))

    school_avg <- part5_pers[
      , .(MVPA = mean(get(mvpa_col) + get(vpa_col), na.rm = TRUE)),
      by = .(school, meting)
    ]
    school_avg[, school_label := SCHOOL_LABELS[school]]
    school_avg[, school_label := factor(school_label, levels = paste("School", 1:6))]

    ggplot(school_avg, aes(x = school_label, y = MVPA, fill = school)) +
      geom_col(width = 0.65, show.legend = FALSE) +
      geom_text(aes(label = round(MVPA, 0)), vjust = -0.4, size = 3.5) +
      scale_fill_manual(values = SCHOOL_COLOURS) +
      facet_wrap(~meting, labeller = as_labeller(
        c(meting_1 = "Meting 1", meting_2 = "Meting 2"))) +
      labs(x = NULL, y = "Mean MVPA (min/day)",
           title = "Average daily MVPA (MPA + VPA) per school") +
      theme_minimal(base_size = 13) +
      theme(axis.text.x = element_text(angle = 20, hjust = 1))
  })

  output$table_overview_validity <- renderDT({
    if (nrow(participant_validity) == 0) return(datatable(data.frame()))
    tbl <- participant_validity[
      , .(Participants       = uniqueN(ID),
          `Included`         = sum(meets_criteria, na.rm = TRUE),
          `Mean wear (h/day)`= round(mean(mean_wear_h, na.rm = TRUE), 1)),
      by = .(School = SCHOOL_LABELS[school], Meting = meting)
    ][order(School, Meting)]
    datatable(tbl, options = list(pageLength = 12, dom = "t"), rownames = FALSE)
  })

  # ── Participants tab ──────────────────────────────────────────────────────────
  par_part2    <- reactive({ filter_dt(part2,               input$par_school, input$par_meting) })
  par_validity <- reactive({ filter_dt(participant_validity, input$par_school, input$par_meting) })

  output$plot_wear_heatmap <- renderPlot({
    dt <- par_part2()
    if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())
    dt[, pupil := sub("\\.csv$", "", ID)]
    ggplot(dt, aes(x = calendar_date, y = pupil, fill = n_valid_hours)) +
      geom_tile(colour = "white", linewidth = 0.3) +
      scale_fill_gradient2(
        low = "#d73027", mid = "#fee090", high = "#1a9850",
        midpoint = cfg$validity$min_wear_hours_per_day / 2,
        name = "Valid hours/day"
      ) +
      facet_wrap(~meting, ncol = 1, scales = "free_x",
                 labeller = as_labeller(c(meting_1 = "Meting 1",
                                          meting_2 = "Meting 2"))) +
      labs(x = NULL, y = NULL,
           title = "Wear time heatmap  —  green = valid day") +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })

  output$table_participants <- renderDT({
    dt <- par_validity()
    if (is.null(dt) || nrow(dt) == 0) return(datatable(data.frame()))
    display <- dt[, .(
      Pupil            = sub("\\.csv$", "", ID),
      School           = SCHOOL_LABELS[school],
      Meting           = meting,
      `Valid days`     = n_valid_days,
      `Total days`     = n_days,
      `Avg wear (h)`   = mean_wear_h,
      `Weekend OK`     = has_weekend,
      `Included`       = meets_criteria
    )]
    datatable(display,
              options = list(pageLength = 30, scrollX = TRUE),
              rownames = FALSE) |>
      formatStyle("Included",
        backgroundColor = styleEqual(c(TRUE, FALSE), c("#d4edda", "#f8d7da")))
  })

  # ── School Day tab ────────────────────────────────────────────────────────────
  seg_data <- reactive({
    if (nrow(segment_summary) == 0) return(NULL)
    dt <- copy(segment_summary)
    if (input$seg_meting != "Both") dt <- dt[meting == input$seg_meting]
    if (input$seg_school != "All schools") dt <- dt[school == input$seg_school]
    dt
  })

  output$plot_school_day <- renderPlot({
    dt <- seg_data()
    if (is.null(dt) || nrow(dt) == 0)
      return(no_data_plot("No segment data available.\nRun pipeline/02_compute_segments.R first."))

    agg <- dt[, .(SB   = mean(dur_IN_min,  na.rm = TRUE),
                  LPA  = mean(dur_LIG_min, na.rm = TRUE),
                  MVPA = mean(dur_MOD_min + dur_VIG_min, na.rm = TRUE)),
              by = .(school_label, segment)]

    long <- melt(agg, id.vars = c("school_label", "segment"),
                 variable.name = "intensity", value.name = "minutes")
    long[, intensity := factor(intensity, levels = c("SB", "LPA", "MVPA"))]

    seg_colours <- c(SB = "#d1e5f0", LPA = "#92c5de", MVPA = "#f4a582")

    ggplot(long, aes(x = school_label, y = minutes, fill = intensity)) +
      geom_col(position = "stack", width = 0.7) +
      scale_fill_manual(values = seg_colours, name = "Intensity") +
      facet_wrap(~segment, nrow = 1) +
      labs(x = NULL, y = "Mean minutes",
           title    = "Activity intensity by school context",
           subtitle = "SB < 56.3 mg  |  LPA 56.3–191.6 mg  |  MVPA ≥ 191.6 mg") +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 35, hjust = 1),
            legend.position = "bottom",
            strip.text = element_text(face = "bold"))
  })

  output$plot_recess_mvpa <- renderPlot({
    dt <- seg_data()
    if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())

    recess <- dt[segment == "Recess"]
    if (nrow(recess) == 0) return(no_data_plot("No recess data in this selection."))

    agg <- recess[, .(MVPA = mean(dur_MOD_min + dur_VIG_min, na.rm = TRUE),
                      se   = sd(dur_MOD_min  + dur_VIG_min, na.rm = TRUE) /
                               sqrt(.N)),
                  by = .(school_label, school, meting)]
    agg[, meting_label := ifelse(meting == "meting_1", "Meting 1", "Meting 2")]

    ggplot(agg, aes(x = school_label, y = MVPA, fill = school,
                    group = meting_label)) +
      geom_col(position = position_dodge(0.75), width = 0.65,
               show.legend = FALSE) +
      geom_errorbar(aes(ymin = MVPA - se, ymax = MVPA + se),
                    position = position_dodge(0.75), width = 0.25) +
      geom_text(aes(label = round(MVPA, 1)),
                position = position_dodge(0.75),
                vjust = -0.6, size = 3.3) +
      scale_fill_manual(values = SCHOOL_COLOURS) +
      facet_wrap(~meting_label) +
      labs(x = NULL, y = "Mean MVPA (min)",
           title    = "MVPA during recess by school",
           subtitle = "Error bars = ±1 SE across participants") +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 20, hjust = 1))
  })

  output$table_segments <- renderDT({
    dt <- seg_data()
    if (is.null(dt) || nrow(dt) == 0) return(datatable(data.frame()))

    agg <- dt[, .(
      `SB (min)`   = round(mean(dur_IN_min,  na.rm = TRUE), 1),
      `LPA (min)`  = round(mean(dur_LIG_min, na.rm = TRUE), 1),
      `MPA (min)`  = round(mean(dur_MOD_min, na.rm = TRUE), 1),
      `VPA (min)`  = round(mean(dur_VIG_min, na.rm = TRUE), 1),
      `MVPA (min)` = round(mean(dur_MOD_min + dur_VIG_min, na.rm = TRUE), 1),
      `Total (min)`= round(mean(dur_total_min, na.rm = TRUE), 1),
      N            = .N
    ), by = .(School = school_label, Segment = segment, Meting = meting)]

    setorder(agg, School, Segment, Meting)
    datatable(agg, options = list(pageLength = 30, scrollX = TRUE),
              rownames = FALSE)
  })

  # ── Meting Comparison tab ─────────────────────────────────────────────────────
  cmp_data <- reactive({
    dt <- filter_dt(part5_pers, input$cmp_school, NULL)
    if (is.null(dt) || nrow(dt) == 0) return(NULL)
    avail <- INT_PERS[INT_PERS %in% names(dt)]
    if (length(avail) == 0) return(NULL)
    dt[, pupil := sub("\\.csv$", "", ID)]
    dt[, c("pupil", "school", "meting", avail), with = FALSE]
  })

  output$plot_meting_cmp <- renderPlot({
    dt <- cmp_data()
    if (is.null(dt))
      return(no_data_plot("Not enough Part 5 data.\nBoth metingen need valid participants."))

    long <- intensity_long(dt, INT_PERS, c("pupil", "school", "meting"))
    if (is.null(long)) return(no_data_plot())

    ggplot(long, aes(x = meting, y = minutes, colour = meting, group = pupil)) +
      geom_line(alpha = 0.35) +
      geom_point(size = 2.5) +
      facet_wrap(~intensity, scales = "free_y") +
      scale_colour_manual(
        values = c(meting_1 = "#2166ac", meting_2 = "#d6604d"),
        guide  = "none"
      ) +
      scale_x_discrete(labels = c(meting_1 = "Meting 1", meting_2 = "Meting 2")) +
      labs(x = NULL, y = "Mean minutes / day",
           title = "Paired meting comparison — each line is one pupil") +
      theme_minimal(base_size = 12)
  })

  output$table_meting_cmp <- renderDT({
    dt <- cmp_data()
    if (is.null(dt)) return(datatable(data.frame()))
    avail  <- INT_PERS[INT_PERS %in% names(dt)]
    labels <- names(avail)

    wide_in <- dt[, c("pupil", "school", "meting", avail), with = FALSE]
    setnames(wide_in, avail, labels)
    wide_in[, (labels) := lapply(.SD, round, 1), .SDcols = labels]
    wide_in[, school := SCHOOL_LABELS[school]]

    wide <- dcast(wide_in, pupil + school ~ meting, value.var = labels)
    datatable(wide, options = list(pageLength = 30, scrollX = TRUE), rownames = FALSE)
  })

  # ── Export tab ────────────────────────────────────────────────────────────────
  output$dl_part2 <- downloadHandler(
    filename = function() paste0("schoolmove_wear_", Sys.Date(), ".csv"),
    content  = function(file) fwrite(part2, file)
  )
  output$dl_segments <- downloadHandler(
    filename = function() paste0("schoolmove_segments_", Sys.Date(), ".csv"),
    content  = function(file) fwrite(segment_summary, file)
  )
  output$dl_validity <- downloadHandler(
    filename = function() paste0("schoolmove_validity_", Sys.Date(), ".csv"),
    content  = function(file) fwrite(participant_validity, file)
  )
}

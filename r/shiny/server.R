# server.R
# ─────────────────────────────────────────────────────────────────────────────
# SchoolMove dashboard — reactive logic.
# ─────────────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ── Helpers ────────────────────────────────────────────────────────────────
  no_data_plot <- function(msg = "Geen data — voer de pipeline eerst uit.") {
    ggplot() +
      annotate("text", x = 0.5, y = 0.5, label = msg,
               size = 5, colour = "grey60", hjust = 0.5) +
      theme_void()
  }

  # Detect MVPA column in analysis_ready (GGIR naming varies)
  mvpa_col_name <- reactive({
    if (is.null(analysis_ready)) return(NULL)
    col <- grep("mvpa_min_day_avg|^MVPA|^mvpa", names(analysis_ready),
                value = TRUE, ignore.case = TRUE)
    if (length(col) == 0) NULL else col[1]
  })

  # Resolve metric column name from selector value
  metric_col <- function(metric, dt) {
    switch(metric,
      mvpa    = mvpa_col_name(),
      sb      = if ("sb_min_day"       %in% names(dt)) "sb_min_day"       else NULL,
      lpa     = if ("lpa_min_day"      %in% names(dt)) "lpa_min_day"      else NULL,
      bouts30 = if ("bouts_30min_day"  %in% names(dt)) "bouts_30min_day"  else NULL,
      sleep   = if ("sleep_duration_h" %in% names(dt)) "sleep_duration_h" else NULL
    )
  }

  metric_label <- function(metric) {
    switch(metric,
      mvpa    = "MVPA (min/dag)",
      sb      = "Sedentair (min/dag)",
      lpa     = "Licht actief (min/dag)",
      bouts30 = "SB bouts \u226530 min/dag",
      sleep   = "Slaap (h/nacht)",
      metric
    )
  }

  # PNG download helper
  png_dl <- function(plot_expr, filename_stem, width = 1800, height = 1000, dpi = 180) {
    downloadHandler(
      filename = function() paste0(filename_stem, "_", format(Sys.Date(), "%Y%m%d"), ".png"),
      content  = function(f) {
        ggplot2::ggsave(f, plot = plot_expr(), device = "png",
                        width = width / dpi, height = height / dpi,
                        dpi = dpi, bg = "white")
      }
    )
  }

  # ── Global filter helpers ──────────────────────────────────────────────────
  # Safe accessor: returns "all" when global_meting input is hidden/NULL
  safe_meting <- function() {
    val <- tryCatch(input$global_meting, error = function(e) NULL)
    if (is.null(val) || is.na(val) || !nzchar(val)) "all" else val
  }

  # Apply global school/meting selectors to any data.table
  apply_global_filters <- function(dt, school_col = "school", meting_col = "meting") {
    if (is.null(dt) || nrow(dt) == 0) return(dt)
    if (input$global_school != "all") {
      sel <- names(SCHOOL_LABELS)[SCHOOL_LABELS == input$global_school]
      dt  <- dt[get(school_col) %in% sel]
    }
    mv <- safe_meting()
    if (mv != "all") dt <- dt[get(meting_col) == mv]
    dt
  }

  # Verbal label for rank-biserial effect size
  rb_effect_label <- function(r) {
    abs_r <- abs(as.numeric(r))
    if (is.na(abs_r)) return("\u2014")
    if (abs_r >= 0.5) paste0(r, " (groot)")
    else if (abs_r >= 0.1) paste0(r, " (middel)")
    else paste0(r, " (klein)")
  }

  # ── Global UI: meting filter (hidden on Vergelijking tab) ─────────────────
  output$meting_filter_ui <- renderUI({
    active <- input$main_nav
    if (!is.null(active) && active == "Vergelijking") return(NULL)
    # setNames swaps so display labels = "Meting 1"/"Meting 2", values = "meting_1"/"meting_2"
    selectInput("global_meting", NULL, width = "100%",
                choices = c("Beide metingen" = "all",
                            setNames(names(METINGEN_LABELS), METINGEN_LABELS)))
  })
  outputOptions(output, "meting_filter_ui", suspendWhenHidden = FALSE)

  # ── KPI card click → tab navigation ───────────────────────────────────────
  observeEvent(input$kpi_click, {
    nav_select("main_nav", input$kpi_click)
  })

  # ── Pipeline inline status ─────────────────────────────────────────────────
  pipeline_result  <- reactiveVal(NULL)

  output$pipeline_status_inline <- renderUI({
    res <- pipeline_result()
    if (is.null(res)) return(NULL)
    tags$span(
      style = paste0("font-size:0.82rem; color:", if (res$ok) "#198754" else "#dc3545", ";"),
      if (res$ok) icon("circle-check") else icon("triangle-exclamation"),
      " ", res$msg
    )
  })

  # ── Pipeline button: confirm modal ─────────────────────────────────────────
  observeEvent(input$btn_run_pipeline, {
    showModal(modalDialog(
      title = tagList(icon("play"), " Pipeline uitvoeren"),
      p("Dit voert alle pipeline-stappen uit (GGIR \u2192 segmenten \u2192 samenvattingen).",
        "Dit kan enkele minuten duren."),
      p(class = "text-muted small",
        "Of run handmatig in de terminal:",
        tags$code("Rscript --vanilla r/pipeline/run_all.R")),
      footer = tagList(
        actionButton("btn_pipeline_confirm", "Start pipeline",
                     icon  = icon("play"),
                     class = "btn-primary"),
        modalButton("Annuleren")
      )
    ))
  })

  observeEvent(input$btn_pipeline_confirm, {
    removeModal()
    pipeline_result(list(
      ok  = TRUE,
      msg = "Voer de pipeline uit in de terminal en herlaad de app daarna."
    ))
    showNotification(
      tagList(
        tags$strong("Pipeline starten: "),
        "Open een terminal in de projectmap en voer uit:",
        tags$br(),
        tags$code("Rscript --vanilla r/pipeline/run_all.R"),
        tags$br(),
        "Herlaad de app nadat de pipeline klaar is."
      ),
      type     = "message",
      duration = 15
    )
  })

  # ── Data-readiness strip ───────────────────────────────────────────────────
  output$data_readiness_strip <- renderUI({
    checks <- list()

    # GGIR output
    has_ggir <- nrow(part2) > 0
    checks$ggir <- tags$span(
      class = if (has_ggir) "check-ok" else "check-miss",
      if (has_ggir) "\u2714 GGIR" else "\u2717 GGIR niet gevonden"
    )

    # Analysis ready + validity
    has_ar <- !is.null(analysis_ready) && nrow(analysis_ready) > 0
    checks$ar <- tags$span(
      class = if (has_ar) "check-ok" else "check-miss",
      if (has_ar) "\u2714 Samenvattingen" else "\u2717 Samenvattingen niet gevonden \u2014 run stap 03"
    )

    # Segment summary
    has_seg <- !is.null(segment_summary) && nrow(segment_summary) > 0
    checks$seg <- tags$span(
      class = if (has_seg) "check-ok" else "check-warn",
      if (has_seg) "\u2714 Segmenten" else "\u26a0 Segmenten niet gevonden \u2014 run stap 02"
    )

    # Fallback schools
    if (length(FALLBACK_SCHOOLS) > 0) {
      school_names <- paste(SCHOOL_LABELS[FALLBACK_SCHOOLS], collapse = ", ")
      checks$fallback <- tags$span(
        class = "check-warn",
        paste0("\u26a0 Geschat rooster: ", school_names)
      )
    }

    div(class = "readiness-strip",
        tags$span(style = "font-weight:600; color:#6c757d; margin-right:4px;", "Pipeline:"),
        checks)
  })

  # ── Rapport samenvatting (auto-generated findings text) ───────────────────
  rapport_text_reactive <- reactive({
    req(input$global_school)
    mc <- mvpa_col_name()
    if (is.null(analysis_ready) || is.null(validity_summary)) {
      return("Geen data beschikbaar — voer de pipeline eerst uit.")
    }

    # Filter scoping (safe_meting() guards against NULL when meting filter is hidden)
    school_scope <- if (input$global_school == "all") "alle scholen"
                    else SCHOOL_LABELS[names(SCHOOL_LABELS)[SCHOOL_LABELS == input$global_school]]
    mv           <- safe_meting()
    meting_scope <- if (mv != "all") METINGEN_LABELS[mv] else "beide metingen"

    filt_val  <- apply_global_filters(copy(validity_summary))
    filt_ar   <- if (!is.null(mc)) apply_global_filters(
      copy(analysis_ready[meets_sedentary_criteria == TRUE])
    ) else NULL

    # Count participant-meting records (one row per ID × meting)
    n_total   <- nrow(filt_val)
    n_valid   <- sum(filt_val$meets_sedentary_criteria, na.rm = TRUE)
    pct_valid <- round(100 * n_valid / max(n_total, 1))
    n_participants <- uniqueN(filt_val$ID)

    mvpa_line  <- ""
    who_line   <- ""
    school_line <- ""
    sleep_line  <- ""

    if (!is.null(filt_ar) && !is.null(mc) && mc %in% names(filt_ar) && nrow(filt_ar) > 0) {
      filt_ar[, mvpa_val := get(mc)]
      filt_ar[, school_label := SCHOOL_LABELS[school]]

      avg_mvpa  <- round(mean(filt_ar$mvpa_val, na.rm = TRUE))
      pct_who   <- round(100 * mean(filt_ar$mvpa_val >= WHO_MVPA_MIN, na.rm = TRUE))
      mvpa_line <- sprintf("Het cohort haalt gemiddeld %d min/dag MVPA.", avg_mvpa)
      who_line  <- sprintf("%d%% van de deelnemers bereikt de WHO-richtlijn van \u226560 min/dag.", pct_who)

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
      sprintf("SchoolMove \u2014 %s / %s", school_scope, meting_scope),
      "",
      sprintf("Cohort: %d deelnemers \u00b7 %d metingen \u00b7 %d%% van de metingen geldig voor analyse.",
              n_participants, n_total, pct_valid),
      if (nzchar(mvpa_line))  mvpa_line,
      if (nzchar(school_line)) school_line,
      if (nzchar(who_line))   who_line,
      if (nzchar(sleep_line)) sleep_line
    )
    paste(Filter(Negate(is.null), lines), collapse = "\n")
  })

  output$rapport_samenvatting_ui <- renderUI({
    txt <- rapport_text_reactive()
    tagList(
      tags$pre(id = "rapport_text_out", txt),
      tags$div(
        style = "margin-top:8px; display:flex; gap:8px; align-items:center;",
        actionButton("btn_copy_rapport", "Kopieer naar klembord",
                     icon  = icon("copy"),
                     class = "btn-outline-secondary btn-sm"),
        tags$span(id = "copy_confirm",
                  style = "font-size:0.8rem; color:#198754; display:none;",
                  "\u2713 Gekopieerd")
      ),
      tags$script(HTML("
        document.getElementById('btn_copy_rapport').addEventListener('click', function() {
          var txt = document.getElementById('rapport_text_out').innerText;
          navigator.clipboard.writeText(txt).then(function() {
            var conf = document.getElementById('copy_confirm');
            conf.style.display = 'inline';
            setTimeout(function(){ conf.style.display = 'none'; }, 2000);
          });
        });
      "))
    )
  })

  # ── Tab 1: Overzicht ───────────────────────────────────────────────────────
  output$n_participants  <- renderText({
    if (is.null(validity_summary)) return("\u2014")
    uniqueN(validity_summary$ID)
  })

  output$pct_valid <- renderText({
    if (is.null(validity_summary)) return("\u2014")
    sprintf("%.0f%%", 100 * mean(validity_summary$meets_sedentary_criteria, na.rm = TRUE))
  })

  output$avg_mvpa <- renderText({
    mc <- mvpa_col_name()
    if (is.null(analysis_ready) || is.null(mc)) return("\u2014")
    valid <- analysis_ready[meets_sedentary_criteria == TRUE]
    if (nrow(valid) == 0) return("\u2014")
    sprintf("%.0f min/dag", mean(valid[[mc]], na.rm = TRUE))
  })

  output$pct_who <- renderText({
    mc <- mvpa_col_name()
    if (is.null(analysis_ready) || is.null(mc)) return("\u2014")
    valid <- analysis_ready[meets_sedentary_criteria == TRUE & !is.na(get(mc))]
    if (nrow(valid) == 0) return("\u2014")
    sprintf("%.0f%%", 100 * mean(valid[[mc]] >= WHO_MVPA_MIN, na.rm = TRUE))
  })

  output$avg_sleep <- renderText({
    if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready)) return("\u2014")
    valid <- analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)]
    if (nrow(valid) == 0) return("\u2014")
    sprintf("%.1f u/nacht", mean(valid$sleep_duration_h, na.rm = TRUE))
  })

  # Overview dumbbell chart — MVPA M1 → M2 per school
  overview_plot <- reactive({
    mc <- mvpa_col_name()
    if (is.null(analysis_ready)) return(no_data_plot())
    if (is.null(mc) || !mc %in% names(analysis_ready))
      return(no_data_plot("MVPA-kolom niet gevonden \u2014 herrun stap 03."))

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

    wide <- dcast(agg, school_label ~ meting,
                  value.var = c("mean_mvpa", "ci95", "n"))
    # Only schools with both metingen
    wide <- wide[!is.na(mean_mvpa_meting_1) & !is.na(mean_mvpa_meting_2)]
    if (nrow(wide) == 0) {
      # Fall back to single-meting dot plot
      ggplot(agg, aes(y = reorder(school_label, mean_mvpa), x = mean_mvpa,
                      colour = school_label)) +
        geom_pointrange(aes(xmin = mean_mvpa - ci95, xmax = mean_mvpa + ci95),
                        size = 0.7, linewidth = 1.0) +
        geom_vline(xintercept = WHO_MVPA_MIN, linetype = "dashed",
                   colour = "#6554C0", linewidth = 0.6) +
        scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
        labs(x = "Gem. MVPA (min/dag)", y = NULL,
             subtitle = "Enkel geldige deelnemers \u00b7 lijnen = 95% BI") +
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
                   colour = "#6554C0", linewidth = 0.55, alpha = 0.7) +
        annotate("text", x = WHO_MVPA_MIN + 0.5, y = Inf,
                 label = "WHO (60 min)", hjust = 0, vjust = 1.8,
                 colour = "#6554C0", size = 2.8, fontface = "italic") +
        geom_segment(aes(x = mean_mvpa_meting_1, xend = mean_mvpa_meting_2,
                         y = reorder(school_label, mean_mvpa_meting_1),
                         yend = reorder(school_label, mean_mvpa_meting_1),
                         colour = direction),
                     linewidth = 2.0, alpha = 0.80, lineend = "round") +
        geom_errorbar(aes(xmin = mean_mvpa_meting_1 - ci95_meting_1,
                          xmax = mean_mvpa_meting_1 + ci95_meting_1),
                      orientation = "y", width = 0.18,
                      colour = "#97A0AF", linewidth = 0.55) +
        geom_errorbar(aes(xmin = mean_mvpa_meting_2 - ci95_meting_2,
                          xmax = mean_mvpa_meting_2 + ci95_meting_2),
                      orientation = "y", width = 0.18,
                      colour = "#172B4D", linewidth = 0.55) +
        geom_point(aes(x = mean_mvpa_meting_1), colour = "#97A0AF",
                   size = 5, shape = 16) +
        geom_point(aes(x = mean_mvpa_meting_2, colour = direction),
                   size = 5, shape = 16) +
        geom_text(aes(x = mean_mvpa_meting_1, label = lbl_m1),
                  nudge_y = 0.35, hjust = 0.5, size = 2.6, colour = "#6B778C") +
        geom_text(aes(x = mean_mvpa_meting_2, label = lbl_m2),
                  nudge_y = 0.35, hjust = 0.5, size = 2.6, colour = "#172B4D",
                  fontface = "bold") +
        geom_text(aes(x = (mean_mvpa_meting_1 + mean_mvpa_meting_2) / 2,
                      label = lbl_delta, colour = direction),
                  nudge_y = -0.38, hjust = 0.5, size = 2.5, fontface = "bold") +
        scale_colour_manual(
          values = c("Toename" = "#36B37E", "Afname" = "#FF5630"),
          name   = "Verandering M1 \u2192 M2"
        ) +
        scale_x_continuous(expand = expansion(add = c(6, 6))) +
        labs(x = "Gem. MVPA (min/dag)", y = NULL,
             subtitle = "Grijs = Meting 1 \u00b7 kleur = Meting 2 \u00b7 enkel geldige deelnemers \u00b7 foutbalken = 95% BI") +
        theme_schoolmove(legend_pos = "top") +
        theme(panel.grid.major.y = element_blank(),
              panel.grid.major.x = element_line(colour = "#F4F5F7"))
    }
  })

  output$plot_activity_stacked <- renderPlot(overview_plot())
  output$dl_plot_overview      <- png_dl(overview_plot, "activiteitsprofiel", width = 2200)

  output$table_school_overview <- renderDT({
    mc <- mvpa_col_name()
    if (is.null(analysis_ready)) return(datatable(data.frame(Bericht = "Geen data")))
    dt <- apply_global_filters(copy(analysis_ready[meets_sedentary_criteria == TRUE]))
    if (nrow(dt) == 0)
      return(datatable(data.frame(Bericht = "Geen geldige deelnemers voor huidige filter.")))
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
        background = styleColorBar(mvpa_range, "#0052CC33"),
        backgroundSize = "98% 65%", backgroundRepeat = "no-repeat",
        backgroundPosition = "left center"
      ) |>
      formatStyle(
        "WHO % (num)",
        color = styleInterval(50, c("#FF5630", "#36B37E")),
        fontWeight = "bold"
      )
  })

  # ── Tab 2: Deelnemers ──────────────────────────────────────────────────────
  part2_filtered <- reactive({
    if (nrow(part2) == 0) return(part2)
    apply_global_filters(copy(part2))
  })

  # Heatmap — aggregate mode (all schools), single-school, or single-participant mode
  wear_plot <- reactive({
    dt <- part2_filtered()
    if (nrow(dt) == 0) return(no_data_plot())

    # If a specific participant is selected, filter to that person only
    selected_pid <- input$explorer_id
    if (!is.null(selected_pid) && nchar(selected_pid) > 0) {
      pid_clean <- sub("\\.csv$", "", selected_pid)
      dt_pid    <- dt[sub("\\.csv$", "", as.character(ID)) == pid_clean]
      if (nrow(dt_pid) > 0) dt <- dt_pid
    }

    single_school <- input$global_school != "all" || (
      !is.null(selected_pid) && nchar(selected_pid) > 0
    )

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
                     n_pupils   = uniqueN(ID)),
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
             title = "Draagduur overzicht \u2014 alle scholen",
             subtitle = paste0("% geldige dagen per school (drempelwaarde: \u2265", MIN_WEAR_H, "h)")) +
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
             title = paste("Draagduur \u2014", input$global_school),
             subtitle = paste0("Groen = geldige dag (\u2265", MIN_WEAR_H, "h)")) +
        theme_schoolmove() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
              axis.text.y = element_text(size = 7),
              panel.grid  = element_blank())
    }
  })

  output$plot_wear_heatmap <- renderPlot(wear_plot())
  output$dl_plot_wear      <- png_dl(wear_plot, "draagduur_heatmap",
                                     height = if (isolate(input$global_school) == "all") 700 else 1200)

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
                             " \u00b7 rode lijn = WHO-norm (60 min/dag)")) +
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
      SB   = mean(get(sb_c),   na.rm = TRUE),
      LPA  = mean(get(lpa_c),  na.rm = TRUE),
      MVPA = mean(mvpa_seg,    na.rm = TRUE)
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

  output$plot_explorer_mvpa      <- renderPlot(explorer_mvpa_plot())
  output$plot_explorer_segments  <- renderPlot(explorer_seg_plot())
  output$dl_plot_explorer_mvpa   <- png_dl(explorer_mvpa_plot,  "deelnemer_mvpa")
  output$dl_plot_explorer_segments <- png_dl(explorer_seg_plot, "deelnemer_segmenten")

  output$table_inclusion <- renderDT({
    if (is.null(validity_summary)) return(datatable(data.frame(Bericht = "Geen data")))
    dt <- apply_global_filters(copy(validity_summary))
    dt[, school_label := SCHOOL_LABELS[school]]
    dt[, meting_label := METINGEN_LABELS[meting]]
    dt[, status := ifelse(meets_sedentary_criteria, "Inbegrepen", "Uitgesloten")]
    dt[, reden  := fifelse(is.na(exclusion_reason), "\u2014", exclusion_reason)]

    # Apply status filter from radio buttons
    sf <- input$incl_status_filter
    if (!is.null(sf) && sf == "included")  dt <- dt[meets_sedentary_criteria == TRUE]
    if (!is.null(sf) && sf == "excluded")  dt <- dt[meets_sedentary_criteria == FALSE]

    if (!is.null(analysis_ready)) {
      mc <- mvpa_col_name()
      ar_cols <- c("ID", "school", "meting")
      if (!is.null(mc) && mc %in% names(analysis_ready)) ar_cols <- c(ar_cols, mc)
      if ("sleep_duration_h" %in% names(analysis_ready))  ar_cols <- c(ar_cols, "sleep_duration_h")
      ar_sub <- analysis_ready[, ar_cols, with = FALSE]
      if (!is.null(mc) && mc %in% names(ar_sub))
        setnames(ar_sub, mc, "mvpa_avg")
      dt <- merge(dt, ar_sub, by = c("ID", "school", "meting"), all.x = TRUE)
      if ("mvpa_avg" %in% names(dt))
        dt[, mvpa_avg := round(mvpa_avg, 1)]
      if ("sleep_duration_h" %in% names(dt))
        dt[, sleep_duration_h := round(sleep_duration_h, 1)]
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
    wknd_txt <- if (NEED_WKND) "incl. 1 weekenddag" else "geen weekendvereiste"
    caption_txt <- htmltools::tags$caption(
      style = "caption-side:bottom; font-size:0.78rem; color:#64748b; padding:4px 0;",
      sprintf(
        "Inclusiecriterium: \u2265%g geldige draagdagen (%s) \u00b7 \u2265%g uur/dag draagduur",
        MIN_DAYS, wknd_txt, MIN_WEAR_H
      )
    )
    datatable(dt[, ..all_cols], rownames = FALSE,
              caption = caption_txt,
              selection = "single",
              options = list(pageLength = 15, dom = "frtip", scrollX = TRUE),
              filter = "top") |>
      formatStyle("Status",
        backgroundColor = styleEqual(c("Inbegrepen","Uitgesloten"), c("#d4edda","#f8d7da")))
  })

  # ── Individual participant explorer ────────────────────────────────────────
  observe({
    choices <- if (is.null(analysis_ready)) character(0) else {
      dt <- apply_global_filters(copy(analysis_ready))
      sort(unique(as.character(dt$ID)))
    }
    updateSelectInput(session, "explorer_id",
                      choices = c("Kies een deelnemer..." = "", choices))
  })

  # Click a row in the inclusion table → pre-fill explorer_id in sidebar
  observeEvent(input$table_inclusion_rows_selected, {
    row_idx <- input$table_inclusion_rows_selected
    if (length(row_idx) == 0 || is.null(validity_summary)) return()
    dt <- apply_global_filters(copy(validity_summary))
    if (row_idx > nrow(dt)) return()
    selected_id <- as.character(dt$ID[row_idx])
    updateSelectInput(session, "explorer_id", selected = selected_id)
  })


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

  # ── Tab 3: Schooldag ──────────────────────────────────────────────────────
  seg_filtered <- reactive({
    if (is.null(segment_summary)) return(NULL)
    dt <- copy(segment_summary)
    mv <- safe_meting()
    if (mv != "all") dt <- dt[meting == mv]
    if (input$global_school != "all") {
      sel <- names(SCHOOL_LABELS)[SCHOOL_LABELS == input$global_school]
      dt  <- dt[school %in% sel]
    }
    dt
  })

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
      return(no_data_plot("Activiteitskolom niet gevonden."))

    school_day_segs <- c("before_school","in_class","recess","lunch","after_school")
    agg <- dt[segment %in% school_day_segs, {
      n    <- .N
      mu   <- mean(get(metric_col_name), na.rm = TRUE)
      ci95 <- qt(0.975, n - 1) * sd(get(metric_col_name), na.rm = TRUE) / sqrt(n)
      .(mean_val = mu, ci95 = ci95, n = n)
    }, by = .(school_label, segment_label)]
    if (nrow(agg) == 0) return(no_data_plot())

    y_label  <- switch(input$seg_metric,
      mvpa = "Gem. MVPA (min/dag)", lig = "Gem. LPA (min/dag)", sb = "Gem. sedentair (min/dag)")
    mv         <- safe_meting()
    meting_sub <- if (mv == "all") "alle metingen gecombineerd" else METINGEN_LABELS[mv]

    p <- ggplot(agg, aes(x = segment_label, y = mean_val, fill = school_label)) +
      geom_col(position = position_dodge(0.75), width = 0.7) +
      geom_errorbar(aes(ymin = mean_val - ci95, ymax = mean_val + ci95),
                    position = position_dodge(0.75), width = 0.25,
                    colour = "grey25", linewidth = 0.55) +
      scale_fill_manual(values = SCHOOL_COLORS) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
      labs(x = NULL, y = y_label, fill = NULL,
           subtitle = paste(meting_sub, "\u00b7 foutbalken = 95% BI")) +
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

  budget_plot <- reactive({
    if (is.null(segment_summary)) return(no_data_plot("Geen segmentdata."))
    dt <- copy(segment_summary)
    mv <- safe_meting()
    if (mv != "all") dt <- dt[meting == mv]
    if (input$global_school != "all") {
      sel <- names(SCHOOL_LABELS)[SCHOOL_LABELS == input$global_school]
      dt  <- dt[school %in% sel]
    }
    school_day_segs <- c("before_school","in_class","recess","lunch","after_school")
    dt <- dt[segment %in% school_day_segs]
    if (nrow(dt) == 0) return(no_data_plot())

    mod_c <- grep("^dur_MOD", names(dt), value = TRUE)[1]
    vig_c <- grep("^dur_VIG", names(dt), value = TRUE)[1]
    lpa_c <- grep("^dur_LIG", names(dt), value = TRUE)[1]
    sb_c  <- grep("^dur_IN",  names(dt), value = TRUE)[1]

    if (any(is.na(c(mod_c, vig_c, lpa_c, sb_c))))
      return(no_data_plot("Activiteitszones niet gevonden in segmentdata."))

    dt[, mvpa_val := get(mod_c) + get(vig_c)]

    agg <- dt[, .(
      SB   = mean(get(sb_c),   na.rm = TRUE),
      LPA  = mean(get(lpa_c),  na.rm = TRUE),
      MVPA = mean(mvpa_val,    na.rm = TRUE)
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
           subtitle = "SB / LPA / MVPA per segment \u00b7 rijen = segment, kolommen = meting") +
      theme_schoolmove() +
      theme(axis.text.x  = element_text(angle = 30, hjust = 1, size = 7),
            strip.text.y = element_text(size = 8, face = "bold", angle = 0),
            strip.text.x = element_text(size = 9, face = "bold"),
            legend.position = "top")
  })

  weekday_plot <- reactive({
    if (is.null(segment_summary)) return(no_data_plot("Geen segmentdata."))
    dt <- copy(segment_summary)

    mod_c <- grep("^dur_MOD", names(dt), value = TRUE)[1]
    vig_c <- grep("^dur_VIG", names(dt), value = TRUE)[1]
    if (is.na(mod_c) || is.na(vig_c)) return(no_data_plot())
    dt[, mvpa_val := get(mod_c) + get(vig_c)]

    # Sum all segments per participant × day for total daily MVPA
    daily <- dt[, .(mvpa_day = sum(mvpa_val, na.rm = TRUE)),
                by = .(ID, school_label, meting, calendar_date, weekday)]

    # Filter by weekday/weekend toggle
    if (isTRUE(input$seg_weekday == "weekend")) {
      wd_order <- c("Saturday","Sunday")
      wd_nl    <- c(Saturday = "Za", Sunday = "Zo")
    } else {
      wd_order <- c("Monday","Tuesday","Wednesday","Thursday","Friday")
      wd_nl    <- c(Monday = "Ma", Tuesday = "Di", Wednesday = "Wo",
                    Thursday = "Do", Friday = "Vr")
    }

    mv <- safe_meting()
    if (mv != "all") daily <- daily[meting == mv]

    agg <- daily[weekday %in% wd_order,
                 .(mean_mvpa = mean(mvpa_day, na.rm = TRUE),
                   ci95 = qt(0.975, max(.N - 1, 1)) * sd(mvpa_day, na.rm = TRUE) / sqrt(.N)),
                 by = .(school_label, meting, weekday)]
    agg[, meting_label := METINGEN_LABELS[meting]]
    agg      <- agg[weekday %in% wd_order]
    agg[, weekday_f := factor(wd_nl[weekday], levels = wd_nl)]

    if (nrow(agg) == 0) return(no_data_plot("Geen data voor geselecteerd dagtype."))

    dag_type <- if (isTRUE(input$seg_weekday == "weekend")) "weekenddagen" else "schooldagen (Ma\u2013Vr)"

    ggplot(agg, aes(x = weekday_f, y = mean_mvpa, colour = school_label,
                    group = school_label)) +
      geom_ribbon(aes(ymin = mean_mvpa - ci95, ymax = mean_mvpa + ci95, fill = school_label),
                  alpha = 0.12, colour = NA) +
      geom_line(linewidth = 1.2) +
      geom_point(size = 2.5) +
      scale_colour_manual(values = SCHOOL_COLORS) +
      scale_fill_manual(values = SCHOOL_COLORS, guide = "none") +
      scale_y_continuous(expand = expansion(mult = c(0.02, 0.1))) +
      facet_wrap(~ meting_label) +
      labs(x = NULL, y = "Gem. MVPA (min/dag)", colour = NULL,
           subtitle = paste0("Totale MVPA per dag (", dag_type, ") \u00b7 lint = 95% BI")) +
      theme_schoolmove() +
      theme(strip.text = element_text(face = "bold", size = 11))
  })

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
      n   <- .N
      mu  <- mean(get(mvpa_col_s), na.rm = TRUE)
      ci  <- qt(0.975, n - 1) * sd(get(mvpa_col_s), na.rm = TRUE) / sqrt(n)
      .(mean_mvpa = mu, ci95 = ci, n = n)
    }, by = school_label]

    ggplot(agg, aes(x = reorder(school_label, mean_mvpa), y = mean_mvpa, fill = school_label)) +
      geom_col(show.legend = FALSE) +
      geom_errorbar(aes(ymin = mean_mvpa - ci95, ymax = mean_mvpa + ci95),
                    width = 0.25, colour = "grey30") +
      geom_text(aes(y = mean_mvpa + ci95 + 0.3, label = paste0("n=", n)),
                size = 3, colour = "grey40", hjust = 0) +
      scale_fill_manual(values = SCHOOL_COLORS) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.28))) +
      coord_flip() +
      labs(x = NULL, y = "Gem. MVPA (min)", subtitle = "Beweging tijdens pauze \u00b7 foutbalken = 95% BI") +
      theme_schoolmove(legend_pos = "none")
  })

  # Sedentary bouts dumbbell chart (M1 vs M2 per school)
  bouts_plot <- reactive({
    if (is.null(analysis_ready) || !"bouts_30min_day" %in% names(analysis_ready))
      return(no_data_plot("Sedentaire boutdata niet beschikbaar \u2014 herrun stap 03."))
    dt <- copy(analysis_ready[meets_sedentary_criteria == TRUE & !is.na(bouts_30min_day)])
    dt <- apply_global_filters(dt)
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
      # Single meting: simple dot plot
      ggplot(agg, aes(y = reorder(school_label, mean_bouts), x = mean_bouts,
                      colour = school_label)) +
        geom_pointrange(aes(xmin = mean_bouts - ci95, xmax = mean_bouts + ci95),
                        size = 0.6, linewidth = 0.9) +
        scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
        labs(x = "Gem. bouten per dag (\u226530 min)", y = NULL,
             subtitle = "Aaneengesloten sedentaire perioden \u00b7 lijnen = 95% BI") +
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
        geom_point(aes(x = mean_bouts_meting_1), colour = "#97A0AF",
                   size = 5, shape = 16) +
        geom_point(aes(x = mean_bouts_meting_2, colour = direction),
                   size = 5, shape = 16) +
        geom_text(aes(x = mean_bouts_meting_2,
                      label = paste0(ifelse(delta <= 0, "", "+"), round(delta, 1))),
                  nudge_y = 0.32, hjust = 0.5, size = 2.6,
                  colour = "#172B4D", fontface = "bold") +
        scale_colour_manual(
          values = c("Afname (positief)" = "#36B37E", "Toename" = "#FF5630"),
          name   = NULL
        ) +
        scale_x_continuous(expand = expansion(add = c(0.5, 0.8))) +
        labs(x = "Gem. bouten per dag (\u226530 min)", y = NULL,
             subtitle = "Grijs = M1 \u00b7 kleur = M2 \u00b7 afname sedentaire bouten = gezondheidswinst") +
        theme_schoolmove(legend_pos = "top") +
        theme(panel.grid.major.y = element_blank())
    }
  })

  output$plot_segment_activity <- renderPlot({
    if (isTRUE(input$seg_view == "budget")) budget_plot() else seg_plot()
  })
  output$plot_recess_mvpa  <- renderPlot(recess_plot())
  output$plot_weekday      <- renderPlot(weekday_plot())
  output$plot_bouts        <- renderPlot(bouts_plot())

  output$dl_plot_segment  <- png_dl(
    function() if (isTRUE(input$seg_view == "budget")) budget_plot() else seg_plot(),
    "schooldag_activiteit", width = 2200, height = 1100)
  output$dl_plot_recess   <- png_dl(recess_plot, "pauze_mvpa")
  output$dl_plot_weekday  <- png_dl(weekday_plot, "weekdag_profiel", width = 2000)

  output$table_segment_detail <- renderDT({
    dt <- seg_filtered()
    if (is.null(dt) || nrow(dt) == 0) return(datatable(data.frame(Bericht = "Geen data")))
    intensity_cols <- grep("^(dur_IN|dur_LIG|dur_MOD|dur_VIG)", names(dt),
                           value = TRUE, ignore.case = TRUE)
    agg <- dt[, c(list(n_dagen = .N),
                  lapply(.SD, function(x) round(mean(x, na.rm = TRUE), 1))),
               by = .(School = school_label, Segment = segment_label,
                      Meting = METINGEN_LABELS[meting]), .SDcols = intensity_cols]
    # Rename technical column names to readable Dutch labels
    col_rename <- c(
      dur_IN_min  = "Sedentair (min)", dur_IN_sec  = "Sedentair (s)",
      dur_LIG_min = "Licht actief (min)", dur_LIG_sec = "Licht actief (s)",
      dur_MOD_min = "Matig actief (min)", dur_MOD_sec = "Matig actief (s)",
      dur_VIG_min = "Intensief actief (min)", dur_VIG_sec = "Intensief actief (s)"
    )
    for (raw in intersect(names(col_rename), names(agg))) {
      setnames(agg, raw, col_rename[raw])
    }
    datatable(agg, rownames = FALSE,
              options = list(pageLength = 20, dom = "frtip", scrollX = TRUE),
              filter = "top")
  })

  # ── Tab 4: Slaap ──────────────────────────────────────────────────────────
  sleep_data <- reactive({
    if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready)) return(NULL)
    dt <- apply_global_filters(
      copy(analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)])
    )
    dt[, school_label := SCHOOL_LABELS[school]]
    dt[, meting_label := METINGEN_LABELS[meting]]
    dt
  })

  output$sleep_avg_pooled <- renderText({
    dt <- if (is.null(analysis_ready)) NULL else
      analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)]
    if (is.null(dt) || nrow(dt) == 0) return("\u2014")
    sprintf("%.1f u/nacht", mean(dt$sleep_duration_h))
  })

  output$sleep_delta <- renderText({
    if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready)) return("\u2014")
    m1_dt <- analysis_ready[meets_sedentary_criteria == TRUE & meting == "meting_1" & !is.na(sleep_duration_h)]
    m2_dt <- analysis_ready[meets_sedentary_criteria == TRUE & meting == "meting_2" & !is.na(sleep_duration_h)]
    if (nrow(m1_dt) == 0 || nrow(m2_dt) == 0) return("\u2014")
    delta <- mean(m2_dt$sleep_duration_h) - mean(m1_dt$sleep_duration_h)
    arrow <- if (delta > 0.05) "\u25b2 " else if (delta < -0.05) "\u25bc " else "\u25ba "
    paste0(arrow, sprintf("%+.2f u", delta))
  })

  output$sleep_pct_short <- renderText({
    dt <- if (is.null(analysis_ready)) NULL else
      analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)]
    if (is.null(dt) || nrow(dt) == 0) return("\u2014")
    sprintf("%.0f%%", 100 * mean(dt$sleep_duration_h < WHO_SLEEP_MIN_H))
  })

  sleep_dist_plot <- reactive({
    dt <- sleep_data()
    if (is.null(dt) || nrow(dt) == 0) return(no_data_plot("Geen slaapdata."))
    y_col  <- if (input$sleep_metric == "duration") "sleep_duration_h" else "sleep_efficiency_pct"
    y_lab  <- if (input$sleep_metric == "duration") "Slaapduur (h/nacht)" else "Slaapeffici\u00ebntie (%)"
    if (!y_col %in% names(dt)) return(no_data_plot("Kolom niet beschikbaar."))

    # Aggregate per school × meting
    agg <- dt[, {
      n   <- .N
      mu  <- mean(get(y_col), na.rm = TRUE)
      ci  <- qt(0.975, max(n - 1, 1)) * sd(get(y_col), na.rm = TRUE) / sqrt(n)
      .(mean_val = mu, ci95 = ci, n = n)
    }, by = .(school_label, meting_label)]

    # Try dumbbell (requires both metingen)
    wide <- tryCatch(
      dcast(agg, school_label ~ meting_label, value.var = c("mean_val", "ci95", "n")),
      error = function(e) NULL
    )
    has_both <- !is.null(wide) &&
      all(c("mean_val_Meting 1", "mean_val_Meting 2") %in% names(wide)) &&
      any(!is.na(wide[["mean_val_Meting 1"]]) & !is.na(wide[["mean_val_Meting 2"]]))

    # individual background points (long format)
    dt[, val := get(y_col)]

    if (has_both) {
      wide <- wide[!is.na(`mean_val_Meting 1`) & !is.na(`mean_val_Meting 2`)]
      wide[, delta := `mean_val_Meting 2` - `mean_val_Meting 1`]

      p <- ggplot(wide, aes(y = reorder(school_label, `mean_val_Meting 1`))) +
        # individual background dots — two separate calls with a fixed seed so
        # M1 (blue, nudged up) and M2 (orange, nudged down) don't pile on top
        # of each other; alpha raised so individual points are actually readable
        geom_jitter(data = dt[meting_label == "Meting 1"],
                    aes(x = val, y = school_label),
                    colour = "#3498DB",
                    position = position_jitter(width = 0.12, height = 0, seed = 1L),
                    alpha = 0.42, size = 1.7) +
        geom_jitter(data = dt[meting_label == "Meting 2"],
                    aes(x = val, y = school_label),
                    colour = "#E67E22",
                    position = position_jitter(width = 0.12, height = 0, seed = 2L),
                    alpha = 0.42, size = 1.7) +
        # CI error bars
        geom_errorbar(aes(xmin = `mean_val_Meting 1` - `ci95_Meting 1`,
                          xmax = `mean_val_Meting 1` + `ci95_Meting 1`),
                      orientation = "y", width = 0.18,
                      colour = "#3498DB", linewidth = 0.55) +
        geom_errorbar(aes(xmin = `mean_val_Meting 2` - `ci95_Meting 2`,
                          xmax = `mean_val_Meting 2` + `ci95_Meting 2`),
                      orientation = "y", width = 0.18,
                      colour = "#E67E22", linewidth = 0.55) +
        # connecting segment
        geom_segment(aes(x = `mean_val_Meting 1`, xend = `mean_val_Meting 2`,
                         yend = reorder(school_label, `mean_val_Meting 1`),
                         colour = ifelse(delta >= 0, "Toename", "Afname")),
                     linewidth = 1.4, alpha = 0.7) +
        # mean dots
        geom_point(aes(x = `mean_val_Meting 1`), colour = "#3498DB", size = 4, shape = 16) +
        geom_point(aes(x = `mean_val_Meting 2`), colour = "#E67E22", size = 4, shape = 16) +
        # n labels
        geom_text(aes(x = pmin(`mean_val_Meting 1`, `mean_val_Meting 2`) - 0.1,
                      label = paste0("n=", `n_Meting 1`)),
                  hjust = 1, size = 2.5, colour = "grey50") +
        scale_colour_manual(
          values = c("Meting 1" = "#3498DB", "Meting 2" = "#E67E22",
                     "Toename" = "#36B37E", "Afname" = "#FF5630"),
          guide = "none"
        ) +
        labs(x = y_lab, y = NULL,
             subtitle = "Punten = individuele leerlingen \u00b7 M1 (blauw) \u00b7 M2 (oranje) \u00b7 grote punten = schoolgemiddelde \u00b7 foutbalken = 95% BI") +
        theme_schoolmove(legend_pos = "none") +
        theme(panel.grid.major.y = element_blank(),
              panel.grid.major.x = element_line(colour = "#F4F5F7"))

      if (input$sleep_metric == "duration")
        p <- p +
          annotate("rect", xmin = 8, xmax = 10, ymin = -Inf, ymax = Inf,
                   fill = "#36B37E", alpha = 0.07, colour = NA) +
          annotate("text", x = 9, y = Inf,
                   label = "WHO: 8\u201310u", vjust = -0.4, colour = "#36B37E",
                   size = 2.8, fontface = "italic")
      p

    } else {
      # Single-meting fallback: dot + CI per school
      ggplot(agg, aes(x = mean_val, y = reorder(school_label, mean_val),
                      colour = meting_label)) +
        geom_pointrange(aes(xmin = mean_val - ci95, xmax = mean_val + ci95),
                        linewidth = 0.8, size = 2.0) +
        geom_text(aes(label = paste0("n=", n)),
                  hjust = -0.3, size = 2.6, colour = "grey50") +
        scale_colour_manual(values = c("Meting 1" = "#3498DB", "Meting 2" = "#E67E22")) +
        labs(x = y_lab, y = NULL, colour = NULL,
             subtitle = "Schoolgemiddelde \u00b7 foutbalken = 95% BI") +
        theme_schoolmove() +
        theme(panel.grid.major.y = element_blank())
    }
  })

  bland_altman_plot <- reactive({
    if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready))
      return(no_data_plot())
    dt <- apply_global_filters(
      copy(analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)])
    )
    dt[, school_label := SCHOOL_LABELS[school]]
    wide <- dcast(dt, ID + school_label ~ meting, value.var = "sleep_duration_h")
    if (!all(c("meting_1","meting_2") %in% names(wide))) return(no_data_plot("Niet genoeg metingen."))
    wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
    if (nrow(wide) == 0) return(no_data_plot())

    wide[, ba_mean := (meting_1 + meting_2) / 2]
    wide[, ba_diff := meting_2 - meting_1]

    mu_diff <- mean(wide$ba_diff)
    sd_diff <- sd(wide$ba_diff)
    loa_up  <- mu_diff + 1.96 * sd_diff
    loa_lo  <- mu_diff - 1.96 * sd_diff

    ggplot(wide, aes(x = ba_mean, y = ba_diff, colour = school_label)) +
      geom_hline(yintercept = mu_diff, linewidth = 0.8, colour = "grey30") +
      geom_hline(yintercept = c(loa_up, loa_lo), linetype = "dashed",
                 linewidth = 0.7, colour = "#E74C3C") +
      geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey70", linetype = "dotted") +
      geom_jitter(alpha = 0.55, size = 2, width = 0.02) +
      annotate("text", x = Inf, y = mu_diff + 0.05,
               label = sprintf("Gem. verschil: %.2f u", mu_diff),
               hjust = 1.05, size = 3.2, colour = "grey30") +
      annotate("text", x = Inf, y = loa_up + 0.05,
               label = sprintf("+1.96 SD: %.2f u", loa_up),
               hjust = 1.05, size = 3.0, colour = "#E74C3C") +
      annotate("text", x = Inf, y = loa_lo - 0.05,
               label = sprintf("-1.96 SD: %.2f u", loa_lo),
               hjust = 1.05, size = 3.0, colour = "#E74C3C") +
      scale_colour_manual(values = SCHOOL_COLORS) +
      labs(x = "Gemiddelde slaapduur M1 & M2 (u/nacht)",
           y = "Verschil M2 \u2212 M1 (u/nacht)",
           colour = NULL,
           subtitle = "Bland-Altman overeenkomstplot \u00b7 rood = 95% limieten van overeenstemming") +
      theme_schoolmove()
  })

  output$plot_sleep_dist      <- renderPlot(sleep_dist_plot())
  output$plot_bland_altman    <- renderPlot(bland_altman_plot())
  output$dl_plot_sleep        <- png_dl(sleep_dist_plot,   "slaapverdeling")
  output$dl_plot_bland_altman <- png_dl(bland_altman_plot, "slaap_bland_altman")

  # ── Tab 5: Vergelijking metingen ──────────────────────────────────────────
  comp_data <- reactive({
    if (is.null(analysis_ready)) return(NULL)
    dt <- apply_global_filters(copy(analysis_ready[meets_sedentary_criteria == TRUE]))
    dt[, school_label := SCHOOL_LABELS[school]]
    dt
  })

  slope_plot <- reactive({
    dt <- comp_data()
    if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())

    mc <- metric_col(input$comp_metric, dt)
    if (is.null(mc) || !mc %in% names(dt))
      return(no_data_plot("Kolom niet beschikbaar voor geselecteerde maat."))

    wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
    if (!all(c("meting_1","meting_2") %in% names(wide))) return(no_data_plot("Niet genoeg metingen."))
    wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
    if (nrow(wide) == 0) return(no_data_plot("Geen deelnemers met beide metingen."))

    school_means <- wide[, .(m1 = mean(meting_1), m2 = mean(meting_2),
                               n  = .N), by = school_label]
    y_lab <- metric_label(input$comp_metric)

    wide[, tooltip_text := paste0(
      "ID: ", ID,
      "\nM1: ", round(meting_1, 1),
      "\nM2: ", round(meting_2, 1),
      "\n\u0394: ", round(meting_2 - meting_1, 1)
    )]

    ggplot() +
      # Individual spaghetti lines (behind, transparent)
      geom_segment(data = wide,
                   aes(x = 1, xend = 2, y = meting_1, yend = meting_2,
                       colour = school_label, text = tooltip_text),
                   alpha = 0.14, linewidth = 0.55) +
      # School mean line — clean, no arrow
      geom_segment(data = school_means,
                   aes(x = 1, xend = 2, y = m1, yend = m2, colour = school_label),
                   linewidth = 2.0, alpha = 0.92) +
      # Mean endpoint dots — solid on both ends
      geom_point(data = school_means,
                 aes(x = 1, y = m1, colour = school_label),
                 size = 4, shape = 16) +
      geom_point(data = school_means,
                 aes(x = 2, y = m2, colour = school_label),
                 size = 4, shape = 16) +
      geom_text(data = school_means,
                aes(x = 2.08, y = m2, label = paste0(school_label, " (n=", n, ")"),
                    colour = school_label),
                hjust       = 0,
                size        = 3.0,
                fontface    = "bold",
                show.legend = FALSE) +
      scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
      scale_x_continuous(breaks = c(1, 2), labels = c("Meting 1", "Meting 2"),
                         expand = expansion(add = c(0.3, 1.4))) +
      labs(x = NULL, y = y_lab,
           subtitle = "Individuele trajecten (dun) \u00b7 schoolgemiddelde (dik) \u00b7 hover = ID + waarden") +
      theme_schoolmove() +
      theme(panel.grid.major.x = element_blank(), legend.position = "none")
  })

  delta_plot <- reactive({
    dt <- comp_data()
    if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())
    mc <- metric_col(input$comp_metric, dt)
    if (is.null(mc) || !mc %in% names(dt)) return(no_data_plot())

    wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
    if (!all(c("meting_1","meting_2") %in% names(wide))) return(no_data_plot())
    wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
    wide[, delta := meting_2 - meting_1]

    agg <- wide[, {
      n    <- .N
      mu   <- mean(delta, na.rm = TRUE)
      ci95 <- qt(0.975, n - 1) * sd(delta, na.rm = TRUE) / sqrt(n)
      .(mean_delta = mu, ci95 = ci95, n = n)
    }, by = school_label]

    ggplot(agg, aes(x = mean_delta, y = reorder(school_label, mean_delta),
                    colour = school_label)) +
      geom_vline(xintercept = 0, colour = "#5E6C84", linewidth = 0.7) +
      geom_pointrange(aes(xmin = mean_delta - ci95, xmax = mean_delta + ci95),
                      linewidth = 1.0, size = 2.5) +
      geom_text(aes(label = paste0(ifelse(mean_delta >= 0, "+", ""),
                                   round(mean_delta, 1), "  (n=", n, ")")),
                hjust = -0.08, size = 2.9, colour = "#172B4D", fontface = "bold") +
      scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
      scale_x_continuous(expand = expansion(add = c(5, 12))) +
      labs(x = paste("\u0394", metric_label(input$comp_metric)), y = NULL,
           subtitle = "M2 \u2212 M1 per school \u00b7 horizontale lijnen = 95% BI") +
      theme_schoolmove(legend_pos = "none") +
      theme(panel.grid.major.y = element_blank(),
            panel.grid.major.x = element_line(colour = "#F4F5F7"))
  })

  # Correlation scatter (X-axis selectable, Y = sleep)
  corr_plot <- reactive({
    if (is.null(analysis_ready)) return(no_data_plot())
    if (!"sleep_duration_h" %in% names(analysis_ready))
      return(no_data_plot("Slaapkolom ontbreekt."))

    x_mc  <- metric_col(input$comp_corr_x, analysis_ready)
    x_lab <- metric_label(input$comp_corr_x)
    if (is.null(x_mc) || !x_mc %in% names(analysis_ready))
      return(no_data_plot("Kolom niet beschikbaar voor geselecteerde X-as."))

    dt <- copy(analysis_ready[meets_sedentary_criteria == TRUE &
                               !is.na(get(x_mc)) & !is.na(sleep_duration_h)])
    dt <- apply_global_filters(dt)
    dt <- dt[meting == input$comp_corr_meting]
    dt[, school_label := SCHOOL_LABELS[school]]
    if (nrow(dt) < 3) return(no_data_plot("Te weinig datapunten."))

    r_val <- round(cor(dt[[x_mc]], dt$sleep_duration_h, use = "complete.obs"), 2)
    n_val <- nrow(dt)

    ggplot(dt, aes(x = get(x_mc), y = sleep_duration_h, colour = school_label)) +
      geom_point(alpha = 0.45, size = 2) +
      geom_smooth(method = "lm", se = TRUE, colour = "grey30", linewidth = 1,
                  fill = "grey80", alpha = 0.3, show.legend = FALSE) +
      annotate("text", x = Inf, y = Inf,
               label = sprintf("r = %.2f  (n=%d)", r_val, n_val),
               hjust = 1.1, vjust = 1.5, size = 4.5, colour = "grey30") +
      scale_colour_manual(values = SCHOOL_COLORS) +
      labs(x = x_lab, y = "Slaapduur (h/nacht)", colour = NULL,
           subtitle = paste0(METINGEN_LABELS[input$comp_corr_meting],
                             " \u00b7 Pearson r \u00b7 lint = 95% BI")) +
      theme_schoolmove()
  })

  output$plot_slopegraph  <- renderPlotly({
    p <- slope_plot()
    # suppressWarnings: geom_segment uses aes(text=) for plotly hover,
    # which ggplot2 warns about as an unknown aesthetic — intentional.
    suppressWarnings(
      ggplotly(p, tooltip = "text") |>
        layout(legend = list(orientation = "h")) |>
        config(displayModeBar = FALSE)
    )
  })
  output$plot_delta       <- renderPlot(delta_plot())
  output$plot_corr        <- renderPlot(corr_plot())

  output$dl_plot_slope    <- png_dl(slope_plot, "vergelijking_pijlen",  height = 1200)
  output$dl_plot_delta    <- png_dl(delta_plot, "delta_per_school")
  output$dl_plot_corr     <- png_dl(corr_plot,  "correlatie")

  output$table_stats <- renderDT({
    dt <- comp_data()
    if (is.null(dt)) return(datatable(data.frame(Bericht = "Geen data")))
    mc <- metric_col(input$comp_metric, dt)
    if (is.null(mc) || !mc %in% names(dt))
      return(datatable(data.frame(Bericht = "Kolom niet gevonden.")))

    wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
    if (!all(c("meting_1","meting_2") %in% names(wide)))
      return(datatable(data.frame(Bericht = "Onvoldoende data.")))
    wide <- wide[!is.na(meting_1) & !is.na(meting_2)]

    results <- wide[, {
      w     <- tryCatch(wilcox.test(meting_2, meting_1, paired = TRUE, exact = FALSE),
                        error = function(e) NULL)
      delta <- meting_2 - meting_1
      n     <- .N
      se    <- sd(delta) / sqrt(n)
      ci95  <- qt(0.975, n - 1) * se
      p_val <- if (!is.null(w)) w$p.value else NA_real_
      r_rb  <- if (!is.null(w) && !is.na(w$statistic))
        round(1 - 2 * w$statistic / (n * (n + 1) / 2), 3) else NA_real_
      sig   <- if (is.na(p_val)) "\u2014"
               else if (p_val < 0.05) "Ja" else "Nee"
      .(
        N           = n,
        M1_gem      = round(mean(meting_1), 1),
        M2_gem      = round(mean(meting_2), 1),
        delta_gem   = round(mean(delta), 1),
        CI_95       = sprintf("[%.1f, %.1f]", mean(delta) - ci95, mean(delta) + ci95),
        p_waarde    = if (is.na(p_val)) "\u2014"
                      else if (p_val < 0.001) "<0.001"
                      else sprintf("%.3f", p_val),
        sig         = sig,
        r_effect    = if (is.na(r_rb)) "\u2014" else rb_effect_label(r_rb)
      )
    }, by = school_label]

    setnames(results,
             c("school_label","M1_gem","M2_gem","delta_gem","CI_95",
               "p_waarde","sig","r_effect"),
             c("School","M1 gem.","M2 gem.","\u0394 gem.","95% BI",
               "p-waarde","Sig.?","r (effectgrootte)"))

    datatable(results, rownames = FALSE, options = list(dom = "t", pageLength = 10)) |>
      formatStyle("\u0394 gem.", color = styleInterval(0, c("#C0392B","#27AE60"))) |>
      formatStyle("p-waarde",
                  color = styleEqual(c("<0.001"), c("#C0392B")),
                  fontWeight = "bold") |>
      formatStyle("Sig.?",
                  backgroundColor = styleEqual(c("Ja","Nee"), c("#d4edda","#ffffff")))
  })

  # School comparison summary table
  output$table_school_comparison <- renderDT({
    mc <- mvpa_col_name()
    if (is.null(analysis_ready) || is.null(mc)) return(datatable(data.frame(Bericht = "Geen data")))

    dt <- copy(analysis_ready[meets_sedentary_criteria == TRUE])
    dt[, school_label := SCHOOL_LABELS[school]]
    dt[, meting_label := METINGEN_LABELS[meting]]
    dt[, mvpa_val := get(mc)]

    has_sleep <- "sleep_duration_h" %in% names(dt)

    agg <- dt[, {
      n_valid <- .N
      mvpa_m  <- round(mean(mvpa_val, na.rm = TRUE), 1)
      who_pct <- round(100 * mean(mvpa_val >= WHO_MVPA_MIN, na.rm = TRUE))
      slaap_m <- if (has_sleep) round(mean(sleep_duration_h, na.rm = TRUE), 1) else NA_real_
      .(N          = n_valid,
        `MVPA gem. (min/dag)` = mvpa_m,
        `% WHO-norm` = paste0(who_pct, "%"),
        `Slaap gem. (h)` = if (has_sleep) as.character(slaap_m) else "\u2014")
    }, by = .(School = school_label, Meting = meting_label)]

    datatable(agg[order(School, Meting)], rownames = FALSE,
              options = list(dom = "t", pageLength = 20)) |>
      formatStyle("% WHO-norm",
                  color = styleInterval(c("50%"), c("#C0392B", "#27AE60")))
  })

  # Per-participant wide comparison table
  participant_comp_data <- reactive({
    dt <- comp_data()
    if (is.null(dt)) return(NULL)
    mc <- metric_col(input$comp_metric, dt)
    if (is.null(mc) || !mc %in% names(dt)) return(NULL)

    wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
    if (!all(c("meting_1","meting_2") %in% names(wide))) return(NULL)
    wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
    wide[, delta_val := round(meting_2 - meting_1, 1)]
    wide[, meting_1  := round(meting_1, 1)]
    wide[, meting_2  := round(meting_2, 1)]
    wide <- wide[order(school_label, delta_val)]
    y_lab      <- metric_label(input$comp_metric)
    delta_name <- "\u0394 (M2\u2212M1)"
    setnames(wide, c("school_label","meting_1","meting_2","delta_val"),
             c("School", paste0("M1 (", y_lab, ")"), paste0("M2 (", y_lab, ")"), delta_name))
    wide
  })

  output$table_participant_comp <- renderDT({
    dt <- participant_comp_data()
    if (is.null(dt) || nrow(dt) == 0)
      return(datatable(data.frame(Bericht = "Geen data beschikbaar.")))
    delta_col <- "\u0394 (M2\u2212M1)"
    datatable(dt, rownames = FALSE, filter = "top",
              options = list(pageLength = 20, dom = "frtip", scrollX = TRUE)) |>
      formatStyle(delta_col,
                  color = styleInterval(0, c("#C0392B", "#27AE60")),
                  fontWeight = "bold")
  })

  output$dl_participant_comp <- downloadHandler(
    filename = function() paste0("deelnemer_vergelijking_", input$comp_metric, "_",
                                 format(Sys.Date(), "%Y%m%d"), ".csv"),
    content  = function(f) {
      dt <- participant_comp_data()
      if (!is.null(dt)) write.csv(dt, f, row.names = FALSE) else write.csv(data.frame(), f)
    }
  )

  # ── Tab 6: Export panel UI (with availability status) ─────────────────────
  output$export_panel_ui <- renderUI({
    seg_path_exists      <- !is.null(segment_summary)
    ar_path_exists       <- !is.null(analysis_ready)
    val_path_exists      <- !is.null(validity_summary)
    manifest_path_exists <- file.exists("../logs/input_manifest.csv")
    run_log_path_exists  <- file.exists("../logs/pipeline_runs.csv")

    status_badge <- function(ok, ok_msg = "Beschikbaar", miss_msg = "Nog niet gegenereerd") {
      tags$span(
        class = if (ok) "badge bg-success ms-1" else "badge bg-secondary ms-1",
        style = "font-size:0.7rem;",
        if (ok) ok_msg else miss_msg
      )
    }

    tagList(
    layout_columns(
      col_widths = c(4, 4, 4),
      card(
        card_header("GGIR ruwe output"),
        p(class = "text-muted small", "Dagsamenvattingen per deelnemer:"),
        downloadButton("dl_part2", "Dagsamenvattingen (GGIR)",
                       class = "btn-outline-primary btn-sm export-dl-btn"),
        br(), br(),
        p(class = "text-muted small", "Activiteitsintensiteit per deelnemer:"),
        downloadButton("dl_part5", "Activiteitsprofiel per deelnemer",
                       class = "btn-outline-primary btn-sm export-dl-btn")
      ),
      card(
        card_header("Analyse output"),
        p(class = "text-muted small",
          "Activiteit per schooldagsegment per dag:",
          status_badge(seg_path_exists, miss_msg = "Run stap 02 eerst")),
        tags$div(
          title = if (!seg_path_exists) "Bestand niet gevonden \u2014 voer stap 02 (label_segments) uit" else NULL,
          downloadButton("dl_segments", "Activiteit per schoolsegment",
                         class = paste("btn-sm export-dl-btn",
                                       if (seg_path_exists) "btn-outline-primary" else "btn-outline-secondary disabled-btn"))
        ),
        br(), br(),
        p(class = "text-muted small",
          "Analysetabel \u2014 \u00e9\u00e9n rij per deelnemer \u00d7 meting:",
          status_badge(ar_path_exists, miss_msg = "Run stap 03 eerst")),
        tags$div(
          title = if (!ar_path_exists) "Bestand niet gevonden \u2014 voer stap 03 (build_summaries) uit" else NULL,
          downloadButton("dl_ready", "Analysetabel",
                         class = paste("btn-sm export-dl-btn",
                                       if (ar_path_exists) "btn-outline-success" else "btn-outline-secondary disabled-btn"))
        ),
        br(), br(),
        p(class = "text-muted small",
          "Inclusie/exclusie per deelnemer:",
          status_badge(val_path_exists, miss_msg = "Run stap 03 eerst")),
        tags$div(
          title = if (!val_path_exists) "Bestand niet gevonden \u2014 voer stap 03 (build_summaries) uit" else NULL,
          downloadButton("dl_validity", "Inclusie / exclusie",
                         class = paste("btn-sm export-dl-btn",
                                       if (val_path_exists) "btn-outline-primary" else "btn-outline-secondary disabled-btn"))
        )
      ),
      card(
        card_header("Gefilterde export"),
        p(class = "text-muted small",
          "Exporteer enkel de deelnemers die overeenkomen met de actieve filter (school + meting) bovenaan."),
        downloadButton("dl_filtered", "Analysetabel (gefilterd)",
                       class = "btn-outline-primary btn-sm export-dl-btn"),
        br(), br(),
        p(class = "text-muted small",
          "Exporteer segmentdata gefilterd op actieve school + meting:",
          status_badge(seg_path_exists, miss_msg = "Run stap 02 eerst")),
        tags$div(
          title = if (!seg_path_exists) "Segmenten nog niet gegenereerd \u2014 voer stap 02 uit" else NULL,
          downloadButton("dl_segments_filtered", "Segmentdata (gefilterd)",
                         class = paste("btn-sm export-dl-btn",
                                       if (seg_path_exists) "btn-outline-primary" else "btn-outline-secondary disabled-btn"))
        )
      )
    ),
    # ── Reproducibility files ─────────────────────────────────────────────────
    card(
      class = "mt-3 shadow-sm",
      card_header("Reproduceerbaarheid"),
      card_body(
        p(class = "text-muted small",
          "Technische logs voor reproductie en archivering van de analyse."),
        layout_columns(
          col_widths = c(6, 6),
          div(
            p(class = "text-muted small",
              "Input manifest — overzicht van verwerkte bestanden:",
              status_badge(manifest_path_exists, miss_msg = "Nog niet aangemaakt")),
            tags$div(
              downloadButton("dl_input_manifest", "Input manifest",
                             class = paste("btn-sm export-dl-btn",
                                           if (manifest_path_exists) "btn-outline-primary"
                                           else "btn-outline-secondary disabled-btn"))
            )
          ),
          div(
            p(class = "text-muted small",
              "Pipeline run log \u2014 versies en tijdstippen per uitvoering:",
              status_badge(run_log_path_exists, miss_msg = "Nog niet aangemaakt")),
            tags$div(
              downloadButton("dl_run_log", "Pipeline run log",
                             class = paste("btn-sm export-dl-btn",
                                           if (run_log_path_exists) "btn-outline-primary"
                                           else "btn-outline-secondary disabled-btn"))
            )
          )
        )
      )
    )
    ) # end tagList
  })

  # ── Tab 6: Export download handlers ───────────────────────────────────────
  ts <- format(Sys.Date(), "%Y%m%d")

  dl_ggir <- function(meting, filename = NULL, pattern = NULL) {
    results_dir <- file.path("..", cfg$paths$data_processed, meting,
                             paste0("output_", meting), "results")
    if (!is.null(pattern)) {
      files <- list.files(results_dir, pattern = pattern, full.names = TRUE)
      if (length(files) == 0) return(NULL)
      fread(files[1], data.table = FALSE)
    } else {
      fpath <- file.path(results_dir, filename)
      if (!file.exists(fpath)) return(NULL)
      fread(fpath, data.table = FALSE)
    }
  }

  dl_combined <- function(filename = NULL, pattern = NULL) {
    rows <- lapply(metingen, function(m) {
      dt <- dl_ggir(m, filename, pattern)
      if (!is.null(dt)) { dt$meting <- m; dt } else NULL
    })
    do.call(rbind, Filter(Negate(is.null), rows))
  }

  output$dl_part2 <- downloadHandler(
    filename = function() paste0("part2_daysummary_", ts, ".csv"),
    content  = function(f) {
      # Use in-memory part2 (already filtered by apply_global_filters)
      dt <- if (nrow(part2) > 0) as.data.frame(apply_global_filters(copy(part2))) else NULL
      if (!is.null(dt) && nrow(dt) > 0) write.csv(dt, f, row.names = FALSE)
      else write.csv(data.frame(), f)
    }
  )
  output$dl_part5 <- downloadHandler(
    filename = function() paste0("part5_personsummary_", ts, ".csv"),
    content  = function(f) {
      raw <- dl_combined(pattern = "^part5_personsummary_WW_")
      if (!is.null(raw)) {
        raw$school <- extract_school_id(raw$ID)
        raw <- apply_global_filters(setDT(raw))
        write.csv(as.data.frame(raw), f, row.names = FALSE)
      } else write.csv(data.frame(), f)
    }
  )
  output$dl_segments <- downloadHandler(
    filename = function() paste0("segment_summary_", ts, ".csv"),
    content  = function(f) {
      src <- file.path("..", cfg$paths$data_processed, "..", "segment_summary.csv")
      if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
    }
  )
  output$dl_ready <- downloadHandler(
    filename = function() paste0("analysis_ready_", ts, ".csv"),
    content  = function(f) {
      src <- file.path("..", cfg$paths$data_processed, "..", "analysis_ready.csv")
      if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
    }
  )
  output$dl_validity <- downloadHandler(
    filename = function() paste0("validity_summary_", ts, ".csv"),
    content  = function(f) {
      src <- file.path("..", cfg$paths$data_processed, "..", "validity_summary.csv")
      if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
    }
  )

  # Filtered exports (respects global school + meting selectors)
  output$dl_filtered <- downloadHandler(
    filename = function() {
      school_part <- if (input$global_school == "all") "all"
                     else gsub(" ", "_", tolower(input$global_school))
      meting_part <- safe_meting()
      paste0("analysis_ready_", school_part, "_", meting_part, "_", ts, ".csv")
    },
    content = function(f) {
      dt <- if (!is.null(analysis_ready)) apply_global_filters(copy(analysis_ready)) else NULL
      if (!is.null(dt) && nrow(dt) > 0) write.csv(dt, f, row.names = FALSE)
      else write.csv(data.frame(), f)
    }
  )

  output$dl_segments_filtered <- downloadHandler(
    filename = function() {
      school_part <- if (input$global_school == "all") "all"
                     else gsub(" ", "_", tolower(input$global_school))
      meting_part <- safe_meting()
      paste0("segment_summary_", school_part, "_", meting_part, "_", ts, ".csv")
    },
    content = function(f) {
      dt <- if (!is.null(segment_summary)) apply_global_filters(copy(segment_summary)) else NULL
      if (!is.null(dt) && nrow(dt) > 0) write.csv(dt, f, row.names = FALSE)
      else write.csv(data.frame(), f)
    }
  )

  # ── Tab 6: Reproducibility download handlers ─────────────────────────────────
  output$dl_input_manifest <- downloadHandler(
    filename = function() paste0("input_manifest_", ts, ".csv"),
    content  = function(f) {
      src <- "../logs/input_manifest.csv"
      if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
    }
  )

  output$dl_run_log <- downloadHandler(
    filename = function() paste0("pipeline_runs_", ts, ".csv"),
    content  = function(f) {
      src <- "../logs/pipeline_runs.csv"
      if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
    }
  )

  # ── Tab 7: Instellingen — Settings ─────────────────────────────────────────

  profiles_dir <- file.path("..", cfg$profiles$directory %||% "profiles/")

  # Reactive file reader: re-scans profiles/ every 5 s so new profiles appear
  # automatically without an app restart.
  profile_list <- reactiveFileReader(
    intervalMillis = 5000,
    session        = session,
    filePath       = profiles_dir,
    readFunc       = function(dir) {
      yamls <- list.files(dir, pattern = "\\.yaml$", full.names = FALSE)
      tools::file_path_sans_ext(yamls)
    }
  )

  # Keep the selectInput in sync with the profiles directory
  observe({
    choices <- profile_list()
    if (length(choices) == 0) choices <- "default"
    updateSelectInput(session, "settings_profile_select", choices = choices,
                      selected = cfg$profiles$active %||% "default")
  })

  # Active profile badge and notes
  output$settings_active_profile_badge <- renderUI({
    active <- cfg$profiles$active %||% "default"
    div(
      class = "alert alert-info py-2 small mb-2",
      icon("check-circle"), " Actief profiel: ", strong(active)
    )
  })

  output$settings_profile_notes <- renderUI({
    selected <- input$settings_profile_select
    if (is.null(selected)) return(NULL)
    path <- file.path(profiles_dir, paste0(selected, ".yaml"))
    if (!file.exists(path)) return(NULL)
    prof <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
    if (is.null(prof) || is.null(prof$notes)) return(NULL)
    p(class = "text-muted small", icon("info-circle"), " ", prof$notes)
  })

  # Load: populate form fields from selected profile
  observeEvent(input$settings_load_profile, {
    selected <- input$settings_profile_select
    path <- file.path(profiles_dir, paste0(selected, ".yaml"))
    if (!file.exists(path)) {
      showNotification("Profiel niet gevonden.", type = "error"); return()
    }
    prof <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
    if (is.null(prof)) {
      showNotification("Kon profiel niet lezen.", type = "error"); return()
    }
    v <- prof$validity %||% list()
    updateNumericInput(session, "settings_min_wear_h",
                       value = v$min_wear_hours_per_day %||% 16)
    updateNumericInput(session, "settings_min_valid_days",
                       value = v$min_valid_days %||% 3)
    updateCheckboxInput(session, "settings_require_weekend",
                        value = isTRUE(v$require_weekend_day %||% TRUE))
    updateNumericInput(session, "settings_min_valid_nights",
                       value = v$min_valid_nights_sleep %||% 5)
    updateNumericInput(session, "settings_min_pct_night",
                       value = v$min_pct_night_valid %||% 50)
    cp <- (prof$ggir$cut_points_mg) %||% list()
    updateNumericInput(session, "settings_cp_sb_lpa",
                       value = cp$sedentary_to_light %||% 56.3)
    updateNumericInput(session, "settings_cp_lpa_mpa",
                       value = cp$light_to_moderate %||% 191.6)
    updateNumericInput(session, "settings_cp_mpa_vpa",
                       value = cp$moderate_to_vigorous %||% 695.8)
    b <- prof$bouts %||% list()
    updateNumericInput(session, "settings_bout_sb_min",
                       value = b$sedentary_min %||% 30)
    updateCheckboxInput(session, "settings_bout_split_context",
                        value = isTRUE(b$split_at_context_boundary %||% TRUE))
    showNotification(paste0("Profiel '", selected, "' geladen."), type = "message")
  })

  # Save As: show modal asking for a name and notes
  observeEvent(input$settings_save_profile, {
    showModal(modalDialog(
      title = "Profiel opslaan als\u2026",
      textInput("settings_new_profile_name", "Profielnaam", placeholder = "bijv. strenge_drempel"),
      textAreaInput("settings_new_profile_notes", "Notities (optioneel)",
                    placeholder = "Beschrijf waarvoor dit profiel bedoeld is.",
                    rows = 3),
      footer = tagList(
        modalButton("Annuleren"),
        actionButton("settings_confirm_save", "Opslaan", class = "btn-primary")
      )
    ))
  })

  observeEvent(input$settings_confirm_save, {
    removeModal()
    prof_name <- trimws(input$settings_new_profile_name)
    if (nchar(prof_name) == 0) {
      showNotification("Geef een profielnaam op.", type = "error"); return()
    }
    # Sanitise: only alphanumeric, hyphens, underscores
    safe_name <- gsub("[^a-zA-Z0-9_\\-]", "_", prof_name)
    dst_path  <- file.path(profiles_dir, paste0(safe_name, ".yaml"))

    profile_content <- list(
      profile_name = prof_name,
      created_at   = as.character(Sys.Date()),
      notes        = input$settings_new_profile_notes,
      validity     = list(
        min_wear_hours_per_day  = input$settings_min_wear_h,
        min_valid_days          = input$settings_min_valid_days,
        require_weekend_day     = input$settings_require_weekend,
        min_valid_nights_sleep  = input$settings_min_valid_nights,
        min_pct_night_valid     = input$settings_min_pct_night
      ),
      ggir = list(
        cut_points_mg = list(
          sedentary_to_light    = input$settings_cp_sb_lpa,
          light_to_moderate     = input$settings_cp_lpa_mpa,
          moderate_to_vigorous  = input$settings_cp_mpa_vpa
        )
      ),
      bouts = list(
        sedentary_min               = input$settings_bout_sb_min,
        split_at_context_boundary   = input$settings_bout_split_context
      )
    )

    tryCatch({
      yaml::write_yaml(profile_content, dst_path)
      showNotification(paste0("Profiel '", safe_name, "' opgeslagen."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Fout bij opslaan: ", e$message), type = "error")
    })
  })

  # Activate: patch only the `active:` line under `profiles:` in config.yaml.
  # Using readLines/writeLines instead of yaml::write_yaml to preserve all comments.
  observeEvent(input$settings_activate_profile, {
    selected <- input$settings_profile_select
    cfg_path <- "../../config.yaml"
    lines <- tryCatch(readLines(cfg_path, warn = FALSE), error = function(e) NULL)
    if (is.null(lines)) {
      showNotification("Kon config.yaml niet lezen.", type = "error"); return()
    }
    lines <- sub('^(\\s*active:\\s*).*', paste0('\\1"', selected, '"'), lines)
    tryCatch({
      writeLines(lines, cfg_path)
      showNotification(
        paste0("Profiel '", selected, "' geactiveerd. ",
               "Herstart de pipeline om de nieuwe instellingen toe te passen."),
        type    = "message",
        duration = 6
      )
    }, error = function(e) {
      showNotification(paste0("Fout bij activeren: ", e$message), type = "error")
    })
  })

  output$settings_status_msg <- renderUI({ NULL })
}

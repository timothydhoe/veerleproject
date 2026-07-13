# mod_comparison.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 5 "Meting 1 vs 2"
# Slopegraph, delta chart, Wilcoxon stats table, correlation scatter,
# school-comparison summary table, per-participant wide table + CSV download.
#
# shared list keys used:
#   apply_filters  — session-scoped filter function from server.R
#   mvpa_col       — reactive returning MVPA column name (character or NULL)
#
# Global objects accessed directly (defined in global.R):
#   analysis_ready, SCHOOL_LABELS, SCHOOL_COLORS, METINGEN_LABELS,
#   WHO_MVPA_MIN
#   metric_col_pure(), metric_label(), rb_effect_label() — util_filters.R
#   no_data_plot(), png_dl(), theme_schoolmove()        — util_plots.R
#
# NOTE: suppressWarnings on ggplotly(slope_plot) is intentional:
#   geom_segment uses aes(text = tooltip_text) for hover — ggplot2 warns
#   about unknown aesthetics; we accept this trade-off.
# ─────────────────────────────────────────────────────────────────────────────

# DT falls back to English UI strings ("No data available in table", etc.)
# unless a language list is supplied — the rest of the dashboard is Dutch.
.dt_lang_nl <- list(
  search       = "Zoeken:",
  lengthMenu   = "Toon _MENU_ rijen",
  info         = "_START_ tot _END_ van _TOTAL_ rijen",
  infoEmpty    = "Geen rijen om te tonen",
  infoFiltered = "(gefilterd uit _MAX_ rijen)",
  zeroRecords  = "Geen resultaten gevonden",
  emptyTable   = "Geen data beschikbaar",
  paginate     = list(previous = "Vorige", `next` = "Volgende")
)

#' Comparison tab UI
modComparisonUI <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    id = ns("comp_subtab"),

    # ── Sub-tab A: Longitudinaal ─────────────────────────────────────────────
    nav_panel(
      title = tagList(icon("clock-rotate-left"), " Longitudinaal"),
      value = "longitudinaal",
      div(class = "comp-subtab-content",
        layout_sidebar(
          sidebar = sidebar(
            width = 230,
            selectInput(ns("comp_metric"), "Maat",
                        choices = c(
                          "MVPA (min/dag)"             = "mvpa",
                          "Sedentair (min/dag)"        = "sb",
                          "SB bouts ≥30 min/dag"  = "bouts30",
                          "Licht actief (min/dag)"     = "lpa",
                          "Slaap (h/nacht)"            = "sleep"
                        )),
            hr(),
            p(class = "text-muted small",
              "Pijlen = schoolgemiddelde · punten = individuele deelnemers.",
              "Stijgende pijl = toename in Meting 2.")
          ),
          card(
            class       = "shadow-sm",
            full_screen = TRUE,
            card_header("Meting 1 → Meting 2 per deelnemer"),
            card_body(
              p(class = "text-muted small mb-2",
                "Punten = individuele deelnemers · pijlen = schoolgemiddelde · hover = ID + waarden"),
              plotlyOutput(ns("plot_slopegraph"), height = "520px")
            ),
            card_footer(
              class = "d-flex justify-content-end py-1",
              downloadButton(ns("dl_plot_slope"), "PNG opslaan",
                             icon  = icon("download"),
                             class = "btn-outline-secondary btn-sm")
            )
          ),
          layout_columns(
            col_widths = c(6, 6),
            card(
              class = "shadow-sm",
              card_header(
                tip("Statistisch overzicht",
                    "Wilcoxon signed-rank test (paarsgewijs). r = rang-biseriële correlatie: |r| < 0.1 klein, 0.1–0.3 middel, > 0.5 groot")
              ),
              card_body(
                p(class = "text-muted small mb-2",
                  "Gemiddelde verandering (Δ) en 95%-betrouwbaarheidsinterval per school."),
                DTOutput(ns("table_stats"))
              )
            ),
            chart_card(
              header   = "Effectgrootte per school",
              plot_id  = ns("plot_delta"),
              dl_id    = ns("dl_plot_delta"),
              height   = "300px",
              subtitle = "Δ = M2 − M1 · punt = gemiddelde · lijn = 95% BI"
            )
          )
        )
      )
    ),

    # ── Sub-tab B: Correlaties ───────────────────────────────────────────────
    nav_panel(
      title = tagList(icon("circle-dot"), " Correlaties"),
      value = "correlaties",
      div(class = "comp-subtab-content",
        layout_sidebar(
          sidebar = sidebar(
            width = 230,
            selectInput(ns("comp_corr_x"), "X-as",
                        choices = c(
                          "MVPA (min/dag)"        = "mvpa",
                          "Sedentair (min/dag)"   = "sb",
                          "SB bouts ≥30 min" = "bouts30"
                        )),
            selectInput(ns("comp_corr_meting"), "Meting",
                        choices = setNames(names(METINGEN_LABELS), METINGEN_LABELS)),
            hr(),
            p(class = "text-muted small",
              "Y-as is altijd slaapduur. Pearson r staat in de grafiek.")
          ),
          chart_card(
            header   = "Correlatie",
            plot_id  = ns("plot_corr"),
            dl_id    = ns("dl_plot_corr"),
            height   = "380px",
            subtitle = "Verband tussen geselecteerde maten per school · lijn = lineaire trend · lint = 95% BI"
          ),
          card(
            class       = "shadow-sm",
            full_screen = TRUE,
            card_header("Schoolvergelijking: samenvatting"),
            card_body(
              p(class = "text-muted small mb-2",
                "Overzicht van alle scholen per meting — enkel geldige deelnemers."),
              DTOutput(ns("table_school_comparison"))
            )
          ),
          card(
            class       = "shadow-sm",
            full_screen = TRUE,
            card_header("Per deelnemer: Meting 1 vs Meting 2"),
            card_body(
              p(class = "text-muted small mb-2",
                "Gesorteerd op kleinste verandering (Δ). Rood = afname, groen = toename."),
              DTOutput(ns("table_participant_comp"))
            ),
            card_footer(
              class = "d-flex justify-content-end py-1",
              downloadButton(ns("dl_participant_comp"), "CSV downloaden",
                             icon  = icon("download"),
                             class = "btn-outline-success btn-sm")
            )
          )
        )
      )
    )
  )
}

#' Comparison tab server
mod_comparison_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    # ── Filtered reactive ─────────────────────────────────────────────────────
    comp_data <- reactive({
      if (is.null(analysis_ready)) return(NULL)
      dt <- shared$apply_filters(copy(analysis_ready[meets_sedentary_criteria == TRUE]))
      dt[, school_label := SCHOOL_LABELS[school]]
      dt
    })

    # ── Slopegraph ────────────────────────────────────────────────────────────
    slope_plot <- reactive({
      dt <- comp_data()
      if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())

      mc <- metric_col_pure(input$comp_metric, dt, shared$mvpa_col())
      if (is.null(mc) || !mc %in% names(dt))
        return(no_data_plot("Kolom niet beschikbaar voor geselecteerde maat."))

      wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
      if (!all(c("meting_1","meting_2") %in% names(wide))) return(no_data_plot("Niet genoeg metingen."))
      n_total_slope <- nrow(wide)
      wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
      if (nrow(wide) == 0) return(no_data_plot("Geen deelnemers met beide metingen."))
      n_excl_slope <- n_total_slope - nrow(wide)

      school_means <- wide[, .(m1 = mean(meting_1), m2 = mean(meting_2), n = .N),
                            by = school_label]
      y_lab <- metric_label(input$comp_metric)

      wide[, tooltip_text := paste0(
        "ID: ", ID,
        "\nM1: ", round(meting_1, 1),
        "\nM2: ", round(meting_2, 1),
        "\nΔ: ", round(meting_2 - meting_1, 1)
      )]

      ggplot() +
        geom_segment(data = wide,
                     aes(x = 1, xend = 2, y = meting_1, yend = meting_2,
                         colour = school_label, text = tooltip_text),
                     alpha = 0.14, linewidth = 0.55) +
        geom_segment(data = school_means,
                     aes(x = 1, xend = 2, y = m1, yend = m2, colour = school_label),
                     linewidth = 2.0, alpha = 0.92) +
        geom_point(data = school_means,
                   aes(x = 1, y = m1, colour = school_label),
                   size = 4, shape = 16) +
        geom_point(data = school_means,
                   aes(x = 2, y = m2, colour = school_label),
                   size = 4, shape = 16) +
        geom_text(data = school_means,
                  aes(x = 2.08, y = m2, label = paste0(school_label, " (n=", n, ")"),
                      colour = school_label),
                  hjust = 0, size = 3.0, fontface = "bold", show.legend = FALSE) +
        scale_colour_manual(values = SCHOOL_COLORS, guide = "none") +
        scale_x_continuous(breaks = c(1, 2), labels = c("Meting 1", "Meting 2"),
                           expand = expansion(add = c(0.3, 1.4))) +
        labs(x = NULL, y = y_lab,
             subtitle = paste0(
               "Individuele trajecten (dun) · schoolgemiddelde (dik) · hover = ID + waarden",
               if (n_excl_slope > 0)
                 paste0(" · ", n_excl_slope, " uitgesloten (ontbreekt ≥1 meting)")
               else "")) +
        theme_schoolmove() +
        theme(panel.grid.major.x = element_blank(), legend.position = "none")
    })

    # ── Delta chart ───────────────────────────────────────────────────────────
    delta_plot <- reactive({
      dt <- comp_data()
      if (is.null(dt) || nrow(dt) == 0) return(no_data_plot())
      mc <- metric_col_pure(input$comp_metric, dt, shared$mvpa_col())
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
        labs(x = paste("Δ", metric_label(input$comp_metric)), y = NULL,
             subtitle = "M2 − M1 per school · horizontale lijnen = 95% BI") +
        theme_schoolmove(legend_pos = "none") +
        theme(panel.grid.major.y = element_blank(),
              panel.grid.major.x = element_line(colour = "#F4F5F7"))
    })

    # ── Correlation scatter ───────────────────────────────────────────────────
    corr_plot <- reactive({
      if (is.null(analysis_ready)) return(no_data_plot())
      if (!"sleep_duration_h" %in% names(analysis_ready))
        return(no_data_plot("Slaapkolom ontbreekt."))

      x_mc  <- metric_col_pure(input$comp_corr_x, analysis_ready, shared$mvpa_col())
      x_lab <- metric_label(input$comp_corr_x)
      if (is.null(x_mc) || !x_mc %in% names(analysis_ready))
        return(no_data_plot("Kolom niet beschikbaar voor geselecteerde X-as."))

      dt <- copy(analysis_ready[meets_sedentary_criteria == TRUE &
                                 !is.na(get(x_mc)) & !is.na(sleep_duration_h)])
      dt <- shared$apply_filters(dt)
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
                               " · Pearson r · lint = 95% BI")) +
        theme_schoolmove()
    })

    # ── Render outputs ────────────────────────────────────────────────────────
    output$plot_slopegraph <- renderPlotly({
      p <- slope_plot()
      suppressWarnings(
        ggplotly(p, tooltip = "text") |>
          layout(legend = list(orientation = "h")) |>
          config(displayModeBar = FALSE)
      )
    })
    output$plot_delta <- renderPlot(delta_plot())
    output$plot_corr  <- renderPlot(corr_plot())

    output$dl_plot_slope <- png_dl(slope_plot, "vergelijking_pijlen",  height = 1200)
    output$dl_plot_delta <- png_dl(delta_plot, "delta_per_school")
    output$dl_plot_corr  <- png_dl(corr_plot,  "correlatie")

    # ── Wilcoxon stats table ──────────────────────────────────────────────────
    output$table_stats <- renderDT({
      dt <- comp_data()
      if (is.null(dt)) return(datatable(data.frame(Bericht = "Geen data"), options = list(language = .dt_lang_nl)))
      mc <- metric_col_pure(input$comp_metric, dt, shared$mvpa_col())
      if (is.null(mc) || !mc %in% names(dt))
        return(datatable(data.frame(Bericht = "Kolom niet gevonden."), options = list(language = .dt_lang_nl)))

      wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
      if (!all(c("meting_1","meting_2") %in% names(wide)))
        return(datatable(data.frame(Bericht = "Onvoldoende data."), options = list(language = .dt_lang_nl)))
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
        sig   <- if (is.na(p_val)) "—"
                 else if (p_val < 0.05) "Ja" else "Nee"
        .(
          N         = n,
          M1_gem    = round(mean(meting_1), 1),
          M2_gem    = round(mean(meting_2), 1),
          delta_gem = round(mean(delta), 1),
          CI_95     = sprintf("[%.1f, %.1f]", mean(delta) - ci95, mean(delta) + ci95),
          p_waarde  = if (is.na(p_val)) "—"
                      else if (p_val < 0.001) "<0.001"
                      else sprintf("%.3f", p_val),
          sig       = sig,
          r_effect  = if (is.na(r_rb)) "—" else rb_effect_label(r_rb)
        )
      }, by = school_label]

      setnames(results,
               c("school_label","M1_gem","M2_gem","delta_gem","CI_95",
                 "p_waarde","sig","r_effect"),
               c("School","M1 gem.","M2 gem.","Δ gem.","95% BI",
                 "p-waarde","Sig.?","r (effectgrootte)"))

      datatable(results, rownames = FALSE, options = list(dom = "t", pageLength = 10, language = .dt_lang_nl)) |>
        formatStyle("Δ gem.", color = styleInterval(0, c("#C0392B","#27AE60"))) |>
        formatStyle("p-waarde",
                    color = styleEqual(c("<0.001"), c("#C0392B")),
                    fontWeight = "bold") |>
        formatStyle("Sig.?",
                    backgroundColor = styleEqual(c("Ja","Nee"), c("#d4edda","#ffffff")))
    })

    # ── School comparison summary table ───────────────────────────────────────
    output$table_school_comparison <- renderDT({
      mc <- shared$mvpa_col()
      if (is.null(analysis_ready) || is.null(mc)) return(datatable(data.frame(Bericht = "Geen data"), options = list(language = .dt_lang_nl)))

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
        .(N                    = n_valid,
          `MVPA gem. (min/dag)` = mvpa_m,
          `% WHO-norm`          = paste0(who_pct, "%"),
          `Slaap gem. (h)`      = if (has_sleep) as.character(slaap_m) else "—")
      }, by = .(School = school_label, Meting = meting_label)]

      datatable(agg[order(School, Meting)], rownames = FALSE,
                options = list(dom = "t", pageLength = 20, language = .dt_lang_nl)) |>
        formatStyle("% WHO-norm",
                    color = styleInterval(c("50%"), c("#C0392B", "#27AE60")))
    })

    # ── Per-participant wide comparison table ─────────────────────────────────
    participant_comp_data <- reactive({
      dt <- comp_data()
      if (is.null(dt)) return(NULL)
      mc <- metric_col_pure(input$comp_metric, dt, shared$mvpa_col())
      if (is.null(mc) || !mc %in% names(dt)) return(NULL)

      wide <- dcast(dt[!is.na(get(mc))], ID + school_label ~ meting, value.var = mc)
      if (!all(c("meting_1","meting_2") %in% names(wide))) return(NULL)
      wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
      wide[, delta_val := round(meting_2 - meting_1, 1)]
      wide[, meting_1  := round(meting_1, 1)]
      wide[, meting_2  := round(meting_2, 1)]
      wide <- wide[order(school_label, delta_val)]
      y_lab      <- metric_label(input$comp_metric)
      delta_name <- "Δ (M2−M1)"
      setnames(wide, c("school_label","meting_1","meting_2","delta_val"),
               c("School", paste0("M1 (", y_lab, ")"), paste0("M2 (", y_lab, ")"), delta_name))
      wide
    })

    output$table_participant_comp <- renderDT({
      dt <- participant_comp_data()
      if (is.null(dt) || nrow(dt) == 0)
        return(datatable(data.frame(Bericht = "Geen data beschikbaar."), options = list(language = .dt_lang_nl)))
      delta_col <- "Δ (M2−M1)"
      datatable(dt, rownames = FALSE, filter = "top",
                options = list(pageLength = 20, dom = "frtip", scrollX = TRUE, language = .dt_lang_nl)) |>
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
  })
}

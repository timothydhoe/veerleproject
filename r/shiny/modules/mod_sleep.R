# mod_sleep.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 4 "Slaap"
# UI + server for sleep KPIs, distribution violin, and Bland-Altman plot.
#
# shared list keys used:
#   apply_filters — session-scoped filter function from server.R
#
# Global objects accessed directly (defined in global.R):
#   analysis_ready, SCHOOL_LABELS, METINGEN_LABELS, WHO_SLEEP_MIN_H,
#   SCHOOL_COLORS, no_data_plot(), png_dl(), theme_schoolmove()
#
# NOTE: Sleep KPI cards (sleep_avg_pooled, sleep_delta, sleep_pct_short)
# read unfiltered analysis_ready — this is intentional; they show whole-cohort
# summary statistics, not filtered subsets.
# ─────────────────────────────────────────────────────────────────────────────

#' Sleep tab UI
modSleepUI <- function(id) {
  ns <- NS(id)
  tagList(
    # KPI ribbon (3 equal columns)
    layout_columns(
      fill       = FALSE,
      col_widths = c(4, 4, 4),
      gap        = "0.75rem",
      kpi_strip_card("moon",
        tip("Gem. slaap",
            "Gemiddelde geschatte slaapduur per nacht (SPT) · alle geldige deelnemers, beide metingen"),
        ns("sleep_avg_pooled")),
      kpi_strip_card("arrow-trend-up",
        tip("Δ M1 → M2",
            "Verandering in gem. slaapduur van Meting 1 naar Meting 2. Positief = langere slaap in M2."),
        ns("sleep_delta")),
      kpi_strip_card("triangle-exclamation",
        tip("< 8 uur per nacht",
            "% deelnemers onder WHO-aanbeveling voor 6–12 jaar (8–10h)"),
        ns("sleep_pct_short"))
    ),

    layout_sidebar(
      sidebar = sidebar(
        width = 230,
        selectInput(ns("sleep_metric"), "Maat",
                    choices = c(
                      "Slaapduur (h/nacht)"        = "duration",
                      "Slaapefficiëntie (%)"  = "efficiency"
                    )),
        hr(),
        p(class = "text-muted small",
          "Slaapdata zijn schattingen van de SPT (sleep period time) uit GGIR Part 5.",
          "WHO-richtlijn voor kinderen 6–12 jaar: 8–10 uur per nacht.")
      ),
      layout_columns(
        col_widths = c(8, 4),
        chart_card(
          header   = "Slaapverdeling per school",
          plot_id  = ns("plot_sleep_dist"),
          dl_id    = ns("dl_plot_sleep"),
          height   = "420px",
          subtitle = "Verdeling slaapduur per school en meting — vioolplot met mediaan"
        ),
        card(
          class       = "shadow-sm",
          full_screen = TRUE,
          card_header("Bland-Altman: Meting 1 vs Meting 2"),
          card_body(
            div(
              class = "alert alert-light border py-2 px-3 mb-2",
              style = "font-size:0.8rem; line-height:1.5;",
              tags$strong("Hoe lees je dit? "),
              "X-as = gemiddelde slaapduur M1 & M2. Y-as = verschil M2−M1.",
              " Zwarte lijn = gem. bias. Rode stippellijnen = 95% LoA (±1,96 SD).",
              tags$strong(" Goede overeenstemming:"),
              " bias ≈ 0, meeste punten vallen binnen de rode lijnen."
            ),
            plotOutput(ns("plot_bland_altman"), height = "300px")
          ),
          card_footer(
            class = "d-flex justify-content-end py-1",
            downloadButton(ns("dl_plot_bland_altman"), "PNG opslaan",
                           icon  = icon("download"),
                           class = "btn-outline-secondary btn-sm")
          )
        )
      )
    )
  )
}

#' Sleep tab server
mod_sleep_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    # ── Filtered reactive ────────────────────────────────────────────────────
    sleep_data <- reactive({
      if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready)) return(NULL)
      dt <- shared$apply_filters(
        copy(analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)])
      )
      dt[, school_label := SCHOOL_LABELS[school]]
      dt[, meting_label := METINGEN_LABELS[meting]]
      dt
    })

    sleep_data_msg <- reactive({
      if (is.null(analysis_ready))
        "Analysedata niet geladen — voer stap 03 opnieuw uit."
      else if (!"sleep_duration_h" %in% names(analysis_ready))
        "Slaapkolommen ontbreken — voer stap 03 opnieuw uit."
      else
        NULL
    })

    # ── KPI cards (whole-cohort, not filtered) ───────────────────────────────
    output$sleep_avg_pooled <- renderText({
      dt <- if (is.null(analysis_ready)) NULL else
        analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)]
      if (is.null(dt) || nrow(dt) == 0) return("—")
      sprintf("%.1f u/nacht", mean(dt$sleep_duration_h))
    })

    output$sleep_delta <- renderText({
      if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready)) return("—")
      m1_dt <- analysis_ready[meets_sedentary_criteria == TRUE & meting == "meting_1" & !is.na(sleep_duration_h)]
      m2_dt <- analysis_ready[meets_sedentary_criteria == TRUE & meting == "meting_2" & !is.na(sleep_duration_h)]
      if (nrow(m1_dt) == 0 || nrow(m2_dt) == 0) return("—")
      delta <- mean(m2_dt$sleep_duration_h) - mean(m1_dt$sleep_duration_h)
      arrow <- if (delta > 0.05) "▲ " else if (delta < -0.05) "▼ " else "► "
      paste0(arrow, sprintf("%+.2f u", delta))
    })

    output$sleep_pct_short <- renderText({
      dt <- if (is.null(analysis_ready)) NULL else
        analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)]
      if (is.null(dt) || nrow(dt) == 0) return("—")
      sprintf("%.0f%%", 100 * mean(dt$sleep_duration_h < WHO_SLEEP_MIN_H))
    })

    # ── Sleep distribution plot ──────────────────────────────────────────────
    sleep_dist_plot <- reactive({
      dt <- sleep_data()
      if (is.null(dt) || nrow(dt) == 0) return(no_data_plot(sleep_data_msg() %||% "Geen slaapdata."))
      y_col  <- if (input$sleep_metric == "duration") "sleep_duration_h" else "sleep_efficiency_pct"
      y_lab  <- if (input$sleep_metric == "duration") "Slaapduur (h/nacht)" else "Slaapefficiëntie (%)"
      if (!y_col %in% names(dt)) return(no_data_plot("Kolom niet beschikbaar — controleer of stap 03 klaar is."))

      agg <- dt[, {
        n   <- .N
        mu  <- mean(get(y_col), na.rm = TRUE)
        ci  <- qt(0.975, max(n - 1, 1)) * sd(get(y_col), na.rm = TRUE) / sqrt(n)
        .(mean_val = mu, ci95 = ci, n = n)
      }, by = .(school_label, meting_label)]

      wide <- tryCatch(
        dcast(agg, school_label ~ meting_label, value.var = c("mean_val", "ci95", "n")),
        error = function(e) NULL
      )
      m_labels <- unname(METINGEN_LABELS)
      has_both <- !is.null(wide) &&
        all(paste0("mean_val_", m_labels) %in% names(wide)) &&
        any(!is.na(wide[[paste0("mean_val_", m_labels[1])]]) &
              !is.na(wide[[paste0("mean_val_", m_labels[2])]]))

      dt[, val := get(y_col)]

      if (has_both) {
        wide <- wide[!is.na(`mean_val_Meting 1`) & !is.na(`mean_val_Meting 2`)]
        wide[, delta := `mean_val_Meting 2` - `mean_val_Meting 1`]

        p <- ggplot(wide, aes(y = reorder(school_label, `mean_val_Meting 1`))) +
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
          geom_errorbar(aes(xmin = `mean_val_Meting 1` - `ci95_Meting 1`,
                            xmax = `mean_val_Meting 1` + `ci95_Meting 1`),
                        orientation = "y", width = 0.18,
                        colour = "#3498DB", linewidth = 0.55) +
          geom_errorbar(aes(xmin = `mean_val_Meting 2` - `ci95_Meting 2`,
                            xmax = `mean_val_Meting 2` + `ci95_Meting 2`),
                        orientation = "y", width = 0.18,
                        colour = "#E67E22", linewidth = 0.55) +
          geom_segment(aes(x = `mean_val_Meting 1`, xend = `mean_val_Meting 2`,
                           yend = reorder(school_label, `mean_val_Meting 1`),
                           colour = ifelse(delta >= 0, "Toename", "Afname")),
                       linewidth = 1.4, alpha = 0.7) +
          geom_point(aes(x = `mean_val_Meting 1`), colour = "#3498DB", size = 4, shape = 16) +
          geom_point(aes(x = `mean_val_Meting 2`), colour = "#E67E22", size = 4, shape = 16) +
          geom_text(aes(x = pmin(`mean_val_Meting 1`, `mean_val_Meting 2`) - 0.1,
                        label = paste0("n=", `n_Meting 1`)),
                    hjust = 1, size = 2.5, colour = "grey50") +
          scale_colour_manual(
            values = c("Meting 1" = "#3498DB", "Meting 2" = "#E67E22",
                       "Toename" = "#36B37E", "Afname" = "#FF5630"),
            guide = "none"
          ) +
          labs(x = y_lab, y = NULL,
               subtitle = "Punten = individuele leerlingen · M1 (blauw) · M2 (oranje) · grote punten = schoolgemiddelde · foutbalken = 95% BI") +
          theme_schoolmove(legend_pos = "none") +
          theme(panel.grid.major.y = element_blank(),
                panel.grid.major.x = element_line(colour = "#F4F5F7"))

        if (input$sleep_metric == "duration")
          p <- p +
            annotate("rect", xmin = 8, xmax = 10, ymin = -Inf, ymax = Inf,
                     fill = "#36B37E", alpha = 0.07, colour = NA) +
            annotate("text", x = 9, y = Inf,
                     label = "WHO: 8–10u", vjust = -0.4, colour = "#36B37E",
                     size = 2.8, fontface = "italic")
        else if (input$sleep_metric == "efficiency")
          p <- p +
            geom_hline(yintercept = 85, linetype = "dashed",
                       colour = "#36B37E", linewidth = 0.6) +
            annotate("text", x = Inf, y = 85,
                     label = "85% drempel", hjust = 1.1, vjust = -0.5,
                     colour = "#36B37E", size = 2.8, fontface = "italic")
        p

      } else {
        ggplot(agg, aes(x = mean_val, y = reorder(school_label, mean_val),
                        colour = meting_label)) +
          geom_pointrange(aes(xmin = mean_val - ci95, xmax = mean_val + ci95),
                          linewidth = 0.8, size = 2.0) +
          geom_text(aes(label = paste0("n=", n)),
                    hjust = -0.3, size = 2.6, colour = "grey50") +
          scale_colour_manual(values = c("Meting 1" = "#3498DB", "Meting 2" = "#E67E22")) +
          labs(x = y_lab, y = NULL, colour = NULL,
               subtitle = "Schoolgemiddelde · foutbalken = 95% BI") +
          theme_schoolmove() +
          theme(panel.grid.major.y = element_blank())
      }
    })

    # ── Bland-Altman plot ────────────────────────────────────────────────────
    bland_altman_plot <- reactive({
      if (is.null(analysis_ready) || !"sleep_duration_h" %in% names(analysis_ready))
        return(no_data_plot())
      dt <- shared$apply_filters(
        copy(analysis_ready[meets_sedentary_criteria == TRUE & !is.na(sleep_duration_h)])
      )
      dt[, school_label := SCHOOL_LABELS[school]]
      wide <- dcast(dt, ID + school_label ~ meting, value.var = "sleep_duration_h")
      if (!all(c("meting_1","meting_2") %in% names(wide))) return(no_data_plot("Niet genoeg metingen."))
      wide <- wide[!is.na(meting_1) & !is.na(meting_2)]
      if (nrow(wide) == 0) return(no_data_plot("Geen data om te vergelijken — beide metingen nodig."))

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
             y = "Verschil M2 − M1 (u/nacht)",
             colour = NULL,
             subtitle = "Bland-Altman overeenkomstplot · rood = 95% limieten van overeenstemming") +
        theme_schoolmove()
    })

    # ── Render outputs ───────────────────────────────────────────────────────
    output$plot_sleep_dist      <- renderPlot(sleep_dist_plot())
    output$plot_bland_altman    <- renderPlot(bland_altman_plot())
    output$dl_plot_sleep        <- png_dl(sleep_dist_plot,   "slaapverdeling")
    output$dl_plot_bland_altman <- png_dl(bland_altman_plot, "slaap_bland_altman")
  })
}

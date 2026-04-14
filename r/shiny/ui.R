# ui.R
# ─────────────────────────────────────────────────────────────────────────────
# SchoolMove dashboard layout — 6 tabs.
# ─────────────────────────────────────────────────────────────────────────────

# ── Reusable: chart card with optional PNG download button ────────────────────
chart_card <- function(header, plot_id, dl_id = NULL, height = "460px",
                       subtitle = NULL, full_screen = TRUE, plotly = FALSE) {
  footer <- if (!is.null(dl_id)) {
    card_footer(
      class = "d-flex justify-content-end py-1",
      downloadButton(dl_id, "PNG opslaan",
                     icon  = icon("download"),
                     class = "btn-outline-secondary btn-sm")
    )
  }
  plot_widget <- if (plotly) plotlyOutput(plot_id, height = height) else plotOutput(plot_id, height = height)
  card(
    class       = "shadow-sm",
    full_screen = full_screen,
    card_header(header),
    card_body(
      class = "p-3",
      if (!is.null(subtitle)) p(class = "text-muted small mb-2", subtitle),
      plot_widget
    ),
    footer
  )
}

# ── Tooltip helper ────────────────────────────────────────────────────────────
tip <- function(label, text) {
  tagList(
    label,
    tooltip(
      span(icon("circle-info"), style = "color:#94a3b8; margin-left:4px; font-size:0.8em;"),
      text
    )
  )
}

# ── Compact KPI strip card ────────────────────────────────────────────────────
kpi_strip_card <- function(icon_nm, title_ui, value_id) {
  div(
    class = "card kpi-strip",
    div(
      class = "card-body",
      div(class = "kpi-strip-icon", icon(icon_nm)),
      div(
        class = "kpi-strip-text",
        div(class = "kpi-strip-title", title_ui),
        div(class = "kpi-strip-value", textOutput(value_id))
      )
    )
  )
}

# ── Fallback warning (shared across tabs that use segment data) ───────────────
fallback_banner <- function() {
  if (length(FALLBACK_SCHOOLS) == 0) return(NULL)
  school_names <- paste(SCHOOL_LABELS[FALLBACK_SCHOOLS], collapse = ", ")
  div(
    class = "readiness-strip",
    style = "background:#fff3cd; border-bottom-color:#ffc107;",
    tags$span(class = "check-warn",
      icon("triangle-exclamation"),
      paste0(" Geschat rooster: ", school_names,
             " \u2014 segmentresultaten zijn benaderingen.")
    )
  )
}

# ── Custom CSS ────────────────────────────────────────────────────────────────
app_css <- tags$head(tags$style(HTML("

  /* ── Global base ── */
  body {
    background-color: #f1f5f9 !important;
    font-size: 15px;
  }

  /* ── Cards: white with subtle lift shadow, no harsh border ── */
  .card {
    background: #ffffff;
    border: 1px solid #e2e8f0 !important;
    box-shadow: 0 1px 4px rgba(30,41,59,0.07) !important;
    border-radius: 8px !important;
  }
  .card-header {
    background: #ffffff !important;
    border-bottom: 1px solid #f1f5f9 !important;
    font-weight: 600;
    font-size: 0.88rem;
    color: #1e293b;
    padding: 0.75rem 1rem !important;
  }
  .card-body { padding: 1rem !important; }
  .card-footer {
    background: #ffffff !important;
    border-top: 1px solid #f1f5f9 !important;
  }

  /* ── Sidebar: lightly tinted background ── */
  .bslib-sidebar-layout > .sidebar,
  .bslib-sidebar-layout > .bslib-sidebar {
    background-color: #f8fafc !important;
    border-right: 1px solid #e2e8f0 !important;
  }
  .sidebar .form-label,
  .sidebar label { font-size: 0.82rem; font-weight: 600; color: #475569; }
  .sidebar .form-control,
  .sidebar .form-select { font-size: 0.85rem; }
  .sidebar hr { border-color: #e2e8f0; }

  /* ── layout_columns: breathing room between cards ── */
  .bslib-gap-spacing { gap: 1.1rem !important; }

  /* ── KPI strip cards ── */
  .kpi-strip {
    background: #ffffff;
    border: 1px solid #e2e8f0 !important;
    box-shadow: 0 1px 3px rgba(30,41,59,0.06) !important;
    height: 82px !important;
    border-radius: 8px !important;
  }
  .kpi-strip .card-body {
    padding: 0 1rem !important;
    height: 100%;
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }
  .kpi-strip-icon {
    color: #94a3b8;
    font-size: 1.25rem;
    width: 28px;
    flex-shrink: 0;
    text-align: center;
    line-height: 1;
  }
  .kpi-strip-icon svg { width: 1.25rem !important; height: 1.25rem !important; }
  .kpi-strip-text { min-width: 0; }
  .kpi-strip-title {
    font-size: 0.63rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #94a3b8;
    line-height: 1.2;
    margin-bottom: 3px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .kpi-strip-value {
    font-size: 1.35rem;
    font-weight: 700;
    color: #1e293b;
    line-height: 1.1;
    white-space: nowrap;
  }
  .kpi-strip-value .shiny-text-output { display: inline; }

  /* ── Clickable KPI cards ── */
  .kpi-nav-card { cursor: pointer; }
  .kpi-nav-card:hover .kpi-strip {
    border-color: #cbd5e1 !important;
    box-shadow: 0 3px 10px rgba(30,41,59,0.11) !important;
    transform: translateY(-2px);
    transition: all 0.15s ease;
  }

  /* ── Pipeline trigger row ── */
  .pipeline-bar {
    display: flex;
    align-items: center;
    gap: 12px;
    background: #f8fafc;
    border-bottom: 1px solid #e2e8f0;
    padding: 8px 20px;
    font-size: 0.82rem;
    color: #64748b;
    margin-bottom: 0.25rem;
  }
  .pipeline-bar .pipeline-label { font-weight: 600; color: #475569; }

  /* ── Active navbar tab ── */
  .navbar-nav .nav-link[aria-selected='true'],
  .navbar-nav .nav-link.active {
    color: rgba(255,255,255,1) !important;
    background: rgba(255,255,255,0.15) !important;
    border-radius: 5px;
  }
  .navbar-nav .nav-link { color: rgba(255,255,255,0.8) !important; font-size: 0.87rem; }

  /* ── Navbar filter controls ── */
  .navbar .form-select,
  .navbar .form-control {
    background-color: rgba(255,255,255,0.12) !important;
    border-color: rgba(255,255,255,0.22) !important;
    color: #fff !important;
    font-size: 0.81rem !important;
    height: 30px !important;
    padding-top: 3px !important;
    padding-bottom: 3px !important;
    line-height: 1.3 !important;
  }
  .navbar .form-select option,
  .navbar .form-control option {
    background-color: #1e293b;
    color: #fff;
  }
  .navbar .filter-label {
    color: rgba(255,255,255,0.65);
    font-size: 0.78rem;
    font-weight: 500;
    white-space: nowrap;
    line-height: 30px;
  }
  .navbar-nav > .nav-item > div {
    padding-top: 4px !important;
    padding-bottom: 4px !important;
  }
  .navbar .shiny-input-container,
  .navbar .form-group { margin-bottom: 0 !important; }
  .navbar-collapse {
    flex-wrap: nowrap !important;
    align-items: center !important;
  }
  .navbar .navbar-nav {
    flex-wrap: nowrap !important;
    align-items: center !important;
  }

  /* ── Data-readiness strip ── */
  .readiness-strip {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 16px;
    align-items: center;
    background: #f8fafc;
    border-bottom: 1px solid #e2e8f0;
    padding: 8px 20px;
    font-size: 0.8rem;
    color: #64748b;
  }
  .readiness-strip .check-ok   { color: #16a34a; font-weight: 600; }
  .readiness-strip .check-warn { color: #b45309; font-weight: 600; }
  .readiness-strip .check-miss { color: #dc2626; font-weight: 600; }

  /* ── Loading shimmer on recalculating plots ── */
  .shiny-plot-output.shiny-output-recalculating,
  .shiny-plotly-output.shiny-output-recalculating {
    min-height: 40px;
    background: linear-gradient(90deg, #f1f5f9 25%, #e2e8f0 50%, #f1f5f9 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
    border-radius: 4px;
    opacity: 0.8;
  }
  @keyframes shimmer {
    0%   { background-position: 200% 0; }
    100% { background-position: -200% 0; }
  }

  /* ── Segmented control (Schooldag view toggle) ── */
  #seg_view .shiny-options-group {
    display: flex;
    margin-top: 4px;
  }
  #seg_view .shiny-options-group .radio { flex: 1; margin: 0; }
  #seg_view .shiny-options-group .radio label {
    display: block;
    text-align: center;
    padding: 5px 8px;
    font-size: 0.8rem;
    border: 1.5px solid #1e293b;
    cursor: pointer;
    background: white;
    color: #1e293b;
    font-weight: 500;
    margin: 0;
    transition: background 0.1s, color 0.1s;
  }
  #seg_view .shiny-options-group .radio:first-child label { border-radius: 4px 0 0 4px; }
  #seg_view .shiny-options-group .radio:last-child label {
    border-radius: 0 4px 4px 0;
    border-left: none;
  }
  #seg_view .shiny-options-group .radio input[type=radio]:checked + label {
    background: #1e293b;
    color: white;
  }
  #seg_view .shiny-options-group .radio input[type=radio] {
    position: absolute;
    width: 1px;
    height: 1px;
    opacity: 0;
    pointer-events: none;
  }
  #seg_view > label { font-weight: 600; font-size: 0.85rem; color: #334155; }

  /* ── Rapport samenvatting text area ── */
  #rapport_text_out {
    font-family: 'Georgia', serif;
    font-size: 0.92rem;
    line-height: 1.65;
    white-space: pre-wrap;
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
    padding: 0.85rem 1.1rem;
    color: #1e293b;
  }

  /* ── Vergelijking tab: no height clipping ── */
  .comp-subtab-content { padding-top: 0.5rem; }
  #comp_subtab,
  #comp_subtab .bslib-sidebar-layout,
  #comp_subtab .bslib-sidebar-layout > .main,
  #comp_subtab .bslib-card,
  #comp_subtab .card {
    overflow: visible !important;
    max-height: none !important;
  }

  /* ── No internal scroll on cards containing plots ── */
  .card-body.plot-body {
    overflow: visible !important;
    min-height: 300px;
  }

  /* ── Export buttons ── */
  .export-dl-btn { min-width: 180px; text-align: left; }
  .export-dl-btn.disabled-btn {
    opacity: 0.4;
    cursor: not-allowed;
    pointer-events: none;
  }

  /* ── Accordion: match card aesthetic ── */
  .accordion-item { border: 1px solid #e2e8f0 !important; border-radius: 8px !important; }
  .accordion-button { font-size: 0.88rem; font-weight: 600; }
  .accordion-button:not(.collapsed) { background-color: #f8fafc !important; color: #1e293b !important; }
")))

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- tagList(
  app_css,
  page_navbar(
    id       = "main_nav",
    title    = "SchoolMove",
    fillable = FALSE,
    theme    = bs_theme(
      version      = 5,
      bg           = "#f1f5f9",
      fg           = "#1e293b",
      primary      = "#1e293b",
      base_font    = font_google("Inter"),
      heading_font = font_google("Inter")
    ),
    navbar_options = navbar_options(bg = "#1e293b"),

    # ── Tab 1: Overzicht ───────────────────────────────────────────────────────
    nav_panel(
      "Overzicht",
      icon = icon("chart-bar"),

      uiOutput("data_readiness_strip"),

      div(class = "pipeline-bar",
        span(class = "pipeline-label", "Pipeline:"),
        actionButton("btn_run_pipeline", "Pipeline uitvoeren",
                     icon  = icon("play"),
                     class = "btn-sm btn-outline-primary"),
        uiOutput("pipeline_status_inline")
      ),

      # KPI ribbon
      layout_columns(
        fill = FALSE,
        col_widths = c(2, 2, 3, 2, 3),
        gap = "0.75rem",
        tags$div(class = "kpi-nav-card",
          onclick = "Shiny.setInputValue('kpi_click','Deelnemers',{priority:'event'})",
          kpi_strip_card("users", "Deelnemers", "n_participants")
        ),
        tags$div(class = "kpi-nav-card",
          onclick = "Shiny.setInputValue('kpi_click','Deelnemers',{priority:'event'})",
          kpi_strip_card("circle-check",
            tip("Geldig voor analyse",
                "Voldoet aan draagduurcriteria (minimaal geldige dagen incl. 1 weekend)"),
            "pct_valid")
        ),
        tags$div(class = "kpi-nav-card",
          onclick = "Shiny.setInputValue('kpi_click','Schooldag',{priority:'event'})",
          kpi_strip_card("person-running",
            tip("Gem. MVPA",
                "Matig-tot-intensieve beweging per dag \u00b7 enkel geldige deelnemers"),
            "avg_mvpa")
        ),
        tags$div(class = "kpi-nav-card",
          onclick = "Shiny.setInputValue('kpi_click','Vergelijking',{priority:'event'})",
          kpi_strip_card("award",
            tip("WHO-richtlijn gehaald", "% deelnemers met \u226560 min MVPA/dag"),
            "pct_who")
        ),
        tags$div(class = "kpi-nav-card",
          onclick = "Shiny.setInputValue('kpi_click','Slaap',{priority:'event'})",
          kpi_strip_card("moon",
            tip("Gem. slaap", "Geschatte slaapduur per nacht (SPT)"),
            "avg_sleep")
        )
      ),

      # Main content: focal activity plot + school summary table
      layout_columns(
        col_widths = c(8, 4),
        chart_card(
          header   = "MVPA verandering per school: Meting 1 \u2192 Meting 2",
          plot_id  = "plot_activity_stacked",
          dl_id    = "dl_plot_overview",
          height   = "500px",
          subtitle = "Grijs = M1 \u00b7 kleur = M2 \u00b7 groen = toename MVPA \u00b7 enkel geldige deelnemers"
        ),
        card(
          class       = "shadow-sm",
          full_screen = TRUE,
          card_header(tip("Schooloverzicht",
            "Gem. MVPA, % WHO-norm en slaap per school \u00b7 enkel geldige deelnemers")),
          card_body(
            p(class = "text-muted small mb-2",
              "Gecombineerd over beide metingen \u00b7 enkel geldige deelnemers."),
            DTOutput("table_school_overview")
          )
        )
      ),

      accordion(
        id   = "rapport_accordion",
        open = "rapport",
        accordion_panel(
          title = tagList(icon("file-lines"), " Samenvatting voor rapport"),
          value = "rapport",
          uiOutput("rapport_samenvatting_ui")
        )
      )
    ),

    # ── Tab 2: Deelnemers ─────────────────────────────────────────────────────
    nav_panel(
      "Deelnemers",
      icon = icon("users"),
      layout_sidebar(
        sidebar = sidebar(
          width = 240,
          p(class = "text-muted small fw-semibold mb-1", "Deelnemer bekijken"),
          selectInput("explorer_id", NULL,
                      choices = c("Kies een deelnemer..." = ""),
                      width   = "100%"),
          helpText(class = "text-muted", style = "font-size:0.75rem;",
                   "Of klik een rij in de inclusietabel hieronder.")
        ),
        # Individual explorer charts — primary focus, always visible
        layout_columns(
          col_widths = c(6, 6),
          chart_card(header = "MVPA per dag",
                     plot_id = "plot_explorer_mvpa",
                     dl_id   = "dl_plot_explorer_mvpa",
                     height  = "380px"),
          chart_card(header = "Activiteit per segment (M1 vs M2)",
                     plot_id = "plot_explorer_segments",
                     dl_id   = "dl_plot_explorer_segments",
                     height  = "380px")
        ),
        # Wear heatmap — secondary context
        chart_card(
          header   = "Draagduuroverzicht",
          plot_id  = "plot_wear_heatmap",
          dl_id    = "dl_plot_wear",
          height   = "500px",
          subtitle = paste0("Groen = geldig (\u2265", MIN_WEAR_H,
                            "h draagduur) \u00b7 rood = onvoldoende of niet gedragen")
        ),
        # Inclusion table — reference
        card(
          class       = "shadow-sm",
          full_screen = TRUE,
          card_header("Inclusie / exclusie"),
          card_body(
            div(
              style = "display:flex; align-items:center; gap:16px; margin-bottom:10px; flex-wrap:wrap;",
              div(style = "font-size:0.82rem; font-weight:600; color:#475569;", "Filter:"),
              radioButtons(
                "incl_status_filter", NULL,
                choices  = c("Alle" = "all", "Inbegrepen" = "included", "Uitgesloten" = "excluded"),
                selected = "all",
                inline   = TRUE
              )
            ),
            p(class = "text-muted small",
              "Deelnemers die niet voldoen aan het minimumaantal geldige draagdagen",
              "worden uitgesloten van de sedentaire analyse.",
              strong(" Klik een rij om die deelnemer te bekijken.")),
            DTOutput("table_inclusion")
          )
        )
      )
    ),

    # ── Tab 3: Schooldag ──────────────────────────────────────────────────────
    nav_panel(
      "Schooldag",
      icon = icon("school"),
      fallback_banner(),
      layout_sidebar(
        sidebar = sidebar(
          width = 230,
          radioButtons("seg_view", "Hoofdgrafiek",
                       choices  = c("E\u00e9n zone" = "single", "Alle zones" = "budget"),
                       selected = "single"),
          conditionalPanel(
            condition = "input.seg_view == 'single'",
            selectInput("seg_metric", "Zone",
                        choices = c(
                          "MVPA (min/dag)"         = "mvpa",
                          "Licht actief (min/dag)" = "lig",
                          "Sedentair (min/dag)"    = "sb"
                        ))
          ),
        ),
        layout_columns(
          col_widths = c(7, 5),
          chart_card(
            header   = "Activiteit per schooldagsegment",
            plot_id  = "plot_segment_activity",
            dl_id    = "dl_plot_segment",
            height   = "480px",
            subtitle = "Gem. min/dag per activiteitszone voor elk deel van de schooldag (Ma\u2013Vr) \u00b7 enkel geldige deelnemers"
          ),
          chart_card(
            header   = "MVPA tijdens pauze per school",
            plot_id  = "plot_recess_mvpa",
            dl_id    = "dl_plot_recess",
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
              radioButtons("seg_weekday", NULL, inline = TRUE,
                           choices  = c("Schooldagen (Ma\u2013Vr)" = "schooldays",
                                        "Weekend (Za & Zo)"        = "weekend"),
                           selected = "schooldays")
            )
          ),
          card_body(
            class = "p-3",
            p(class = "text-muted small mb-2",
              "Gem. MVPA per dag per school \u00b7 lijn = gem., band = 95% BI"),
            plotOutput("plot_weekday", height = "320px")
          ),
          card_footer(
            class = "d-flex justify-content-end py-1",
            downloadButton("dl_plot_weekday", "PNG opslaan",
                           icon  = icon("download"),
                           class = "btn-outline-secondary btn-sm")
          )
        ),
        card(
          class       = "shadow-sm",
          full_screen = TRUE,
          card_header(
            tip("Sedentaire bouten",
                "Aaneengesloten perioden van inactiviteit. Langdurig zitten (\u226530 min) is een onafhankelijke gezondheidsrisicofactor.")
          ),
          card_body(
            p(class = "text-muted small mb-2",
              "Gem. aantal aaneengesloten sedentaire perioden (\u226530 min) per dag \u00b7 foutbalken = 95% BI"),
            plotOutput("plot_bouts", height = "280px")
          )
        ),
        card(
          class       = "shadow-sm",
          full_screen = TRUE,
          card_header("Detailtabel per segment"),
          card_body(DTOutput("table_segment_detail"))
        )
      )
    ),

    # ── Tab 4: Slaap ──────────────────────────────────────────────────────────
    nav_panel(
      "Slaap",
      icon = icon("moon"),

      # KPI ribbon (3 equal columns)
      layout_columns(
        fill       = FALSE,
        col_widths = c(4, 4, 4),
        gap        = "0.75rem",
        kpi_strip_card("moon",
          tip("Gem. slaap",
              "Gemiddelde geschatte slaapduur per nacht (SPT) \u00b7 alle geldige deelnemers, beide metingen"),
          "sleep_avg_pooled"),
        kpi_strip_card("arrow-trend-up",
          tip("\u0394 M1 \u2192 M2",
              "Verandering in gem. slaapduur van Meting 1 naar Meting 2. Positief = langere slaap in M2."),
          "sleep_delta"),
        kpi_strip_card("triangle-exclamation",
          tip("< 8 uur per nacht",
              "% deelnemers onder WHO-aanbeveling voor 6\u201312 jaar (8\u201310h)"),
          "sleep_pct_short")
      ),

      layout_sidebar(
        sidebar = sidebar(
          width = 230,
          selectInput("sleep_metric", "Maat",
                      choices = c(
                        "Slaapduur (h/nacht)"       = "duration",
                        "Slaapeffici\u00ebntie (%)" = "efficiency"
                      )),
          hr(),
          p(class = "text-muted small",
            "Slaapdata zijn schattingen van de SPT (sleep period time) uit GGIR Part 5.",
            "WHO-richtlijn voor kinderen 6\u201312 jaar: 8\u201310 uur per nacht.")
        ),
        # Violin 2/3, Bland-Altman 1/3
        layout_columns(
          col_widths = c(8, 4),
          chart_card(
            header   = "Slaapverdeling per school",
            plot_id  = "plot_sleep_dist",
            dl_id    = "dl_plot_sleep",
            height   = "420px",
            subtitle = "Verdeling slaapduur per school en meting \u2014 vioolplot met mediaan"
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
                "X-as = gemiddelde slaapduur M1 & M2. Y-as = verschil M2\u2212M1.",
                " Zwarte lijn = gem. bias. Rode stippellijnen = 95% LoA (\u00b11,96 SD).",
                tags$strong(" Goede overeenstemming:"),
                " bias \u2248 0, meeste punten vallen binnen de rode lijnen."
              ),
              plotOutput("plot_bland_altman", height = "300px")
            ),
            card_footer(
              class = "d-flex justify-content-end py-1",
              downloadButton("dl_plot_bland_altman", "PNG opslaan",
                             icon  = icon("download"),
                             class = "btn-outline-secondary btn-sm")
            )
          )
        )
      )
    ),

    # ── Tab 5: Vergelijking metingen ──────────────────────────────────────────
    nav_panel(
      "Meting 1 vs 2",
      value = "Vergelijking",
      icon  = icon("arrows-left-right"),
      navset_card_tab(
        id = "comp_subtab",

        # ── Sub-tab A: Longitudinaal ──
        nav_panel(
          title = tagList(icon("clock-rotate-left"), " Longitudinaal"),
          value = "longitudinaal",
          div(class = "comp-subtab-content",
            layout_sidebar(
              sidebar = sidebar(
                width = 230,
                selectInput("comp_metric", "Maat",
                            choices = c(
                              "MVPA (min/dag)"            = "mvpa",
                              "Sedentair (min/dag)"       = "sb",
                              "SB bouts \u226530 min/dag" = "bouts30",
                              "Licht actief (min/dag)"    = "lpa",
                              "Slaap (h/nacht)"           = "sleep"
                            )),
                hr(),
                p(class = "text-muted small",
                  "Pijlen = schoolgemiddelde \u00b7 punten = individuele deelnemers.",
                  "Stijgende pijl = toename in Meting 2.")
              ),
              # Full-width slope graph
              card(
                class       = "shadow-sm",
                full_screen = TRUE,
                card_header("Meting 1 \u2192 Meting 2 per deelnemer"),
                card_body(
                  p(class = "text-muted small mb-2",
                    "Punten = individuele deelnemers \u00b7 pijlen = schoolgemiddelde \u00b7 hover = ID + waarden"),
                  plotlyOutput("plot_slopegraph", height = "520px")
                ),
                card_footer(
                  class = "d-flex justify-content-end py-1",
                  downloadButton("dl_plot_slope", "PNG opslaan",
                                 icon  = icon("download"),
                                 class = "btn-outline-secondary btn-sm")
                )
              ),
              # Stats + effect size below, side by side
              layout_columns(
                col_widths = c(6, 6),
                card(
                  class = "shadow-sm",
                  card_header(
                    tip("Statistisch overzicht",
                        "Wilcoxon signed-rank test (paarsgewijs). r = rang-biseri\u00eble correlatie: |r| < 0.1 klein, 0.1\u20130.3 middel, > 0.5 groot")
                  ),
                  card_body(
                    p(class = "text-muted small mb-2",
                      "Gemiddelde verandering (\u0394) en 95%-betrouwbaarheidsinterval per school."),
                    DTOutput("table_stats")
                  )
                ),
                chart_card(
                  header   = "Effectgrootte per school",
                  plot_id  = "plot_delta",
                  dl_id    = "dl_plot_delta",
                  height   = "300px",
                  subtitle = "\u0394 = M2 \u2212 M1 \u00b7 punt = gemiddelde \u00b7 lijn = 95% BI"
                )
              )
            )
          )
        ),

        # ── Sub-tab B: Correlaties ──
        nav_panel(
          title = tagList(icon("circle-dot"), " Correlaties"),
          value = "correlaties",
          div(class = "comp-subtab-content",
            layout_sidebar(
              sidebar = sidebar(
                width = 230,
                selectInput("comp_corr_x", "X-as",
                            choices = c(
                              "MVPA (min/dag)"        = "mvpa",
                              "Sedentair (min/dag)"   = "sb",
                              "SB bouts \u226530 min" = "bouts30"
                            )),
                selectInput("comp_corr_meting", "Meting",
                            choices = setNames(names(METINGEN_LABELS), METINGEN_LABELS)),
                hr(),
                p(class = "text-muted small",
                  "Y-as is altijd slaapduur. Pearson r staat in de grafiek.")
              ),
              chart_card(
                header   = "Correlatie",
                plot_id  = "plot_corr",
                dl_id    = "dl_plot_corr",
                height   = "380px",
                subtitle = "Verband tussen geselecteerde maten per school \u00b7 lijn = lineaire trend \u00b7 lint = 95% BI"
              ),
              card(
                class       = "shadow-sm",
                full_screen = TRUE,
                card_header("Schoolvergelijking: samenvatting"),
                card_body(
                  p(class = "text-muted small mb-2",
                    "Overzicht van alle scholen per meting \u2014 enkel geldige deelnemers."),
                  DTOutput("table_school_comparison")
                )
              ),
              card(
                class       = "shadow-sm",
                full_screen = TRUE,
                card_header("Per deelnemer: Meting 1 vs Meting 2"),
                card_body(
                  p(class = "text-muted small mb-2",
                    "Gesorteerd op kleinste verandering (\u0394). Rood = afname, groen = toename."),
                  DTOutput("table_participant_comp")
                ),
                card_footer(
                  class = "d-flex justify-content-end py-1",
                  downloadButton("dl_participant_comp", "CSV downloaden",
                                 icon  = icon("download"),
                                 class = "btn-outline-success btn-sm")
                )
              )
            )
          )
        )
      )
    ),

    # ── Tab 6: Export ─────────────────────────────────────────────────────────
    nav_panel(
      "Export",
      icon = icon("download"),
      card(
        class = "shadow-sm",
        card_header("Download analysedata"),
        card_body(
          p("Alle bestanden zijn CSV-formaat en bevatten de meest recente pipeline-output."),
          uiOutput("export_panel_ui")
        )
      )
    ),

    # ── Tab 7: Instellingen (Settings) ───────────────────────────────────────
    nav_panel(
      "Instellingen",
      icon = icon("sliders"),
      layout_columns(
        col_widths = c(12),

        # ── Profile manager ────────────────────────────────────────────────────
        card(
          class = "shadow-sm",
          card_header(
            class = "d-flex align-items-center gap-2",
            icon("layer-group"), "Profielbeheer"
          ),
          card_body(
            p(class = "text-muted small",
              "Sla een set parameters op onder een naam en laad deze later terug. ",
              "Klik 'Activeer' om het profiel te koppelen aan de pipeline."),
            layout_columns(
              col_widths = c(5, 7),
              div(
                selectInput("settings_profile_select", "Beschikbare profielen",
                            choices = character(0), width = "100%"),
                div(
                  style = "display:flex; gap:8px; flex-wrap:wrap;",
                  actionButton("settings_load_profile",     "Laad",
                               icon = icon("upload"), class = "btn-outline-secondary btn-sm"),
                  actionButton("settings_save_profile",     "Opslaan als\u2026",
                               icon = icon("floppy-disk"), class = "btn-outline-primary btn-sm"),
                  actionButton("settings_activate_profile", "Activeer",
                               icon = icon("check"),       class = "btn-success btn-sm")
                )
              ),
              div(
                uiOutput("settings_active_profile_badge"),
                uiOutput("settings_profile_notes")
              )
            )
          )
        ),

        # ── Validity parameters ────────────────────────────────────────────────
        card(
          class = "shadow-sm",
          card_header(
            class = "d-flex align-items-center gap-2",
            icon("calendar-check"), "Geldigheidsparameters"
          ),
          card_body(
            p(class = "text-muted small",
              "Bepaal wanneer een dag, nacht of meting als geldig telt. ",
              "Pas alleen aan op basis van het studieprotocol."),
            layout_columns(
              col_widths = c(6, 6),
              div(
                numericInput("settings_min_wear_h", "Min. draaguren per dag",
                             value = 16, min = 1, max = 24, step = 1, width = "100%"),
                p(class = "text-muted small mt-n2",
                  "Een dag telt als geldig als het acceleratometer \u2265N uur gedragen werd."),

                numericInput("settings_min_valid_days", "Min. geldige dagen per meting",
                             value = 3, min = 1, max = 14, step = 1, width = "100%"),
                p(class = "text-muted small mt-n2",
                  "Een deelnemer wordt alleen opgenomen als hij/zij \u2265N geldige dagen heeft."),

                checkboxInput("settings_require_weekend", "Minstens 1 geldig weekenddag vereist",
                              value = TRUE)
              ),
              div(
                numericInput("settings_min_valid_nights", "Min. geldige nachten (slaap)",
                             value = 5, min = 1, max = 14, step = 1, width = "100%"),
                p(class = "text-muted small mt-n2",
                  "Voor de slaapanalyse: min. nachten met \u226550% geldige slaapregistratie."),

                numericInput("settings_min_pct_night", "Min. % geldige slaap per nacht",
                             value = 50, min = 10, max = 100, step = 5, width = "100%")
              )
            )
          )
        ),

        # ── Activity cut-points ────────────────────────────────────────────────
        card(
          class = "shadow-sm",
          card_header(
            class = "d-flex align-items-center gap-2",
            icon("gauge"), "Activiteitsdrempels (ENMO, mg)"
          ),
          card_body(
            div(
              class = "alert alert-warning small py-2 mb-3",
              icon("triangle-exclamation"), " ",
              "Pas deze waarden alleen aan als je de wetenschappelijke referentie hebt ",
              "gecontroleerd. Standaard: Hildebrand et al. 2014/2017, pols, kinderen."
            ),
            layout_columns(
              col_widths = c(4, 4, 4),
              numericInput("settings_cp_sb_lpa", "SB \u2192 LPA (mg)",
                           value = 56.3,  min = 1, max = 999, step = 0.1, width = "100%"),
              numericInput("settings_cp_lpa_mpa", "LPA \u2192 MPA (mg)",
                           value = 191.6, min = 1, max = 999, step = 0.1, width = "100%"),
              numericInput("settings_cp_mpa_vpa", "MPA \u2192 VPA (mg)",
                           value = 695.8, min = 1, max = 9999, step = 0.1, width = "100%")
            ),
            layout_columns(
              col_widths = c(6, 6),
              numericInput("settings_bout_sb_min", "Min. sedentaire bout (min.)",
                           value = 30, min = 1, max = 120, step = 1, width = "100%"),
              checkboxInput("settings_bout_split_context",
                            "Bouts splitsen op contextgrens (schoolsegment)",
                            value = TRUE)
            )
          )
        ),

        # ── Save/activate confirmation area ────────────────────────────────────
        uiOutput("settings_status_msg")
      )
    ),

    # ── Global persistent filters (right side of navbar) ──────────────────────
    nav_spacer(),
    nav_item(
      div(
        style = "display:flex; align-items:center; gap:6px; padding:2px 0;",
        span(class = "filter-label", "Filter:"),
        div(style = "width:150px;",
          selectInput("global_school", NULL, width = "100%",
                      choices = c("Alle scholen" = "all", SCHOOL_LABELS))
        ),
        div(style = "width:160px;",
          uiOutput("meting_filter_ui")
        )
      )
    )
  )
)

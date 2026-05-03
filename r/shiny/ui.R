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
    background-color: #e9f0fa !important;
    font-size: 15px;
  }

  /* ── Cards: white with subtle lift shadow, no harsh border ── */
  .card {
    background: #ffffff;
    border: 1px solid #dce6f5 !important;
    box-shadow: 0 1px 4px rgba(30,100,200,0.07) !important;
    border-radius: 8px !important;
  }
  .card-header {
    background: #ffffff !important;
    border-top: 3px solid #1E64C8 !important;
    border-bottom: 1px solid #e9f0fa !important;
    border-radius: 8px 8px 0 0 !important;
    font-weight: 600;
    font-size: 0.88rem;
    color: #202020;
    padding: 0.75rem 1rem !important;
  }
  .card-body { padding: 1rem !important; }
  .card-footer {
    background: #ffffff !important;
    border-top: 1px solid #e9f0fa !important;
  }

  /* ── Sidebar: lightly tinted background ── */
  .bslib-sidebar-layout > .sidebar,
  .bslib-sidebar-layout > .bslib-sidebar {
    background-color: #f0f5fc !important;
    border-right: 1px solid #c8d8f0 !important;
  }
  .sidebar .form-label,
  .sidebar label { font-size: 0.82rem; font-weight: 600; color: #3a5080; }
  .sidebar .form-control,
  .sidebar .form-select { font-size: 0.85rem; }
  .sidebar hr { border-color: #c8d8f0; }

  /* ── layout_columns: breathing room between cards ── */
  .bslib-gap-spacing { gap: 1.1rem !important; }

  /* ── KPI strip cards ── */
  .kpi-strip {
    background: #ffffff;
    border: 1px solid #dce6f5 !important;
    box-shadow: 0 1px 3px rgba(30,100,200,0.06) !important;
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
    color: #1E64C8;
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
    color: #5a6e8c;
    line-height: 1.2;
    margin-bottom: 3px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .kpi-strip-value {
    font-size: 1.35rem;
    font-weight: 700;
    color: #202020;
    line-height: 1.1;
    white-space: nowrap;
  }
  .kpi-strip-value .shiny-text-output { display: inline; }

  /* ── Clickable KPI cards ── */
  .kpi-nav-card { cursor: pointer; }
  .kpi-nav-card:hover .kpi-strip {
    border-color: #1E64C8 !important;
    box-shadow: 0 3px 10px rgba(30,100,200,0.15) !important;
    transform: translateY(-2px);
    transition: all 0.15s ease;
  }
  .kpi-nav-card:active .kpi-strip {
    transform: translateY(0px);
    box-shadow: none !important;
    transition: all 0.05s ease;
  }
  .kpi-nav-card:focus-visible .kpi-strip {
    outline: 2px solid #1E64C8;
    outline-offset: 2px;
  }

  /* ── Pipeline trigger row ── */
  .pipeline-bar {
    display: flex;
    align-items: center;
    gap: 12px;
    background: #f0f5fc;
    border-bottom: 1px solid #c8d8f0;
    padding: 8px 20px;
    font-size: 0.82rem;
    color: #3a5080;
    margin-bottom: 0.25rem;
  }
  .pipeline-bar .pipeline-label { font-weight: 600; color: #3a5080; }

  /* ── Active navbar tab — UGent yellow-underline pattern ── */
  .navbar-nav .nav-link[aria-selected='true'],
  .navbar-nav .nav-link.active {
    color: #ffffff !important;
    background: transparent !important;
    border-radius: 0 !important;
    border-bottom: 3px solid #FFD200 !important;
    padding-bottom: calc(0.5rem - 3px) !important;
  }
  .navbar-nav .nav-link { color: rgba(255,255,255,0.9) !important; font-size: 0.87rem; }
  .navbar-nav .nav-link:hover:not(.active):not([aria-selected='true']) {
    color: #ffffff !important;
    border-bottom: 3px solid rgba(255,210,0,0.45) !important;
    padding-bottom: calc(0.5rem - 3px) !important;
  }

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
    background-color: #1E64C8;
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
    background: #f0f5fc;
    border-bottom: 1px solid #c8d8f0;
    padding: 8px 20px;
    font-size: 0.8rem;
    color: #3a5080;
  }
  .readiness-strip .check-ok   { color: #16a34a; font-weight: 600; }
  .readiness-strip .check-warn { color: #b45309; font-weight: 600; }
  .readiness-strip .check-miss { color: #dc2626; font-weight: 600; }

  /* ── Loading shimmer on recalculating plots ── */
  .shiny-plot-output.shiny-output-recalculating,
  .shiny-plotly-output.shiny-output-recalculating {
    min-height: 40px;
    background: linear-gradient(90deg, #e9f0fa 25%, #dce8f5 50%, #e9f0fa 75%);
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
  #schoolday-seg_view .shiny-options-group {
    display: flex;
    margin-top: 4px;
  }
  #schoolday-seg_view .shiny-options-group .radio { flex: 1; margin: 0; }
  #schoolday-seg_view .shiny-options-group .radio label {
    display: block;
    text-align: center;
    padding: 5px 8px;
    font-size: 0.8rem;
    border: 1.5px solid #1E64C8;
    cursor: pointer;
    background: white;
    color: #1E64C8;
    font-weight: 500;
    margin: 0;
    transition: background 0.1s, color 0.1s;
  }
  #schoolday-seg_view .shiny-options-group .radio:first-child label { border-radius: 4px 0 0 4px; }
  #schoolday-seg_view .shiny-options-group .radio:last-child label {
    border-radius: 0 4px 4px 0;
    border-left: none;
  }
  #schoolday-seg_view .shiny-options-group .radio input[type=radio]:checked + label {
    background: #1E64C8;
    color: white;
  }
  #schoolday-seg_view .shiny-options-group .radio input[type=radio] {
    position: absolute;
    width: 1px;
    height: 1px;
    opacity: 0;
    pointer-events: none;
  }
  #schoolday-seg_view > label { font-weight: 600; font-size: 0.85rem; color: #202020; }

  /* ── Rapport samenvatting text area ── */
  #rapport_text_out {
    font-family: 'Georgia', serif;
    font-size: 0.92rem;
    line-height: 1.65;
    white-space: pre-wrap;
    background: #f0f5fc;
    border: 1px solid #c8d8f0;
    border-radius: 6px;
    padding: 0.85rem 1.1rem;
    color: #202020;
  }

  /* ── Vergelijking tab: no height clipping ── */
  .comp-subtab-content { padding-top: 0.5rem; }
  #comparison-comp_subtab,
  #comparison-comp_subtab .bslib-sidebar-layout,
  #comparison-comp_subtab .bslib-sidebar-layout > .main,
  #comparison-comp_subtab .bslib-card,
  #comparison-comp_subtab .card {
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
  .accordion-item { border: 1px solid #dce6f5 !important; border-radius: 8px !important; }
  .accordion-button { font-size: 0.88rem; font-weight: 600; }
  .accordion-button:not(.collapsed) { background-color: #f0f5fc !important; color: #202020 !important; }
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
      bg           = "#e9f0fa",
      fg           = "#202020",
      primary      = "#1E64C8",
      base_font    = font_google("Source Sans 3"),
      heading_font = font_google("Source Sans 3")
    ),
    navbar_options = navbar_options(bg = "#1E64C8"),

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

      modOverviewUI("overview")
    ),
    # ── Tab 2: Deelnemers ─────────────────────────────────────────────────────
    nav_panel(
      "Deelnemers",
      icon = icon("users"),
      modParticipantsUI("participants")
    ),
    # ── Tab 3: Schooldag ──────────────────────────────────────────────────────
    nav_panel(
      "Schooldag",
      icon = icon("school"),
      modSchooldayUI("schoolday")
    ),
    # ── Tab 4: Slaap ──────────────────────────────────────────────────────────
    nav_panel(
      "Slaap",
      icon = icon("moon"),
      modSleepUI("sleep")
    ),

    # ── Tab 5: Vergelijking metingen ──────────────────────────────────────────
    nav_panel(
      "Meting 1 vs 2",
      value = "Vergelijking",
      icon  = icon("arrows-left-right"),
      modComparisonUI("comparison")
    ),
    # ── Tab 6: Export ─────────────────────────────────────────────────────────
    nav_panel(
      "Export",
      icon = icon("download"),
      modExportUI("export")
    ),

    nav_panel(
      "Instellingen",
      icon = icon("sliders"),
      modSettingsUI("settings")
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

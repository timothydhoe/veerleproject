# ui.R
# ─────────────────────────────────────────────────────────────────────────────
# SchoolMove dashboard layout — 6 tabs.
# ─────────────────────────────────────────────────────────────────────────────

# ── Custom CSS ────────────────────────────────────────────────────────────────
app_css <- tags$head(tags$style(HTML("

  /* ── UGent corporate typeface (styleguide.ugent.be/basisprincipes/typografie.html) ── */
  @font-face { font-family: 'PannoText'; font-weight: 300; font-style: normal; src: url('font/PannoText-Light.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 300; font-style: italic; src: url('font/PannoText-LightItalic.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 350; font-style: normal; src: url('font/PannoText-SemiLight.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 350; font-style: italic; src: url('font/PannoText-SemiLightItalic.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 400; font-style: normal; src: url('font/PannoText-Normal.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 400; font-style: italic; src: url('font/PannoText-NormalItalic.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 500; font-style: normal; src: url('font/PannoText-Medium.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 500; font-style: italic; src: url('font/PannoText-MediumItalic.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 600; font-style: normal; src: url('font/PannoText-SemiBold.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 600; font-style: italic; src: url('font/PannoText-SemiBoldItalic.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 700; font-style: normal; src: url('font/PannoText-Bold.woff') format('woff'); }
  @font-face { font-family: 'PannoText'; font-weight: 700; font-style: italic; src: url('font/PannoText-BoldItalic.woff') format('woff'); }

  /* ── Global base ── */
  body {
    background-color: #e9f0fa !important;
    font-size: 15px;
  }

  /* ── Page grid: one consistent left/right margin everywhere (navbar,
     pipeline/readiness strips, KPI cards, chart cards all share this gutter
     instead of each picking their own padding) ── */
  .container-fluid { padding-left: 28px !important; padding-right: 28px !important; }

  /* ── Navbar logo ── */
  /* Navbar bg is white (see navbar_options below), so the logo's native
     blue-on-transparent artwork sits correctly without any plate/recoloring —
     matches how studiekiezer.ugent.be places the logo on a white cell. */
  .navbar {
    background-color: #ffffff !important;
    border-bottom: 1px solid #dce6f5;
    padding: 0 !important;
  }
  /* The navbar's own container is a flex row holding .navbar-header (logo) and
     .navbar-collapse (pills) side by side. Pin the row to one deliberate,
     compact height instead of letting padding + logo size fight each other.
     .navbar-header itself always stretches to fill that row (this markup's
     default behaviour, immune to align-self overrides), so rather than fight
     that, make .navbar-header a flex container too and center its own content
     (the logo) inside whatever height it ends up stretched to. */
  .navbar > .container-fluid {
    align-items: center !important;
    min-height: 64px;
    padding-top: 0 !important;
    padding-bottom: 0 !important;
  }
  .navbar-header {
    display: flex !important;
    align-items: center !important;
    margin-right: 40px !important;
  }
  .navbar-brand-logo { height: 40px; width: auto; display: block; }
  .navbar .navbar-brand {
    padding-top: 0; padding-bottom: 0;
  }

  /* ── Buttons & alerts (styleguide.ugent.be/websites/basis-elementen.html) ── */
  /* .btn-primary already inherits UGent blue/white from bs_theme(primary=). */
  .btn-secondary {
    background-color: #e9f0fa !important;
    border-color: #e9f0fa !important;
    color: #1E64C8 !important;
  }
  .btn-secondary:hover, .btn-secondary:focus {
    background-color: #d7e4f7 !important;
    border-color: #d7e4f7 !important;
    color: #1E64C8 !important;
  }
  .alert-warning {
    background-color: #fffae5 !important;
    border-color: #FFD200 !important;
    color: #202020 !important;
  }
  /* Bootstrap's default alert-info is a cyan/teal, not UGent's light-blue tint. */
  .alert-info {
    background-color: #e9f0fa !important;
    border-color: #c8d8f0 !important;
    color: #1E64C8 !important;
  }
  /* Bootstrap derives --bs-secondary-bg from our theme's fg (#202020), which
     renders .badge.bg-secondary as near-black — too harsh for a routine
     not-generated-yet status pill. Soften to the app's neutral gray token. */
  .badge.bg-secondary {
    background-color: #646464 !important;
  }

  /* ── Dropdown arrows: browser/Bootstrap default is a dark-gray chevron —
     replace with a UGent-blue one everywhere a native <select> is used
     (Instellingen forms, DataTables length picker). ── */
  .form-select {
    background-image: url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath fill='none' stroke='%231E64C8' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M2 5l6 6 6-6'/%3E%3C/svg%3E\") !important;
    background-repeat: no-repeat !important;
    background-position: right 0.7rem center !important;
    background-size: 13px 13px !important;
  }
  /* Most of the app's dropdowns (navbar filters, sidebar selectors, participant
     explorer) are Shiny's selectize widgets, not plain <select> — they render
     via a .selectize-input div that carries no arrow at all by default, so
     the rule above never reaches them. Draw one directly instead. */
  .selectize-control { position: relative; }
  .selectize-control::after {
    content: '';
    position: absolute;
    top: 50%;
    right: 12px;
    width: 7px;
    height: 7px;
    border-right: 2px solid #1E64C8;
    border-bottom: 2px solid #1E64C8;
    transform: translateY(-65%) rotate(45deg);
    transition: transform 0.1s;
    pointer-events: none;
  }
  .selectize-control.dropdown-active::after { transform: translateY(-35%) rotate(225deg); }
  .selectize-input { padding-right: 28px !important; }
  .navbar .selectize-control::after { right: 10px; }

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

  /* ── Full-screen expand icon: bslib defaults it to the bottom-right corner,
     which collides with our own bottom-right PNG-download footer button.
     Move it into the header band instead and reserve room for it there. ── */
  .bslib-full-screen-enter {
    top: 8px !important;
    right: 8px !important;
    bottom: auto !important;
  }
  .card:has(.bslib-full-screen-enter) .card-header {
    padding-right: 2.5rem !important;
  }
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
    padding: 8px 0;
    font-size: 0.82rem;
    color: #3a5080;
    margin-bottom: 0.25rem;
  }
  .pipeline-bar .pipeline-label { font-weight: 600; color: #3a5080; }

  /* ── Navbar tabs — UGent pill pattern (styleguide.ugent.be tab component:
     active = solid blue bg / white text, inactive = light-blue bg / blue text,
     confirmed live on studiekiezer.ugent.be's programme-page tab nav) ── */
  .navbar-nav .nav-link {
    color: #1E64C8 !important;
    background: #e9f0fa !important;
    font-size: 0.87rem;
    font-weight: 500;
    border-radius: 20px !important;
    padding: 0.4rem 0.9rem !important;
    margin: 0 3px;
    transition: background 0.1s, color 0.1s;
  }
  .navbar-nav .nav-link[aria-selected='true'],
  .navbar-nav .nav-link.active {
    color: #ffffff !important;
    background: #1E64C8 !important;
  }
  .navbar-nav .nav-link:hover:not(.active):not([aria-selected='true']) {
    color: #1E64C8 !important;
    background: #d7e4f7 !important;
  }
  .navbar-nav .nav-link:focus-visible {
    outline: 2px solid #1E64C8;
    outline-offset: 2px;
  }

  /* ── Navbar filter controls (light bg to match the now-white navbar) ── */
  .navbar .form-select,
  .navbar .form-control {
    background-color: #e9f0fa !important;
    border-color: #c8d8f0 !important;
    color: #1E64C8 !important;
    font-size: 0.81rem !important;
    height: 30px !important;
    padding-top: 3px !important;
    padding-bottom: 3px !important;
    line-height: 1.3 !important;
  }
  .navbar .form-select option,
  .navbar .form-control option {
    background-color: #ffffff;
    color: #1E64C8;
  }
  .navbar .filter-label {
    color: #5a6e8c;
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
    padding: 8px 0;
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
    id           = "main_nav",
    title        = tags$img(src = "logo-ugent-en.svg", class = "navbar-brand-logo",
                            alt = "Universiteit Gent"),
    window_title = "SchoolMove",
    fillable     = FALSE,
    theme    = bs_theme(
      version      = 5,
      bg           = "#e9f0fa",
      fg           = "#202020",
      primary      = "#1E64C8",
      base_font    = "PannoText, Arial, sans-serif",
      heading_font = "PannoText, Arial, sans-serif"
    ),
    navbar_options = navbar_options(bg = "#ffffff", theme = "light", underline = FALSE),

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
                      choices = c("Alle scholen" = "all", setNames(names(SCHOOL_LABELS), SCHOOL_LABELS)))
        ),
        div(style = "width:160px;",
          uiOutput("meting_filter_ui")
        )
      )
    )
  )
)

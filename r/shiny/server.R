# server.R
# ─────────────────────────────────────────────────────────────────────────────
# SchoolMove dashboard — orchestration only (~90 lines).
# All tab logic lives in modules/mod_*.R.
# ─────────────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ── MVPA column detection ──────────────────────────────────────────────────
  # GGIR naming varies across versions; detect once and pass to all modules.
  mvpa_col_name <- reactive({
    if (is.null(analysis_ready)) return(NULL)
    col <- grep("mvpa_min_day_avg|^MVPA|^mvpa", names(analysis_ready),
                value = TRUE, ignore.case = TRUE)
    if (length(col) == 0) NULL else col[1]
  })

  # ── Global filter helpers ──────────────────────────────────────────────────
  # Returns "all" when global_meting is hidden (Vergelijking tab) or NULL.
  safe_meting <- function() {
    val <- tryCatch(input$global_meting, error = function(e) NULL)
    if (is.null(val) || is.na(val) || !nzchar(val)) "all" else val
  }

  # Session-scoped wrapper around apply_global_filters_pure() (util_filters.R).
  apply_filters <- function(dt, school_col = "school", meting_col = "meting") {
    apply_global_filters_pure(dt, input$global_school, safe_meting(),
                              school_col, meting_col)
  }

  # ── Global UI: meting filter (hidden on Vergelijking tab) ─────────────────
  output$meting_filter_ui <- renderUI({
    active <- input$main_nav
    if (!is.null(active) && active == "Vergelijking") return(NULL)
    selectInput("global_meting", NULL, width = "100%",
                choices = c("Beide metingen" = "all",
                            setNames(names(METINGEN_LABELS), METINGEN_LABELS)))
  })
  # NOTE: outputOptions must stay in root server — not portable to a module
  outputOptions(output, "meting_filter_ui", suspendWhenHidden = FALSE)

  # ── KPI card click → tab navigation ───────────────────────────────────────
  # NOTE: kpi_click is set by root-session JS (non-namespaced); observer must stay here
  observeEvent(input$kpi_click, {
    nav_select("main_nav", input$kpi_click)
  })

  # ── Pipeline controls (global, not tab-specific) ───────────────────────────
  pipeline_result <- reactiveVal(NULL)

  output$pipeline_status_inline <- renderUI({
    res <- pipeline_result()
    if (is.null(res)) return(NULL)
    tags$span(
      style = paste0("font-size:0.82rem; color:", if (res$ok) "#198754" else "#dc3545", ";"),
      if (res$ok) icon("circle-check") else icon("triangle-exclamation"),
      " ", res$msg
    )
  })

  observeEvent(input$btn_run_pipeline, {
    showModal(modalDialog(
      title = tagList(icon("play"), " Pipeline uitvoeren"),
      p("Dit voert alle pipeline-stappen uit (GGIR → segmenten → samenvattingen).",
        "Dit kan 30-60 minuten of langer duren, afhankelijk van het aantal deelnemers."),
      p(class = "text-muted small", "Of run handmatig in de terminal:",
        tags$code("Rscript --vanilla r/pipeline/run_all.R")),
      footer = tagList(
        actionButton("btn_pipeline_confirm", "Start pipeline",
                     icon = icon("play"), class = "btn-primary"),
        modalButton("Annuleren")
      )
    ))
  })

  observeEvent(input$btn_pipeline_confirm, {
    removeModal()
    pipeline_result(list(ok = TRUE,
      msg = "Voer de pipeline uit in de terminal en herlaad de app daarna."))
    showNotification(
      tagList(tags$strong("Pipeline starten: "),
              "Open een terminal in de projectmap en voer uit:", tags$br(),
              tags$code("Rscript --vanilla r/pipeline/run_all.R"), tags$br(),
              "Herlaad de app nadat de pipeline klaar is."),
      type = "message", duration = 15
    )
  })

  output$data_readiness_strip <- renderUI({
    has_ggir <- nrow(part2) > 0
    has_ar   <- !is.null(analysis_ready) && nrow(analysis_ready) > 0
    has_seg  <- !is.null(segment_summary) && nrow(segment_summary) > 0
    checks <- list(
      ggir = tags$span(class = if (has_ggir) "check-ok" else "check-miss",
               if (has_ggir) "✔ GGIR" else "✗ GGIR niet gevonden"),
      ar   = tags$span(class = if (has_ar) "check-ok" else "check-miss",
               if (has_ar) "✔ Samenvattingen"
               else "✗ Samenvattingen niet gevonden — voer de pipeline uit"),
      seg  = tags$span(class = if (has_seg) "check-ok" else "check-warn",
               if (has_seg) "✔ Segmenten"
               else "⚠ Segmenten niet gevonden — voer de pipeline uit")
    )
    if (length(FALLBACK_SCHOOLS) > 0)
      checks$fallback <- tags$span(class = "check-warn",
        paste0("⚠ Geschat rooster: ",
               paste(SCHOOL_LABELS[FALLBACK_SCHOOLS], collapse = ", ")))
    div(class = "readiness-strip",
        tags$span(style = "font-weight:600; color:#6c757d; margin-right:4px;", "Pipeline:"),
        checks)
  })

  # ── Module calls ───────────────────────────────────────────────────────────
  mod_overview_server("overview", shared = list(
    apply_filters     = apply_filters,
    mvpa_col          = mvpa_col_name,
    global_school_val = reactive(input$global_school),
    safe_meting_val   = reactive(safe_meting())
  ))

  mod_participants_server("participants", shared = list(
    apply_filters     = apply_filters,
    mvpa_col          = mvpa_col_name,
    global_school_val = reactive(input$global_school)
  ))

  mod_schoolday_server("schoolday", shared = list(
    apply_filters   = apply_filters,
    safe_meting_val = reactive(safe_meting())
  ))

  mod_sleep_server("sleep", shared = list(
    apply_filters = apply_filters
  ))

  mod_comparison_server("comparison", shared = list(
    apply_filters = apply_filters,
    mvpa_col      = mvpa_col_name
  ))

  mod_export_server("export", shared = list(
    analysis_ready    = analysis_ready,
    segment_summary   = segment_summary,
    validity_summary  = validity_summary,
    part2             = part2,
    cfg               = cfg,
    metingen          = metingen,
    apply_filters     = apply_filters,
    global_school_val = reactive(input$global_school),
    safe_meting_val   = reactive(safe_meting())
  ))

  settings_out <- mod_settings_server("settings", shared = list(cfg = cfg))
}

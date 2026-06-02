# mod_export.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 6 "Export"
# UI + server for all CSV download handlers and the availability panel.
#
# shared list keys used:
#   analysis_ready, segment_summary, validity_summary, part2 — static data.tables
#   cfg, metingen                                            — static config
#   apply_filters                                            — session-scoped filter fn
#   global_school_val, safe_meting_val                      — reactives for filenames
# ─────────────────────────────────────────────────────────────────────────────

#' Export tab UI
modExportUI <- function(id) {
  ns <- NS(id)
  card(
    class = "shadow-sm",
    card_header("Download analysedata"),
    card_body(
      p("Alle bestanden zijn CSV-formaat en bevatten de meest recente pipeline-output."),
      uiOutput(ns("export_panel_ui"))
    )
  )
}

#' Export tab server
mod_export_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Date stamp — evaluated once at session start (intentional: stable within session)
    ts <- format(Sys.Date(), "%Y%m%d")

    # ── Availability panel UI ────────────────────────────────────────────────
    output$export_panel_ui <- renderUI({
      seg_path_exists      <- !is.null(shared$segment_summary)
      ar_path_exists       <- !is.null(shared$analysis_ready)
      val_path_exists      <- !is.null(shared$validity_summary)
      manifest_path_exists <- file.exists("../logs/input_manifest.csv")
      run_log_path_exists  <- file.exists("../logs/pipeline_runs.csv")

      status_badge <- function(ok, ok_msg = "Beschikbaar",
                               miss_msg = "Nog niet gegenereerd") {
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
            downloadButton(ns("dl_part2"), "Dagsamenvattingen (GGIR)",
                           class = "btn-outline-primary btn-sm export-dl-btn"),
            br(), br(),
            p(class = "text-muted small", "Activiteitsintensiteit per deelnemer:"),
            downloadButton(ns("dl_part5"), "Activiteitsprofiel per deelnemer",
                           class = "btn-outline-primary btn-sm export-dl-btn")
          ),
          card(
            card_header("Analyse output"),
            p(class = "text-muted small",
              "Activiteit per schooldagsegment per dag:",
              status_badge(seg_path_exists, miss_msg = "Run stap 02 eerst")),
            tags$div(
              title = if (!seg_path_exists)
                "Bestand niet gevonden — voer stap 02 (label_segments) uit" else NULL,
              downloadButton(ns("dl_segments"), "Activiteit per schoolsegment",
                             class = paste("btn-sm export-dl-btn",
                                           if (seg_path_exists) "btn-outline-primary"
                                           else "btn-outline-secondary disabled-btn"))
            ),
            br(), br(),
            p(class = "text-muted small",
              "Analysetabel — één rij per deelnemer × meting:",
              status_badge(ar_path_exists, miss_msg = "Run stap 03 eerst")),
            tags$div(
              title = if (!ar_path_exists)
                "Bestand niet gevonden — voer stap 03 (build_summaries) uit" else NULL,
              downloadButton(ns("dl_ready"), "Analysetabel",
                             class = paste("btn-sm export-dl-btn",
                                           if (ar_path_exists) "btn-outline-success"
                                           else "btn-outline-secondary disabled-btn"))
            ),
            br(), br(),
            p(class = "text-muted small",
              "Inclusie/exclusie per deelnemer:",
              status_badge(val_path_exists, miss_msg = "Run stap 03 eerst")),
            tags$div(
              title = if (!val_path_exists)
                "Bestand niet gevonden — voer stap 03 (build_summaries) uit" else NULL,
              downloadButton(ns("dl_validity"), "Inclusie / exclusie",
                             class = paste("btn-sm export-dl-btn",
                                           if (val_path_exists) "btn-outline-primary"
                                           else "btn-outline-secondary disabled-btn"))
            )
          ),
          card(
            card_header("Gefilterde export"),
            p(class = "text-muted small",
              "Exporteer enkel de deelnemers die overeenkomen met de actieve filter",
              " (school + meting) bovenaan."),
            downloadButton(ns("dl_filtered"), "Analysetabel (gefilterd)",
                           class = "btn-outline-primary btn-sm export-dl-btn"),
            br(), br(),
            p(class = "text-muted small",
              "Exporteer segmentdata gefilterd op actieve school + meting:",
              status_badge(seg_path_exists, miss_msg = "Run stap 02 eerst")),
            tags$div(
              title = if (!seg_path_exists)
                "Segmenten nog niet gegenereerd — voer stap 02 uit" else NULL,
              downloadButton(ns("dl_segments_filtered"), "Segmentdata (gefilterd)",
                             class = paste("btn-sm export-dl-btn",
                                           if (seg_path_exists) "btn-outline-primary"
                                           else "btn-outline-secondary disabled-btn"))
            )
          )
        ),
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
                downloadButton(ns("dl_input_manifest"), "Input manifest",
                               class = paste("btn-sm export-dl-btn",
                                             if (manifest_path_exists) "btn-outline-primary"
                                             else "btn-outline-secondary disabled-btn"))
              ),
              div(
                p(class = "text-muted small",
                  "Pipeline run log — versies en tijdstippen per uitvoering:",
                  status_badge(run_log_path_exists, miss_msg = "Nog niet aangemaakt")),
                downloadButton(ns("dl_run_log"), "Pipeline run log",
                               class = paste("btn-sm export-dl-btn",
                                             if (run_log_path_exists) "btn-outline-primary"
                                             else "btn-outline-secondary disabled-btn"))
              )
            )
          )
        )
      ) # end tagList
    })

    # ── Private GGIR file readers (private to this module) ───────────────────
    # NOTE: do not expose in utils/ — depend on cfg path conventions
    dl_ggir <- function(meting, filename = NULL, pattern = NULL) {
      results_dir <- file.path("..", shared$cfg$paths$data_processed, meting,
                               paste0("output_", meting), "results")
      if (!is.null(pattern)) {
        files <- list.files(results_dir, pattern = pattern, full.names = TRUE)
        if (length(files) == 0) return(NULL)
        fread(files[1], data.table = FALSE, encoding = "UTF-8")
      } else {
        fpath <- file.path(results_dir, filename)
        if (!file.exists(fpath)) return(NULL)
        fread(fpath, data.table = FALSE, encoding = "UTF-8")
      }
    }

    dl_combined <- function(filename = NULL, pattern = NULL) {
      rows <- lapply(shared$metingen, function(m) {
        dt <- dl_ggir(m, filename, pattern)
        if (!is.null(dt)) { dt$meting <- m; dt } else NULL
      })
      do.call(rbind, Filter(Negate(is.null), rows))
    }

    # ── Download handlers ────────────────────────────────────────────────────
    output$dl_part2 <- downloadHandler(
      filename = function() paste0("part2_daysummary_", ts, ".csv"),
      content  = function(f) {
        dt <- if (nrow(shared$part2) > 0)
          as.data.frame(shared$apply_filters(copy(shared$part2))) else NULL
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
          raw <- shared$apply_filters(setDT(raw))
          write.csv(as.data.frame(raw), f, row.names = FALSE)
        } else write.csv(data.frame(), f)
      }
    )

    output$dl_segments <- downloadHandler(
      filename = function() paste0("segment_summary_", ts, ".csv"),
      content  = function(f) {
        src <- file.path("..", shared$cfg$paths$data_processed, "..", "segment_summary.csv")
        if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
      }
    )

    output$dl_ready <- downloadHandler(
      filename = function() paste0("analysis_ready_", ts, ".csv"),
      content  = function(f) {
        src <- file.path("..", shared$cfg$paths$data_processed, "..", "analysis_ready.csv")
        if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
      }
    )

    output$dl_validity <- downloadHandler(
      filename = function() paste0("validity_summary_", ts, ".csv"),
      content  = function(f) {
        src <- file.path("..", shared$cfg$paths$data_processed, "..", "validity_summary.csv")
        if (file.exists(src)) file.copy(src, f) else write.csv(data.frame(), f)
      }
    )

    # Filtered exports — filenames include active school + meting
    output$dl_filtered <- downloadHandler(
      filename = function() {
        school_val  <- shared$global_school_val()
        school_part <- if (school_val == "all") "all"
                       else gsub(" ", "_", tolower(school_val))
        paste0("analysis_ready_", school_part, "_", shared$safe_meting_val(),
               "_", ts, ".csv")
      },
      content = function(f) {
        dt <- if (!is.null(shared$analysis_ready))
          shared$apply_filters(copy(shared$analysis_ready)) else NULL
        if (!is.null(dt) && nrow(dt) > 0) write.csv(dt, f, row.names = FALSE)
        else write.csv(data.frame(), f)
      }
    )

    output$dl_segments_filtered <- downloadHandler(
      filename = function() {
        school_val  <- shared$global_school_val()
        school_part <- if (school_val == "all") "all"
                       else gsub(" ", "_", tolower(school_val))
        paste0("segment_summary_", school_part, "_", shared$safe_meting_val(),
               "_", ts, ".csv")
      },
      content = function(f) {
        dt <- if (!is.null(shared$segment_summary))
          shared$apply_filters(copy(shared$segment_summary)) else NULL
        if (!is.null(dt) && nrow(dt) > 0) write.csv(dt, f, row.names = FALSE)
        else write.csv(data.frame(), f)
      }
    )

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
  })
}

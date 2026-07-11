# mod_settings.R
# ─────────────────────────────────────────────────────────────────────────────
# Shiny module — Tab 7 "Instellingen"
# Profile manager, validity parameters, cut-points, absence registry.
#
# shared list keys used:
#   cfg  — static config list (for paths and current active profile)
#
# Global objects accessed directly (defined in global.R):
#   analysis_ready, part2 — for pupil ID dropdown in absence registry
#
# Returns a reactiveValues list:
#   $profile_activated — increments when "Activeer" succeeds
#   $absence_changed   — increments on add/delete (future-proofing)
# ─────────────────────────────────────────────────────────────────────────────

#' Settings tab UI
modSettingsUI <- function(id) {
  ns <- NS(id)

  # JS bridge: absence delete button → namespaced Shiny input
  # NOTE: .abs-del-btn class is scoped to this module's rendered table
  abs_del_js <- tags$script(HTML(sprintf("
    $(document).on('click', '.abs-del-btn', function() {
      var row = $(this).data('row');
      Shiny.setInputValue('%s', row, {priority: 'event'});
    });
  ", ns("abs_delete_row"))))

  tagList(
    abs_del_js,
    layout_columns(
      col_widths = c(12),

      # ── Profile manager ──────────────────────────────────────────────────────
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
              selectInput(ns("settings_profile_select"), "Beschikbare profielen",
                          choices = character(0), width = "100%"),
              div(
                style = "display:flex; gap:8px; flex-wrap:wrap;",
                actionButton(ns("settings_load_profile"),     "Laad",
                             icon = icon("upload"), class = "btn-outline-secondary btn-sm"),
                actionButton(ns("settings_save_profile"),     "Opslaan als…",
                             icon = icon("floppy-disk"), class = "btn-outline-primary btn-sm"),
                actionButton(ns("settings_activate_profile"), "Activeer",
                             icon = icon("check"),       class = "btn-success btn-sm")
              )
            ),
            div(
              uiOutput(ns("settings_active_profile_badge")),
              uiOutput(ns("settings_profile_notes"))
            )
          )
        )
      ),

      # ── Validity parameters ──────────────────────────────────────────────────
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
              numericInput(ns("settings_min_wear_h"), "Min. draaguren per dag",
                           value = 16, min = 1, max = 24, step = 1, width = "100%"),
              p(class = "text-muted small mt-n2",
                "Een dag telt als geldig als het acceleratometer ≥N uur gedragen werd."),
              numericInput(ns("settings_min_valid_days"), "Min. geldige dagen per meting",
                           value = 3, min = 1, max = 14, step = 1, width = "100%"),
              p(class = "text-muted small mt-n2",
                "Een deelnemer wordt alleen opgenomen als hij/zij ≥N geldige dagen heeft."),
              checkboxInput(ns("settings_require_weekend"),
                            "Minstens 1 geldig weekenddag vereist", value = TRUE)
            ),
            div(
              numericInput(ns("settings_min_valid_nights"), "Min. geldige nachten (slaap)",
                           value = 5, min = 1, max = 14, step = 1, width = "100%"),
              p(class = "text-muted small mt-n2",
                "Voor de slaapanalyse: min. nachten met ≥50% geldige slaapregistratie."),
              numericInput(ns("settings_min_pct_night"), "Min. % geldige slaap per nacht",
                           value = 50, min = 10, max = 100, step = 5, width = "100%")
            )
          )
        )
      ),

      # ── Activity cut-points ──────────────────────────────────────────────────
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
            numericInput(ns("settings_cp_sb_lpa"),   "SB → LPA (mg)",
                         value = 56.3,  min = 1, max = 999,  step = 0.1, width = "100%"),
            numericInput(ns("settings_cp_lpa_mpa"),  "LPA → MPA (mg)",
                         value = 191.6, min = 1, max = 999,  step = 0.1, width = "100%"),
            numericInput(ns("settings_cp_mpa_vpa"),  "MPA → VPA (mg)",
                         value = 695.8, min = 1, max = 9999, step = 0.1, width = "100%")
          ),
          layout_columns(
            col_widths = c(6, 6),
            numericInput(ns("settings_bout_sb_min"), "Min. sedentaire bout (min.)",
                         value = 30, min = 1, max = 120, step = 1, width = "100%"),
            checkboxInput(ns("settings_bout_split_context"),
                          "Bouts splitsen op contextgrens (schoolsegment)", value = TRUE)
          )
        )
      ),

      # ── Absence registry ─────────────────────────────────────────────────────
      card(
        class = "shadow-sm",
        card_header(
          class = "d-flex align-items-center gap-2",
          icon("user-xmark"), "Afwezigheden"
        ),
        card_body(
          p(class = "text-muted small",
            "Registreer schooldagen waarop een leerling afwezig was.",
            " De pipeline markeert die dag als 'absent' zodat schooluren niet meegeteld worden",
            " in de analyse. Herstart de pipeline na elke wijziging."),
          layout_columns(
            col_widths = c(4, 3, 3, 2),
            selectInput(ns("abs_pupil"), "Leerling",
                        choices = character(0), width = "100%"),
            dateInput(ns("abs_date"), "Datum",
                      value = Sys.Date(), language = "nl",
                      format = "yyyy-mm-dd", width = "100%"),
            textInput(ns("abs_reason"), "Reden (optioneel)",
                      placeholder = "bijv. ziek", width = "100%"),
            div(
              style = "display:flex; align-items:flex-end; padding-bottom:1px;",
              actionButton(ns("abs_add"), "Toevoegen",
                           icon  = icon("plus"),
                           class = "btn-primary btn-sm w-100")
            )
          ),
          uiOutput(ns("abs_status_msg")),
          DTOutput(ns("abs_table"))
        )
      ),

      uiOutput(ns("settings_status_msg"))
    )
  )
}

#' Settings tab server
#'
#' @return reactiveValues with $profile_activated and $absence_changed counters
mod_settings_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Paths derived from config (unified here; global.R has profiles_dir too,
    # but this module uses its own local copy to be self-contained)
    profiles_dir        <- resolve_cfg_path(shared$cfg$profiles$directory %||% "profiles/")
    absences_path_server <- resolve_cfg_path(
      shared$cfg$paths$absences %||% "../data/absences.csv")

    # Return signals for server.R (future-proofing; not acted on currently)
    out <- reactiveValues(profile_activated = 0L, absence_changed = 0L)

    # ── Profile manager ──────────────────────────────────────────────────────

    profile_list <- reactiveFileReader(
      intervalMillis = 5000,
      session        = session,
      filePath       = profiles_dir,
      readFunc       = function(dir) {
        yamls <- list.files(dir, pattern = "\\.yaml$", full.names = FALSE)
        tools::file_path_sans_ext(yamls)
      }
    )

    observe({
      choices <- profile_list()
      if (length(choices) == 0) choices <- "default"
      updateSelectInput(session, "settings_profile_select", choices = choices,
                        selected = shared$cfg$profiles$active %||% "default")
    })

    output$settings_active_profile_badge <- renderUI({
      active <- shared$cfg$profiles$active %||% "default"
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
      v  <- prof$validity %||% list()
      cp <- (prof$ggir$cut_points_mg) %||% list()
      b  <- prof$bouts %||% list()
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
      updateNumericInput(session, "settings_cp_sb_lpa",
                         value = cp$sedentary_to_light %||% 56.3)
      updateNumericInput(session, "settings_cp_lpa_mpa",
                         value = cp$light_to_moderate %||% 191.6)
      updateNumericInput(session, "settings_cp_mpa_vpa",
                         value = cp$moderate_to_vigorous %||% 695.8)
      updateNumericInput(session, "settings_bout_sb_min",
                         value = b$sedentary_min %||% 30)
      updateCheckboxInput(session, "settings_bout_split_context",
                          value = isTRUE(b$split_at_context_boundary %||% TRUE))
      showNotification(paste0("Profiel '", selected, "' geladen."), type = "message")
    })

    observeEvent(input$settings_save_profile, {
      showModal(modalDialog(
        title = "Profiel opslaan als…",
        textInput(ns("settings_new_profile_name"), "Profielnaam",
                  placeholder = "bijv. strenge_drempel"),
        textAreaInput(ns("settings_new_profile_notes"), "Notities (optioneel)",
                      placeholder = "Beschrijf waarvoor dit profiel bedoeld is.",
                      rows = 3),
        footer = tagList(
          modalButton("Annuleren"),
          actionButton(ns("settings_confirm_save"), "Opslaan", class = "btn-primary")
        )
      ))
    })

    observeEvent(input$settings_confirm_save, {
      removeModal()
      prof_name <- trimws(input$settings_new_profile_name)
      if (nchar(prof_name) == 0) {
        showNotification("Geef een profielnaam op.", type = "error"); return()
      }
      safe_name <- gsub("[^a-zA-Z0-9_\\-]", "_", prof_name)
      dst_path  <- file.path(profiles_dir, paste0(safe_name, ".yaml"))

      profile_content <- list(
        profile_name = prof_name,
        created_at   = as.character(Sys.Date()),
        notes        = input$settings_new_profile_notes,
        validity = list(
          min_wear_hours_per_day  = input$settings_min_wear_h,
          min_valid_days          = input$settings_min_valid_days,
          require_weekend_day     = input$settings_require_weekend,
          min_valid_nights_sleep  = input$settings_min_valid_nights,
          min_pct_night_valid     = input$settings_min_pct_night
        ),
        ggir = list(
          cut_points_mg = list(
            sedentary_to_light   = input$settings_cp_sb_lpa,
            light_to_moderate    = input$settings_cp_lpa_mpa,
            moderate_to_vigorous = input$settings_cp_mpa_vpa
          )
        ),
        bouts = list(
          sedentary_min             = input$settings_bout_sb_min,
          split_at_context_boundary = input$settings_bout_split_context
        )
      )

      tryCatch({
        yaml::write_yaml(profile_content, dst_path)
        showNotification(paste0("Profiel '", safe_name, "' opgeslagen."), type = "message")
      }, error = function(e) {
        showNotification(paste0("Fout bij opslaan: ", e$message), type = "error")
      })
    })

    # Activate: patch only the `active:` line in config.yaml (preserves all comments)
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
          type = "message", duration = 6
        )
        out$profile_activated <- out$profile_activated + 1L
      }, error = function(e) {
        showNotification(paste0("Fout bij activeren: ", e$message), type = "error")
      })
    })

    output$settings_status_msg <- renderUI({ NULL })

    # ── Absence registry ─────────────────────────────────────────────────────

    read_absences <- function() {
      if (!file.exists(absences_path_server))
        return(data.table(pupil_id = character(), date = character(),
                          reason = character()))
      tryCatch(
        fread(absences_path_server,
              colClasses = c(pupil_id = "character", date = "character",
                             reason   = "character")),
        error = function(e) data.table(pupil_id = character(), date = character(),
                                       reason = character())
      )
    }

    absences_rv <- reactiveVal(read_absences())

    observe({
      ids <- character(0)
      if (!is.null(analysis_ready) && "ID" %in% names(analysis_ready))
        ids <- sort(unique(as.character(analysis_ready$ID)))
      else if (nrow(part2) > 0 && "ID" %in% names(part2))
        ids <- sort(unique(as.character(part2$ID)))
      updateSelectInput(session, "abs_pupil", choices = ids)
    })

    output$abs_table <- renderDT({
      dt <- absences_rv()
      if (nrow(dt) == 0)
        return(datatable(data.frame(Bericht = "Geen afwezigheden geregistreerd."),
                         options = list(dom = "t"), rownames = FALSE))
      dt[, Verwijderen := paste0(
        '<button class="btn btn-outline-danger btn-sm abs-del-btn" ',
        'data-row="', seq_len(.N), '">',
        '<i class="fa fa-times"></i></button>'
      )]
      datatable(
        dt,
        colnames  = c("Leerling", "Datum", "Reden", ""),
        escape    = FALSE,
        rownames  = FALSE,
        selection = "none",
        options   = list(dom = "tp", pageLength = 10, ordering = TRUE,
                         columnDefs = list(list(orderable = FALSE, targets = 3)))
      )
    })

    output$abs_status_msg <- renderUI({ NULL })

    observeEvent(input$abs_add, {
      pupil  <- trimws(input$abs_pupil)
      date   <- as.character(input$abs_date)
      reason <- trimws(input$abs_reason)
      if (!nzchar(pupil)) {
        output$abs_status_msg <- renderUI(
          div(class = "alert alert-danger small py-2 mt-2", "Selecteer een leerling."))
        return()
      }
      dt <- absences_rv()
      if (any(dt$pupil_id == pupil & dt$date == date)) {
        output$abs_status_msg <- renderUI(
          div(class = "alert alert-warning small py-2 mt-2",
              paste0("Leerling ", pupil, " is al afwezig op ", date, ".")))
        return()
      }
      new_row <- data.table(pupil_id = pupil, date = date, reason = reason)
      dt <- rbindlist(list(dt, new_row))
      tryCatch(
        fwrite(dt, absences_path_server),
        error = function(e) {
          output$abs_status_msg <- renderUI(
            div(class = "alert alert-danger small py-2 mt-2",
                icon("triangle-exclamation"),
                paste0(" Opslaan mislukt: ", conditionMessage(e))))
          return()
        }
      )
      absences_rv(dt)
      out$absence_changed <- out$absence_changed + 1L
      output$abs_status_msg <- renderUI(
        div(class = "alert alert-success small py-2 mt-2",
            icon("circle-check"),
            " Afwezigheid opgeslagen. Herstart de pipeline om toe te passen."))
      updateTextInput(session, "abs_reason", value = "")
    })

    observeEvent(input$abs_delete_row, {
      row_idx <- as.integer(input$abs_delete_row)
      dt <- absences_rv()
      if (row_idx < 1 || row_idx > nrow(dt)) return()
      dt <- dt[-row_idx]
      tryCatch(
        fwrite(dt, absences_path_server),
        error = function(e) {
          output$abs_status_msg <- renderUI(
            div(class = "alert alert-danger small py-2 mt-2",
                icon("triangle-exclamation"),
                paste0(" Verwijderen mislukt: ", conditionMessage(e))))
          return()
        }
      )
      absences_rv(dt)
      out$absence_changed <- out$absence_changed + 1L
      output$abs_status_msg <- renderUI(
        div(class = "alert alert-success small py-2 mt-2",
            icon("circle-check"), " Afwezigheid verwijderd."))
    })

    return(out)
  })
}

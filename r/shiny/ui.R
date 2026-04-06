# ui.R
# ─────────────────────────────────────────────────────────────────────────────
# Dashboard layout for the SchoolMove QC and results app.
# ─────────────────────────────────────────────────────────────────────────────

term_tip <- function(term, explanation) {
  tagList(
    tags$strong(term), " ",
    tooltip(
      tags$sup(icon("circle-question",
                    style = "color: #6c757d; font-size: 0.75em; cursor: help;")),
      explanation
    )
  )
}

ui <- page_navbar(
  title = "SchoolMove",
  theme = bs_theme(bootswatch = "flatly"),

  # ── Overview ────────────────────────────────────────────────────────────────
  nav_panel(
    "Overview",
    layout_columns(
      col_widths = 12,
      card(
        card_header("Study summary"),
        uiOutput("overview_cards")
      )
    ),
    layout_columns(
      col_widths = 12,
      card(
        card_header("Average daily MVPA by school"),
        plotOutput("plot_overview_mvpa", height = "320px")
      )
    ),
    layout_columns(
      col_widths = 12,
      card(
        card_header("Validity by school and meting"),
        DTOutput("table_overview_validity")
      )
    )
  ),

  # ── Participants ─────────────────────────────────────────────────────────────
  nav_panel(
    "Participants",
    layout_sidebar(
      sidebar = sidebar(
        selectInput("par_school", "School",
                    choices = c("All schools", schools)),
        selectInput("par_meting", "Meting",
                    choices = c("Both", metingen)),
        hr(),
        helpText(
          "A participant is ", tags$strong("included"), " if they have at least ",
          cfg$validity$min_valid_days, " valid days",
          if (isTRUE(cfg$validity$require_weekend_day)) " including at least one weekend day." else "."
        )
      ),
      card(
        card_header("Wear time per participant-day"),
        plotOutput("plot_wear_heatmap", height = "420px")
      ),
      card(
        card_header("Inclusion summary"),
        DTOutput("table_participants")
      )
    )
  ),

  # ── School Day ───────────────────────────────────────────────────────────────
  nav_panel(
    "School Day",
    layout_sidebar(
      sidebar = sidebar(
        selectInput("seg_meting", "Meting",
                    choices = c("Both", metingen)),
        selectInput("seg_school", "School",
                    choices = c("All schools", schools)),
        hr(),
        helpText(
          "Activity intensity during each part of the school day,",
          "averaged across all valid weekdays per school.",
          tags$br(), tags$br(),
          "Segments are derived from each school's confirmed timetable",
          "(", tags$em("config.yaml"), ").",
          tags$br(), tags$br(),
          term_tip("MVPA", "Moderate-to-Vigorous Physical Activity — ENMO ≥ 191.6 mg."),
          tags$br(),
          term_tip("LPA",  "Light Physical Activity — ENMO 56.3–191.6 mg."),
          tags$br(),
          term_tip("SB",   "Sedentary Behavior — ENMO < 56.3 mg.")
        )
      ),
      card(
        card_header("Mean minutes per intensity by school context"),
        plotOutput("plot_school_day", height = "420px")
      ),
      card(
        card_header("MVPA during recess — school comparison"),
        plotOutput("plot_recess_mvpa", height = "320px")
      ),
      card(
        card_header("Segment detail table"),
        DTOutput("table_segments")
      )
    )
  ),

  # ── Meting Comparison ────────────────────────────────────────────────────────
  nav_panel(
    "Meting Comparison",
    layout_sidebar(
      sidebar = sidebar(
        selectInput("cmp_school", "School",
                    choices = c("All schools", schools))
      ),
      card(
        card_header("Meting 1 vs Meting 2 — mean daily activity (minutes)"),
        plotOutput("plot_meting_cmp", height = "400px")
      ),
      card(
        card_header("Paired comparison table"),
        DTOutput("table_meting_cmp")
      )
    )
  ),

  # ── Export ───────────────────────────────────────────────────────────────────
  nav_panel(
    "Export",
    card(
      card_header("Download research-ready tables"),
      layout_columns(
        col_widths = c(4, 4, 4),
        card(
          card_body(
            p(strong("Part 2 — daily wear time")),
            p("One row per participant-day. Contains valid hours,",
              "measurement day, and weekday labels."),
            downloadButton("dl_part2", "Download Part 2 CSV")
          )
        ),
        card(
          card_body(
            p(strong("School Day segments")),
            p("One row per participant × day × segment.",
              "Contains SB, LPA, MPA, VPA minutes for each",
              "part of the school day."),
            downloadButton("dl_segments", "Download segment CSV")
          )
        ),
        card(
          card_body(
            p(strong("Validity summary")),
            p("One row per participant × meting. Indicates whether",
              "validity criteria are met (≥3 valid days incl. weekend)."),
            downloadButton("dl_validity", "Download validity CSV")
          )
        )
      )
    )
  )
)

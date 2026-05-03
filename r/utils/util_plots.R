# util_plots.R
# ─────────────────────────────────────────────────────────────────────────────
# Pure plotting utilities: no reactive context, no Shiny input dependencies.
# Sourced by global.R so everything here is available in server.R and modules.
# ─────────────────────────────────────────────────────────────────────────────

#' Return a minimal ggplot carrying a centred message (used when data is absent).
no_data_plot <- function(msg = "Geen data — voer de pipeline eerst uit.") {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5, label = msg,
             size = 5, colour = "grey60", hjust = 0.5) +
    theme_void()
}

#' Standardised PNG download handler factory.
#'
#' @param plot_expr  Zero-argument function (or reactive) returning a ggplot.
#' @param filename_stem  Base name for the downloaded file (date appended).
png_dl <- function(plot_expr, filename_stem, width = 1800, height = 1000, dpi = 180) {
  downloadHandler(
    filename = function() paste0(filename_stem, "_", format(Sys.Date(), "%Y%m%d"), ".png"),
    content  = function(f) {
      ggplot2::ggsave(f, plot = plot_expr(), device = "png",
                      width  = width  / dpi,
                      height = height / dpi,
                      dpi    = dpi, bg = "white")
    }
  )
}

#' Shared ggplot2 theme (Atlassian-inspired neutrals, UGent blue accent).
theme_schoolmove <- function(legend_pos = "bottom") {
  theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(face = "bold", size = 13, colour = "#202020",
                                      margin = margin(b = 2)),
      plot.subtitle    = element_text(colour = "#6B778C", size = 10.5,
                                      margin = margin(b = 8)),
      plot.background  = element_rect(fill = "white", colour = NA),
      plot.margin      = margin(10, 14, 10, 14),
      panel.grid.major = element_line(colour = "#F4F5F7", linewidth = 0.8),
      panel.grid.minor = element_blank(),
      axis.title       = element_text(size = 10, colour = "#6B778C"),
      axis.text        = element_text(colour = "#5E6C84", size = 9.5),
      axis.ticks       = element_blank(),
      legend.position  = legend_pos,
      legend.title     = element_blank(),
      legend.text      = element_text(size = 10, colour = "#5E6C84"),
      strip.text       = element_text(face = "bold", size = 10.5, colour = "#202020"),
      strip.background = element_rect(fill = "#e9f0fa", colour = NA)
    )
}

# Atlassian-inspired: SB de-emphasised (grey), LPA cyan, MVPA bold blue (hero)
ZONE_COLORS <- c(
  SB   = "#DFE1E6",
  LPA  = "#79E2F2",
  MVPA = "#1E64C8"
)

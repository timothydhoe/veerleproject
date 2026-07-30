# util_plots.R
# ─────────────────────────────────────────────────────────────────────────────
# Pure plotting utilities: no reactive context, no Shiny input dependencies.
# Sourced by global.R so everything here is available in server.R and modules.
# ─────────────────────────────────────────────────────────────────────────────

#' Return a minimal ggplot carrying a centred message (used when data is absent).
no_data_plot <- function(msg = "Nog geen data — voer de pipeline uit.") {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5, label = msg,
             size = 5, colour = UGENT_TEXT_GRAY, hjust = 0.5) +
    theme_void() +
    theme(
      plot.background  = element_rect(fill = UGENT_BG_LIGHT_BLUE, colour = NA),
      panel.background = element_rect(fill = UGENT_BG_LIGHT_BLUE, colour = NA)
    )
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

#' Shared ggplot2 theme (UGent neutrals + blue accent).
theme_schoolmove <- function(legend_pos = "bottom") {
  theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(face = "bold", size = 13, colour = UGENT_BLACK,
                                      margin = margin(b = 2)),
      plot.subtitle    = element_text(colour = UGENT_TEXT_GRAY, size = 10.5,
                                      margin = margin(b = 8)),
      plot.background  = element_rect(fill = "white", colour = NA),
      plot.margin      = margin(10, 14, 10, 14),
      panel.grid.major = element_line(colour = UGENT_BORDER_LIGHTER, linewidth = 0.8),
      panel.grid.minor = element_blank(),
      axis.title       = element_text(size = 10, colour = UGENT_TEXT_GRAY),
      axis.text        = element_text(colour = UGENT_TEXT_GRAY, size = 9.5),
      axis.ticks       = element_blank(),
      legend.position  = legend_pos,
      legend.title     = element_blank(),
      legend.text      = element_text(size = 10, colour = UGENT_TEXT_GRAY),
      strip.text       = element_text(face = "bold", size = 10.5, colour = UGENT_BLACK),
      strip.background = element_rect(fill = UGENT_BG_LIGHT_BLUE, colour = NA)
    )
}

# UGent-toned: SB de-emphasised (light border grey), LPA light blue tint, MVPA
# UGent blue (hero) — a monochrome-blue progression rather than an arbitrary accent.
ZONE_COLORS <- c(
  SB   = UGENT_BORDER_LIGHTER,
  LPA  = "#8BBEE8",  # UGent faculty "sky blue" tint — reads as a lighter step of blue
  MVPA = UGENT_BLUE
)

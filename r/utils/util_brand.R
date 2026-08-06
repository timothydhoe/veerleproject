# util_brand.R
# ─────────────────────────────────────────────────────────────────────────────
# UGent brand constants (styleguide.ugent.be) — single source of truth for every
# hex value used in the dashboard's theme, CSS, and charts. Sourced by global.R
# before util_plots.R.
# ─────────────────────────────────────────────────────────────────────────────

# ── Core palette ────────────────────────────────────────────────────────────
UGENT_BLUE   <- "#1E64C8"
UGENT_YELLOW <- "#FFD200"
UGENT_BLACK  <- "#202020"
UGENT_WHITE  <- "#FFFFFF"

# ── UI-component tokens (styleguide.ugent.be/websites/basis-elementen.html) ──
UGENT_BG_LIGHT_BLUE   <- "#e9f0fa"  # secondary button / navbar / page bg
UGENT_BG_LIGHT_YELLOW <- "#fffae5"  # alert background
UGENT_TEXT_GRAY       <- "#646464"  # secondary text (e.g. dates)
UGENT_BORDER_LIGHT    <- "#CCCCCC"
UGENT_BORDER_LIGHTER  <- "#DDDDDD"
UGENT_DISABLED_GRAY   <- "#B4B4B4"

# ── Official faculty colors (11) — each pairs with UGENT_BLUE, replacing the
# yellow accent. Not used here for faculty affiliation; reused as a ready-made,
# brand-legitimate categorical palette for charts (schools, groups, series). ──
UGENT_FACULTY_COLORS <- c(
  LW_orange        = "#F1A42B",
  RE_warm_red      = "#DC4E28",
  WE_aqua          = "#2D8CA8",
  GE_salmon        = "#E85E71",
  EA_sky_blue      = "#8BBEE8",
  EB_light_green   = "#AEB050",
  DI_purple        = "#825491",
  PP_warm_orange   = "#FB7E3A",
  BW_turquoise     = "#27ABAD",
  FW_light_purple  = "#BE5190",
  PS_green         = "#71A860"
)

#' Colorblind-safe categorical palette for schools (Okabe & Ito, 2008) —
#' verified distinguishable under protanopia, deuteranopia, and tritanopia.
#' Replaces an earlier hand-picked set of 6 UGent faculty colors that looked
#' fine to unimpaired vision but had two real confusable pairs: the two
#' greens (EB_light_green/PS_green) both drift toward yellow-brown under
#' deuteranopia and converge with RE_warm_red, and the two purples
#' (DI_purple/FW_light_purple) are close in hue even without any deficiency.
#' Uses 6 of Okabe-Ito's 8 colors — dropping black (already used for chart
#' text/gridlines) and yellow (#F0E442, poor contrast on this app's white
#' chart backgrounds) — since n is always small (<=6, one per school).
ugent_categorical_palette <- function(n) {
  okabe_ito <- c(
    "#E69F00",  # orange
    "#56B4E9",  # sky blue
    "#009E73",  # bluish green
    "#0072B2",  # blue
    "#D55E00",  # vermillion
    "#CC79A7"   # reddish purple
  )
  unname(okabe_ito[seq_len(n)])
}

# ── Semantic chart colors ────────────────────────────────────────────────────
# Blue/orange is a colorblind-safe pair (unlike red/green); reused consistently
# app-wide instead of ggplot/Atlassian defaults for any good-vs-bad or
# valid-vs-invalid encoding (wear-time heatmap, Toename/Afname, DT deltas).
UGENT_POSITIVE <- UGENT_BLUE                              # good / increase / valid
UGENT_NEGATIVE <- UGENT_FACULTY_COLORS[["PP_warm_orange"]] # bad / decrease / invalid

# Two measurement waves (Meting 1 / Meting 2) — a distinct pair from
# UGENT_POSITIVE/UGENT_NEGATIVE since it encodes time, not good/bad.
UGENT_METING_COLORS <- c(
  "Meting 1" = UGENT_BLUE,
  "Meting 2" = UGENT_FACULTY_COLORS[["GE_salmon"]]
)

# WHO/guideline dashed reference lines: neutral, not an alarm color.
UGENT_REFERENCE_LINE <- UGENT_TEXT_GRAY

# Light tint of UGENT_NEGATIVE, for table row/badge backgrounds paired with
# UGENT_BG_LIGHT_BLUE (e.g. included/excluded status cells).
UGENT_BG_LIGHT_NEGATIVE <- "#fde9dc"

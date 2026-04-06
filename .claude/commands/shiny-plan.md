---
description: Plan a new tab or feature for the Shiny dashboard before writing any code. Describe what you want in plain language.
---

The user wants to add the following to the Shiny dashboard:

$ARGUMENTS

Before writing any code, read the current state of:

- `r/shiny/ui.R` — existing tabs and layout structure
- `r/shiny/server.R` — existing reactive logic
- `r/shiny/global.R` — shared data and helpers
- `r/install.R` — currently installed packages
- `config.yaml` — available school/schedule data

Then produce a concrete implementation plan. Structure it as:

**What this adds**
One short paragraph describing the feature as a researcher would experience it — not
technically, but from the user's perspective. What will they see? What can they do?

**Files to change**
List each file that needs to change and briefly what changes in it.

**Data required**
Which GGIR output files or config sections does this feature depend on? Does that data
already exist in `global.R`, or does something new need to be loaded?

**UI elements needed**
List the inputs (dropdowns, sliders, buttons) and outputs (plots, tables, text) needed,
and where in the tab layout they go.

**Reactive logic**
Describe what the server needs to compute — without writing code, just explain the logic
in plain terms.

**New packages needed**
List any R packages not already in `install.R` that would be required.

**Open questions**
List anything that needs a decision before implementation (e.g. "Should this show
individual pupils or school averages by default?").

Do not write any R code yet. Present the plan and wait for confirmation.

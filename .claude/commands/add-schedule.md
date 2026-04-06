---
description: Add or update a school's timetable in config.yaml. Pass the school number and schedule details, even in plain text.
---

The user wants to add or update a school schedule in `config.yaml`.

$ARGUMENTS

First, read `config.yaml` to see the current schedule structure so you match the exact
format.

Then extract or ask for the following information:

- **Which school** (1–6)
- **School start time** (same every day, or different on Wednesday?)
- **School end time** (weekday vs Wednesday — Belgian schools typically finish early on
  Wednesdays)
- **Morning recess** — start and end time
- **Lunch break** — start and end time
- **Afternoon recess** — start and end time (if there is one)
- **Is this schedule confirmed?** (yes = `fallback: false`, still approximate =
  `fallback: true`)

If the user has provided this information in $ARGUMENTS (even as free-form text like "
starts at 8:30, break from 10:15 to 10:30, lunch 12 to 1"), extract it and structure it
correctly.

If information is missing, ask for it before editing the file.

Once you have everything, update `config.yaml` under the correct school entry in
`schedules:`. After saving, confirm in plain language what was changed and whether the
school is now marked as confirmed or still approximate.

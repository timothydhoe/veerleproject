# SchoolMove — Feature Log

Tracks **new/requested functionality** — work that isn't a defect in existing behavior,
but something that doesn't exist yet (or exists in code but isn't actually usable by
Veerle in the delivered Windows bundle). Kept separate from `docs/test/bug_log.md`,
which tracks defects in already-intended behavior. Uses its own number sequence
(unrelated to `bug_log.md`'s numbering) — cross-reference by filename + number, e.g.
"see bug_log.md #17".

If investigation during any item below turns up an actual defect (not a missing
feature), log that as a new item in `bug_log.md` instead — don't let it hide inside a
feature entry here.

Status legend: `proposed` · `in-progress` · `built-unverified` · `verified` ·
`wontfix` · `deferred`

- **proposed** — requested, not yet planned/scoped.
- **in-progress** — plan approved, being implemented.
- **built-unverified** — code written, but not yet confirmed working end-to-end
  through the actual delivery path (the built Windows bundle Veerle runs — see
  workflow step 8 below). Don't linger here; this status exists to make an
  untested-in-the-real-path feature visible, not to be a comfortable resting state.
- **verified** — confirmed working through the built Windows bundle, not just in
  RStudio/dev. This is the bar for "done" in this log.
- **wontfix** — considered, deliberately not building it (document why).
- **deferred** — real, scoped, but intentionally postponed (document why and what
  would trigger picking it back up).

---

## Workflow

Paste this to continue in the same style:

> We're working through `docs/test/feature_log.md` in SchoolMove, one feature at a
> time. Keep using this workflow for every item:
>
> 1. **Describe the request in plain terms** — what's wanted and why it matters to
>    the study/researcher, in your own words back to me, so we can catch
>    misunderstandings early.
> 2. **Ask clarifying questions** to pin down exactly what's wanted/expected —
>    acceptance criteria, edge cases, who uses it and how (Veerle via the dashboard?
>    a script? both?). Don't assume — a feature request is inherently more
>    underspecified than a bug report, since there's no existing broken behavior to
>    anchor on.
> 3. **Investigate the current state of the program against that request** before
>    proposing anything — read the actual current code, don't assume the request
>    describes a blank slate. Check whether it already exists in whole or in part
>    (this has already happened once: the absence feature turned out to be fully
>    built via `data/absences.csv` + the Instellingen tab, just not reachable through
>    the Windows bundle). Check `bug_log.md` too in case this is actually a known,
>    already-tracked defect rather than new work.
> 4. **Write up a plan**: approach, files touched, what "done" looks like, and any
>    tradeoffs worth flagging.
> 5. **Get an independent agent review of the plan itself** (fresh context,
>    static/read-only, no code execution) before presenting it to me — catch flawed
>    assumptions or design issues before I ever see the plan, same discipline
>    `bug_log.md` uses for non-trivial fixes.
> 6. **Present the (possibly revised) plan**, with options/tradeoffs where relevant,
>    and a clear recommendation. Leave room for my questions.
> 7. **Wait for explicit approval before touching any file** — no changes on spec
>    alone.
> 8. **Apply the change**, then **test afterward**: confirm the feature actually
>    works as intended, and confirm nothing else broke — run the affected
>    pipeline/dashboard before and after, diff output CSVs where relevant, same
>    regression discipline as `bug_log.md`. If the feature is anything Veerle would
>    touch standalone (dashboard, pipeline run, config), also confirm it works
>    through an actual built Windows bundle (`scripts/bundle/build-bundle.ps1`
>    output), not only in RStudio/dev — that gap is exactly what's currently blocking
>    the absence feature, and dev-only testing is what let it go unnoticed.
> 9. **Update `docs/test/feature_log.md`**: set the status, and document what was
>    tried/rejected and why, what was applied, and exactly how it was verified —
>    same reference format `bug_log.md` uses for its fixed items.
> 10. **Log any new issues discovered along the way** as their own tracked items —
>     new items here if feature-shaped, or flag for `bug_log.md` if it's actually a
>     defect — don't just mention them in passing and drop them.
> 11. Move to the next item, one at a time. Don't batch multiple items' approvals
>     together.

---

## Open

Collected from the project owner on 2026-07-23, not yet investigated/planned. See
`docs/test/order_of_approach.md` for working order and reasoning across these plus
the parallel `bug_log.md` items (#29–31).

### 1. Pipeline-wide error/log-to-file capture — status: `proposed`

Write errors/warnings encountered along the full pipeline run to a `.txt` log file,
overwritten by default on each run, with the option to redirect to a different
(persistent) location when a specific run is worth keeping. Directly closes the
follow-up noted in `bug_log.md` #17 ("if a general error-logging system gets built
for other reasons, route this constraint's warning through it too" — no such system
currently exists in the codebase). Second in working order per
`order_of_approach.md` — pure infrastructure, no dependencies, and helps debug
several later items (bug #29, feature #4 below).

### 2. Make `split_at_context_boundary` / `labeled_epochs.csv` functional — status: `proposed`

Is `split_at_context_boundary()` (in `utils_bouts.R`) actually functional end-to-end?
If not, make it so. Same gap already tracked as `bug_log.md` #10 (`deferred`): that
item confirmed `split_at_context_boundary()` and `detect_activity_bouts()` are
correctly implemented, but inert because `labeled_epochs.csv` doesn't exist yet — the
missing piece is a new pipeline step joining GGIR's raw epoch export against school-
schedule boundaries (~480M rows at full study scale — real design work, not a quick
fix). To decide: whether this feature-log item simply reopens/supersedes bug #10, or
stays a separate, forward-looking entry while #10 stays closed as historical record.
Fifth in working order per `order_of_approach.md` — self-contained, but best tackled
after the validity-criterion bug (bug #31) settles so new output columns aren't built
against soon-to-change validity logic.

### 3. Shiny dashboard startup performance / loading indicator — status: `proposed`

`2 - Dashboard starten.bat` takes a long time to open because of the data volume
being read in. Wanted: faster perceived startup, plus a visible progress indicator
(percentage or count) while data loads — and to investigate proper use of Shiny's
`reactive()`/lazy-loading patterns so startup isn't fully blocking. Sixth in working
order per `order_of_approach.md` — do this after feature #2 (labeled_epochs.csv), not
before, since that feature will add more data for the dashboard to load and any
loading-indicator design should reflect the real eventual data volume.

### 4. Full bundle functional audit — status: `proposed`

Does the delivered Windows bundle work as it should, and what's needed to make it
so? Specifically: the dashboard should support rerunning the pipeline with different
configurations (adjustments or a chosen profile), and recording absences should
actually work end-to-end through the bundle Veerle runs (the absence-registry
feature already exists in Shiny/pipeline code — see the earlier conversation in this
log's history — but isn't reachable/functional through the bundle; root cause not
yet confirmed, candidate leads include Shiny's working-directory shift when launched
via `runApp('shiny', ...)` vs. `resolve_cfg_path()`'s relative-path assumptions).
Explicitly deprioritized by the project owner ("the dashboard is a nice to have — I
want to focus on the codebase and correctness of output data first"). Last in
working order per `order_of_approach.md` — biggest scope, most cross-cutting, and
benefits from every other item above being settled first. Decide at investigation
time whether the absence-recording gap is folded into this item or split out
separately.

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

*(none yet — first item pending)*

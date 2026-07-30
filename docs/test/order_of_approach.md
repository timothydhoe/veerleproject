# Order of Approach

Working order for the batch of items collected on 2026-07-23 (not yet individually
logged in `bug_log.md` / `feature_log.md` — that happens when each item's turn comes
up, per those files' own workflows). Optimized for two things:

1. **Correctness of output data before UI/tooling work** (explicit priority from the
   project owner — the dashboard and bundle are "nice to have," the pipeline's
   scientific output is not).
2. **Sequencing to avoid rework** — tackle foundational items before anything that
   would need to be redone or re-verified once a foundational item changes.

---

## 1. Bug — `min_wear_hours_per_day`: waking-hours vs. 24h calendar day — `fixed`

Highest priority. This gates which participant-days count as valid across the
**entire** dataset — every downstream thing (dashboard graphs, exports, the bundle
audit, even the epoch-level bouts feature) displays or builds on data shaped by this
criterion. Veerle is actively asking about it directly (see her quoted question in
`bug_log.md`'s corresponding item), so it's also the most urgent. Doing it first means
nothing else gets built or tested against soon-to-change validity numbers.

**Resolved** — see `bug_log.md` #31.

## 2. Bug — `calendar_date` not found (Shiny "MVPA per dag" graph, Deelnemers tab) — `fixed`

Small, isolated, no dependencies either direction. Cheap to fix now while the
dashboard is still simple — cheaper than fixing it later once startup-performance
work (item 7) and the bundle audit (item 8) have added more moving parts to the same
dashboard code.

**Resolved** — see `bug_log.md` #30. Turned out to be a stale duplicate: already fixed
by commit `1b22e668` (2026-07-15), 8 days before this item was logged as `open`.

## 3. Feature — pipeline-wide error/log-to-file capture

Pure infrastructure, no dependencies. Put it in early because everything after this
benefits from it: debugging the bundle terminal issue (item 5), the epoch-level
feature build (item 6), and especially the big bundle audit (item 8) all get easier
with persistent logs instead of console-only output that vanishes when a window
closes. Also directly closes the follow-up noted in `bug_log.md` #17 ("if a general
error-logging system gets built for other reasons, route this constraint's warning
through it too").

See `feature_log.md` #1.

## 4. Feature — performance / dead-code audit ("fluidity" check)

Added 2026-07-27, requested by the project owner while item 3 was being scoped — out
of concern that the bundle is "already a pretty slow process," and more
infrastructure shouldn't be layered onto un-investigated existing slowness without
first checking whether some of it is avoidable (unnecessary code, redundant
computation, dead weight) rather than inherent GGIR/IO cost. Placed here, right after
logging (item 3) and before the bundle-terminal bug (item 5), so later
performance-sensitive work (dashboard startup performance, item 7; the full bundle
audit, item 8) targets a lean baseline instead of possibly redoing tuning around code
this audit ends up trimming — and so the heaviest remaining feature
(`labeled_epochs.csv`, item 6 — ~480M rows at full study scale) isn't built on top of
unexamined existing inefficiency.

See `feature_log.md` #5.

## 5. Bug — bundle: must keep first `.bat` terminal open to run the second — `fixed`

Investigated after the performance/dead-code audit (item 4, optimization_log.md #10)
had already checked the `.bat` launchers and found nothing relevant there. Both
halves of the original report turned out to be real (window 1 must stay open while
the pipeline runs; window 2 must stay open while using the dashboard) — the actual
fix: detach the pipeline run (the expensive one to lose) into a true background
process with a live progress indicator, verified empirically to survive the
launching window being closed. Dashboard left as a simple blocking process, per
project-owner decision, so this closes out before the big bundle audit (item 8)
without pulling that deprioritized item forward — though the fix's status-file/
progress-polling piece was deliberately designed generically enough to be reusable
there later (per independent review of that specific sequencing question).

**Resolved** — see `bug_log.md` #29.

## 6. Feature — make `split_at_context_boundary` / `labeled_epochs.csv` functional

Substantial, self-contained new pipeline step (epoch-level join against school-day
boundaries, real design work — same gap `bug_log.md` #10 deferred). Doesn't touch
existing validity/segment/sleep logic, so it's independent of items 1–5, but best
done after item 1 settles so we're not designing new output columns against
validity logic that's about to change, and after item 4's audit so it isn't adding
~480M rows of new processing on top of unexamined existing inefficiency.

See `feature_log.md` #2.

## 7. Feature — dashboard startup performance / loading indicator

Do this after item 6, not before — if labeled_epochs.csv/bouts data gets added,
dashboard load time gets worse, and any loading-indicator design should reflect the
real eventual data volume rather than being reworked once the dataset grows. Also
benefits from item 2 already being fixed (one less moving part in the same code) and
from item 4's audit (targets a lean baseline instead of tuning around code that gets
trimmed).

See `feature_log.md` #3.

## 8. Feature — full bundle functional audit

Dashboard-triggered pipeline reruns with chosen config/profile, plus absence
recording, actually working end-to-end through the delivered Windows bundle. Biggest
scope, most cross-cutting — touches the `.bat` launchers, dashboard reactivity,
config writing, and absence writing all at once. Already flagged by the project
owner as lower priority; the rework-avoidance sequencing above confirms that's also
the right call, since this item overlaps with nearly everything above and benefits
from all of it being settled first. Likely subsumes the earlier "absence feature
blocked by the bundle" discussion — decide at the time whether that's folded into
this item or kept separate.

See `feature_log.md` #4.

---

Revisit this ordering if investigating an earlier item surfaces something that
changes a later item's scope or priority — this is a working plan, not a fixed
sequence.

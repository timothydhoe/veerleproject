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

## 1. Bug — `min_wear_hours_per_day`: waking-hours vs. 24h calendar day

Highest priority. This gates which participant-days count as valid across the
**entire** dataset — every downstream thing (dashboard graphs, exports, the bundle
audit, even the epoch-level bouts feature) displays or builds on data shaped by this
criterion. Veerle is actively asking about it directly (see her quoted question in
`bug_log.md`'s corresponding item), so it's also the most urgent. Doing it first means
nothing else gets built or tested against soon-to-change validity numbers.

## 2. Bug — `calendar_date` not found (Shiny "MVPA per dag" graph, Deelnemers tab)

Small, isolated, no dependencies either direction. Cheap to fix now while the
dashboard is still simple — cheaper than fixing it later once startup-performance
work (item 6) and the bundle audit (item 7) have added more moving parts to the same
dashboard code.

## 3. Feature — pipeline-wide error/log-to-file capture

Pure infrastructure, no dependencies. Put it in early because everything after this
benefits from it: debugging the bundle terminal issue (item 4), the epoch-level
feature build (item 5), and especially the big bundle audit (item 7) all get easier
with persistent logs instead of console-only output that vanishes when a window
closes. Also directly closes the follow-up noted in `bug_log.md` #17 ("if a general
error-logging system gets built for other reasons, route this constraint's warning
through it too").

## 4. Bug — bundle: must keep first `.bat` terminal open to run the second

Investigate now that logging (item 3) exists to help pin down the actual cause.
Worth closing out before the big bundle audit (item 7) so that audit isn't
rediscovering the same root cause from scratch.

## 5. Feature — make `split_at_context_boundary` / `labeled_epochs.csv` functional

Substantial, self-contained new pipeline step (epoch-level join against school-day
boundaries, real design work — same gap `bug_log.md` #10 deferred). Doesn't touch
existing validity/segment/sleep logic, so it's independent of items 1–4, but best
done after item 1 settles so we're not designing new output columns against
validity logic that's about to change.

## 6. Feature — dashboard startup performance / loading indicator

Do this after item 5, not before — if labeled_epochs.csv/bouts data gets added,
dashboard load time gets worse, and any loading-indicator design should reflect the
real eventual data volume rather than being reworked once the dataset grows. Also
benefits from item 2 already being fixed (one less moving part in the same code).

## 7. Feature — full bundle functional audit

Dashboard-triggered pipeline reruns with chosen config/profile, plus absence
recording, actually working end-to-end through the delivered Windows bundle. Biggest
scope, most cross-cutting — touches the `.bat` launchers, dashboard reactivity,
config writing, and absence writing all at once. Already flagged by the project
owner as lower priority; the rework-avoidance sequencing above confirms that's also
the right call, since this item overlaps with nearly everything above and benefits
from all of it being settled first. Likely subsumes the earlier "absence feature
blocked by the bundle" discussion — decide at the time whether that's folded into
this item or kept separate.

---

Revisit this ordering if investigating an earlier item surfaces something that
changes a later item's scope or priority — this is a working plan, not a fixed
sequence.

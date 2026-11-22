# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. Claim one task, not a range: an item that lists several tasks or issues in order is claimed one task at a
time, the first without a PR. `scripts/claim-task.py --next` reads this list: it skips closed and umbrella issues,
tasks also listed in a later section and tasks written as "once #N is done" (or "once #N and #M are done") while any of them is open. When you merge a PR
that finishes or changes an item, update this list in the same PR. Every item links an issue or a design-doc task
(`check-repo.py` fails otherwise). `--next --dry-run` reads the list on `origin/main`, not your working copy.

Reviewed 2026-11-22. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **Coherent daily recommendation after training** — [#202](https://github.com/droidsam1/overreach/issues/202),
   one task at a time: [#204](https://github.com/droidsam1/overreach/issues/204) (share "trained today" and
   lower-body load with the Assistant and Plan). Shipped: no second session after training
   ([#201](https://github.com/droidsam1/overreach/pull/201)), no unplanned run after lower-body strength
   ([#203](https://github.com/droidsam1/overreach/issues/203)), evidence entry
   ([#205](https://github.com/droidsam1/overreach/issues/205)). Touches Today: never in parallel with #181–#185.
2. **Minimal UI with progressive disclosure** — [#179](https://github.com/droidsam1/overreach/issues/179)
   ([ADR-0041](adr/0041-minimal-ui-progressive-disclosure.md)), one task at a time in this order:
   [#181](https://github.com/droidsam1/overreach/issues/181) (one pending prompt),
   [#184](https://github.com/droidsam1/overreach/issues/184) (two-step onboarding),
   [#185](https://github.com/droidsam1/overreach/issues/185) (sections by data, once #220 is done, so it builds on the
   new hero). #181–#185 touch Today: never in parallel. [#186](https://github.com/droidsam1/overreach/issues/186) (set feedback and achievements) shipped
   lift records and set feedback; a running-goal milestone waits for a goal-progress event to attach it to.
3. **Visual Today** — [#211](https://github.com/droidsam1/overreach/issues/211)
   ([ADR-0042](adr/0042-visual-today.md), [spec](design/today-visual.md)). Tasks run in parallel; each names the files
   it owns. Wave 1, no dependencies:
   [#212](https://github.com/droidsam1/overreach/issues/212) (ring, tone surfaces, progress bar),
   [#213](https://github.com/droidsam1/overreach/issues/213) (signal tile, trend chart, gauge),
   [#214](https://github.com/droidsam1/overreach/issues/214) (week strip, link tiles, answer scale),
   [#215](https://github.com/droidsam1/overreach/issues/215) (hero signals),
   [#216](https://github.com/droidsam1/overreach/issues/216) (week progress shared with Plan),
   [#217](https://github.com/droidsam1/overreach/issues/217) (one-tap check-in),
   [#218](https://github.com/droidsam1/overreach/issues/218) (done-today summary),
   [#219](https://github.com/droidsam1/overreach/issues/219) (Why values, once #215 is done).
   Wave 2, FeatureToday:
   [#220](https://github.com/droidsam1/overreach/issues/220) (hero card, once #212, #213 and #215 are done),
   [#221](https://github.com/droidsam1/overreach/issues/221) (Why screen, once #213 and #219 are done),
   [#222](https://github.com/droidsam1/overreach/issues/222) (Your week card, once #214, #216 and #220 are done),
   [#223](https://github.com/droidsam1/overreach/issues/223) (prompt and link tiles, once #214, #217 and #222 are
   done),
   [#224](https://github.com/droidsam1/overreach/issues/224) (done-today hero, once #218 and #220 are done),
   [#225](https://github.com/droidsam1/overreach/issues/225) (accessibility pass and docs, once #221, #223 and #224
   are done).
4. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Validate hybrid planning candidates with historical replay and coach and clinician review before integrating
  automatic planning. [Task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans)

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review — [#21](https://github.com/droidsam1/overreach/issues/21). Compare the Today decision,
  access to recovery and everyday movement details (#125), and Plan scheduling. Compare the time and taps
  to find a Garmin run and a prior lift in History (#92). Time the active logger
  one-handed (#93). Use the [iPhone UX guide](design/iphone-ux.md#repeatable-beforeafter-check)
  to record large text, VoiceOver and before/after timings. Revisit tab placement with those observations.
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

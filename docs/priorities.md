# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. Claim one task, not a range: an item that lists several tasks or issues in order is claimed one task at a
time, the first without a PR. `scripts/claim-task.py --next` reads this list: it skips closed and umbrella issues,
tasks also listed in a later section and tasks written as "once #N is done" (or "once #N and #M are done") while any of them is open. When you merge a PR
that finishes or changes an item, update this list in the same PR. Every item links an issue or a design-doc task
(`check-repo.py` fails otherwise). `--next --dry-run` reads the list on `origin/main`, not your working copy.

Reviewed 2026-11-23. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **Minimal UI with progressive disclosure** — [#179](https://github.com/droidsam1/overreach/issues/179)
   ([ADR-0041](adr/0041-minimal-ui-progressive-disclosure.md)): all sub-issues shipped, including
   [#185](https://github.com/droidsam1/overreach/issues/185) (sections by data) and
   [#186](https://github.com/droidsam1/overreach/issues/186) (set feedback and achievements); a running-goal
   milestone waits for a goal-progress event to attach it to. What remains is the device measurement in
   [#21](https://github.com/droidsam1/overreach/issues/21).
2. **Rotation after a recorded run** — [#268](https://github.com/droidsam1/overreach/issues/268)
   ([ADR-0044](adr/0044-rotation-after-a-recorded-run.md)), one task at a time in this order:
   [#269](https://github.com/droidsam1/overreach/issues/269) (run carry-over, done),
   [#270](https://github.com/droidsam1/overreach/issues/270) (record swaps, done),
   [#271](https://github.com/droidsam1/overreach/issues/271) (decision ladder, once #269 and #270 are done),
   [#272](https://github.com/droidsam1/overreach/issues/272) (Today, once #271 is done; Today work, now free to start),
   [#273](https://github.com/droidsam1/overreach/issues/273) (replay and AI context, once #271 is done),
   [#274](https://github.com/droidsam1/overreach/issues/274) (elevation loss, done).
3. **Per-lap Garmin values** — [#259](https://github.com/droidsam1/overreach/issues/259).
4. **Run offer follow-up** — [#265](https://github.com/droidsam1/overreach/issues/265) (learn usual run slots).

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Validate hybrid planning candidates with historical replay and coach and clinician review before integrating
  automatic planning. [Task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans)

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review — [#21](https://github.com/droidsam1/overreach/issues/21). Compare the Today decision,
  access to recovery and everyday movement details (#125), and Plan scheduling. Compare the time and taps
  to find a Garmin run and a prior lift in History (#92). Time the active logger
  one-handed (#93). Use the [iPhone UX guide](design/iphone-ux.md#repeatable-beforeafter-check)
  to record large text, VoiceOver and before/after timings, including the Visual Today cards
  ([#211](https://github.com/droidsam1/overreach/issues/211), pending on a device). Revisit tab placement with those
  observations.
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

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
   ([ADR-0041](adr/0041-minimal-ui-progressive-disclosure.md)), one task at a time in this order:
   [#181](https://github.com/droidsam1/overreach/issues/181) (one pending prompt),
   [#184](https://github.com/droidsam1/overreach/issues/184) (two-step onboarding),
   [#185](https://github.com/droidsam1/overreach/issues/185) (sections by data, once #220 is done, so it builds on the
   new hero). #181–#185 touch Today: never in parallel. [#186](https://github.com/droidsam1/overreach/issues/186) (set feedback and achievements) shipped
   lift records and set feedback; a running-goal milestone waits for a goal-progress event to attach it to.
2. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.
3. **Pain for any run** — [#256](https://github.com/droidsam1/overreach/issues/256): ask about pain after every run of
   a pain-free goal, with severity and next-morning status, so the run/walk progression
   ([ADR-0043](adr/0043-running-dose-single-session-ceiling.md)) stops reading unreported pain as none.
4. **Per-lap Garmin values** — [#259](https://github.com/droidsam1/overreach/issues/259).

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

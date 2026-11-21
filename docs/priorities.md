# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. Claim one task, not a range: an item that lists several tasks or issues in order is claimed one task at a
time, the first without a PR (see "Working in parallel" in `AGENTS.md`). When you merge a PR that finishes or changes
an item, update this list in the same PR.

Reviewed 2026-11-21. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **Running priority and the shared schedule** —
   [hybrid backlog tasks 7–8](design/readiness-and-hybrid-planning.md#7-represent-planned-runs-races-and-dates):
   structured runs in the shared schedule, then adjusting planned runs. The priority control shipped.
2. **Planned versus completed work for imported plans** — follow-up of
   [#34](https://github.com/droidsam1/overreach/issues/34).
3. **Faster History lookups** — [#92](https://github.com/droidsam1/overreach/issues/92).
4. **Hybrid planning research** —
   [hybrid backlog task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans).
   Runs in parallel. Integrate after the shared schedule work.
5. **Longer trends** — [#127](https://github.com/droidsam1/overreach/issues/127). Add 30- and
   90-day views inside the relevant details. Use the activity matching from #40 for combined-source totals.
6. **Dog walks from a pet tracker** — [#154](https://github.com/droidsam1/overreach/issues/154), one task at a time:
   [#155](https://github.com/droidsam1/overreach/issues/155) (matcher), then
   [#157](https://github.com/droidsam1/overreach/issues/157) once the device check #156 is done, then
   [#159](https://github.com/droidsam1/overreach/issues/159), [#158](https://github.com/droidsam1/overreach/issues/158).
   [#160](https://github.com/droidsam1/overreach/issues/160) only if #156 fails. Design:
   [companion walks](design/companion-walks.md).
7. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review — [#21](https://github.com/droidsam1/overreach/issues/21). Compare the Today decision,
  access to recovery and everyday movement details (#125), and Plan scheduling. Time the active logger
  one-handed (#93). Use the [iPhone UX guide](design/iphone-ux.md#repeatable-beforeafter-check)
  to record large text, VoiceOver and before/after timings. Revisit tab placement with those observations.
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).
- Does a Tractive walk reach Apple Health through Strava? — [#156](https://github.com/droidsam1/overreach/issues/156).
  Decides whether #157 or #160 comes next.

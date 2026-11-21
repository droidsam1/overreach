# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. Claim one task, not a range: an item that lists several tasks or issues in order is claimed one task at a
time, the first without a PR (see "Working in parallel" in `AGENTS.md`). When you merge a PR that finishes or changes
an item, update this list in the same PR.

Reviewed 2026-11-21. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **Stalled lifts with a next step** —
   [deloads task 6](design/deloads-and-breaks.md#6-stalled-lifts-as-their-own-recommendation).
2. **One clear next action in Today** — [#94](https://github.com/droidsam1/overreach/issues/94). Put resume or the
   next useful action first, with its reason and any warning that affects it. Use the existing compact deload card.
3. **Fewer taps in the active logger** — [#93](https://github.com/droidsam1/overreach/issues/93). Used in every
   session. Shipped: the first set leads the screen (help and focus in session options), "Last time" with its
   date under today's target, haptic set completion and a report that leads with the saved confirmation and any
   record. Next: an opt-in "use last time's values" and the one-handed timing on a device
   ([#21](https://github.com/droidsam1/overreach/issues/21)).
4. **Recovery & Progress from Today** — [#125](https://github.com/droidsam1/overreach/issues/125). After #94
   and shared readiness, open the new destination and move the metrics and everyday movement details together.
5. **One activity log** — [#40](https://github.com/droidsam1/overreach/issues/40), in order
   [#85](https://github.com/droidsam1/overreach/issues/85) → [#86](https://github.com/droidsam1/overreach/issues/86)
   → [#87](https://github.com/droidsam1/overreach/issues/87) → [#88](https://github.com/droidsam1/overreach/issues/88).
   Correct wrong merges and count every activity once.
6. **Running priority and the shared schedule** —
   [hybrid backlog tasks 6–8](design/readiness-and-hybrid-planning.md#6-add-a-running-objective-to-hybrid-goals):
   running/strength priority, dated strength in the calendar, structured runs, then adjusting planned runs.
7. **Planned versus completed work for imported plans** — follow-up of
   [#34](https://github.com/droidsam1/overreach/issues/34).
8. **Schedule-first Plan** — [#126](https://github.com/droidsam1/overreach/issues/126). After #125, bring the
   calendar forward and move retrospective detail to Recovery & Progress as shared break and lift results land.
9. **Faster History lookups** — [#92](https://github.com/droidsam1/overreach/issues/92).
10. **Hybrid planning research** —
   [hybrid backlog task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans).
   Runs in parallel. Integrate after the shared schedule work.
11. **Longer trends** — [#127](https://github.com/droidsam1/overreach/issues/127). After #126, add 30- and
    90-day views inside the relevant details. Use the activity matching from #40 for combined-source totals.
12. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review — [#21](https://github.com/droidsam1/overreach/issues/21). Compare the Today decision,
  access to recovery and progress details, and Plan scheduling. Use the [iPhone UX guide](design/iphone-ux.md#repeatable-beforeafter-check)
  to record large text, VoiceOver and before/after timings. Revisit tab placement with those observations.
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

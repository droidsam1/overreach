# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. When you merge a PR that finishes or changes an item, update this list in the same PR.

Reviewed 2026-11-21. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **Fewer break questions** —
   [deloads and breaks task 4](design/deloads-and-breaks.md#4-ask-about-the-latest-periods-only), then the running
   return left in task 3. Breaks per discipline and the automatic setting shipped (ADR-0037).
2. **Explain deloads and stalled lifts step by step** —
   [tasks 5–6](design/deloads-and-breaks.md#5-today-deload-card-summary-first-details-on-demand).
   Before [#94](https://github.com/droidsam1/overreach/issues/94), which places this card in Today.
3. **One clear next action in Today** — [#94](https://github.com/droidsam1/overreach/issues/94). Put resume or the
   next useful action first, with its reason and any warning that affects it.
4. **Fewer taps in the active logger** — [#93](https://github.com/droidsam1/overreach/issues/93). Used in every
   session. Shipped: the first set leads the screen (help and focus in session options), "Last time" with its
   date under today's target, haptic set completion and a report that leads with the saved confirmation and any
   record. Next: an opt-in "use last time's values" and the one-handed timing on a device
   ([#21](https://github.com/droidsam1/overreach/issues/21)).
5. **Recovery & Progress from Today** — [#125](https://github.com/droidsam1/overreach/issues/125). After #94
   and shared readiness, open the new destination and move the metrics and everyday movement details together.
6. **One activity log** — [#40](https://github.com/droidsam1/overreach/issues/40), in order
   [#85](https://github.com/droidsam1/overreach/issues/85) → [#86](https://github.com/droidsam1/overreach/issues/86)
   → [#87](https://github.com/droidsam1/overreach/issues/87) → [#88](https://github.com/droidsam1/overreach/issues/88).
   Correct wrong merges and count every activity once.
7. **Running priority and the shared schedule** —
   [hybrid backlog tasks 6–8](design/readiness-and-hybrid-planning.md#6-add-a-running-objective-to-hybrid-goals):
   running/strength priority, dated strength in the calendar, structured runs, then adjusting planned runs.
8. **Planned versus completed work for imported plans** — follow-up of
   [#34](https://github.com/droidsam1/overreach/issues/34).
9. **Schedule-first Plan** — [#126](https://github.com/droidsam1/overreach/issues/126). After #125, bring the
    calendar forward and move retrospective detail to Recovery & Progress as shared break and lift results land.
10. **Faster History lookups** — [#92](https://github.com/droidsam1/overreach/issues/92).
11. **Hybrid planning research** —
   [hybrid backlog task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans).
   Runs in parallel. Integrate after the shared schedule work.
12. **Longer trends** — [#127](https://github.com/droidsam1/overreach/issues/127). After #126, add 30- and
    90-day views inside the relevant details. Use the activity matching from #40 for combined-source totals.
13. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review — [#21](https://github.com/droidsam1/overreach/issues/21). Compare the Today decision,
  access to recovery and progress details, and Plan scheduling. Use the [iPhone UX guide](design/iphone-ux.md#repeatable-beforeafter-check)
  to record large text, VoiceOver and before/after timings. Revisit tab placement with those observations.
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

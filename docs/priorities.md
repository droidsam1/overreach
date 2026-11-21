# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. When you merge a PR that finishes or changes an item, update this list in the same PR.

Reviewed 2026-11-21. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **One source of truth per training question** —
   [training services, tasks 4–5](design/training-services.md#4-readiness-and-the-deload-recommendation) (ADR-0035). Screens read sources and combine rules
   on their own, so Today, Plan, Workout and the AI context could give different answers. Reading, the last
   recovery, lift status and the deload decision are shared; one loader for the training record and the
   same answers in the AI context remain.
2. **Correct deload signals** —
   [deloads and breaks, task 2](design/deloads-and-breaks.md#2-count-only-lifts-in-current-training-and-say-which).
   Check rotation membership, show the lifts behind the signals and require evidence of fatigue.
3. **Breaks per discipline, counted automatically** —
   [tasks 3–4](design/deloads-and-breaks.md#3-breaks-per-discipline-counted-automatically). A setting that counts a
   week without lifting or running as rest, and Plan asking only about recent periods.
4. **Explain deloads and stalled lifts step by step** —
   [tasks 5–6](design/deloads-and-breaks.md#5-today-deload-card-summary-first-details-on-demand). Before item 5,
   which places this card in Today.
5. **One clear next action in Today** — [#94](https://github.com/droidsam1/overreach/issues/94). Put resume or the
   next useful action first, with its reason and any warning that affects it.
6. **Fewer taps in the active logger** — [#93](https://github.com/droidsam1/overreach/issues/93). Used in every
   session. Shipped: the first set leads the screen (help and focus in session options), "Last time" with its
   date under today's target, haptic set completion and a report that leads with the saved confirmation and any
   record. Next: an opt-in "use last time's values" and the one-handed timing on a device
   ([#21](https://github.com/droidsam1/overreach/issues/21)).
7. **Recovery & Progress from Today** — [#125](https://github.com/droidsam1/overreach/issues/125). After #94
   and shared readiness, open the new destination and move the metrics and everyday movement details together.
8. **One activity log** — [#40](https://github.com/droidsam1/overreach/issues/40), in order
   [#85](https://github.com/droidsam1/overreach/issues/85) → [#86](https://github.com/droidsam1/overreach/issues/86)
   → [#87](https://github.com/droidsam1/overreach/issues/87) → [#88](https://github.com/droidsam1/overreach/issues/88).
   Correct wrong merges and count every activity once.
9. **Running priority and the shared schedule** —
   [hybrid backlog tasks 6–8](design/readiness-and-hybrid-planning.md#6-add-a-running-objective-to-hybrid-goals):
   running/strength priority, dated strength in the calendar, structured runs, then adjusting planned runs.
10. **Planned versus completed work for imported plans** — follow-up of
   [#34](https://github.com/droidsam1/overreach/issues/34).
11. **Schedule-first Plan** — [#126](https://github.com/droidsam1/overreach/issues/126). After #125, bring the
    calendar forward and move retrospective detail to Recovery & Progress as shared break and lift results land.
12. **Faster History lookups** — [#92](https://github.com/droidsam1/overreach/issues/92).
13. **Hybrid planning research** —
   [hybrid backlog task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans).
   Runs in parallel. Integrate after the shared schedule work.
14. **Longer trends** — [#127](https://github.com/droidsam1/overreach/issues/127). After #126, add 30- and
    90-day views inside the relevant details. Use the activity matching from #40 for combined-source totals.
15. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review — [#21](https://github.com/droidsam1/overreach/issues/21). Compare the Today decision,
  access to recovery and progress details, and Plan scheduling. Use the [iPhone UX guide](design/iphone-ux.md#repeatable-beforeafter-check)
  to record large text, VoiceOver and before/after timings. Revisit tab placement with those observations.
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

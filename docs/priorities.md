# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. When you merge a PR that finishes or changes an item, update this list in the same PR.

Reviewed 2026-11-21. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **One source of truth per training question** —
   [training services, tasks 1–5](design/training-services.md) (ADR-0035). Screens read sources and combine rules
   on their own, so Today, Plan, Workout and the AI context give different answers (51 vs 2 weeks since the last
   deload, unmerged metrics for the Assistant).
2. **Correct deload signals** —
   [deloads and breaks, task 2](design/deloads-and-breaks.md#2-count-only-lifts-in-current-training-and-say-which);
   task 1 there is done by training services task 2. Stalls count lifts no longer trained.
3. **Breaks per discipline, counted automatically** —
   [tasks 3–4](design/deloads-and-breaks.md#3-breaks-per-discipline-counted-automatically). A setting that counts a
   week without lifting or running as rest, and Plan asking only about recent periods.
4. **Explain deloads and stalled lifts step by step** —
   [tasks 5–6](design/deloads-and-breaks.md#5-today-deload-card-summary-first-details-on-demand). Before item 5,
   which places this card in Today.
5. **One clear next action in Today** — [#94](https://github.com/droidsam1/overreach/issues/94). Today has grown
   card by card (readiness, deload, strength and running options, check-in and everyday movement).
6. **Fewer taps in the active logger** — [#93](https://github.com/droidsam1/overreach/issues/93). Used in every
   session. Shipped: the first set leads the screen (help and focus in session options), "Last time" with its
   date under today's target, haptic set completion and a report that leads with the saved confirmation and any
   record. Next: an opt-in "use last time's values" and the one-handed timing on a device
   ([#21](https://github.com/droidsam1/overreach/issues/21)).
7. **One activity log** — [#40](https://github.com/droidsam1/overreach/issues/40), in order
   [#85](https://github.com/droidsam1/overreach/issues/85) → [#86](https://github.com/droidsam1/overreach/issues/86)
   → [#87](https://github.com/droidsam1/overreach/issues/87) → [#88](https://github.com/droidsam1/overreach/issues/88).
   Correct wrong merges and count every activity once.
8. **Running priority and the shared schedule** —
   [hybrid backlog tasks 6–8](design/readiness-and-hybrid-planning.md#6-add-a-running-objective-to-hybrid-goals):
   running/strength priority, dated strength in the calendar, structured runs, then adjusting planned runs.
9. **Planned versus completed work for imported plans** — follow-up of
   [#34](https://github.com/droidsam1/overreach/issues/34).
10. **Faster History lookups** — [#92](https://github.com/droidsam1/overreach/issues/92).
11. **Hybrid planning research** —
   [hybrid backlog task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans).
   Runs in parallel. Integrate after item 8.
12. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review: large text, VoiceOver, before/after timings — [#21](https://github.com/droidsam1/overreach/issues/21).
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

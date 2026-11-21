# Priorities

The order in which to take open work, highest user value first. Take the first item that is not blocked and has
no open PR. When you merge a PR that finishes or changes an item, update this list in the same PR.

Reviewed 2026-11-21. Value is judged for one hybrid athlete who uses Overreach every day: decisions in Today
and the logger come before review tools, and work that only a person with an iPhone can do is listed apart.

## Ready to implement

1. **Walks and steps against the personal baseline** — [#103](https://github.com/droidsam1/overreach/issues/103).
   The last open item of v0.2 Recovery. Walking is the athlete's daily background load and recovery tool, and
   Today ignored it. The first delivery shipped the baselines, signals, Today card and Apple Health walking
   workouts; the rest is listed in [daily activity](design/daily-activity.md#shipped). Next: Garmin walking
   activities and walks detected from step samples.
2. **Compare today's strength session with an optional alternative** —
   [hybrid backlog task 5](design/readiness-and-hybrid-planning.md#5-compare-against-todays-strength-session-and-offer-an-optional-alternative).
   Rotation, dated routines and the easy example shipped; remaining: load next to sets and reps, the opt-in
   "I want to train" path and suppression rules.
3. **One clear next action in Today** — [#94](https://github.com/droidsam1/overreach/issues/94). Today has grown
   card by card (readiness, deload, strength and running options, check-in, now movement). Do it after items 1
   and 2 so the layout is settled once.
4. **Fewer taps in the active logger** — [#93](https://github.com/droidsam1/overreach/issues/93). Used in every
   session; "last time" next to "today's target".
5. **One activity log** — [#40](https://github.com/droidsam1/overreach/issues/40), in order
   [#85](https://github.com/droidsam1/overreach/issues/85) → [#86](https://github.com/droidsam1/overreach/issues/86)
   → [#87](https://github.com/droidsam1/overreach/issues/87) → [#88](https://github.com/droidsam1/overreach/issues/88).
   Correct wrong merges and count every activity once.
6. **Running priority and the shared schedule** —
   [hybrid backlog tasks 6–8](design/readiness-and-hybrid-planning.md#6-add-a-running-objective-to-hybrid-goals):
   running/strength priority, dated strength in the calendar, structured runs, then adjusting planned runs.
7. **Planned versus completed work for imported plans** — follow-up of
   [#34](https://github.com/droidsam1/overreach/issues/34).
8. **Faster History lookups** — [#92](https://github.com/droidsam1/overreach/issues/92).
9. **Hybrid planning research** —
   [hybrid backlog task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans).
   Runs in parallel; integrate only after items 2 and 6.
10. **Pounds** — [#37](https://github.com/droidsam1/overreach/issues/37). Current users train in kilograms.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Real-device review: large text, VoiceOver, before/after timings — [#21](https://github.com/droidsam1/overreach/issues/21).
- Clinical review of symptom wording —
  [hybrid backlog task 3](design/readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

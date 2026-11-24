# Priorities

Take the first available issue in order. `scripts/claim-task.py --next --dry-run` reads the list on `origin/main`
and shows the next issue and why earlier issues were skipped. To reserve it, run `scripts/claim-task.py --next`.

Use one issue link and a short summary per row. Record prerequisites as GitHub issue dependencies. When a PR
finishes a task, close the issue and update this list in the same PR. Link any remaining work to its own issue.
Keep delivery history in the relevant design document or ADR.

Reviewed 2026-11-24. Give priority to work that completes a feature and improves daily decisions or logging for a
hybrid athlete. The device and external review steps below have their own acceptance criteria.

## Ready to implement

1. [#292](https://github.com/droidsam1/overreach/issues/292) — Use the daily recovery assessment in imported-plan follow-up.
2. [#247](https://github.com/droidsam1/overreach/issues/247) — Audit screens for consistency with Today.
3. [#127](https://github.com/droidsam1/overreach/issues/127) — Add 30- and 90-day trends to Recovery & Progress.
4. [#279](https://github.com/droidsam1/overreach/issues/279) — Add a one-time hint when a section first appears.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Validate hybrid planning candidates with historical replay and coach and clinician review before integrating
  automatic planning. [Task 9](design/readiness-and-hybrid-planning.md#9-research-and-validate-hybrid-planning-rules-before-automating-plans)

- Data survives re-signing and reinstall — [#11](https://github.com/droidsam1/overreach/issues/11).
- Verify the unified activity log with Overreach, Apple Health and Garmin — [#40](https://github.com/droidsam1/overreach/issues/40).
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

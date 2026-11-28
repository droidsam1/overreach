# Priorities

Take the first available issue in order. `scripts/claim-task.py --next --dry-run` reads the list on `origin/main`
and shows the next issue and why earlier issues were skipped. To reserve it, run `scripts/claim-task.py --next`.

Use one issue link and a short summary per row. Record prerequisites as GitHub issue dependencies. When a PR
finishes a task, close the issue and update this list in the same PR. Link any remaining work to its own issue.
Keep delivery history in the relevant design document or ADR.

Reviewed 2026-11-24. Give priority to work that completes a feature and improves daily decisions or logging for a
hybrid athlete. The device and external review steps below have their own acceptance criteria.

## Ready to implement

1. [#410](https://github.com/droidsam1/overreach/issues/410) — Show the last heavy leg session and days since it when legs are sore.
2. [#411](https://github.com/droidsam1/overreach/issues/411) — Suggest an easier day when leg soreness lasts beyond 72 h, after the leg-session helper.
3. [#414](https://github.com/droidsam1/overreach/issues/414) — Ask what explains an HRV or resting-HR deviation.
4. [#416](https://github.com/droidsam1/overreach/issues/416) — Add stress and sleep quality scales to the check-in.
5. [#412](https://github.com/droidsam1/overreach/issues/412) — Show short-sleep nights this week with the 7 h guidance.
6. [#413](https://github.com/droidsam1/overreach/issues/413) — Add days since the last heavy leg session and run to the report, after the leg-session helper.
7. [#415](https://github.com/droidsam1/overreach/issues/415) — Ask soreness zone and type plus a joint-pain block; needs the clinical review first.

## Needs a person or an iPhone

Agents can prepare these but not finish them.

- Validate the circadian timing thresholds on real histories — [#349](https://github.com/droidsam1/overreach/issues/349).

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
- Close the UI consistency epic [#247](https://github.com/droidsam1/overreach/issues/247) once its issues are done:
  before screenshots (light and dark) need a Mac and simulator and are deferred, they do not block the issues; the
  owner approves the Train and Plan layouts on the design canvas. The audit is in
  [ui-consistency-audit.md](design/ui-consistency-audit.md).
- Release v0.1.0 and the beta guide — [#22](https://github.com/droidsam1/overreach/issues/22).

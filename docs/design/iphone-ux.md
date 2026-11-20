# iPhone UX guide

Make it easy to decide what to do, log a workout, and find a past result. Keep the app’s
recommendations explainable and its advanced controls easy to find.

## Design rules

- Give each screen state one visually dominant action when there is a useful next step. Use a verb
  that names the outcome. Keep frequent actions visible and put the facts needed to act beside them.
- Show the essential facts first. Use descriptive routes such as **Why this recommendation?**,
  **View metrics**, and **Session options** for supporting information. Put evidence, source coverage
  and advanced settings where they can be found with a clear label.
- Show the result of an action where it happened. Make set completion visible and expose its state
  to VoiceOver. Confirm a workout save when it succeeds. On failure, say what was kept
  and give a recovery action. Highlight a real achievement when available. Let people resume
  without pressure from streaks or prompts.
- Keep labels, navigation and the use of color consistent. Use text or a symbol alongside status
  colors. Check touch targets against Apple’s 44 × 44 pt recommendation. Allow controls to wrap or
  stack with Dynamic Type. Check VoiceOver order and labels, dark mode and Reduce Motion on the
  affected path. [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)

| Flow | Default view | Details and exceptions |
| --- | --- | --- |
| **Today** | Put **Resume workout** first when a session can be resumed. Otherwise lead with the next useful action and a short reason. | Put evidence, history and metric sources behind descriptive labels. With sparse data, show what is available and how to connect a source. When a source fails, keep available data visible and explain how to retry. |
| **Active logger** | Keep the current exercise, actionable set, last result and today’s target together. Keep completion and the compact countdown reachable with the keyboard open. | Keep notes, help and focus easy to find. Explain missing history in place. If training is interrupted, preserve the draft and offer to resume. Offer the full report after confirming the save. |
| **History** | Make activity type, date and key result easy to scan. Show active filters. Provide a direct route to an exercise’s last logged result. | Open metrics and provenance in the activity detail. Distinguish an empty history from an empty filtered result. Give the filtered state a clear reset. |

## Research and evidence

Reviewed **2026-11-20**. The first-party references describe guidelines or published product
behavior. The Overreach use cases above are design proposals to test.

- Apple emphasizes recognizable controls, clear hierarchy and feedback. Its disclosure guidance
  keeps frequently used actions visible while revealing detail when needed.
  [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/) ·
  [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
- Hevy shows previous workout values where the user logs a set and starts its rest timer on set
  completion. [Previous values](https://www.hevyapp.com/features/track-exercises/) ·
  [Automatic rest timer](https://www.hevyapp.com/features/workout-rest-timer/)
- Gentler Streak lets users open a daily suggestion for duration and intensity. Fitness on iPhone
  offers a customizable summary. These are references for choosing what Today shows first and how
  to open more detail.
  [Gentler Streak recommendations](https://docs.gentler.app/daily-workout-recommendations/how-to-find-and-understand-your-daily-workout-recommendation) ·
  [Fitness summary](https://support.apple.com/en-gb/guide/iphone/ipha5dddb411/26/ios/26)

**Overreach code inspection.** Today can surface recovery, training suggestions and check-in
together. The logger can place help and session focus above the first set. These are plausible
sources of extra scanning. Layout changes, workout recovery and History filters have shipped.
[UX review plan](https://github.com/droidsam1/overreach/issues/90) ·
[Layout PR](https://github.com/droidsam1/overreach/pull/72) ·
[Workout recovery PR](https://github.com/droidsam1/overreach/pull/74) ·
[History PR](https://github.com/droidsam1/overreach/pull/77)

**Usability results.** The real-device baseline and before/after observations are pending. Record
observations and device-specific defects in the verification issue. Report simulator builds
separately from observed device results. [Real-device verification](https://github.com/droidsam1/overreach/issues/21)

## Repeatable before/after check

Use the same compact iPhone, starting screen, configuration and comparable synthetic data for
both builds. Seed a routine with two exercises, a saved draft, a prior logged lift with known
weight and reps, and a mixed History with at least two Garmin runs. Seed Today with a recommendation
that has an explanation. Recreate each start state before its task. Give the goal without naming
the controls. Start timing on the prompt and stop at the listed result.

| Task | Start state | Stop when |
| --- | --- | --- |
| Decide what to do today and find out why | Today, with a recommendation available | The person states the next action and opens or identifies its reason. |
| Start or resume a workout | Today, once with the routine available and once with a saved draft | The correct workout opens for editing. Record the two runs separately. |
| Edit and complete the first set of an exercise during rest | Active workout, countdown running from the prior exercise and numeric keyboard open on the next exercise’s first set | The new value is retained and the intended set is marked complete. |
| Find the latest Garmin run | Mixed History with filters cleared | The person opens the latest Garmin run and identifies its date. |
| Find the last logged weight for an exercise | App launch with a named exercise and prior sessions loaded | The person identifies the expected weight, reps and date. |

Record build, device model or viewport, language, appearance, text size, VoiceOver and keyboard state.
For each attempt, use **task · before/after · unaided yes/no · elapsed time · taps · wrong turns ·
hesitations · observation**. Mark skipped scenarios as pending and note why. After the default pass,
repeat the affected paths at large text sizes and with VoiceOver. Check dark mode, Reduce Motion
and one-handed use where relevant. [Record results in #21](https://github.com/droidsam1/overreach/issues/21)

## UI pull request checklist

- [ ] State the frequent user goal, the primary action and the information visible by default.
- [ ] Name the route to supporting details and describe the relevant empty, error or recovery state.
- [ ] List how the affected flow was checked. Include the before/after observations or link the
  pending device checks in #21, with build and runtime results identified separately.

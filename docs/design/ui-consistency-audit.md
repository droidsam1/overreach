# UI consistency audit against the visual Today

Audit for [#247](https://github.com/droidsam1/overreach/issues/247). Reference: [Visual Today](today-visual.md),
[ADR-0041](../adr/0041-minimal-ui-progressive-disclosure.md), [ADR-0042](../adr/0042-visual-today.md) and the
[iPhone UX guide](iphone-ux.md).

**Method.** Static read of `Packages/OverreachKit/Sources/Feature*` (everything except `FeatureToday`) and
`DesignSystem`, plus counts by search, at `origin/main` 119dc54, 2026-11-24. Nothing was run: the screenshots,
contrast and VoiceOver checks below are **pending** and need a Mac or simulator (see [Not covered](#not-covered)).
Severity: **High** = visible on a daily path or hides state; **Medium** = looks like another app; **Low** = polish.

## Cross-cutting gaps

| # | Gap | Evidence | Sev. | Proposed change |
| --- | --- | --- | --- | --- |
| X1 | Errors and warnings are ad-hoc `Label(...).foregroundStyle(.red/.orange)`, not `StatusLabel`/`StatusTone.critical`. Light/dark red differs from Today's accent and the symbol is not the tone's. | About 40 sites in 20 files, for example `PlanView.swift:37,217`, `HistoryView.swift:79`, `RoutinesView.swift:24,135`, `ExercisesView.swift:22,144,238`, `SettingsView.swift:132,227,307-334` | High | One DesignSystem `InlineNotice(message, tone)` (symbol + word, tone colours, optional **Try again**) and replace every site. |
| X2 | Almost every screen is a plain `Form`/`List` on the system grouped background. Today uses cards on the page colour with radius 24 / tiles 16. | `Form` in 16 files, `List` in 14 (excluding Today); cards only in Trends, Onboarding, Garmin setup | Medium | Add a generic `Card` (surface, radius, padding) and `SectionHeader` to DesignSystem; migrate screen by screen, Train and History first. Keep `List` where rows are long and swipeable (History, Exercises). |
| X3 | No generic card or section header: Today builds cards inline (`TodayWeekCard.swift:36-38`, `TodayPromptCard.swift:36-38`) so other features cannot reuse them. | `Components.swift` has only `MetricTile`, `StatusLabel`, `StatusBadge`, `ComingSoonView`; `MetricTile` is unused outside DesignSystem | Medium | Extract `Card`, `SectionHeader`, `IconTile` from Today (deliverable 3). Remove or adopt `MetricTile` and `ComingSoonView`. |
| X4 | Radius tokens disagree with the spec. `Radius.card` is 16 (the spec's tile radius) while the hero uses `HeroMetrics.radius` 24 and the week card uses 24 but the prompt card 16. | `Theme.swift:12`, `TodayHero.swift:165`, `TodayWeekCard.swift:38`, `TodayPromptCard.swift:38` | Medium | Add `Radius.card = 24`, `Radius.tile = 16`; move `HeroMetrics.radius` into them; fix the prompt card. |
| X5 | Spacing is not tokenised in places and the 14 pt gap between blocks has no token. | Spec: gap 14; `Spacing` has 4/8/16/24/32 | Low | Add `Spacing.block = 14` or change the spec. |
| X6 | Tone colours are used only on Today, History status and Workout status labels. Settings uses `.green/.orange/.red` for connection state. | `SettingsView.swift:204,307,326-334`, `OnboardingView.swift:169`, `GarminSetupView.swift:313` | Medium | Use `StatusTone` via `StatusLabel`/`StatusBadge`. |
| X7 | Haptics are used only for set completion, rest end, reorder and the Today celebration. Missing: save success (workout, session edit, plan change), destructive confirmation, check-in answer. Ties to #245. | `.haptic(` in 5 places | Medium | Define the haptic per interaction in #245 and apply with `.haptic`. |
| X8 | Dynamic Type adaptation (`isAccessibilitySize`) exists in Today, History and `DesignSystem`; none in Workout, Plan, Settings, Trends, Exercises, Assistant. Fixed-size glyphs in onboarding, What's New and Garmin setup (72-84 pt) do not scale. | grep `isAccessibilitySize` | Medium | Check each screen at AX5; use `@ScaledMetric` for glyphs. |
| X9 | VoiceOver labels: Today has about 55 `accessibility*` modifiers; Exercises, Onboarding, Settings, Garmin setup, New exercise and Routine editor have none. Rows that combine several texts are read piecemeal. | grep `accessibility` | Medium | One pass per screen: combine rows, label icon-only buttons, hide decorative images. |
| X10 | Touch target below 44 pt. | `GarminSetupView.swift:294` frame 28 × 28 | Low | Check it is only an indicator; otherwise enlarge. |
| X11 | Titles: large title on tab roots, inline on pushed screens, but mixed (`Train` switches to inline during a session; `Recovery & Progress` is inline at root). Today uses a large title. | `TrendsView.swift:69-70`, `WorkoutView.swift:49-50` | Low | Rule: tab roots large, pushes inline. Decide with #244 (navigation). |
| X12 | Empty states: Today-style one line plus action is used only in History (`ContentUnavailableView`) and Exercises/Plan (`ListEmptyState`). Two components do the same. Loading is a bare `ProgressView` or text. | `HistoryView.swift:128-138`, `Layout.swift:73`, `PlanView.swift:29-33` | Medium | Make `ListEmptyState` wrap `ContentUnavailableView` with the shared tone; add `LoadingState`. |

## Per screen

Order is by impact: Train and History first (daily use).

### Train

| Screen | Gaps | Sev. | Proposed change |
| --- | --- | --- | --- |
| `WorkoutView` / `StartSessionView` (`RoutinesView.swift`) | Plain `List`; "Up next" is a bare button row, not the hero + verb of Today; error and notice as X1/X6; saving shows a bare `ProgressView("Saving workout…")`; no summary card on finish apart from the sheet. | High | Start screen as hero card (next session, one verb button) over routine cards; live session keeps the list for set entry; saving uses `LoadingState`. Mock-up first. |
| Live session (`SessionList`, `SetEntryRow`) | Functional and tested, but sets are in a system list with no card per exercise; completed state is a checkmark only (check colour/symbol parity with Today's done tone). Reduce Motion is handled. | Medium | Exercise as card with done tone when all sets are done. |
| `RestTimerView` | Own layout; uses `List`; haptic present. | Low | Compact timer as `IconTile` + progress bar from DesignSystem. |
| Finish summary (`SessionReportSheet`) | DesignSystem component, but not Today's "After training" layout (done-tone hero, totals, record row). | Medium | Reuse the done hero from `TodayDoneSummary`. |
| `RoutinesView` / `RoutineEditorView` | `Form`, `.orange` lightbulb at line 203, red errors. | Medium | X1, X6; tone for the suggestion row. |
| `NewExerciseForm` | `Form` with inline red error, no accessibility labels. | Low | X1, X9. |

### History

| Screen | Gaps | Sev. | Proposed change |
| --- | --- | --- | --- |
| `HistoryView` | `List` with filters, last-time card (`lastTimeCard`), match review links, empty states via `ContentUnavailableView`. Row icons use `ActivityColor` (good). The "Last time" card is a different style from Today cards; red error at line 79, orange at 306. | Medium | Cards from X3, `InlineNotice`; keep list for rows. |
| `HistoryCalendarView` / `MonthCalendar` | DesignSystem calendar with `ActivityColor`; red at line 183; fixed 7 pt glyph in `MonthCalendar.swift:77`. | Low | `StatusTone` for the red; scale glyph. |
| Strength / run / walk detail, `RecordedStrengthDetail`, `HistoryRunDetail` | `List`/`Form` with no hero; the key result is not first (ADR-0041: summary, then details). | Medium | Summary tiles on top (totals as in Today's done summary), details below. |
| `SessionEditorView` | `Form`, red/orange messages (X1). | Low | X1. |
| Match review (`RunMatchReviewLink`, `StrengthMatchReviewLink`) | Row linking to a plain list; no explanation card. | Low | One-line summary card with the count and verb. |

### Plan

| Screen | Gaps | Sev. | Proposed change |
| --- | --- | --- | --- |
| `PlanView` | One long `Form` of 9 sections (progress, schedule, recent break, block, next, goal, plan, findings, block, progress, assistant). Violates two levels and the "at most four blocks" budget; `Next` decision is a headline in a section, not a hero. Progress bars are plain `ProgressView` instead of `ProgressBar`. | High | Level 1: next session hero, week strip, one prompt; goal, blocks and findings one level down. Use `WeekStrip` and `ProgressBar`. Mock-up first. |
| `HybridCalendarView`, `RunningCalendarEntryView`, running plan/goal | `Form`; calendar not `MonthCalendar`/`WeekStrip`; orange warnings, red errors. | Medium | Use `MonthCalendar` and `InlineNotice`. |
| `PlanProgressView`, `RunningGoalProgressView` | Charts and bars local; no `SignalTrendChart`/`RangeGauge`. | Medium | Replace with DesignSystem charts. |
| `LiftsToUnblockView` | `Form`, one red error. | Low | X1. |

### Recovery & Progress

| Screen | Gaps | Sev. | Proposed change |
| --- | --- | --- | --- |
| `TrendsView` | Already cards (`SectionRow`) and `Spacing`; large-title rule X11. Closest to Today. | Low | X3 swap local card for `Card`. |
| `TrendChartView` | Own chart; Today's signal tiles use `SignalTrendChart` over the personal band. | Medium | Reuse `SignalTrendChart` with the band; keep detail axis. |
| `RecoveryDetail`, `RecentLoadDetail` | Pushed screens inside `TrendsView.swift`; check against the Why screen (one card per signal). | Medium | Same card per signal as `TodayWhyView`; ACWR as `RangeGauge`. |

### Other

| Screen | Gaps | Sev. | Proposed change |
| --- | --- | --- | --- |
| `SettingsView` | Standard `Form` is appropriate for settings; fix colour use (X6) and add a header row for Garmin state using `StatusBadge`. | Medium | X6, X9. |
| `GarminSetupView` | Own cards (good) but fixed 72 pt glyph, 28 pt target, orange/red notices. | Medium | X1, X8, X10. |
| `TrainingProfileView` | `Form`, no accessibility labels. | Low | X9. |
| `ExercisesView`, `ExerciseSettingsView` | `Form`/`List`; four red errors; orange at line 79. | Low | X1. |
| Onboarding, tour, What's New | Own cards (`TourPageView`, `WhatsNewView`) with fixed 72-84 pt glyphs; no a11y labels in `OnboardingView`; green at line 169. | Medium | X6, X8, X9. |
| `AskAIView` | Five coloured labels; `Form`. | Low | X1. |
| `SessionReportSheet` | See Train finish summary. | Medium | See above. |

## Child issues

Epic: [#247](https://github.com/droidsam1/overreach/issues/247). Order is the order in [Priorities](../priorities.md). Every screen issue is blocked by #296.

1. [#296](https://github.com/droidsam1/overreach/issues/296) DesignSystem foundations (X1, X3, X4, X5, X12). **Blocks the rest.**
2. [#297](https://github.com/droidsam1/overreach/issues/297) Status colours to `InlineNotice` in Train, History and Plan (X1, X6).
3. [#298](https://github.com/droidsam1/overreach/issues/298) Train start screen as hero and routine cards.
4. [#300](https://github.com/droidsam1/overreach/issues/300) History cards and summary-first details.
5. [#299](https://github.com/droidsam1/overreach/issues/299) Live session cards, rest timer, finish summary.
6. [#301](https://github.com/droidsam1/overreach/issues/301) Plan two-level layout.
7. [#302](https://github.com/droidsam1/overreach/issues/302) Status colours in Settings, Garmin, Exercises, Onboarding, Ask AI.
8. [#303](https://github.com/droidsam1/overreach/issues/303) Recovery & Progress charts and cards.
9. [#304](https://github.com/droidsam1/overreach/issues/304) Plan detail screens (after #301).
10. [#305](https://github.com/droidsam1/overreach/issues/305) Dynamic Type and touch targets (X8, X10).
11. [#306](https://github.com/droidsam1/overreach/issues/306) VoiceOver labels (X9).
12. [#307](https://github.com/droidsam1/overreach/issues/307) Haptics (X7).
13. [#308](https://github.com/droidsam1/overreach/issues/308) Titles rule (X11).

## Not covered

- Before screenshots (light/dark) of every screen, using the check in [iPhone UX guide](iphone-ux.md): need a Mac
  with a simulator. Deferred: no simulator is available, and the child issues do not wait for them.
- Contrast of each screen, VoiceOver order and real Dynamic Type results: the findings above come from the code.
- Copy in Spanish and Galician: reviewed, see [Copy review](#copy-review).
- Mock-ups for the bigger changes (Train start, Plan) go on the design canvas before implementation.

## Copy review

All 1,640 es and gl strings of `Localizable.xcstrings` were read against the English source (the app is not a
medical device: no diagnosis wording was found). 61 strings were fixed; the main term decisions:

- es: source = fuente (not origen); reps in reserve = en reserva (not recámara); lift = ejercicio (not
  levantamiento); skip = omitir (not saltar); period = periodo; range = rango (not intervalo); easy run = rodaje suave.
- gl: easy run = rodaxe (as before; owner's choice); skip = omitir; bpm = ppm; dor is feminine; keep "aparte", "app".
- Both: the daily questionnaire is registro diario / rexistro diario, never "check-in" or "benestar" mixed in.

- Both: heart rate is "frecuencia cardíaca" (es) / "frecuencia cardíaca" (gl), never "pulso"; "FC" stays as the short
  label. "Intervals" = Series is confirmed.

Open questions: "Updates" = Actualiza (verb as heading), "Readiness" = Preparación vs semáforo, and es "entreno(s)"
next to "entrenamiento(s)".

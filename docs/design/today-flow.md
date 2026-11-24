# How Today decides

Where the Today recommendation is built, for anyone changing it. The rules are in `docs/evidence.md`; this is the
path from data to the screen.

1. `TodayModel.load` (`Presentation/TodayPresentation/TodayModel.swift`) reads sources once through
   `TrainingServices`, computes readiness, then calls `loadRecentTraining`.
2. `loadRunningPlan` asks `EasyRunAdvisor.advise` (`Analytics`) for a decision about an extra or planned run and wraps
   it in a `RunningOption`. Rules that hold a run back, such as a run already done today or lower-body work
   (`LowerBodyLoad`), live in `advise`, not in the view.
   On a rest day of the projected strength rotation (`RotationProjection.runWindows`), `TodayModel.runOffer` adds one
   secondary line under the hero ("Good day for an easy run"). It needs `RunningOption.offersEasyRun`, so every
   guardrail of `advise` applies, and it never adds a block (ADR-0041). "Not today" hides it for the day, also after a
   relaunch (the day is kept on the device only, not in backups).
3. `trainingAction` turns the scheduled strength, scheduled runs, `RunningOption` and what is already done today
   into `heroTrainingAction`. Training already done today ends the recommendation unless the plan has another dated
   session. On the day of a projected leg-heavy session, a run within the last 48 hours can produce a rotation
   suggestion (ADR-0044). A swap or postponement uses the secondary action under the hero. Acceptance saves the
   change, and Keep plan is remembered on the device for the day. Why shows the inputs and the heuristic, including
   when the plan stands. A capped session carries its effort limit into the workout and is excluded from progression.
4. `nextAction` (`baseAction`) orders the hero by urgency: safety advice, check-in, red light, deload proposal,
   then `heroTrainingAction`. `heroTitle` and `heroReason` are the texts for that action.
5. `FeatureToday` only renders: `TodayView` lays out the blocks and its `primaryAction` switch maps each `NextAction`
   to a button. `TodayHero` draws the card (ring, badge, `heroTitle`, `heroReason`, `signals`) around that button, or
   `TodayDoneSummary` once `doneToday` is set; `TodayHeroPlaceholder` while loading. `TodayWeekCard` draws `yourWeek`,
   `TodayPromptCard` the `pendingPrompt` (the last one, `profileQuestion`, asks the cycle or dog question once when it
would change a recommendation, and "Later" brings it back tomorrow), and the link tiles open `TodayWhyView` (`why`), Other options, Recovery
   and History. `SectionAvailability` (PresentationKit) decides which exist: Recovery needs a reading and History a
   logged session or run; with neither there are no links (ADR-0041, rule 6).

A new hero state is a `NextAction` case, its title in `NextAction.title`, its place in `baseAction` or
`trainingAction`, and one case in the view's switch. Tests in `Tests/TodayPresentationTests` build a `TodayModel` with
`TestStore` and a small `MetricsSource`, as `TrainedTodayTests` does.

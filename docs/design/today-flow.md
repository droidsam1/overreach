# How Today decides

Where the Today recommendation is built, for anyone changing it. The rules are in `docs/evidence.md`; this is the
path from data to the screen.

1. `TodayModel.load` (`Presentation/TodayPresentation/TodayModel.swift`) reads sources once through
   `TrainingServices`, computes readiness, then calls `loadRecentTraining`.
2. `loadRunningPlan` asks `EasyRunAdvisor.advise` (`Analytics`) for a decision about an extra or planned run and wraps
   it in a `RunningOption`. Rules that hold a run back, such as a run already done today or lower-body work
   (`LowerBodyLoad`), live in `advise`, not in the view.
3. `trainingAction` turns the scheduled strength, scheduled runs, `RunningOption` and what is already done today
   into `heroTrainingAction`. Training already done today ends the recommendation unless the plan has another dated
   session.
4. `nextAction` (`baseAction`) orders the hero by urgency: safety advice, check-in, red light, deload proposal,
   then `heroTrainingAction`. `heroTitle` and `heroReason` are the texts for that action.
5. `FeatureToday/TodayView.swift` only renders: its `primaryAction` switch maps each `NextAction` to a button.

A new hero state is a `NextAction` case, its title in `NextAction.title`, its place in `baseAction` or
`trainingAction`, and one case in the view's switch. Tests in `Tests/TodayPresentationTests` build a `TodayModel` with
`TestStore` and a small `MetricsSource`, as `TrainedTodayTests` does.

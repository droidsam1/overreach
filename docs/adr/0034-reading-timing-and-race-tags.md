# 0034 — Order training by the sleep behind a reading and tag races by the athlete's link

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

The readiness explanation listed the workouts recorded on the calendar day before the latest comparable HRV reading.
Calendar days misplace an evening run that ends after midnight, a late bedtime and a trip across time zones. Nothing
marked a race either, so the explanation could not show how a reading compared before and after one. Both sources
already report when a night started and ended: Garmin's sleep record and the merged sleep samples in Apple Health.

## Decision

1. **`DailyMetrics` keeps the night's interval** (`sleepStart`, `sleepEnd`) from the source that supplied
   `sleepSeconds`. A merge never pairs one source's duration with another's interval. Apple Health uses the span of
   asleep samples, not time in bed.
2. **A reading's interval is its night** (`hrvReadingInterval`) only for sleep readings whose source also supplied the
   sleep. Daytime readings and nights without an interval fall back to calendar order.
3. **Workouts before a reading** are those that ended after the previous night's wake-up and before the reading's
   night began. Without the previous night, the window is the 24 hours before that night. Each recorded workout keeps
   its start and end.
4. **A race is a recorded run the athlete linked to a planned race in Plan** (`PlannedRun.purpose == .race` with a
   completion). Names, pace and effort never make a race.
5. **Races get a before-and-after comparison, not a cause.** On a low-HRV day the explanation shows the closest
   comparable reading of the judged series before and after the most recent confirmed race this week. A reading counts
   as before when its night ended before the race started, and after when its night began after the race ended.

## Consequences

- No stored data changes: metrics are read from the sources on each load, and race links already exist in Plan.
- A race only appears once the athlete links the recording, so an unplanned race is not tagged.
- Within-person patterns (repeated comparable bouts, lag, uncertainty) remain future work and need more than one race.

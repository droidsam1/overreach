import Analytics
import Domain
import Foundation

/// What the athlete has already trained today, answered once for every consumer (ADR-0035): Today holds back a second
/// session, the Assistant context states it and Plan does not propose an unplanned run on top of it.
public struct DayTraining: Hashable, Sendable {
    public let hasStrength: Bool
    public let hasRun: Bool
    /// Lower-body strength today, or a heavy lower-body session yesterday.
    public let lowerBody: LowerBodyLoad.Level

    public init(hasStrength: Bool = false, hasRun: Bool = false, lowerBody: LowerBodyLoad.Level = .none) {
        self.hasStrength = hasStrength
        self.hasRun = hasRun
        self.lowerBody = lowerBody
    }

    public var hasTrained: Bool { hasStrength || hasRun }

    /// An unplanned run today would stack on work already done or on tired legs.
    public var holdsBackUnplannedRun: Bool { hasTrained || lowerBody != .none }

    /// - Parameters:
    ///   - sessions: Logged strength sessions, in progress included.
    ///   - recordings: Strength activities recorded by a watch.
    ///   - runs: Runs read from the sources.
    ///   - planned: Runs the plan scheduled today; a completion counts as a run done.
    public static func assess(
        sessions: [StrengthSession], recordings: [RecordedStrengthActivity], runs: [RunActivity],
        planned: [PlannedRun] = [], exercises: [Exercise], now: Date, calendar: Calendar = .current,
        lowerBodySettings: LowerBodyLoad.Settings = .init()
    ) -> DayTraining {
        let start = calendar.startOfDay(for: now)
        let finishedToday: (Date, Double) -> Bool = { began, seconds in
            seconds.isFinite && (start...now).contains(began.addingTimeInterval(seconds))
        }
        let strength = sessions.contains { $0.startedAt <= now && ($0.endedAt ?? $0.startedAt) >= start }
            || recordings.contains { $0.durationSeconds.isFinite && (start...now).contains($0.endedAt) }
        let run = runs.contains { finishedToday($0.startedAt, $0.durationSeconds) }
            || planned.contains { $0.completion.map { finishedToday($0.startedAt, $0.durationSeconds) } ?? false }
        return DayTraining(
            hasStrength: strength, hasRun: run,
            lowerBody: LowerBodyLoad.assess(
                sessions: sessions, exercises: exercises, now: now, calendar: calendar, settings: lowerBodySettings
            )
        )
    }
}

extension TrainingRecordLoader.Snapshot {
    /// The day's training from everything this snapshot read. A failed session read counts as no lower-body load.
    public func dayTraining(profile: AthleteProfile?, now: Date, calendar: Calendar = .current) -> DayTraining {
        let today = CalendarDay(now, calendar: calendar)
        let planned = profile?.goal?.scheduledRuns.filter { $0.day == today && !$0.isPostponed } ?? []
        let training = DayTraining.assess(
            sessions: allSessions, recordings: record.recordings, runs: record.runs, planned: planned,
            exercises: record.exercises, now: now, calendar: calendar
        )
        return sessionsFailed ? DayTraining(hasStrength: training.hasStrength, hasRun: training.hasRun) : training
    }
}

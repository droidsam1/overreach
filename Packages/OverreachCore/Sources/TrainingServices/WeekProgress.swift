import Domain
import Foundation

/// This week's training, Monday to Sunday, as one shared answer for Today and Plan (ADR-0035, ADR-0042): per day what
/// was done and what is planned, sessions done against planned, and the week of the current block.
///
/// Counting rules (the ones Plan already used):
/// - A dated run is done only when a recording is linked to it (ADR-0040); a dated strength entry when a completed
///   session of its routine was logged that day.
/// - Rest entries and postponed runs are not planned sessions, so a missed day never shows as a failure.
/// - Without dated entries the current block's weekly target counts.
/// - A past day with neither strength nor a run counts as rest, as does one with rest logged: a completed day,
///   never a missed one. There is no streak.
public struct WeekProgress: Hashable, Sendable {
    /// What a day got done.
    public enum Done: Hashable, Sendable {
        case strength, run, both, restLogged, nothing
    }

    public struct Day: Identifiable, Hashable, Sendable {
        public var id: CalendarDay { day }
        public let day: CalendarDay
        public let isToday: Bool
        public let done: Done
        public let plannedStrength: Bool
        public let plannedRun: Bool
        /// The day falls inside a deload: fewer sessions are intended, not missed.
        public let isDeload: Bool

        public var isPlanned: Bool { plannedStrength || plannedRun }
    }

    /// The week of the declared block that contains today.
    public struct BlockWeek: Hashable, Sendable {
        public let focus: TrainingFocus
        public let name: String?
        /// 1-based.
        public let week: Int
        public let weeks: Int
    }

    public struct Inputs: Sendable {
        public var strength: [PlannedStrength]
        public var runs: [PlannedRun]
        public var sessions: [StrengthSession]
        /// Recorded runs, planned or not.
        public var recordedRuns: [RunActivity]
        public var restDays: [CalendarDay]
        public var deloadDays: Set<CalendarDay>
        /// The block's weekly target and sessions done, used when no entry is dated this week.
        public var blockWeek: (planned: Int, done: Int)?
        public var currentBlock: TrainingBlock?

        public init(
            strength: [PlannedStrength] = [], runs: [PlannedRun] = [], sessions: [StrengthSession] = [],
            recordedRuns: [RunActivity] = [], restDays: [CalendarDay] = [], deloadDays: Set<CalendarDay> = [],
            blockWeek: (planned: Int, done: Int)? = nil, currentBlock: TrainingBlock? = nil
        ) {
            self.strength = strength
            self.runs = runs
            self.sessions = sessions
            self.recordedRuns = recordedRuns
            self.restDays = restDays
            self.deloadDays = deloadDays
            self.blockWeek = blockWeek
            self.currentBlock = currentBlock
        }
    }

    /// Seven days, Monday to Sunday (the calendar's week).
    public let days: [Day]
    public let sessionsPlanned: Int
    public let sessionsDone: Int
    public let strengthPlanned: Int
    public let strengthDone: Int
    public let runsPlanned: Int
    public let runsDone: Int
    public let block: BlockWeek?

    /// Whether anything was planned or done this week, logged rest included. Days that are rest only because
    /// nothing happened do not count.
    public var hasActivity: Bool { hasEntries }
    private let hasEntries: Bool

    public static func make(_ inputs: Inputs, now: Date, calendar: Calendar = .current) -> WeekProgress? {
        let today = CalendarDay(now, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today.startDate(in: calendar)) else {
            return nil
        }
        let start = CalendarDay(interval.start, calendar: calendar)
        let weekDays = (0..<7).map { start.adding(days: $0, calendar: calendar) }
        let inWeek = Set(weekDays)
        let completed = inputs.sessions.filter { $0.isCompleted(through: now) }
        let sessionDays = Set(completed.map { CalendarDay($0.startedAt, calendar: calendar) })
        let plannedStrength = inputs.strength.filter { inWeek.contains($0.day) && $0.routineID != nil }
        let plannedRuns = inputs.runs.filter { inWeek.contains($0.day) && $0.purpose != .rest && !$0.isPostponed }

        let strengthDone = plannedStrength.filter { entry in
            completed.contains { session in
                session.routineID == entry.routineID && CalendarDay(session.startedAt, calendar: calendar) == entry.day
            }
        }.count
        let runsDone = plannedRuns.filter { $0.completion != nil }.count
        var planned = plannedStrength.count + plannedRuns.count
        var done = strengthDone + runsDone
        if planned == 0, let target = blockTarget(inputs, completed: completed, inWeek: inWeek, calendar: calendar) {
            planned = target.planned
            done = target.done
        }

        let recorded = inputs.recordedRuns.filter { $0.startedAt <= now }
        let runDays = Set(recorded.map { CalendarDay($0.startedAt, calendar: calendar) })
            .union(plannedRuns.filter { $0.completion != nil }.map(\.day))
        let rests = Set(inputs.restDays)
        let days = weekDays.map { day -> Day in
            let strength = sessionDays.contains(day)
            let run = runDays.contains(day)
            let outcome: Done = switch (strength, run) {
            case (true, true): .both
            case (true, false): .strength
            case (false, true): .run
            // A past day with no training is a rest day, logged or not.
            case (false, false): rests.contains(day) || day < today ? .restLogged : .nothing
            }
            return Day(
                day: day, isToday: day == today, done: outcome,
                plannedStrength: plannedStrength.contains { $0.day == day },
                plannedRun: plannedRuns.contains { $0.day == day },
                isDeload: inputs.deloadDays.contains(day)
            )
        }
        let blockWeek = inputs.currentBlock.flatMap { Self.blockWeek($0, today: today, calendar: calendar) }
        let progress = WeekProgress(
            days: days, sessionsPlanned: planned, sessionsDone: done,
            strengthPlanned: plannedStrength.count, strengthDone: strengthDone,
            runsPlanned: plannedRuns.count, runsDone: runsDone,
            block: blockWeek,
            hasEntries: planned > 0 || blockWeek != nil
                || weekDays.contains { sessionDays.contains($0) || runDays.contains($0) || rests.contains($0) }
                || days.contains(where: \.isPlanned)
        )
        return progress.hasActivity ? progress : nil
    }

    /// The weekly target of the running block and the sessions of its routines done this week (any strength
    /// session when the block names no routines).
    private static func blockTarget(
        _ inputs: Inputs, completed: [StrengthSession], inWeek: Set<CalendarDay>, calendar: Calendar
    ) -> (planned: Int, done: Int)? {
        if let blockWeek = inputs.blockWeek { return blockWeek }
        guard let block = inputs.currentBlock, block.isDeclared, !block.routineIDs.isEmpty else { return nil }
        let rotation = Set(block.routineIDs)
        let done = completed.filter { session in
            inWeek.contains(CalendarDay(session.startedAt, calendar: calendar))
                && (session.routineID.map(rotation.contains) ?? false)
        }.count
        return (block.plannedSessionsPerWeek, done)
    }

    private static func blockWeek(_ block: TrainingBlock, today: CalendarDay, calendar: Calendar) -> BlockWeek? {
        guard block.isDeclared, let weeks = block.plannedWeeks, weeks > 0, block.start <= today else { return nil }
        let elapsed = calendar.dateComponents(
            [.day], from: block.start.startDate(in: calendar), to: today.startDate(in: calendar)
        ).day ?? 0
        let week = elapsed / 7 + 1
        guard week <= weeks else { return nil }
        return BlockWeek(focus: block.focus, name: block.name, week: week, weeks: weeks)
    }
}

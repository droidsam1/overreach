import Domain
import Foundation
import PresentationKit
import TrainingServices

/// Real progress through the athlete's own plan (ADR-0041 rule 7): sessions done this week and the week of the block.
/// Nothing is invented: without a plan there is no progress to show.
public struct PlanProgress: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        /// "This week: 3 of 4 sessions" or "Block: week 2 of 5".
        public let title: String
        /// What VoiceOver reads: "3 of 4 sessions done this week".
        public let accessibilityLabel: String
        /// Bar value from 0 to 1. Always shown with `title`, never alone.
        public let fraction: Double
    }

    public let week: Line?
    public let block: Line?
    /// The lines to show, week first.
    public var lines: [Line] { [week, block].compactMap { $0 } }

    /// What the week's count reads: the dated entries, the sessions logged and the current block's weekly target.
    struct Schedule {
        var strength: [PlannedStrength] = []
        var runs: [PlannedRun] = []
        var sessions: [StrengthSession] = []
        var blockWeek: (planned: Int, done: Int)?
    }

    /// The count and the block week come from `WeekProgress`, the answer Today shares (ADR-0042).
    static func make(_ schedule: Schedule, currentBlock: TrainingBlock?, now: Date, calendar: Calendar) -> Self? {
        let progress = WeekProgress.make(
            .init(
                strength: schedule.strength, runs: schedule.runs, sessions: schedule.sessions,
                blockWeek: schedule.blockWeek, currentBlock: currentBlock
            ),
            now: now, calendar: calendar
        )
        return make(progress)
    }

    static func make(_ progress: WeekProgress?) -> Self? {
        let week = progress.flatMap(weekLine)
        let block = progress?.block.map(blockLine)
        guard week != nil || block != nil else { return nil }
        return Self(week: week, block: block)
    }

    private static func weekLine(_ progress: WeekProgress) -> Line? {
        let (planned, done) = (progress.sessionsPlanned, progress.sessionsDone)
        guard planned > 0 else { return nil }
        return Line(
            title: L10n.format("This week: {1} of {2} sessions", done, planned),
            accessibilityLabel: L10n.format("{1} of {2} sessions done this week", done, planned),
            fraction: min(1, Double(done) / Double(planned))
        )
    }

    private static func blockLine(_ block: WeekProgress.BlockWeek) -> Line {
        Line(
            title: L10n.format("Block: week {1} of {2}", block.week, block.weeks),
            accessibilityLabel: L10n.format("Week {1} of {2} of the block", block.week, block.weeks),
            fraction: Double(block.week) / Double(block.weeks)
        )
    }
}

public struct PlanWeekDay: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case strengthDone, runDone, restLogged, plannedStrength, plannedRun, today, empty
    }

    public let id: CalendarDay
    public let initial: String
    public let kind: Kind
    public let accessibilityLabel: String

    init(_ day: WeekProgress.Day, calendar: Calendar) {
        id = day.day
        let date = day.day.startDate(in: calendar)
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        initial = date.formatted(style.weekday(.narrow))
        let weekday = date.formatted(style.weekday(.wide))
        let state: String
        switch day.done {
        case .strength: (kind, state) = (.strengthDone, L10n.text("Strength done"))
        case .run: (kind, state) = (.runDone, L10n.text("Run done"))
        case .both: (kind, state) = (.strengthDone, L10n.text("Strength and run done"))
        case .restLogged: (kind, state) = (.restLogged, L10n.text("Rest logged"))
        case .nothing where day.plannedStrength: (kind, state) = (.plannedStrength, L10n.text("Planned"))
        case .nothing where day.plannedRun: (kind, state) = (.plannedRun, L10n.text("Planned"))
        case .nothing: (kind, state) = (day.isToday ? .today : .empty, L10n.text("Nothing planned"))
        }
        accessibilityLabel = day.isToday
            ? L10n.format("{1}, today: {2}", weekday, state)
            : L10n.format("{1}: {2}", weekday, state)
    }
}

extension PlanModel {
    public var weekDays: [PlanWeekDay] {
        weekProgress?.days.map { PlanWeekDay($0, calendar: calendar) } ?? []
    }

    /// This week's sessions and the block's week, for the top of Plan. `nil` without a plan.
    public var progress: PlanProgress? { PlanProgress.make(weekProgress) }

    public var completedTrainingCalendarRows: [CompletedTrainingCalendarRow] {
        let now = now
        let runs = completedCalendarRuns(through: now)
        let days = Set(weekProgress(through: now, runs: runs)?.days.map(\.day) ?? [])
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()

        let strength = weekSessions.filter { $0.isCompleted(through: now) }.map { session in
            (session.startedAt, CompletedTrainingCalendarRow(
                id: "strength:\(session.id)", title: session.name,
                date: session.startedAt.formatted(style), isRun: false
            ))
        }
        let running = runs.map { run in
            (run.startedAt, CompletedTrainingCalendarRow(
                id: "run:\(run.source.rawValue):\(run.id)", title: run.name ?? L10n.text("Run"),
                date: run.startedAt.formatted(style), isRun: true
            ))
        }
        return (strength + running)
            .filter { days.contains(CalendarDay($0.0, calendar: calendar)) }
            .sorted { $0.0 > $1.0 }
            .map { $0.1 }
    }

    private func completedCalendarRuns(through now: Date) -> [RunActivity] {
        let linked = profile.goal?.scheduledRuns.filter { $0.purpose != .rest && !$0.isPostponed }
            .compactMap(\.completion) ?? []
        let missing = linked.filter { completion in !recentRuns.contains(where: { completion.matches($0) }) }
        let snapshots = missing.map { completion in
            RunActivity(
                id: completion.activityID, source: completion.source, startedAt: completion.startedAt,
                durationSeconds: completion.durationSeconds, distanceMeters: completion.distanceMeters ?? 0
            )
        }
        return (recentRuns + snapshots).filter { run in
            run.durationSeconds.isFinite && run.durationSeconds >= 0
                && run.startedAt.addingTimeInterval(run.durationSeconds) <= now
        }
    }

    private var weekProgress: WeekProgress? {
        let now = now
        return weekProgress(through: now, runs: completedCalendarRuns(through: now))
    }

    private func weekProgress(through now: Date, runs: [RunActivity]) -> WeekProgress? {
        let goal = profile.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        return WeekProgress.make(
            .init(strength: goal?.scheduledStrength ?? [], runs: goal?.scheduledRuns ?? [],
                  sessions: weekSessions, recordedRuns: runs, restDays: profile.restDays,
                  currentBlock: currentBlock),
            now: now, calendar: calendar
        )
    }
}

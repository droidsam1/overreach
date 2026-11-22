import Analytics
import Domain
import Foundation
import PresentationKit

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

    /// Counts this calendar week's dated entries. Without any, it uses the current block's weekly target.
    ///
    /// - A run is done only when a recording is linked to it (ADR-0040); a strength entry when a completed session of
    ///   its routine was logged that day.
    /// - Rest days and postponed runs count as handled: they are not planned sessions, so a missed day never shows
    ///   as a failure.
    static func make(_ schedule: Schedule, currentBlock: TrainingBlock?, now: Date, calendar: Calendar) -> Self? {
        let today = CalendarDay(now, calendar: calendar)
        let week = weekLine(schedule, today: today, now: now, calendar: calendar)
        let block = currentBlock.flatMap { blockLine($0, today: today, calendar: calendar) }
        guard week != nil || block != nil else { return nil }
        return Self(week: week, block: block)
    }

    private static func weekLine(_ schedule: Schedule, today: CalendarDay, now: Date, calendar: Calendar) -> Line? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today.startDate(in: calendar)) else {
            return nil
        }
        let start = CalendarDay(interval.start, calendar: calendar)
        let end = CalendarDay(interval.end, calendar: calendar)
        let inWeek = { (day: CalendarDay) in day >= start && day < end }
        let completed = schedule.sessions.filter { $0.isCompleted(through: now) }

        let plannedStrength = schedule.strength.filter { inWeek($0.day) && $0.routineID != nil }
        let plannedRuns = schedule.runs.filter { inWeek($0.day) && $0.purpose != .rest && !$0.isPostponed }
        var planned = plannedStrength.count + plannedRuns.count
        var done = plannedRuns.filter { $0.completion != nil }.count + plannedStrength.filter { entry in
            completed.contains { session in
                session.routineID == entry.routineID && CalendarDay(session.startedAt, calendar: calendar) == entry.day
            }
        }.count
        if planned == 0, let blockWeek = schedule.blockWeek {
            planned = blockWeek.planned
            done = blockWeek.done
        }
        guard planned > 0 else { return nil }
        return Line(
            title: L10n.format("This week: {1} of {2} sessions", done, planned),
            accessibilityLabel: L10n.format("{1} of {2} sessions done this week", done, planned),
            fraction: min(1, Double(done) / Double(planned))
        )
    }

    private static func blockLine(_ block: TrainingBlock, today: CalendarDay, calendar: Calendar) -> Line? {
        guard block.isDeclared, let weeks = block.plannedWeeks, weeks > 0, block.start <= today else { return nil }
        let elapsed = calendar.dateComponents(
            [.day], from: block.start.startDate(in: calendar), to: today.startDate(in: calendar)
        ).day ?? 0
        let week = elapsed / 7 + 1
        guard week <= weeks else { return nil }
        return Line(
            title: L10n.format("Block: week {1} of {2}", week, weeks),
            accessibilityLabel: L10n.format("Week {1} of {2} of the block", week, weeks),
            fraction: Double(week) / Double(weeks)
        )
    }
}

extension PlanModel {
    /// This week's sessions and the block's week, for the top of Plan. `nil` without a plan.
    public var progress: PlanProgress? {
        let goal = profile.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        let schedule = PlanProgress.Schedule(
            strength: goal?.scheduledStrength ?? [], runs: goal?.scheduledRuns ?? [], sessions: weekSessions,
            blockWeek: currentPlanWeek.map { ($0.planned, $0.done) }
        )
        return PlanProgress.make(schedule, currentBlock: currentBlock, now: now, calendar: calendar)
    }
}

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

extension PlanModel {
    /// This week's sessions and the block's week, for the top of Plan. `nil` without a plan.
    public var progress: PlanProgress? {
        let goal = profile.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        let schedule = PlanProgress.Schedule(
            strength: goal?.scheduledStrength ?? [], runs: goal?.scheduledRuns ?? [], sessions: weekSessions
        )
        return PlanProgress.make(schedule, currentBlock: currentBlock, now: now, calendar: calendar)
    }
}

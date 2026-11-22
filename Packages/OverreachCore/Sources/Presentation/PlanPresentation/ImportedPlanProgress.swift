import Analytics
import Domain
import Foundation
import PresentationKit

/// Session counts in Recovery & Progress, grouped by the plan's block and week.
public struct ImportedPlanProgressRow: Identifiable, Hashable, Sendable {
    public struct Week: Identifiable, Hashable, Sendable {
        public let id: Int
        public let title: String
        public let summary: String
    }

    public let id: CalendarDay
    public let title: String
    public let summary: String
    public let weeks: [Week]

    init(block: TrainingBlock, weeks: [PlanWeek], calendar: Calendar) {
        id = block.start
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        let date = block.start.startDate(in: calendar).formatted(style)
        title = "\(block.name ?? block.focus.displayName) \u{00B7} \(date)"
        summary = Self.sessionCount(
            done: weeks.reduce(0) { $0 + $1.done },
            planned: weeks.reduce(0) { $0 + $1.planned }
        )
        self.weeks = weeks.reversed().map { week in
            Week(
                id: week.week,
                title: week.isCurrent ? L10n.text("This week") : L10n.format("Week {1}", week.week),
                summary: Self.sessionCount(done: week.done, planned: week.planned)
            )
        }
    }

    private static func sessionCount(done: Int, planned: Int) -> String {
        L10n.format("{1} completed / {2} planned", done, planned)
    }
}

import Domain
import Foundation
import PresentationKit

public struct ScheduledTrainingRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let status: String?

    static func strength(
        _ assignment: PlannedStrength, routine: Routine?, sessions: [StrengthSession], now: Date, calendar: Calendar
    ) -> Self {
        guard let routineID = assignment.routineID else {
            return Self(id: assignment.id, title: assignment.displayName(routineName: nil), status: nil)
        }
        let completed = sessions.first { session in
            session.routineID == routineID && CalendarDay(session.startedAt, calendar: calendar) == assignment.day
                && RecentTraining.isCompleted(session, through: now)
        }
        let name = routine?.name ?? completed?.name
        return Self(
            id: assignment.id,
            title: assignment.displayName(routineName: name),
            status: completed == nil ? nil : L10n.text("Completed")
        )
    }

    static func run(_ entry: PlannedRun, format: Format) -> Self {
        Self(
            id: entry.id,
            title: entry.calendarTitle(format: format),
            status: entry.completion == nil ? nil : L10n.text("Completed")
        )
    }
}

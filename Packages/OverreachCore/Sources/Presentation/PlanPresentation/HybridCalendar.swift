import Domain
import Foundation

public struct StrengthCalendarDraft: Identifiable, Sendable {
    public let id: UUID
    public let isNew: Bool
    public var date: Date
    public var routineID: UUID?

    init(entry: PlannedStrength?, today: Date, calendar: Calendar) {
        id = entry?.id ?? UUID()
        isNew = entry == nil
        date = entry?.day.startDate(in: calendar) ?? today
        routineID = entry?.routineID
    }
}

public struct StrengthCalendarRow: Identifiable, Sendable {
    public let entry: PlannedStrength
    public let date: String
    public let title: String
    public var id: UUID { entry.id }
}

public struct RecordedRunCalendarRow: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let date: String
    public let status: String
}

public enum HybridCalendarRow: Identifiable, Sendable {
    case run(RunningCalendarRow)
    case strength(StrengthCalendarRow)

    public enum ID: Hashable, Sendable {
        case run(UUID)
        case strength(UUID)
    }

    public var id: ID {
        switch self {
        case let .run(row): .run(row.id)
        case let .strength(row): .strength(row.id)
        }
    }

    var day: CalendarDay {
        switch self {
        case let .run(row): row.entry.day
        case let .strength(row): row.entry.day
        }
    }
}

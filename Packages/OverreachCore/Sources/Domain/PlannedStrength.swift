import Foundation

/// An athlete's dated strength assignment. A missing routine represents an explicit strength rest day.
public struct PlannedStrength: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let day: CalendarDay
    public let routineID: UUID?

    public init(id: UUID = UUID(), day: CalendarDay, routineID: UUID? = nil) {
        self.id = id
        self.day = day
        self.routineID = routineID
    }
}

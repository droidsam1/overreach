import Domain
import Foundation
import PresentationKit

public struct RunningCalendarDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let isNew: Bool
    public var date: Date
    public var purpose: PlannedRun.Purpose
    public var minutes: Int
    public var distanceKm: Double
    public var completion: PlannedRunCompletion?

    init(entry: PlannedRun?, today: Date, calendar: Calendar) {
        id = entry?.id ?? UUID()
        isNew = entry == nil
        date = entry?.day.startDate(in: calendar) ?? today
        purpose = entry?.purpose ?? .easy
        minutes = entry?.durationMinutes ?? 0
        distanceKm = Double(entry?.distanceMeters ?? 0) / 1_000
        completion = entry?.completion
    }

    public var showsWorkoutDetails: Bool { purpose != .rest }
    public var showsCompletion: Bool { purpose != .rest || completion != nil }
    public var canSave: Bool {
        purpose == .rest ? completion == nil : (0...1_440).contains(minutes) && (0...1_000).contains(distanceKm)
    }

    func entry(calendar: Calendar) -> PlannedRun {
        let distance = showsWorkoutDetails ? Int((distanceKm * 1_000).rounded()) : 0
        return PlannedRun(id: id, day: CalendarDay(date, calendar: calendar), purpose: purpose,
                          durationMinutes: minutes > 0 ? minutes : nil, distanceMeters: distance > 0 ? distance : nil,
                          completion: completion)
    }
}

public struct RunningCalendarRow: Identifiable, Hashable, Sendable {
    public let entry: PlannedRun
    public let date: String
    public let title: String
    public let status: String?
    public var id: UUID { entry.id }
}

public struct RunningCompletionChoice: Identifiable, Hashable, Sendable {
    public let completion: PlannedRunCompletion
    public let title: String
    public var id: PlannedRunCompletion { completion }
}

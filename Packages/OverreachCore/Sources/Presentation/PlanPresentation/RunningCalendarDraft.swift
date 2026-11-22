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
    public var repetitions: Int
    public var recoverySeconds: Int
    public var intensityBasis: PlannedRun.IntensityBasis?
    public var intensityTarget: Int
    public var racePriority: PlannedRun.RacePriority?
    public var postponed: Bool
    public var completion: PlannedRunCompletion?
    var moveOriginal: PlannedRun?
    private let previousDay: CalendarDay?
    private let originalDay: CalendarDay?

    init(entry: PlannedRun?, today: Date, calendar: Calendar) {
        id = entry?.id ?? UUID()
        isNew = entry == nil
        date = entry?.day.startDate(in: calendar) ?? today
        purpose = entry?.purpose ?? .easy
        minutes = entry?.durationMinutes ?? 0
        distanceKm = Double(entry?.distanceMeters ?? 0) / 1_000
        repetitions = entry?.prescription?.repetitions ?? 0
        recoverySeconds = entry?.prescription?.recoverySeconds ?? 0
        intensityBasis = entry?.prescription?.intensityBasis
        intensityTarget = entry?.prescription?.intensityTarget ?? 0
        racePriority = entry?.racePriority
        postponed = entry?.isPostponed ?? false
        completion = entry?.completion
        previousDay = entry?.day
        originalDay = entry?.originalDay
    }

    public var isSuggestedRunMove: Bool { moveOriginal != nil }
    public var showsWorkoutDetails: Bool { purpose != .rest }
    public var showsRacePriority: Bool { purpose == .race }
    public var showsPostpone: Bool { showsWorkoutDetails && completion == nil }
    public var showsCompletion: Bool { (showsWorkoutDetails && !postponed) || completion != nil }
    public var intensityTargetLabel: String? {
        switch intensityBasis {
        case .pace: L10n.text("Target seconds per km")
        case .heartRateZone: L10n.text("Target heart rate zone")
        case .perceivedEffort: L10n.text("Target effort (1–10)")
        case nil: nil
        }
    }
    public var canSave: Bool {
        if purpose == .rest { return completion == nil }
        return !(postponed && completion != nil) && (0...1_440).contains(minutes) && (0...1_000).contains(distanceKm)
            && (0...999).contains(repetitions) && (repetitions == 0 || (0...86_400).contains(recoverySeconds))
            && validIntensityTarget
    }

    private var validIntensityTarget: Bool {
        switch intensityBasis {
        case .pace: (1...86_400).contains(intensityTarget)
        case .heartRateZone, .perceivedEffort: (1...10).contains(intensityTarget)
        case nil: true
        }
    }

    private var prescription: PlannedRun.Prescription? {
        guard showsWorkoutDetails, repetitions > 0 || intensityBasis != nil else { return nil }
        return .init(repetitions: repetitions > 0 ? repetitions : nil,
                     recoverySeconds: recoverySeconds > 0 ? recoverySeconds : nil,
                     intensityBasis: intensityBasis, intensityTarget: intensityTarget)
    }

    func entry(calendar: Calendar) -> PlannedRun {
        let day = CalendarDay(date, calendar: calendar)
        if let original = moveOriginal {
            return PlannedRun(id: original.id, day: day, purpose: original.purpose,
                              durationMinutes: original.durationMinutes, distanceMeters: original.distanceMeters,
                              prescription: original.prescription, racePriority: original.racePriority,
                              originalDay: original.originalDay ?? original.day)
        }
        let distance = showsWorkoutDetails ? Int((distanceKm * 1_000).rounded()) : 0
        let firstDay = originalDay ?? (previousDay == day ? nil : previousDay)
        return PlannedRun(id: id, day: day, purpose: purpose,
                          durationMinutes: minutes > 0 ? minutes : nil, distanceMeters: distance > 0 ? distance : nil,
                          completion: completion, prescription: prescription, racePriority: racePriority,
                          originalDay: firstDay, postponed: postponed)
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

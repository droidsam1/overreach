public enum DeloadReason: String, Codable, Hashable, Sendable {
    case noTraining, easyRuns, reducedStrength
}

public enum TrainingDiscipline: String, Codable, Hashable, Sendable {
    case strength, running
}

/// The athlete's answer for an inferred recovery period. Dates are inclusive.
public struct DeloadDecision: Hashable, Codable, Sendable {
    public let start: CalendarDay
    public let end: CalendarDay
    public let reason: DeloadReason
    public let accepted: Bool
    /// Older answers apply to both disciplines.
    public let discipline: TrainingDiscipline?

    public init(
        start: CalendarDay, end: CalendarDay, reason: DeloadReason, accepted: Bool,
        discipline: TrainingDiscipline? = nil
    ) {
        self.start = start
        self.end = end
        self.reason = reason
        self.accepted = accepted
        self.discipline = discipline
    }
}

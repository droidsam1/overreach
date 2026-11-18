import Foundation

/// A session template: a name, an optional focus and an ordered list of exercises. It stores no weights or reps:
/// the progression engine prefills them from history when a session starts.
public struct Routine: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// Focus declared for sessions started from this routine. `nil` = automatic (per exercise).
    public var focus: TrainingFocus?
    /// Exercises in training order, each at most once.
    public private(set) var exerciseIDs: [UUID]

    public init(id: UUID = UUID(), name: String, focus: TrainingFocus? = nil, exerciseIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.focus = focus
        self.exerciseIDs = Self.withoutRepeats(exerciseIDs)
    }

    /// A routine with the name, focus and exercise order of a past session.
    public init(from session: StrengthSession) {
        self.init(name: session.name, focus: session.focus, exerciseIDs: session.entries.map(\.exerciseID))
    }

    public mutating func setExercises(_ ids: [UUID]) {
        exerciseIDs = Self.withoutRepeats(ids)
    }

    private static func withoutRepeats(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

import Foundation

/// How one exercise is trained in one routine, overriding its own progression settings there. It lets a block's
/// routine prescribe e.g. 5 × 3 for a lift that is 3 × 10 elsewhere. Still no loads: the engine sets them.
public struct RoutinePrescription: Hashable, Codable, Sendable {
    public var exerciseID: UUID
    public var scheme: ProgressionScheme
    public var restSeconds: Int?

    public init(exerciseID: UUID, scheme: ProgressionScheme, restSeconds: Int? = nil) {
        self.exerciseID = exerciseID
        self.scheme = scheme
        self.restSeconds = restSeconds
    }
}

/// A session template: a name, an optional focus and an ordered list of exercises. It stores no weights or reps:
/// the progression engine prefills them from history when a session starts.
public struct Routine: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// Focus declared for sessions started from this routine. `nil` = automatic (per exercise).
    public var focus: TrainingFocus?
    /// Exercises in training order, each at most once.
    public private(set) var exerciseIDs: [UUID]
    /// Sets and reps that apply only in this routine, at most one per exercise of the routine.
    public private(set) var prescriptions: [RoutinePrescription]

    public init(
        id: UUID = UUID(), name: String, focus: TrainingFocus? = nil, exerciseIDs: [UUID] = [],
        prescriptions: [RoutinePrescription] = []
    ) {
        self.id = id
        self.name = name
        self.focus = focus
        self.exerciseIDs = Self.withoutRepeats(exerciseIDs)
        self.prescriptions = []
        setPrescriptions(prescriptions)
    }

    /// The scheme this routine prescribes for an exercise, if any.
    public func prescription(for exerciseID: UUID) -> ProgressionScheme? {
        prescriptionDetails(for: exerciseID)?.scheme
    }

    public func prescriptionDetails(for exerciseID: UUID) -> RoutinePrescription? {
        prescriptions.first { $0.exerciseID == exerciseID }
    }

    /// Keeps one prescription per exercise (the last wins), only for exercises of the routine.
    public mutating func setPrescriptions(_ list: [RoutinePrescription]) {
        let byExercise = Dictionary(list.map { ($0.exerciseID, $0) }, uniquingKeysWith: { _, last in last })
        prescriptions = exerciseIDs.compactMap { byExercise[$0] }
    }

    /// A routine with the name, focus and exercise order of a past session.
    public init(from session: StrengthSession) {
        self.init(name: session.name, focus: session.focus, exerciseIDs: session.entries.map(\.exerciseID))
    }

    /// Sets the exercises; prescriptions of removed exercises are dropped.
    public mutating func setExercises(_ ids: [UUID]) {
        exerciseIDs = Self.withoutRepeats(ids)
        setPrescriptions(prescriptions)
    }

    private static func withoutRepeats(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

extension Routine {
    private enum CodingKeys: String, CodingKey {
        case id, name, focus, exerciseIDs, prescriptions
    }

    /// Tolerant decoding (ADR-0018): routines saved before prescriptions existed have none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            focus: try container.decodeIfPresent(TrainingFocus.self, forKey: .focus),
            exerciseIDs: try container.decode([UUID].self, forKey: .exerciseIDs),
            prescriptions: try container.decodeIfPresent([RoutinePrescription].self, forKey: .prescriptions) ?? []
        )
    }
}

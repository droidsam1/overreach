import Foundation

public enum SetKind: String, Codable, Sendable, CaseIterable {
    case warmup, working, dropSet, failure
}

/// One set of an exercise. Every value is optional: a set can be weight × reps, time, or distance.
public struct WorkoutSet: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: SetKind
    public var weightKg: Double?
    public var reps: Int?
    /// Rate of perceived exertion, 1–10.
    public var rpe: Double?
    public var durationSeconds: Double?
    public var distanceMeters: Double?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: SetKind = .working,
        weightKg: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        durationSeconds: Double? = nil,
        distanceMeters: Double? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.completedAt = completedAt
    }

    /// Whether the set counts towards training volume (everything except warm-ups).
    public var isWorking: Bool { kind != .warmup }
}

/// The sets performed for one exercise within a session.
public struct ExerciseEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var exerciseID: UUID
    public var sets: [WorkoutSet]
    public var notes: String?

    public init(id: UUID = UUID(), exerciseID: UUID, sets: [WorkoutSet] = [], notes: String? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.notes = notes
    }
}

/// A gym session.
public struct StrengthSession: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var startedAt: Date
    public var endedAt: Date?
    public var entries: [ExerciseEntry]
    /// Whole-session RPE (1–10), used for session load (sRPE × minutes).
    public var sessionRPE: Double?
    public var notes: String?
    public var source: DataSourceKind
    /// Declared focus of the session. `nil` = inherit from the block, or infer from the sets.
    public var focus: TrainingFocus?

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        entries: [ExerciseEntry] = [],
        sessionRPE: Double? = nil,
        notes: String? = nil,
        source: DataSourceKind = .app,
        focus: TrainingFocus? = nil
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.entries = entries
        self.sessionRPE = sessionRPE
        self.notes = notes
        self.source = source
        self.focus = focus
    }

    public var durationSeconds: Double? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

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
    /// `false` for an exercise left unfinished (e.g. the session ended early): its sets still count as work done,
    /// but the progression engine ignores them for targets and stalls.
    public var countsForProgression: Bool

    public init(
        id: UUID = UUID(), exerciseID: UUID, sets: [WorkoutSet] = [], notes: String? = nil,
        countsForProgression: Bool = true
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.notes = notes
        self.countsForProgression = countsForProgression
    }
}

extension ExerciseEntry {
    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, sets, notes, countsForProgression
    }

    /// Tolerant decoding: entries stored before `countsForProgression` existed count.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            sets: try container.decode([WorkoutSet].self, forKey: .sets),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            countsForProgression: try container.decodeIfPresent(Bool.self, forKey: .countsForProgression) ?? true
        )
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
    /// The routine it was started from, if any; it tells which planned session comes next.
    public var routineID: UUID?
    /// Recorded when the logger applied the post-run effort cap.
    public var rotationCap: RotationAdjustment.Outcome?

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        entries: [ExerciseEntry] = [],
        sessionRPE: Double? = nil,
        notes: String? = nil,
        source: DataSourceKind = .app,
        focus: TrainingFocus? = nil,
        routineID: UUID? = nil,
        rotationCap: RotationAdjustment.Outcome? = nil
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
        self.routineID = routineID
        self.rotationCap = rotationCap
    }

    public var durationSeconds: Double? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    /// Logged in this app with a real duration. Imported history stays out of the health app (ADR-0016).
    public var belongsInHealth: Bool {
        source == .app && (durationSeconds ?? 0) > 0
    }
}

extension StrengthSession {
    public func isCompleted(through now: Date) -> Bool {
        guard startedAt <= now else { return false }
        if let endedAt { return endedAt <= now }
        // Older imports can have sets but no end time.
        return source == .strongImport && entries.contains { !$0.sets.isEmpty }
    }
}

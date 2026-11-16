import Foundation

// Protocols implemented by data modules (Persistence, HealthKitSource, GarminSource) and injected into
// features by the App's composition root. Features only ever see these.

public protocol WorkoutRepository: Sendable {
    func sessions(from start: Date, to end: Date) async throws -> [StrengthSession]
    func save(_ session: StrengthSession) async throws
    func deleteSession(id: UUID) async throws
}

public protocol ExerciseRepository: Sendable {
    func allExercises() async throws -> [Exercise]
    func save(_ exercise: Exercise) async throws
}

public protocol CheckInRepository: Sendable {
    func checkIn(for day: CalendarDay) async throws -> CheckIn?
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn]
    func save(_ checkIn: CheckIn) async throws
}

/// A source of recovery metrics and runs (Apple Health, Garmin Connect, …).
public protocol MetricsSource: Sendable {
    var kind: DataSourceKind { get }
    /// Whether the source can be used right now (permissions granted, signed in, …).
    func isAvailable() async -> Bool
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics]
    func runs(from start: Date, to end: Date) async throws -> [RunActivity]
}

public protocol ProfileRepository: Sendable {
    func profile() async throws -> AthleteProfile
    func save(_ profile: AthleteProfile) async throws
}

/// A source of menstrual cycle data (Apple Health, manual check-in entries). ADR-0009.
public protocol CycleSource: Sendable {
    func menstrualEvents(in range: ClosedRange<CalendarDay>) async throws -> [MenstrualEvent]
}

/// A source of everyday steps and walks (Apple Health, Garmin). ADR-0010.
public protocol ActivitySource: Sendable {
    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity]
}

/// Per-exercise progression configuration. `nil` means "use the default for the exercise".
public protocol ProgressionSettingsRepository: Sendable {
    func progressionSettings(for exerciseID: UUID) async throws -> ProgressionSettings?
    func save(_ settings: ProgressionSettings, for exerciseID: UUID) async throws
}

/// What an import would add, shown to the user before anything is saved (ADR-0011).
public struct ImportPreview: Sendable {
    public var sessions: [StrengthSession]
    /// Exercises not in the catalog; created as custom exercises that still need a muscle mapping.
    public var newExercises: [Exercise]
    /// 1-based line numbers that could not be read.
    public var skippedLines: [Int]

    public init(sessions: [StrengthSession], newExercises: [Exercise], skippedLines: [Int]) {
        self.sessions = sessions
        self.newExercises = newExercises
        self.skippedLines = skippedLines
    }

    public var setCount: Int {
        sessions.reduce(0) { total, session in total + session.entries.reduce(0) { $0 + $1.sets.count } }
    }
}

/// Reads training history in the canonical CSV format (Strong's columns). Implemented in the App with
/// `StrongImport`, so features don't depend on the parser.
public protocol TrainingHistoryImporter: Sendable {
    func preview(csv: String, weightUnit: WeightUnit, catalog: [Exercise]) throws -> ImportPreview
}

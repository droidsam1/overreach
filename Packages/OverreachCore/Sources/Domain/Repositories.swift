import Foundation

// Protocols implemented by data modules (Persistence, HealthKitSource, GarminSource) and injected into
// features by the App's composition root. Features only ever see these.

public protocol WorkoutRepository: Sendable {
    func sessions(from start: Date, to end: Date) async throws -> [StrengthSession]
    func save(_ session: StrengthSession) async throws
    /// Saves many sessions in one go (import, restore), replacing sessions with the same id.
    func save(_ sessions: [StrengthSession]) async throws
    func deleteSession(id: UUID) async throws
}

extension WorkoutRepository {
    /// Default: one save per session. Stores override it to write a batch at once.
    public func save(_ sessions: [StrengthSession]) async throws {
        for session in sessions {
            try await save(session)
        }
    }
}

public protocol ExerciseRepository: Sendable {
    func allExercises() async throws -> [Exercise]
    func save(_ exercise: Exercise) async throws
    /// Removes a user exercise (e.g. after merging it into another one). For a built-in exercise this only drops
    /// the user's edits; the built-in definition stays.
    func deleteExercise(id: UUID) async throws
}

public protocol RoutineRepository: Sendable {
    /// Every routine, sorted by name.
    func allRoutines() async throws -> [Routine]
    func save(_ routine: Routine) async throws
    func deleteRoutine(id: UUID) async throws
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
    /// Returns the exercise to its defaults.
    func deleteProgressionSettings(for exerciseID: UUID) async throws
    func allProgressionSettings() async throws -> [UUID: ProgressionSettings]
}

/// Whether this device already went through, or skipped, the first-run setup.
public protocol OnboardingStatusStore: Sendable {
    func isOnboardingCompleted() async -> Bool
    func markOnboardingCompleted() async
    /// The last app version whose "What's new" the user saw; `nil` if never.
    func lastSeenReleaseNotesVersion() async -> String?
    func markReleaseNotesSeen(version: String) async
}

/// Alerts the user when a rest ends while the app is in the background. There is at most one pending alert.
public protocol RestAlertScheduler: Sendable {
    func scheduleRestEnd(at date: Date, title: String, body: String) async
    func cancelRestEnd() async
}

/// Keeps logged sessions in the user's health app (ADR-0016). Implementations ask for permission when needed and
/// do nothing if it is refused.
public protocol HealthWorkoutWriter: Sendable {
    /// Writes the workout of `session`, replacing any workout already written for it.
    func saveWorkout(for session: StrengthSession) async throws
    func deleteWorkout(forSessionID sessionID: UUID) async throws
}

extension HealthWorkoutWriter {
    /// Brings the health app in line with `session`. Best effort: the session is already safe in the app.
    public func sync(_ session: StrengthSession) async {
        if session.belongsInHealth {
            try? await saveWorkout(for: session)
        } else {
            await removeWorkout(forSessionID: session.id)
        }
    }

    /// Removes the workout of a session, if there is one. Best effort.
    public func removeWorkout(forSessionID sessionID: UUID) async {
        try? await deleteWorkout(forSessionID: sessionID)
    }
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

/// Why a training history file could not be read.
public enum HistoryImportError: Error, Sendable, Equatable {
    case emptyFile
    case missingColumns([String])
}

/// Reads training history in the canonical CSV format (Strong's columns). Implemented in the App with
/// `StrongImport`, so features don't depend on the parser.
public protocol TrainingHistoryImporter: Sendable {
    func preview(csv: String, weightUnit: WeightUnit, catalog: [Exercise]) throws -> ImportPreview
}

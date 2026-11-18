import Domain
import Foundation

/// In-memory repositories for presentation tests in `OverreachCore` (the app's stores live in OverreachKit).
/// `failing` makes every write throw, to test error handling.
public actor TestStore: WorkoutRepository, ExerciseRepository, ProgressionSettingsRepository, ProfileRepository,
    RoutineRepository, OnboardingStatusStore {
    private var sessionsByID: [UUID: StrengthSession]
    private var exercisesByID: [UUID: Exercise]
    private var settingsByExercise: [UUID: ProgressionSettings] = [:]
    private var routinesByID: [UUID: Routine]
    private var storedProfile = AthleteProfile()
    private var onboardingCompleted = false
    private var failing = false

    public struct WriteFailed: Error {}

    public init(exercises: [Exercise] = [], sessions: [StrengthSession] = [], routines: [Routine] = []) {
        routinesByID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        sessionsByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func setFailing(_ value: Bool) { failing = value }

    private func write() throws {
        if failing { throw WriteFailed() }
    }

    // MARK: WorkoutRepository

    public func sessions(from start: Date, to end: Date) -> [StrengthSession] {
        sessionsByID.values.filter { $0.startedAt >= start && $0.startedAt <= end }.sorted { $0.startedAt < $1.startedAt }
    }

    public func save(_ session: StrengthSession) throws {
        try write()
        sessionsByID[session.id] = session
    }

    public func save(_ sessions: [StrengthSession]) throws {
        try write()
        for session in sessions { sessionsByID[session.id] = session }
    }

    public func deleteSession(id: UUID) throws {
        try write()
        sessionsByID[id] = nil
    }

    // MARK: ExerciseRepository

    public func allExercises() -> [Exercise] {
        exercisesByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ exercise: Exercise) throws {
        try write()
        exercisesByID[exercise.id] = exercise
    }

    public func deleteExercise(id: UUID) throws {
        try write()
        exercisesByID[id] = nil
    }

    // MARK: RoutineRepository

    public func allRoutines() -> [Routine] {
        routinesByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ routine: Routine) throws {
        try write()
        routinesByID[routine.id] = routine
    }

    public func deleteRoutine(id: UUID) throws {
        try write()
        routinesByID[id] = nil
    }

    // MARK: ProgressionSettingsRepository

    public func progressionSettings(for exerciseID: UUID) -> ProgressionSettings? { settingsByExercise[exerciseID] }

    public func save(_ settings: ProgressionSettings, for exerciseID: UUID) throws {
        try write()
        settingsByExercise[exerciseID] = settings
    }

    public func deleteProgressionSettings(for exerciseID: UUID) throws {
        try write()
        settingsByExercise[exerciseID] = nil
    }

    public func allProgressionSettings() -> [UUID: ProgressionSettings] { settingsByExercise }

    // MARK: OnboardingStatusStore

    public func isOnboardingCompleted() -> Bool { onboardingCompleted }

    public func markOnboardingCompleted() { onboardingCompleted = true }

    // MARK: ProfileRepository

    public func profile() -> AthleteProfile { storedProfile }

    public func save(_ profile: AthleteProfile) throws {
        try write()
        storedProfile = profile
    }
}

import Domain
import Foundation

/// In-memory implementation of the repositories, used in phase 0, previews and tests.
///
/// The app uses `SwiftDataStore` (ADR-0004); this one keeps previews and tests fast and dependency-free.
public actor InMemoryStore: WorkoutRepository, ExerciseRepository, CheckInRepository, ProfileRepository,
    ProgressionSettingsRepository {
    private var sessionsByID: [UUID: StrengthSession]
    private var exercisesByID: [UUID: Exercise]
    private var checkInsByDay: [CalendarDay: CheckIn]
    private var storedProfile = AthleteProfile()
    private var progressionByExercise: [UUID: ProgressionSettings] = [:]

    public init(exercises: [Exercise] = [], sessions: [StrengthSession] = [], checkIns: [CheckIn] = []) {
        exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        sessionsByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        checkInsByDay = Dictionary(checkIns.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    // MARK: WorkoutRepository

    public func sessions(from start: Date, to end: Date) -> [StrengthSession] {
        sessionsByID.values
            .filter { $0.startedAt >= start && $0.startedAt <= end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public func save(_ session: StrengthSession) {
        sessionsByID[session.id] = session
    }

    public func save(_ sessions: [StrengthSession]) {
        for session in sessions {
            sessionsByID[session.id] = session
        }
    }

    public func deleteSession(id: UUID) {
        sessionsByID[id] = nil
    }

    // MARK: ExerciseRepository

    public func allExercises() -> [Exercise] {
        exercisesByID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ exercise: Exercise) {
        exercisesByID[exercise.id] = exercise
    }

    public func deleteExercise(id: UUID) {
        exercisesByID[id] = nil
    }

    // MARK: CheckInRepository

    public func checkIn(for day: CalendarDay) -> CheckIn? {
        checkInsByDay[day]
    }

    public func checkIns(in range: ClosedRange<CalendarDay>) -> [CheckIn] {
        checkInsByDay.values
            .filter { range.contains($0.day) }
            .sorted { $0.day < $1.day }
    }

    public func save(_ checkIn: CheckIn) {
        checkInsByDay[checkIn.day] = checkIn
    }

    // MARK: ProfileRepository

    public func profile() -> AthleteProfile {
        storedProfile
    }

    public func save(_ profile: AthleteProfile) {
        storedProfile = profile
    }

    // MARK: ProgressionSettingsRepository

    public func progressionSettings(for exerciseID: UUID) -> ProgressionSettings? {
        progressionByExercise[exerciseID]
    }

    public func save(_ settings: ProgressionSettings, for exerciseID: UUID) {
        progressionByExercise[exerciseID] = settings
    }

    public func allProgressionSettings() -> [UUID: ProgressionSettings] {
        progressionByExercise
    }
}

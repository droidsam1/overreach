import Domain
import Foundation

/// In-memory implementation of the repositories, used in phase 0, previews and tests.
///
/// Phase 1 adds a SwiftData store behind the same protocols, with a CloudKit-compatible model
/// (all properties optional or defaulted, no unique constraints) — see ADR-0004.
public actor InMemoryStore: WorkoutRepository, ExerciseRepository, CheckInRepository {
    private var sessionsByID: [UUID: StrengthSession]
    private var exercisesByID: [UUID: Exercise]
    private var checkInsByDay: [CalendarDay: CheckIn]

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
}

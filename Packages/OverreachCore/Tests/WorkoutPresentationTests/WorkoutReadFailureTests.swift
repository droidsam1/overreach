import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

private struct ReadFailed: Error {}

private struct UnreadableHistory: WorkoutRepository {
    func sessions(from start: Date, to end: Date) async throws -> [StrengthSession] { throw ReadFailed() }
    func save(_ session: StrengthSession) async throws {}
    func deleteSession(id: UUID) async throws {}
}

@MainActor
@Suite("WorkoutModel read failures")
struct WorkoutReadFailureTests {
    @Test func warnsWhenTargetsAreComputedWithoutHistory() async {
        let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
        let store = TestStore(exercises: [bench])
        let model = WorkoutModel(workouts: UnreadableHistory(), exercises: store, progression: store)
        model.start()

        await model.add(bench)

        #expect(model.exercises.count == 1)
        #expect(model.errorMessage == "Could not read your history, so these targets may be off.")
    }
}

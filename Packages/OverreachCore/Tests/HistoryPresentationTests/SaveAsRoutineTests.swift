import Domain
import Fixtures
import Foundation
import HistoryPresentation
import Testing

@MainActor
@Suite("Save a session as a routine")
struct SaveAsRoutineTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest])

    private func makeModel() async -> (HistoryModel, TestStore, StrengthSession) {
        let session = StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [WorkoutSet(weightKg: 60, reps: 8)])],
            focus: .hypertrophy
        )
        let store = TestStore(exercises: [bench], sessions: [session])
        let fixedNow = now
        let model = HistoryModel(workouts: store, exercises: store, routines: store, clock: { fixedNow })
        await model.load()
        return (model, store, session)
    }

    @Test func savesOnceAndTellsTheUser() async throws {
        let (model, store, session) = await makeModel()

        await model.saveAsRoutine(sessionID: session.id)
        #expect(model.routineNotice == "Saved “Push” to your routines.")
        let routine = try #require(try await store.allRoutines().first)
        #expect(routine.exerciseIDs == [bench.id])
        #expect(routine.focus == .hypertrophy)

        model.clearRoutineNotice()
        #expect(model.routineNotice == nil)

        await model.saveAsRoutine(sessionID: session.id)
        #expect(model.routineNotice == "“Push” is already in your routines.")
        #expect(try await store.allRoutines().count == 1)
    }

    @Test func aFailureIsReported() async throws {
        let (model, store, session) = await makeModel()
        await store.setFailing(true)
        await model.saveAsRoutine(sessionID: session.id)
        #expect(model.routineNotice == "Could not save the routine.")
    }
}

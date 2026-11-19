import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("WorkoutModel")
struct WorkoutModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func makeModel(sessions: [StrengthSession] = []) -> (WorkoutModel, TestStore) {
        let store = TestStore(exercises: [bench], sessions: sessions)
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        return (model, store)
    }

    @Test func prefillsSetsFromTheProgressionTarget() async {
        let lastTime = StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
            ])]
        )
        let (model, _) = makeModel(sessions: [lastTime])
        model.start()
        await model.add(bench)

        let sets = model.exercises.first?.workingSets ?? []
        #expect(sets.map(\.weightKg) == [62.5, 62.5, 62.5])  // top of 8–12 reached → +2.5 kg
        #expect(sets.map(\.reps) == [8, 8, 8])
        #expect(sets.allSatisfy { !$0.isDone })
    }

    @Test func finishSavesOnlyCompletedSets() async throws {
        let (model, store) = makeModel()
        model.start(name: "Push A")
        await model.add(bench)
        model.exercises[0].sets[0].weightKg = 50
        model.exercises[0].sets[0].reps = 10
        model.exercises[0].sets[0].isDone = true

        let saved = await model.finish()

        #expect(saved)
        #expect(!model.isSessionActive)
        let sessions = try await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(sessions.count == 1)
        #expect(sessions.first?.name == "Push A")
        #expect(sessions.first?.entries.first?.sets.count == 1)
        #expect(sessions.first?.entries.first?.sets.first?.weightKg == 50)
    }

    @Test func discardOrEmptySessionSavesNothing() async throws {
        let (model, store) = makeModel()
        model.start()
        await model.add(bench)
        #expect(await model.finish())  // no set marked done
        model.start()
        model.discard()

        let sessions = try await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(sessions.isEmpty)
        #expect(!model.isSessionActive)
    }

    @Test func addSetCopiesTheLastSet() async {
        let (model, _) = makeModel()
        model.start()
        await model.add(bench)
        let exerciseID = model.exercises[0].id
        model.exercises[0].sets[2].weightKg = 40
        model.addSet(to: exerciseID)
        #expect(model.exercises[0].sets.count == 4)
        #expect(model.exercises[0].sets[3].weightKg == 40)
    }
}

@MainActor
@Suite("WorkoutModel focus")
struct WorkoutModelFocusTests {
    @Test func sessionFocusPicksTheDefaultSchemeAndRest() async {
        let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
        let store = TestStore(exercises: [bench])
        let model = WorkoutModel(workouts: store, exercises: store, progression: store)
        model.start()
        await model.setSessionFocus(.strength)
        await model.add(bench)

        let exercise = model.exercises.first
        #expect(exercise?.focus == .strength)
        #expect(exercise?.isFocusInferred == false)
        #expect(exercise?.sets.count == 4)  // strength default: 4 × 4 @ RPE 8
        #expect(exercise?.sets.first?.reps == 4)
        #expect((exercise?.restSeconds.lowerBound ?? 0) >= 180)

        await model.setSessionFocus(.hypertrophy)
        #expect(model.exercises.first?.sets.count == 3)
        #expect(model.exercises.first?.focus == .hypertrophy)
    }
}

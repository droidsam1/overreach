import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("Settings changes in an open session")
struct SettingsRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let microplates = ProgressionSettings(incrementKg: 1.25)

    private func makeModel() async -> (WorkoutModel, TestStore) {
        let lastTime = StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
            ])]
        )
        let store = TestStore(exercises: [bench], sessions: [lastTime])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        model.start()
        await model.add(bench)
        return (model, store)
    }

    @Test func changedSettingsRefreshTheTargetAndSets() async throws {
        let (model, store) = await makeModel()
        #expect(model.exercises[0].sets[0].weightKg == 62.5)

        try await store.save(microplates, for: bench.id)
        await model.applySettingsChanges()

        #expect(model.exercises[0].target.sets[0].weightKg == 61.25)
        #expect(model.exercises[0].sets[0].weightKg == 61.25)
    }

    @Test func withoutChangesWhatTheUserTypedStays() async {
        let (model, _) = await makeModel()
        model.exercises[0].sets[0].weightKg = 70
        await model.applySettingsChanges()
        #expect(model.exercises[0].sets[0].weightKg == 70)
    }

    @Test func loggedSetsAreKeptWhileTheTargetUpdates() async throws {
        let (model, store) = await makeModel()
        model.exercises[0].sets[0].isDone = true
        let logged = model.exercises[0].sets

        try await store.save(microplates, for: bench.id)
        await model.applySettingsChanges()

        #expect(model.exercises[0].sets == logged)
        #expect(model.exercises[0].target.sets[0].weightKg == 61.25)
    }

    @Test func removedSettingsAlsoRefresh() async throws {
        let (model, store) = await makeModel()
        try await store.save(microplates, for: bench.id)
        await model.applySettingsChanges()

        try await store.deleteProgressionSettings(for: bench.id)
        await model.applySettingsChanges()

        #expect(model.exercises[0].sets[0].weightKg == 62.5)
    }
}

import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("Choosing progression in Train")
struct FirstProgressionFlowTests {
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    @Test func emptyHistoryThenSavedRoutineOffersAndRemembersTheSelectedProgression() async throws {
        let store = TestStore(exercises: [bench])
        let model = WorkoutModel(workouts: store, exercises: store, progression: store)
        model.start(name: "Push")
        await model.add(bench)
        #expect(model.exercises[0].progressionOffer == nil)
        model.addSet(to: model.exercises[0].id)
        for index in model.exercises[0].sets.indices {
            model.exercises[0].sets[index].weightKg = 100
            model.exercises[0].sets[index].rpe = 8
            model.exercises[0].sets[index].isDone = true
        }
        #expect(await model.finish())

        let sessions = try await store.sessions(from: .distantPast, to: .distantFuture)
        let routine = Routine(from: try #require(sessions.first))
        await model.start(routine)
        let draft = try #require(model.exercises.first)
        let offer = try #require(draft.progressionOffer)
        #expect(draft.workingSets.map(\.weightKg) == [100, 100, 100, 100])
        #expect(offer.options.count == 3)

        model.exercises[0].notes = "Same bench"
        #expect(await model.chooseProgression(offer.options[1], for: draft.id))
        #expect(model.exercises[0].workingSets.map(\.weightKg) == [102.5, 102.5, 102.5, 102.5])
        #expect(model.exercises[0].workingSets.map(\.reps) == [8, 8, 8, 8])
        #expect(model.exercises[0].notes == "Same bench")
        #expect(model.exercises[0].progressionOffer == nil)
        let settings = await store.progressionSettings(for: bench.id)
        #expect(settings?.scheme == .linearLoad(sets: 4, reps: 8, targetRPE: 8))

        model.discard()
        model.start()
        await model.add(bench)
        #expect(model.exercises[0].workingSets.first?.weightKg == 102.5)
        #expect(model.exercises[0].progressionOffer == nil)
    }

    @Test func aRoutinePrescriptionAndManualEditsTakePriority() async throws {
        let session = StrengthSession(name: "Push", startedAt: Date(timeIntervalSinceNow: -86_400), entries: [
            ExerciseEntry(exerciseID: bench.id, sets: (1...4).map { _ in WorkoutSet(weightKg: 100, reps: 8) }),
        ])
        let store = TestStore(exercises: [bench], sessions: [session])
        let model = WorkoutModel(workouts: store, exercises: store, progression: store)
        let scheme = ProgressionScheme.linearLoad(sets: 2, reps: 5, targetRPE: 8)
        let routine = Routine(name: "Plan", exerciseIDs: [bench.id],
                              prescriptions: [RoutinePrescription(exerciseID: bench.id, scheme: scheme)])
        await model.start(routine)
        #expect(model.exercises[0].progressionOffer == nil)
        #expect(model.exercises[0].workingSets.map(\.reps) == [5, 5])

        model.discard()
        model.start()
        await model.add(bench)
        let draft = model.exercises[0]
        let option = try #require(draft.progressionOffer?.options.first)
        let firstWork = try #require(draft.sets.firstIndex { !$0.isWarmUp })
        model.exercises[0].sets[firstWork].weightKg = 95
        #expect(model.exercises[0].progressionOffer == nil)
        #expect(!(await model.chooseProgression(option, for: draft.id)))
        #expect(model.exercises[0].workingSets.first?.weightKg == 95)
        #expect(await store.progressionSettings(for: bench.id) == nil)
    }
}

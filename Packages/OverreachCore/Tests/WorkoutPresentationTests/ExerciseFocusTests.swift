import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import WorkoutPresentation

/// One exercise can train another focus than the session (e.g. bench for strength, accessories for hypertrophy).
@MainActor
@Suite("Exercise focus in the logger")
struct ExerciseFocusTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let fly = Exercise(name: "Cable Fly", primaryMuscles: [.chest], equipment: .cable)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func makeModel() async -> (WorkoutModel, TestStore) {
        let history = StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [
                ExerciseEntry(exerciseID: bench.id, sets: [10, 10, 9].map { WorkoutSet(weightKg: 60, reps: $0, rpe: 8) }),
                ExerciseEntry(exerciseID: fly.id, sets: [12, 12].map { WorkoutSet(weightKg: 15, reps: $0, rpe: 8) }),
            ]
        )
        let store = TestStore(exercises: [bench, fly], sessions: [history])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await model.load()
        model.start()
        await model.setSessionFocus(.hypertrophy)
        await model.add(exerciseID: bench.id)
        await model.add(exerciseID: fly.id)
        return (model, store)
    }

    @Test func oneExerciseCanTrainStrengthInAHypertrophySession() async throws {
        let (model, store) = await makeModel()

        await model.setFocus(.strength, of: model.exercises[0].id)

        let bench = model.exercises[0]
        #expect(bench.declaredFocus == .strength)
        #expect(bench.focus == .strength)
        #expect(bench.sets.allSatisfy { ($0.reps ?? 0) <= 6 })
        #expect(!bench.summary(format: format).focusLine.contains("(detected)"))
        #expect(model.exercises[1].focus == .hypertrophy)
        #expect(model.exercises[1].declaredFocus == nil)
        let saved = try await store.progressionSettings(for: self.bench.id)
        #expect(saved?.focus == .strength)
    }

    @Test func theFocusIsRememberedForTheNextSession() async throws {
        let (model, _) = await makeModel()
        await model.setFocus(.strength, of: model.exercises[0].id)
        model.discard()

        model.start()
        await model.add(exerciseID: bench.id)

        #expect(model.exercises[0].focus == .strength)
    }

    @Test func followingTheSessionAgainForgetsTheFocus() async throws {
        let (model, store) = await makeModel()
        await model.setFocus(.strength, of: model.exercises[0].id)

        await model.setFocus(nil, of: model.exercises[0].id)

        #expect(model.exercises[0].declaredFocus == nil)
        #expect(model.exercises[0].focus == .hypertrophy)
        #expect(try await store.progressionSettings(for: bench.id) == nil)
    }

    @Test func setsAlreadyDoneAreKept() async {
        let (model, _) = await makeModel()
        model.exercises[0].sets[0].reps = 11
        model.exercises[0].sets[0].isDone = true
        let before = model.exercises[0].sets

        await model.setFocus(.strength, of: model.exercises[0].id)

        #expect(model.exercises[0].sets == before)
        #expect(model.exercises[0].declaredFocus == .strength)
    }
}

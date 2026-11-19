import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("Workout notes")
struct WorkoutNotesTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)

    private func makeModel() async -> (WorkoutModel, TestStore) {
        let store = TestStore(exercises: [bench, squat])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await model.load()
        model.start(name: "Push")
        return (model, store)
    }

    @Test func notesAreSavedTrimmedWithTheSessionAndItsExercises() async throws {
        let (model, store) = await makeModel()
        await model.add(exerciseID: bench.id)
        await model.add(exerciseID: squat.id)
        model.exercises[0].sets[0].weightKg = 60
        model.exercises[0].sets[0].isDone = true
        model.exercises[0].notes = "  Left shoulder a bit sore \n"
        model.exercises[1].notes = "Never started"
        model.sessionNotes = " Slept 5 hours "

        #expect(await model.finish())

        let saved = try #require(try await store.sessions(from: .distantPast, to: .distantFuture).first)
        #expect(saved.notes == "Slept 5 hours")
        #expect(saved.entries.map(\.notes) == ["Left shoulder a bit sore"])
    }

    @Test func emptyNotesAreNotSaved() async throws {
        let (model, store) = await makeModel()
        await model.add(exerciseID: bench.id)
        model.exercises[0].sets[0].isDone = true
        model.exercises[0].notes = "   "

        #expect(await model.finish())

        let saved = try #require(try await store.sessions(from: .distantPast, to: .distantFuture).first)
        #expect(saved.notes == nil)
        #expect(saved.entries.first?.notes == nil)
    }

    @Test func aNewSessionStartsWithoutTheLastNotes() async {
        let (model, _) = await makeModel()
        model.sessionNotes = "Old"
        model.discard()
        model.start()
        #expect(model.sessionNotes.isEmpty)
    }

    @Test func changingTheFocusKeepsTheExerciseNotes() async {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        model.exercises[0].notes = "Grip one finger wider"

        await model.setSessionFocus(.strength)

        #expect(model.exercises[0].notes == "Grip one finger wider")
    }
}

import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import WorkoutPresentation

@MainActor
@Suite("Create an exercise from the picker")
struct NewExerciseTests {
    private func makeWorkout(failing: Bool = false) async -> (WorkoutModel, TestStore) {
        let store = TestStore(exercises: ExerciseCatalog.builtIn)
        let model = WorkoutModel(workouts: store, exercises: store, progression: store)
        await model.load()
        await store.setFailing(failing)
        return (model, store)
    }

    private func builtIn(_ name: String) throws -> Exercise {
        try #require(ExerciseCatalog.builtIn.first { $0.name == name })
    }

    @Test func fillsEquipmentAndMusclesFromTheName() async throws {
        let (workout, _) = await makeWorkout()
        let form = workout.newExercise(named: "  Zancada búlgara con kettlebell ")
        #expect(form.name == "Zancada búlgara con kettlebell")
        #expect(form.equipment == .kettlebell)
        let bulgarian = try builtIn("Bulgarian Split Squat")
        #expect(form.draft.primary == bulgarian.primaryMuscles)
        #expect(form.role(of: .hamstrings) == .secondary)
        #expect(form.role(of: .chest) == .none)
        #expect(form.musclesNote.contains("Bulgarian Split Squat") || form.musclesNote.contains("búlgara"))
        #expect(form.existing == nil)
        #expect(form.canSave)
    }

    @Test func unknownNamesAskForMuscles() async {
        let (workout, _) = await makeWorkout()
        let form = workout.newExercise(named: "Turkish get up")
        #expect(form.draft.primary.isEmpty)
        #expect(!form.canSave)
        #expect(form.musclesNote.hasPrefix("Choose at least one primary muscle"))

        form.setRole(.primary, for: .core)
        form.setRole(.secondary, for: .back)
        #expect(form.canSave)
        // Typing more no longer replaces muscles the user chose.
        form.name = "Turkish get up con kettlebell"
        #expect(form.draft.primary == [.core])
        #expect(form.equipment == .kettlebell)
        form.setRole(.none, for: .back)
        #expect(form.draft.secondary.isEmpty)
    }

    @Test func chosenEquipmentIsKept() async {
        let (workout, _) = await makeWorkout()
        let form = workout.newExercise(named: "Remo")
        form.equipment = .band
        form.name = "Remo con mancuerna"
        #expect(form.equipment == .band)
    }

    @Test func offersTheExistingExerciseInsteadOfADuplicate() async throws {
        let (workout, _) = await makeWorkout()
        let form = workout.newExercise(named: "ZANCADA CON BARRA")
        let lunge = try builtIn("Lunge (Barbell)")
        #expect(form.existing?.id == lunge.id)
        #expect(form.existingNotice?.useLabel == "Use Lunge (Barbell)")
        #expect(!form.canSave)
    }

    @Test func savesACustomExerciseAndAddsItToTheSession() async throws {
        let (workout, store) = await makeWorkout()
        workout.start()
        let form = workout.newExercise(named: "Sissy squat")
        form.setRole(.primary, for: .quadriceps)
        let created = try #require(await form.save())
        #expect(created.isCustom)
        #expect(created.name == "Sissy squat")
        #expect(created.primaryMuscles.contains(.quadriceps))

        await workout.addCreated(created)
        #expect(workout.exercises.map(\.exercise.id) == [created.id])
        #expect(workout.exerciseChoices.contains { $0.id == created.id })
        #expect(try await store.allExercises().contains(created))
    }

    @Test func reportsASaveFailure() async {
        let (workout, _) = await makeWorkout(failing: true)
        let form = workout.newExercise(named: "Sissy squat")
        form.setRole(.primary, for: .quadriceps)
        #expect(await form.save() == nil)
        #expect(form.errorMessage == "Could not save the exercise.")
    }

    @Test func routinesAddTheCreatedExercise() async throws {
        let store = TestStore(exercises: ExerciseCatalog.builtIn)
        let list = RoutinesModel(routines: store, exercises: store)
        await list.load()
        let editor = list.newEditor()
        let form = editor.newExercise(named: "Sissy squat")
        form.setRole(.primary, for: .quadriceps)
        let created = try #require(await form.save())
        editor.addCreated(created)
        #expect(editor.exerciseRows.map(\.id) == [created.id])
    }
}

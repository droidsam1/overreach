import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("Routines")
struct RoutinesModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let row = Exercise(name: "Row", primaryMuscles: [.back], equipment: .cable)

    private func makeList(routines: [Routine] = [], failing: Bool = false) async -> (RoutinesModel, TestStore) {
        let store = TestStore(exercises: [squat, bench, row], routines: routines)
        let model = RoutinesModel(routines: store, exercises: store)
        await model.load()
        await store.setFailing(failing)
        return (model, store)
    }

    @Test func createsARoutineWithOrderedExercises() async throws {
        let (list, store) = await makeList()
        #expect(list.showsEmptyHint)
        let editor = list.newEditor()
        #expect(editor.title == "New routine")
        #expect(!editor.canSave)

        editor.name = "  Lower "
        #expect(!editor.canSave)  // still needs an exercise
        editor.addExercise(id: squat.id)
        editor.addExercise(id: row.id)
        editor.addExercise(id: squat.id)
        editor.focus = .strength
        #expect(editor.exerciseRows.map(\.name) == ["Squat", "Row"])
        #expect(editor.exerciseChoices.map(\.name) == ["Bench Press"])
        #expect(await editor.save())

        let stored = try #require(try await store.allRoutines().first)
        #expect(stored.name == "Lower")
        #expect(stored.focus == .strength)
        #expect(stored.exerciseIDs == [squat.id, row.id])
        #expect(list.rows.first?.exerciseList == "Squat, Row")
        #expect(list.rows.first?.focus == "Strength")
    }

    @Test func movesAndRemovesExercises() async throws {
        let routine = Routine(name: "All", exerciseIDs: [squat.id, bench.id, row.id])
        let (list, store) = await makeList(routines: [routine])
        let editor = try #require(list.editor(for: routine.id))
        #expect(editor.title == "Edit routine")

        editor.moveExercises(from: [0], to: 3)
        #expect(editor.exerciseIDs == [bench.id, row.id, squat.id])
        editor.moveExercises(from: [2], to: 0)
        #expect(editor.exerciseIDs == [squat.id, bench.id, row.id])
        editor.moveExercises(from: [0, 1], to: 3)
        #expect(editor.exerciseIDs == [row.id, squat.id, bench.id])
        editor.moveExercises(from: [0], to: 9)  // out of range: ignored
        #expect(editor.exerciseIDs == [row.id, squat.id, bench.id])

        editor.removeExercises(at: [1])
        #expect(await editor.save())
        #expect(try await store.allRoutines() == [
            Routine(id: routine.id, name: "All", exerciseIDs: [row.id, bench.id]),
        ])
    }

    @Test func exercisesThatNoLongerExistLeaveTheRoutine() async throws {
        let routine = Routine(name: "Old", exerciseIDs: [UUID(), bench.id])
        let (list, _) = await makeList(routines: [routine])
        #expect(list.rows.first?.exerciseList == "Bench Press")
        #expect(try #require(list.editor(for: routine.id)).exerciseIDs == [bench.id])
    }

    @Test func deletesARoutine() async throws {
        let routine = Routine(name: "Old", exerciseIDs: [bench.id])
        let (list, store) = await makeList(routines: [routine])
        await list.delete(routine.id)
        #expect(list.rows.isEmpty)
        #expect(try await store.allRoutines().isEmpty)
    }

    @Test func aFailedSaveKeepsTheFormOpenWithAMessage() async {
        let (list, _) = await makeList(failing: true)
        let editor = list.newEditor()
        editor.name = "Push"
        editor.addExercise(id: bench.id)
        #expect(await editor.save() == false)
        #expect(editor.errorMessage == "Could not save the routine.")
    }

    @Test func startingARoutinePrefillsTargetsInOrder() async {
        let lastTime = StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
            ])]
        )
        let store = TestStore(exercises: [squat, bench, row], sessions: [lastTime])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })

        await model.start(Routine(name: "Push day", focus: .hypertrophy, exerciseIDs: [bench.id, UUID(), row.id]))

        #expect(model.isSessionActive)
        #expect(model.sessionName == "Push day")
        #expect(model.sessionFocus == .hypertrophy)
        #expect(model.exercises.map(\.name) == ["Bench Press", "Row"])  // the unknown exercise is skipped
        #expect(model.exercises.first?.workingSets.first?.weightKg == 60)
        #expect(model.exercises.first?.progressionOffer != nil)
    }

    @Test func aRoutineDoesNotReplaceAnOpenSession() async {
        let store = TestStore(exercises: [squat, bench])
        let model = WorkoutModel(workouts: store, exercises: store, progression: store)
        model.start(name: "Open")
        await model.start(Routine(name: "Other", exerciseIDs: [bench.id]))
        #expect(model.sessionName == "Open")
        #expect(model.exercises.isEmpty)
    }
}

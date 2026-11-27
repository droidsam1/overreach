import Domain
import ExercisesPresentation
import Fixtures
import Foundation
import PresentationKit
import Testing

@Suite("MappingDraft")
struct MappingDraftTests {
    @Test func aMuscleIsEitherPrimaryOrSecondary() {
        var draft = MappingDraft(primary: [.chest], secondary: [.chest, .triceps])
        #expect(draft.secondary == [.triceps])

        draft.setSecondary(.chest, true)
        #expect(draft.primary.isEmpty)
        #expect(draft.secondary == [.chest, .triceps])

        draft.setPrimary(.triceps, true)
        #expect(draft.primary == [.triceps])
        #expect(draft.secondary == [.chest])
    }

    @Test func canSaveOnlyWithAPrimaryMuscle() {
        var draft = MappingDraft(secondary: [.core])
        #expect(!draft.canSave)
        draft.setPrimary(.quadriceps, true)
        #expect(draft.canSave)
    }

    @Test func copyTakesMusclesAndKeepsChosenEquipment() {
        let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], secondaryMuscles: [.core], equipment: .barbell)
        var unknown = MappingDraft()
        unknown.copy(from: squat)
        #expect(unknown.primary == [.quadriceps])
        #expect(unknown.secondary == [.core])
        #expect(unknown.equipment == .barbell)

        var chosen = MappingDraft(equipment: .machine)
        chosen.copy(from: squat)
        #expect(chosen.equipment == .machine)
    }
}

@MainActor
@Suite("ExerciseEditorModel")
struct ExerciseEditorModelTests {
    private let bench = Exercise(
        name: "Bench Press (Barbell)", primaryMuscles: [.chest], secondaryMuscles: [.triceps], equipment: .barbell,
        aliases: ["press banca"]
    )
    private let row = Exercise(name: "Seated Row (Cable)", primaryMuscles: [.back], equipment: .cable)
    private let imported = Exercise(name: "Press Banca Pausa", primaryMuscles: [], isCustom: true)

    private func makeList(failing: Bool = false) async -> (ExercisesModel, TestStore) {
        let session = StrengthSession(
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 86_400),
            entries: [ExerciseEntry(exerciseID: imported.id, sets: [WorkoutSet(weightKg: 60, reps: 5)])]
        )
        let store = TestStore(exercises: [bench, row, imported], sessions: [session])
        let list = ExercisesModel(workouts: store, exercises: store, progression: store, routines: store)
        await list.load()
        await store.setFailing(failing)
        return (list, store)
    }

    @Test func startsFromTheExerciseAndOffersSimilarOnes() async throws {
        let (list, _) = await makeList()
        let editor = try #require(list.editor(for: imported.id))

        #expect(editor.title == "Press Banca Pausa")
        #expect(!editor.canSave)
        #expect(editor.canMerge)
        #expect(editor.suggestions.map(\.name) == ["Bench Press (Barbell)"])
        #expect(editor.suggestions.first?.muscles == "Chest")
        #expect(editor.muscleOptions.count == MuscleGroup.allCases.count)
    }

    @Test func customArtworkSuggestionsFollowTheDraftAndSelectionSurvivesReload() async throws {
        let (list, store) = await makeList()
        let editor = try #require(list.editor(for: imported.id))
        #expect(editor.suggestedIllustrations.first?.id == "bench-press")
        #expect(editor.suggestedIllustrations.count <= 3)
        editor.name = "Peso muerto rumano con pausa"
        #expect(editor.suggestedIllustrations.first?.id == "romanian-deadlift")
        editor.illustrationSearchText = "elevaciones laterales"
        #expect(editor.illustrationOptions.contains { $0.id == "cable-lateral-raise" })

        editor.selectIllustration("dead-bug")
        editor.selectIllustration("unknown-artwork")
        editor.setPrimary(.core, true)
        #expect(await editor.save())
        let stored = try #require(await store.allExercises().first { $0.id == imported.id })
        let encoded = try JSONEncoder().encode(stored)
        #expect(try JSONDecoder().decode(Exercise.self, from: encoded).illustrationID == "dead-bug")
        #expect(list.allRows.first { $0.id == stored.id }?.illustration == "dead-bug")

        let reopened = try #require(list.editor(for: stored.id))
        #expect(reopened.illustration == "dead-bug")
        reopened.selectIllustration(nil)
        #expect(await reopened.save())
        #expect(list.allRows.first { $0.id == stored.id }?.illustration == nil)
    }

    @Test func copyThenSaveMapsTheExercise() async throws {
        let (list, store) = await makeList()
        let editor = try #require(list.editor(for: imported.id))

        editor.copyMuscles(from: bench.id)
        #expect(editor.isPrimary(.chest))
        #expect(editor.isSecondary(.triceps))
        #expect(await editor.save())

        #expect(list.needsMappingCount == 0)
        let stored = try #require(await store.allExercises().first { $0.id == imported.id })
        #expect(stored.primaryMuscles == [.chest])
        #expect(stored.equipment == .barbell)
    }

    @Test func createsACustomExercise() async throws {
        let (list, store) = await makeList()
        let editor = list.newExerciseEditor()
        #expect(editor.exists)
        #expect(editor.title == "New exercise")
        #expect(editor.canEditNames)
        #expect(!editor.canMerge)
        #expect(!editor.canSave)

        editor.name = "  Zercher Squat "
        #expect(!editor.canSave)  // still needs a primary muscle
        editor.aliasesText = "sentadilla zercher, ZERCHER SQUAT, , sentadilla zércher"
        editor.setPrimary(.quadriceps, true)
        editor.setSecondary(.core, true)
        editor.draft.equipment = .barbell
        editor.movementPattern = .squat
        #expect(editor.canSave)
        #expect(await editor.save())

        let stored = try #require(await store.allExercises().first { $0.name == "Zercher Squat" })
        #expect(stored.isCustom)
        #expect(stored.aliases == ["sentadilla zercher"])
        #expect(stored.primaryMuscles == [.quadriceps])
        #expect(stored.secondaryMuscles == [.core])
        #expect(stored.equipment == .barbell)
        #expect(stored.movementPattern == .squat)
        #expect(list.allRows.map(\.name).contains("Zercher Squat"))
    }

    @Test func aNewExerciseSuggestsSimilarOnesWhileTyping() async {
        let (list, _) = await makeList()
        let editor = list.newExerciseEditor()
        #expect(editor.suggestions.isEmpty)
        editor.name = "Bench Press (Dumbbell)"
        #expect(editor.suggestions.map(\.id) == [bench.id])
    }

    @Test func namesUsedByAnotherExerciseAreRejected() async {
        let (list, store) = await makeList()
        let editor = list.newExerciseEditor()
        editor.setPrimary(.chest, true)

        editor.name = "PRESS  BANCA"  // alias of the bench press
        #expect(editor.nameMessage == "“PRESS  BANCA” is already used by Bench Press (Barbell).")
        #expect(!editor.canSave)
        #expect(await editor.save() == false)
        #expect(try await store.allExercises().count == 3)

        editor.name = "Floor Press"
        #expect(editor.canSave)
        editor.aliasesText = "seated row (cable)"
        #expect(editor.nameMessage == "“seated row (cable)” is already used by Seated Row (Cable).")
        #expect(!editor.canSave)
    }

    @Test func renamingKeepsTheOldNameForImports() async throws {
        let (list, store) = await makeList()
        let editor = try #require(list.editor(for: imported.id))
        editor.name = "Paused Bench"
        editor.setPrimary(.chest, true)

        #expect(await editor.save())

        let stored = try #require(await store.allExercises().first { $0.id == imported.id })
        #expect(stored.name == "Paused Bench")
        #expect(stored.aliases == ["Press Banca Pausa"])
    }

    @Test func untouchedAliasesAreKeptEvenWithCommas() async throws {
        let odd = Exercise(name: "Curl", primaryMuscles: [.biceps], isCustom: true, aliases: ["Curl, barra"])
        let store = TestStore(exercises: [odd])
        let list = ExercisesModel(workouts: store, exercises: store, progression: store, routines: store)
        await list.load()
        let editor = try #require(list.editor(for: odd.id))

        #expect(await editor.save())

        #expect(try await store.allExercises().first?.aliases == ["Curl, barra"])
    }

    @Test func builtInExercisesKeepTheirNames() async throws {
        let (list, store) = await makeList()
        let editor = try #require(list.editor(for: bench.id))
        #expect(!editor.canEditNames)
        editor.name = "Something else"
        editor.setPrimary(.triceps, true)

        #expect(await editor.save())

        let stored = try #require(await store.allExercises().first { $0.id == bench.id })
        #expect(stored.name == bench.name)
        #expect(stored.primaryMuscles == [.chest, .triceps])
    }

    @Test func aFailedCreationKeepsTheFormOpenWithAMessage() async {
        let (list, store) = await makeList(failing: true)
        let editor = list.newExerciseEditor()
        editor.name = "Zercher Squat"
        editor.setPrimary(.quadriceps, true)

        #expect(await editor.save() == false)
        #expect(editor.errorMessage == "Could not save the exercise.")
        #expect(try await store.allExercises().count == 3)
    }

    @Test func builtInExercisesCannotBeMergedAway() async throws {
        let (list, _) = await makeList()
        let editor = try #require(list.editor(for: bench.id))
        #expect(!editor.canMerge)
        editor.requestMerge(into: row.id)
        #expect(editor.pendingMerge == nil)
    }

    @Test func mergeAsksForConfirmationThenMerges() async throws {
        let (list, store) = await makeList()
        let editor = try #require(list.editor(for: imported.id))

        editor.requestMerge(into: bench.id)
        let confirmation = try #require(editor.pendingMerge)
        #expect(confirmation.confirmLabel == "Merge into Bench Press (Barbell)")
        #expect(confirmation.message.hasPrefix("1 sessions with Press Banca Pausa will use Bench Press (Barbell)."))

        #expect(await editor.confirmMerge())
        #expect(!editor.exists)
        #expect(editor.pendingMerge == nil)
        #expect(try await store.allExercises().map(\.id).contains(imported.id) == false)
    }

    @Test func cancellingKeepsEverything() async throws {
        let (list, _) = await makeList()
        let editor = try #require(list.editor(for: imported.id))
        editor.requestMerge(into: bench.id)
        editor.cancelMerge()
        #expect(editor.pendingMerge == nil)
        #expect(editor.exists)
    }

    @Test func mergeTargetsExcludeItselfAndUnmappedAndFollowTheSearch() async throws {
        let (list, _) = await makeList()
        let editor = try #require(list.editor(for: imported.id))
        #expect(editor.mergeTargets.map(\.name) == ["Bench Press (Barbell)", "Seated Row (Cable)"])

        editor.mergeSearchText = "PRESS banca"
        #expect(editor.mergeTargets.map(\.name) == ["Bench Press (Barbell)"])
    }

    @Test func failedSaveShowsAnErrorAndKeepsTheScreen() async throws {
        let (list, _) = await makeList(failing: true)
        let editor = try #require(list.editor(for: imported.id))
        editor.setPrimary(.chest, true)

        #expect(await editor.save() == false)
        #expect(editor.errorMessage == "Could not save the exercise.")
        #expect(list.needsMappingCount == 1)
    }
}

@MainActor
@Suite("ExercisesModel search")
struct ExercisesSearchTests {
    @Test func searchFiltersByNameAndAliasAndHidesTheNeedsMusclesSection() async {
        let store = TestStore(exercises: [
            Exercise(name: "Bench Press (Barbell)", primaryMuscles: [.chest], aliases: ["press de banca"]),
            Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps]),
            Exercise(name: "Zercher Squat", primaryMuscles: [], isCustom: true),
        ])
        let model = ExercisesModel(workouts: store, exercises: store, progression: store, routines: store)
        await model.load()
        #expect(model.needsMappingRows.map(\.name) == ["Zercher Squat"])

        model.searchText = "PRÉSS  de"
        #expect(model.allRows.map(\.name) == ["Bench Press (Barbell)"])
        #expect(model.needsMappingRows.isEmpty)

        model.searchText = "squat"
        #expect(model.allRows.map(\.name) == ["Squat (Barbell)", "Zercher Squat"])
        #expect(model.allRows.last?.needsMuscles == true)
    }
}

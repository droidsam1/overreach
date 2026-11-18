import Domain
import ExercisesPresentation
import Fixtures
import Foundation
import PresentationKit
import Testing

@MainActor
@Suite("Exercise settings")
struct ExerciseSettingsModelTests {
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func makeModel(stored: ProgressionSettings? = nil) async throws -> (ExerciseSettingsModel, TestStore) {
        let store = TestStore(exercises: [bench])
        if let stored { try await store.save(stored, for: bench.id) }
        let list = ExercisesModel(workouts: store, exercises: store, progression: store, routines: store)
        await list.load()
        let model = try #require(list.settingsEditor(for: bench.id, format: format))
        await model.load()
        return (model, store)
    }

    @Test func showsTheDefaultsWhenNothingIsStored() async throws {
        let (model, store) = try await makeModel()

        #expect(model.schemeKind == .doubleProgression)
        #expect(model.sets == 3 && model.minReps == 8 && model.maxReps == 12 && model.targetRPE == 8)
        #expect(model.incrementKg == 2.5)
        #expect(model.suggestionLine == "Default: 3 × 8–12 @ RPE 8 · +2.5 kg")
        #expect(!model.canUseDefaults)

        #expect(await model.save())
        #expect(try await store.progressionSettings(for: bench.id) == nil)  // stays automatic
    }

    @Test func theSuggestedSchemeFollowsTheFocus() async throws {
        let (model, store) = try await makeModel()

        model.focus = .strength
        #expect(model.schemeKind == .rpeBased)
        #expect(model.sets == 4 && model.reps == 4)
        #expect(model.suggestionLine == "Suggested for Strength: 4 × 4 @ RPE 8 · +2.5 kg · rest 3:00–5:00")

        #expect(await model.save())
        #expect(try await store.progressionSettings(for: bench.id) == ProgressionSettings(
            scheme: .rpeBased(sets: 4, reps: 4, targetRPE: 8), incrementKg: 2.5, focus: .strength
        ))
    }

    @Test func aCustomSchemeSurvivesAFocusChange() async throws {
        let (model, _) = try await makeModel()
        model.sets = 5
        model.focus = .strength
        #expect(model.schemeKind == .doubleProgression)
        #expect(model.sets == 5)
    }

    @Test func savesEverySchemeWithMicroplates() async throws {
        let (model, store) = try await makeModel()
        model.schemeKind = .linearLoad
        model.sets = 5
        model.reps = 5
        model.targetRPE = 7.5
        model.incrementKg = 0.5
        model.isMainLift = true
        #expect(model.showsReps && !model.showsRepRange)
        #expect(model.incrementOptions.contains { $0.value == 0.25 })
        #expect(model.incrementOptions.first?.name == "No added load")

        #expect(await model.save())
        #expect(try await store.progressionSettings(for: bench.id) == ProgressionSettings(
            scheme: .linearLoad(sets: 5, reps: 5, targetRPE: 7.5), incrementKg: 0.5, isMainLift: true
        ))
    }

    @Test func repBlocksMustBeValid() async throws {
        let (model, store) = try await makeModel()
        model.schemeKind = .repCycle
        model.repBlocksText = "12, x"
        #expect(!model.canSave)
        #expect(model.repBlocksMessage != nil)
        #expect(await model.save() == false)

        model.repBlocksText = "12, 8 5"
        #expect(model.repBlocksMessage == nil)
        #expect(await model.save())
        #expect(try await store.progressionSettings(for: bench.id)?.scheme
            == .repCycle(sets: 3, repBlocks: [12, 8, 5], targetRPE: 8))
    }

    @Test func repLimitsNeverCross() async throws {
        let (model, _) = try await makeModel()
        model.minReps = 10
        model.maxReps = 10
        #expect(model.minRepsBounds == 1...10)
        #expect(model.maxRepsBounds == 10...50)
    }

    @Test func loadsStoredSettings() async throws {
        let stored = ProgressionSettings(
            scheme: .repCycle(sets: 4, repBlocks: [10, 6], targetRPE: 9), incrementKg: 1.25, isMainLift: true,
            focus: .mixed
        )
        let (model, _) = try await makeModel(stored: stored)
        #expect(model.schemeKind == .repCycle)
        #expect(model.repBlocksText == "10, 6")
        #expect(model.sets == 4 && model.targetRPE == 9)
        #expect(model.incrementKg == 1.25 && model.isMainLift && model.focus == .mixed)
    }

    @Test func usingDefaultsReturnsTheExerciseToAutomatic() async throws {
        let (model, store) = try await makeModel(stored: ProgressionSettings(incrementKg: 1, focus: .strength))
        #expect(model.canUseDefaults)
        model.useDefaults()
        #expect(model.focus == nil && model.incrementKg == 2.5)
        #expect(await model.save())
        #expect(try await store.progressionSettings(for: bench.id) == nil)
    }

    @Test func aFailedSaveKeepsTheForm() async throws {
        let (model, store) = try await makeModel()
        await store.setFailing(true)
        model.sets = 4
        #expect(await model.save() == false)
        #expect(model.errorMessage == "Could not save the settings.")
    }
}

import AssistantPresentation
import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing

@MainActor
@Suite("Importing an AI answer")
struct PlanImportModelTests {
    private let bench = Exercise(name: "Bench Press (Barbell)", primaryMuscles: [.chest], equipment: .barbell)
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell)

    private let answer = """
        Here you go:
        ```json
        {"format":"overreach.plan","version":1,
         "routines":[{"id":"full-a","name":"Full A","focus":"strength","exercises":["Squat (Barbell)","Bench Press (Barbell)"]}],
         "exerciseSettings":[{"exercise":"Squat (Barbell)","scheme":{"type":"linearLoad","sets":5,"reps":5,"targetRPE":8},
                              "incrementKg":2.5,"isMainLift":true}]}
        ```
        """

    private func makeModel() -> (PlanImportModel, TestStore) {
        let store = TestStore(exercises: [bench, squat])
        let model = PlanImportModel(
            exercises: store, routines: store, progression: store, format: Format(locale: Locale(identifier: "en_US"))
        )
        return (model, store)
    }

    @Test func previewsTheChangesBeforeSaving() async throws {
        let (model, store) = makeModel()
        await model.read(text: answer)

        let preview = try #require(model.preview)
        #expect(preview.canImport)
        #expect(preview.issues.isEmpty)
        #expect(preview.correction == nil)
        #expect(preview.routines.map(\.name) == ["Full A"])
        #expect(preview.routines.first?.detail == "Strength · Squat (Barbell), Bench Press (Barbell)")
        #expect(preview.settings.first?.detail == "5 × 5 @ RPE 8 · +2.5 kg · main lift")
        #expect(try await store.allRoutines().isEmpty)
    }

    @Test func confirmingSavesAndImportingAgainDoesNotDuplicate() async throws {
        let (model, store) = makeModel()
        await model.read(text: answer)
        #expect(await model.confirm())

        #expect(model.preview == nil)
        #expect(model.resultMessage == "Imported 1 routines and 1 exercise settings.")
        #expect(try await store.allRoutines().map(\.name) == ["Full A"])
        let settings = try await store.progressionSettings(for: squat.id)
        #expect(settings?.scheme == .linearLoad(sets: 5, reps: 5, targetRPE: 8))

        await model.read(text: answer)
        #expect(model.preview?.routines.first?.isUpdate == true)
        #expect(await model.confirm())
        #expect(try await store.allRoutines().count == 1)
    }

    @Test func problemsBlockTheImportAndComeWithACorrection() async throws {
        let (model, store) = makeModel()
        await model.read(text: answer.replacingOccurrences(of: "Bench Press (Barbell)\"]", with: "Press de banca\"]"))

        let preview = try #require(model.preview)
        #expect(!preview.canImport)
        #expect(preview.issues.first?.hasPrefix("Unknown exercise “Press de banca”") == true)
        #expect(preview.correction?.contains("\"Press de banca\" is not in the catalog") == true)
        #expect(await model.confirm() == false)
        #expect(try await store.allRoutines().isEmpty)
    }

    @Test func ignoredFieldsAreShownAndCanBeSentBack() async throws {
        let (model, _) = makeModel()
        await model.read(text: answer.replacingOccurrences(of: "\"name\":\"Full A\"", with: "\"name\":\"Full A\",\"day\":1"))

        let preview = try #require(model.preview)
        #expect(preview.canImport)
        #expect(preview.warnings == ["Ignored: routines[0].day. The app does not use this field."])
        #expect(preview.correction?.contains("routines[0].day is not part of the format") == true)
    }

    @Test func textWithoutAPlanSaysWhatToDo() async throws {
        let (model, _) = makeModel()
        await model.read(text: "Sounds good, let's do it!")
        #expect(model.preview?.issues == ["No plan found. Copy the reply format into the chat and ask again."])
    }

    @Test func cancellingDropsThePreview() async {
        let (model, _) = makeModel()
        await model.read(text: answer)
        model.isShowingPreview = false
        #expect(model.preview == nil)
        #expect(await model.confirm() == false)
    }

    @Test func unreadableFilesAreReported() async {
        let (model, _) = makeModel()
        await model.read(fileData: Data([0xFF, 0xFE, 0xFD]))
        #expect(model.errorMessage == "Could not open that file.")
        #expect(model.preview == nil)
    }
}

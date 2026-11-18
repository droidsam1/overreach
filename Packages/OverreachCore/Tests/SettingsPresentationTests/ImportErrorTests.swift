import Domain
import Fixtures
import Foundation
import SettingsPresentation
import Testing

private struct FailingImporter: TrainingHistoryImporter {
    let error: any Error

    func preview(csv: String, weightUnit: WeightUnit, catalog: [Exercise]) throws -> ImportPreview { throw error }
}

@MainActor
@Suite("Import errors")
struct ImportErrorTests {
    private func failure(for error: any Error) async -> ImportModel.State {
        let store = TestStore()
        let model = ImportModel(importer: FailingImporter(error: error), workouts: store, exercises: store)
        await model.load(fileData: Data("x".utf8))
        return model.state
    }

    @Test func explainsAnEmptyFile() async {
        #expect(await failure(for: HistoryImportError.emptyFile) == .failed("The file is empty. Export it again from Strong."))
    }

    @Test func namesTheMissingColumns() async {
        let state = await failure(for: HistoryImportError.missingColumns(["weight", "reps"]))
        #expect(state == .failed("This file is missing these columns: weight, reps. Export it again from Strong."))
    }

    @Test func hidesTechnicalDetails() async {
        let state = await failure(for: CocoaError(.fileReadCorruptFile))
        #expect(state == .failed("Could not read this file. Check that it is a CSV exported from Strong."))
    }

    @Test func reportsAFileThatCouldNotBeOpened() {
        let store = TestStore()
        let model = ImportModel(importer: FailingImporter(error: CancellationError()), workouts: store, exercises: store)

        model.fileCouldNotBeOpened()

        #expect(model.state == .failed("Could not open that file. Try choosing it again."))
    }
}

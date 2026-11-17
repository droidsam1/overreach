import Domain
import FeatureSettings
import Fixtures
import Foundation
import Persistence
import Testing

private struct FakeImporter: TrainingHistoryImporter {
    let preview: ImportPreview

    func preview(csv: String, weightUnit: WeightUnit, catalog: [Exercise]) throws -> ImportPreview { preview }
}

@MainActor
@Suite("ImportModel")
struct ImportModelTests {
    @Test func previewThenConfirmSavesExercisesAndSessions() async throws {
        let newExercise = Exercise(name: "Zercher Squat", primaryMuscles: [], isCustom: true)
        let session = StrengthSession(
            name: "Legs",
            startedAt: Date(timeIntervalSince1970: 1_000),
            entries: [ExerciseEntry(exerciseID: newExercise.id, sets: [WorkoutSet(weightKg: 80, reps: 8)])],
            source: .strongImport
        )
        let store = InMemoryStore()
        let model = ImportModel(
            importer: FakeImporter(preview: ImportPreview(sessions: [session], newExercises: [newExercise], skippedLines: [7])),
            workouts: store,
            exercises: store
        )

        await model.load(fileData: Data("Date,Exercise Name\n".utf8))
        #expect(model.state == .preview)
        #expect(model.preview?.setCount == 1)

        await model.confirm()
        #expect(model.state == .done(sessions: 1, sets: 1))
        #expect(try await store.allExercises().contains(newExercise))
        #expect(try await store.sessions(from: .distantPast, to: .distantFuture).count == 1)
    }
}

@MainActor
@Suite("ImportModel with a large export")
struct LargeImportModelTests {
    @Test func importsSixHundredSessionsInBatches() async throws {
        let history = LargeHistory()
        let store = InMemoryStore()
        let model = ImportModel(
            importer: FakeImporter(preview: ImportPreview(sessions: history.sessions, newExercises: [], skippedLines: [])),
            workouts: store,
            exercises: store
        )
        await model.load(fileData: Data("Date,Exercise Name\n".utf8))

        await model.confirm()

        #expect(model.state == .done(sessions: 600, sets: history.setCount))
        #expect(model.importedSessions == 600)
        #expect(try await store.sessions(from: .distantPast, to: .distantFuture).count == 600)
    }
}

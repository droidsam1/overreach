import Domain
import StrongImport

/// Adapts `StrongCSVImporter` to the `TrainingHistoryImporter` protocol used by features.
struct StrongHistoryImporter: TrainingHistoryImporter {
    func preview(csv: String, weightUnit: WeightUnit, catalog: [Exercise]) throws -> ImportPreview {
        let result = try StrongCSVImporter.parse(
            csv, catalog: catalog, options: StrongCSVImporter.Options(weightUnit: weightUnit)
        )
        return ImportPreview(
            sessions: result.sessions, newExercises: result.newExercises, skippedLines: result.skippedLines
        )
    }
}

import Domain
import Foundation
import Observation

/// Import of training history from a Strong CSV export (ADR-0011): read → preview → confirm → save.
/// Re-importing the same file is safe: imported ids are stable, so sessions are replaced, not duplicated.
@MainActor
@Observable
public final class ImportModel {
    public enum State: Equatable {
        case idle
        case preview
        case importing
        case done(sessions: Int, sets: Int)
        case failed(String)
    }

    public var weightUnit: WeightUnit = .kilograms
    public private(set) var state: State = .idle
    public private(set) var preview: ImportPreview?
    /// Sessions saved so far while importing, for the progress bar.
    public private(set) var importedSessions = 0

    /// Sessions written per batch: large enough to be fast, small enough to show progress and keep memory low.
    static let batchSize = 100

    private var csv: String?
    private let importer: any TrainingHistoryImporter
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository

    public init(
        importer: any TrainingHistoryImporter,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository
    ) {
        self.importer = importer
        self.workouts = workouts
        self.exercises = exercises
    }

    /// Reads the file's text (UTF-8, falling back to Latin-1) and builds a preview.
    public func load(fileData: Data) async {
        let decoded = String(data: fileData, encoding: .utf8) ?? String(data: fileData, encoding: .isoLatin1)
        guard let text = decoded else {
            state = .failed("The file is not a text CSV.")
            return
        }
        csv = text
        await refreshPreview()
    }

    /// Rebuilds the preview, e.g. after changing the weight unit.
    public func refreshPreview() async {
        guard let csv else { return }
        do {
            let catalog = try await exercises.allExercises()
            let importer = importer
            let unit = weightUnit
            // Large exports (thousands of sets) are parsed off the main actor.
            preview = try await Task.detached {
                try importer.preview(csv: csv, weightUnit: unit, catalog: catalog)
            }.value
            state = .preview
        } catch {
            preview = nil
            state = .failed("Could not read the file: \(error)")
        }
    }

    /// Saves new exercises first (so sessions never point to missing exercises), then the sessions.
    public func confirm() async {
        guard let preview else { return }
        state = .importing
        do {
            for exercise in preview.newExercises {
                try await exercises.save(exercise)
            }
            importedSessions = 0
            var start = 0
            while start < preview.sessions.count {
                let batch = Array(preview.sessions[start..<min(start + Self.batchSize, preview.sessions.count)])
                try await workouts.save(batch)
                start += batch.count
                importedSessions = start
            }
            state = .done(sessions: preview.sessions.count, sets: preview.setCount)
            self.preview = nil
            csv = nil
        } catch {
            state = .failed("Import stopped: \(error). Already imported sessions are kept; importing again is safe.")
        }
    }

    public func reset() {
        preview = nil
        csv = nil
        state = .idle
    }
}

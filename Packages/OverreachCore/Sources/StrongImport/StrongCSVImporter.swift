import Domain
import Foundation

/// Imports the CSV export of the Strong app (phase 1).
///
/// Before implementing, verify the layout against a real export: header names, delimiter (`,` or `;`
/// depending on locale), weight units, date format and how RPE and notes are encoded. Keep anonymised
/// sample files under `Tests/StrongImportTests/Fixtures/`.
public enum StrongCSVImporter {
    public enum ImportError: Error, Sendable, Equatable {
        case notImplemented
        case invalidHeader(found: [String])
        case invalidRow(line: Int)
    }

    /// The result of an import: the sessions found, plus exercise names that still need a muscle-group mapping.
    public struct Result: Sendable {
        public var sessions: [StrengthSession]
        public var unmappedExerciseNames: Set<String>

        public init(sessions: [StrengthSession], unmappedExerciseNames: Set<String>) {
            self.sessions = sessions
            self.unmappedExerciseNames = unmappedExerciseNames
        }
    }

    public static func parse(_ csv: String, catalog: [Exercise]) throws -> Result {
        throw ImportError.notImplemented
    }
}

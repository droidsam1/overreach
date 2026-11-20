import Domain
import Foundation

/// The on-device draft lives alongside app data, outside the finished-workout database and JSON exports.
@MainActor
public struct FileWorkoutDraftStore: WorkoutDraftStore {
    private let directory: URL?

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Overreach", isDirectory: true)
    }

    private func draftFile() throws -> URL {
        guard let directory else { throw CocoaError(.fileWriteInvalidFileName) }
        return directory.appendingPathComponent("workout-draft.json")
    }

    public func readDraft() throws -> Data? {
        do {
            return try Data(contentsOf: draftFile())
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    public func writeDraft(_ data: Data?) throws {
        let file = try draftFile()
        if let data {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
        } else {
            do {
                try FileManager.default.removeItem(at: file)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // The draft was already removed.
            }
        }
    }
}

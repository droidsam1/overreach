import Foundation
import Persistence
import Testing

@MainActor
@Suite("Workout draft file")
struct FileWorkoutDraftStoreTests {
    @Test func reopensReplacesAndRemovesTheDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = FileWorkoutDraftStore(directory: directory)
        #expect(try first.readDraft() == nil)

        let initial = Data("first snapshot".utf8)
        try first.writeDraft(initial)
        let reopened = FileWorkoutDraftStore(directory: directory)
        #expect(try reopened.readDraft() == initial)

        let edited = Data("edited snapshot".utf8)
        try reopened.writeDraft(edited)
        #expect(try first.readDraft() == edited)
        try reopened.writeDraft(nil)
        try reopened.writeDraft(nil)
        #expect(try first.readDraft() == nil)
    }
}

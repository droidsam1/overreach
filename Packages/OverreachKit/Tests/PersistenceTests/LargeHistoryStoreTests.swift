import Domain
import Fixtures
import Foundation
import Persistence
import Testing

/// Saving and reading a real-sized history (~600 sessions) with SwiftData. Budgets are generous for CI runners.
@Suite("SwiftDataStore with a large history", .serialized)
struct LargeHistoryStoreTests {
    private static let history = LargeHistory()

    @Test func savesAndReadsSixHundredSessionsInABatch() async throws {
        let store = SwiftDataStore.make(container: try PersistenceContainer.make(inMemory: true))
        let clock = ContinuousClock()

        let saving = try await clock.measure {
            try await store.save(Self.history.sessions)
        }
        let reading = try await clock.measure {
            let sessions = try await store.sessions(from: .distantPast, to: .distantFuture)
            #expect(sessions.count == Self.history.sessions.count)
        }
        print("⏱ SwiftData batch save: \(saving), read all: \(reading)")
        #expect(saving < .seconds(10))
        #expect(reading < .seconds(5))
    }

    @Test func batchSaveReplacesInsteadOfDuplicating() async throws {
        let store = SwiftDataStore.make(container: try PersistenceContainer.make(inMemory: true))
        var sessions = Array(Self.history.sessions.prefix(50))
        try await store.save(sessions)
        sessions[0].name = "Renamed"

        try await store.save(sessions)

        let stored = try await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(stored.count == 50)
        #expect(stored.first?.name == "Renamed")
    }
}

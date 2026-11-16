import Domain
import Foundation
import Persistence
import Testing

@Suite("InMemoryStore")
struct InMemoryStoreTests {
    @Test func savesAndFiltersSessionsByDate() async {
        let store = InMemoryStore()
        let early = StrengthSession(name: "A", startedAt: Date(timeIntervalSince1970: 1_000))
        let late = StrengthSession(name: "B", startedAt: Date(timeIntervalSince1970: 9_000))
        await store.save(early)
        await store.save(late)

        let found = await store.sessions(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 5_000)
        )
        #expect(found.map(\.name) == ["A"])

        await store.deleteSession(id: early.id)
        let afterDelete = await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(afterDelete.map(\.name) == ["B"])
    }

    @Test func checkInsAreKeyedByDay() async throws {
        let store = InMemoryStore()
        let day = CalendarDay(year: 2026, month: 11, day: 16)
        await store.save(CheckIn(day: day, isSick: true))
        await store.save(CheckIn(day: day, isSick: false, energy: 4))  // replaces the first one

        let checkIn = try #require(await store.checkIn(for: day))
        #expect(checkIn.isSick == false)
        #expect(checkIn.energy == 4)
    }

    @Test func worksThroughTheDomainProtocol() async throws {
        let repository: any WorkoutRepository = InMemoryStore()
        try await repository.save(StrengthSession(name: "Legs", startedAt: .now))
        let sessions = try await repository.sessions(from: .distantPast, to: .distantFuture)
        #expect(sessions.count == 1)
    }
}

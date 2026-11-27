import Domain
import Foundation
@testable import GarminImport
import Testing

@Suite("Garmin backup")
struct GarminBackupTests {
    @Test func cachedRecordsRestoreOfflineAndSurviveResync() async throws {
        let key = "valid-key-0123456789"
        let (snapshot, recorded) = try await makeFixture(key: key)
        let day = CalendarDay(fixtureNow, calendar: utcCalendar)

        let data = try BackupCodec.encode(BackupDocument(createdAt: fixtureNow, garmin: snapshot))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains(key))
        #expect(!json.contains("lastSyncedDay"))
        #expect(!json.contains("runningTracks"))
        let restored = try #require(try BackupCodec.decode(data).garmin)

        let transport = FakeGarmin()
        let cache = MemoryCache()
        let destination = makeService(garmin: transport, cache: cache)
        try await destination.restoreBackup(restored)
        try await destination.restoreBackup(restored)

        // A new service instance must see the records, with no Garmin key.
        let relaunched = makeService(garmin: transport, cache: cache)
        #expect(await relaunched.isAvailable())
        #expect(await relaunched.connection() == nil)
        let metrics = try await relaunched.dailyMetrics(in: recorded.day...recorded.day)
        #expect(metrics == [recorded])
        let runs = try await relaunched.runs(from: .distantPast, to: .distantFuture)
        #expect(Set(runs) == Set(snapshot.runs))
        #expect(runs.count == snapshot.runs.count)
        let strength = await relaunched.strengthActivities(from: .distantPast, to: .distantFuture)
        #expect(Set(strength) == Set(snapshot.strength))
        let walks = try await relaunched.dailyActivity(in: day.adding(days: -60, calendar: utcCalendar)...day)
        #expect(Set(walks.flatMap(\.walks)) == Set(snapshot.walks.map(\.walk)))
        #expect(await transport.requests.isEmpty)

        try await relaunched.connect(key: key, lifetime: .recommended)
        _ = try await relaunched.sync { _ in }
        let synced = await relaunched.backupSnapshot()
        #expect(synced.metrics.contains(recorded))
        #expect(Set(synced.runs.map(\.id)) == Set(snapshot.runs.map(\.id)))
        #expect(synced.runs.count == snapshot.runs.count)
        #expect(synced.strength.count == snapshot.strength.count)
        #expect(synced.walks.count == snapshot.walks.count)
    }

    private func makeFixture(key: String) async throws -> (GarminBackup, DailyMetrics) {
        let source = makeService()
        try await source.connect(key: key, lifetime: .recommended)
        _ = try await source.sync { _ in }
        var snapshot = await source.backupSnapshot()
        #expect(!snapshot.runs.isEmpty)
        #expect(!snapshot.strength.isEmpty)
        snapshot.walks = [
            GarminWalk(id: "42", walk: WalkBout(
                start: fixtureNow, durationSeconds: 1_200, distanceMeters: 1_500, source: .garmin
            ))
        ]
        let day = CalendarDay(fixtureNow, calendar: utcCalendar)
        // Garmin can return a shorter window than requested. Choose a day the fixture did not report.
        let earlierDays = (1...60).map { day.adding(days: -$0, calendar: utcCalendar) }
        let recordedDay = try #require(earlierDays.first { candidate in
            !snapshot.metrics.contains { $0.day == candidate }
        })
        var recorded = DailyMetrics(day: recordedDay, sources: [.garmin])
        recorded.setHRV(45, .rmssd)
        snapshot.metrics.append(recorded)
        snapshot.metrics.sort { $0.day < $1.day }
        return (snapshot, recorded)
    }
}

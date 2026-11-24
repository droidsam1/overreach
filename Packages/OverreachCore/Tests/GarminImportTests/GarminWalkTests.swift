import Domain
import Foundation
@testable import GarminImport
import Testing

@Suite("Garmin walks")
struct GarminWalkTests {
    private let key = GarminStoredKey(value: "valid-key-0123456789", lifetime: .oneYear, savedAt: fixtureNow)

    private func activity(id: Int, type: String, start: String, steps: Int? = nil) -> [String: Any] {
        var item: [String: Any] = [
            "activityId": id, "activityType": ["typeKey": type], "startTimeGMT": start, "duration": 2_400,
            "distance": 3_100, "averageHR": 98, "elevationGain": 40
        ]
        item["steps"] = steps
        return item
    }

    @Test func walkingAndHikingActivitiesBecomeWalksOnTheirDay() async throws {
        let garmin = FakeGarmin()
        let page = [
            activity(id: 1, type: "walking", start: "2026-01-08 07:00:00", steps: 4_200),
            activity(id: 2, type: "hiking", start: "2026-01-07 09:00:00"),
            activity(id: 3, type: "running", start: "2026-01-08 18:00:00", steps: 5_000),
            activity(id: 4, type: "strength_training", start: "2026-01-06 18:00:00")
        ]
        await garmin.setActivityPage(start: 0, body: try JSONSerialization.data(withJSONObject: page))
        let service = makeService(garmin: garmin, secrets: MemorySecrets(key: key))

        let days = try await service.dailyActivity(
            in: CalendarDay(year: 2026, month: 1, day: 1)...CalendarDay(year: 2026, month: 1, day: 8)
        )

        let expectedDays = [CalendarDay(year: 2026, month: 1, day: 7), CalendarDay(year: 2026, month: 1, day: 8)]
        #expect(days.map(\.day) == expectedDays)
        let walk = try #require(days.last?.walks.first)
        #expect(days.last?.walks.count == 1)
        #expect(walk.source == .garmin)
        #expect(walk.steps == 4_200)
        #expect(walk.durationSeconds == 2_400)
        #expect(walk.distanceMeters == 3_100)
        #expect(walk.averageHeartRate == 98)
        #expect(walk.elevationGainMeters == 40)
        #expect(days.allSatisfy { $0.steps == nil })  // these days have no daily step totals
    }

    @Test func aCacheFromBeforeWalksFetchesSixtyDaysOfActivitiesOnce() async throws {
        let garmin = FakeGarmin()
        let cache = MemoryCache()
        let json = #"{"lastSync":0,"lastSyncedDay":{"year":2026,"month":1,"day":7},"runs":[],"strength":[]}"#
        await cache.save(try JSONDecoder().decode(GarminCache.self, from: Data(json.utf8)))
        let clock = TestClock(fixtureNow)
        let service = makeService(garmin: garmin, secrets: MemorySecrets(key: key), cache: cache, clock: clock)

        _ = try await service.sync { _ in }
        let first = await garmin.requests.filter { $0.path.hasPrefix("/activitylist-service") }
        #expect(first.first?.path.contains("startDate=2025-11-10") == true)
        #expect(await cache.cache?.walks == [])

        clock.advance(GarminService.autoSyncInterval + 1)
        let before = await garmin.requests.count
        _ = try await service.sync { _ in }
        let second = await garmin.requests.dropFirst(before).filter { $0.path.hasPrefix("/activitylist-service") }
        #expect(second.first?.path.contains("startDate=2026-01-02") == true)
    }

    @Test func walksSurviveAReloadOfTheCache() throws {
        let walk = GarminWalk(id: "7", walk: WalkBout(start: fixtureNow, durationSeconds: 1_200, source: .garmin))
        let cache = GarminCache(walks: [walk, walk])
        var reloaded = try JSONDecoder().decode(GarminCache.self, from: JSONEncoder().encode(cache))
        #expect(reloaded == cache)
        reloaded.removeDuplicateActivities()
        #expect(reloaded.walks == [walk])
    }
}

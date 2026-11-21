import Domain
import Fixtures
import Foundation
import HistoryPresentation
@testable import GarminImport
import Testing

/// A Garmin that answers from the fixtures, and records what it was asked.
actor FakeGarmin: GarminTransport {
    var requests: [GarminHTTPRequest] = []
    /// Responses to return before the normal ones, in order (e.g. a 429 then success).
    var queued: [GarminHTTPResponse] = []
    private var activityPages: [Int: Data] = [:]
    var acceptedKey = "valid-key-0123456789"
    var offline = false
    var tokenExpiry = Date(timeIntervalSince1970: 1_790_086_400)

    func queue(_ responses: GarminHTTPResponse...) { queued += responses }
    func setOffline(_ value: Bool) { offline = value }
    func setAcceptedKey(_ key: String) { acceptedKey = key }

    func setActivityPage(start: Int, body: Data) { activityPages[start] = body }

    func send(_ request: GarminHTTPRequest) throws -> GarminHTTPResponse {
        requests.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        if !queued.isEmpty { return queued.removeFirst() }
        if request.path == GarminEndpoint.tokenPath {
            guard request.headers["Authorization"] == "ApiKey \(acceptedKey)" else {
                return GarminHTTPResponse(status: 401)
            }
            return GarminHTTPResponse(status: 200, body: Data(Self.jwt(expiring: tokenExpiry).utf8))
        }
        guard request.headers["Authorization"]?.hasPrefix("Bearer ") == true else {
            return GarminHTTPResponse(status: 403)
        }
        if request.path.hasPrefix("/activitylist-service"),
            let page = activityPages.first(where: { request.path.contains("?start=\($0.key)&") }) {
            return GarminHTTPResponse(status: 200, body: page.value)
        }
        let name: String? = switch request.path {
        case let path where path.hasPrefix("/hrv-service"): "hrv-daily-range"
        case let path where path.hasPrefix("/sleep-service"): "sleep-summaries-range"
        case let path where path.hasPrefix("/usersummary-service/v2"): "daily-summaries-v2"
        case let path where path.hasPrefix("/metrics-service/metrics/maxmet"): "vo2max"
        case let path where path.hasPrefix("/activitylist-service") && path.contains("start=0&"): "activities"
        default: nil
        }
        guard let name, let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            let body = try? Data(contentsOf: url)
        else { return GarminHTTPResponse(status: 200, body: Data("[]".utf8)) }
        return GarminHTTPResponse(status: 200, body: body)
    }

    static func jwt(expiring date: Date) -> String {
        let claims = #"{"exp":\#(Int(date.timeIntervalSince1970)),"scope":["CONNECT_READ"]}"#
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).c2lnbmF0dXJl"
    }
}

actor MemorySecrets: GarminSecretStore {
    var key: GarminStoredKey?
    var token: GarminToken?
    var failsToSave = false

    init(key: GarminStoredKey? = nil, failsToSave: Bool = false) {
        self.key = key
        self.failsToSave = failsToSave
    }

    struct SaveFailed: Error {}

    func loadKey() -> GarminStoredKey? { key }
    func saveKey(_ key: GarminStoredKey) throws {
        if failsToSave { throw SaveFailed() }
        self.key = key
    }
    func loadToken() -> GarminToken? { token }
    func saveToken(_ token: GarminToken?) { self.token = token }
    func deleteAll() {
        key = nil
        token = nil
    }
}

actor MemoryCache: GarminCacheStore {
    var cache: GarminCache?
    func load() -> GarminCache? { cache }
    func save(_ cache: GarminCache) { self.cache = cache }
}

/// A clock tests can move.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
    return calendar
}()

/// 2026-01-08 12:00 UTC: the last day of the fixtures.
private let fixtureNow = Date(timeIntervalSince1970: 1_767_873_600)

private func makeService(
    garmin: FakeGarmin = FakeGarmin(), secrets: MemorySecrets = MemorySecrets(), cache: MemoryCache = MemoryCache(),
    clock: TestClock = TestClock(fixtureNow)
) -> GarminService {
    GarminService(
        transport: garmin, secrets: secrets, cache: cache, clock: { clock.now }, calendar: utcCalendar,
        sleep: { _ in }
    )
}

@MainActor
@Suite("Garmin runs in History")
struct GarminRunHistoryTests {
    @Test func aRunUploadedLateThisWeekAppearsInTheTimelineAndCalendar() async throws {
        let garmin = FakeGarmin()
        let service = makeService(garmin: garmin)
        await garmin.setActivityPage(start: 0, body: Data("[]".utf8))
        try await service.connect(key: "valid-key-0123456789", lifetime: .recommended)
        #expect(try await service.sync { _ in }.runs == 0)
        let priorRequests = await garmin.requests.count

        // The watch finished uploading a Jan 4 treadmill run after the first sync on Jan 8.
        let payload = """
        [{
          "activityId": 901,
          "activityName": "Treadmill 5K",
          "startTimeGMT": "2026-01-04 08:00:00",
          "activityType": {"typeKey": "treadmill_running"},
          "duration": 1500,
          "distance": 5000,
          "averageHR": 140,
          "activityTrainingLoad": 65
        }]
        """
        await garmin.setActivityPage(start: 0, body: Data(payload.utf8))
        let imported = try await service.sync { _ in }
        #expect(imported.runs == 1)
        let syncRequests = await garmin.requests.dropFirst(priorRequests)
        #expect(syncRequests.contains {
            $0.path.hasPrefix("/activitylist-service") && $0.path.contains("startDate=2026-01-02&endDate=2026-01-08")
        })
        #expect(syncRequests.contains {
            $0.path == "/hrv-service/hrv/daily/2026-01-07/2026-01-08"
        })

        let store = TestStore()
        let history = HistoryModel(
            workouts: store, exercises: store, routines: store, runSources: [service],
            calendar: utcCalendar, clock: { fixtureNow }
        )
        await history.load()
        #expect(history.rows.map(\.id) == [.run("garmin:901")])
        history.activityFilter = .running
        history.sourceFilter = .garmin
        let row = try #require(history.rows.first)
        guard case let .run(run) = row else {
            Issue.record("Expected a Garmin run in History")
            return
        }
        #expect(run.title == "Treadmill 5K")
        #expect(run.sources == [.garmin])
        #expect(run.trainingMetrics.map(\.value) == ["65"])

        await history.calendar.load()
        history.calendar.select(CalendarDay(year: 2026, month: 1, day: 4))
        #expect(history.calendar.selectedDetail?.runs.map(\.id) == ["garmin:901"])
        _ = try await service.sync { _ in }
        await history.load()
        #expect(history.rows.map(\.id) == [.run("garmin:901")])
    }

    @Test func anOfflineSyncWithNoCachedRunsSurfacesAnError() async throws {
        let garmin = FakeGarmin()
        let service = makeService(garmin: garmin)
        try await service.connect(key: "valid-key-0123456789", lifetime: .recommended)
        await garmin.setOffline(true)

        await #expect(throws: GarminAccountError.offline) {
            try await service.runs(from: .distantPast, to: fixtureNow)
        }
    }
}

@Suite("Garmin client")
struct GarminClientTests {
    @Test func theKeyGoesOnlyToTheTokenEndpointAndDataCallsCarryTheToken() async throws {
        let garmin = FakeGarmin()
        let client = GarminClient(transport: garmin, clock: { fixtureNow }, sleep: { _ in })

        let week = CalendarDay(year: 2026, month: 1, day: 1)...CalendarDay(year: 2026, month: 1, day: 8)
        _ = try await client.data(for: .hrv(week), key: "valid-key-0123456789")

        let requests = await garmin.requests
        #expect(requests.map(\.method) == ["POST", "GET"])
        #expect(requests[0].headers["Authorization"] == "ApiKey valid-key-0123456789")
        #expect(requests[1].headers["Authorization"]?.hasPrefix("Bearer eyJ") == true)
        #expect(!requests[1].headers.values.contains { $0.contains("valid-key") })
    }

    @Test func theTokenIsReusedUntilAnHourBeforeItExpires() async throws {
        let garmin = FakeGarmin()
        let clock = TestClock(fixtureNow)
        await garmin.setAcceptedKey("valid-key-0123456789")
        let client = GarminClient(transport: garmin, clock: { clock.now }, sleep: { _ in })
        let token = try await client.mintToken(key: "valid-key-0123456789")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1_790_086_400))  // from the JWT

        let day = CalendarDay(year: 2026, month: 1, day: 8)
        _ = try await client.data(for: .vo2Max(day...day), key: "valid-key-0123456789")
        clock.advance(1_790_086_400 - fixtureNow.timeIntervalSince1970 - 1_800)  // 30 minutes left
        _ = try await client.data(for: .vo2Max(day...day), key: "valid-key-0123456789")

        #expect(await garmin.requests.map(\.method) == ["POST", "GET", "POST", "GET"])
    }

    @Test func rateLimitsAreRetriedTwiceWithWaitsThenGiveUp() async throws {
        let garmin = FakeGarmin()
        let waits = WaitRecorder()
        let client = GarminClient(
            transport: garmin, token: GarminToken(value: "t", expiresAt: .distantFuture), clock: { fixtureNow },
            sleep: { await waits.record($0) }, jitter: { 1 }
        )
        let day = CalendarDay(year: 2026, month: 1, day: 8)
        await garmin.queue(GarminHTTPResponse(status: 429, retryAfter: 5), GarminHTTPResponse(status: 503))

        _ = try await client.data(for: .vo2Max(day...day), key: "k")
        #expect(await waits.waits.filter { $0 > 1 } == [5, 8])  // Retry-After honoured, then the second backoff

        await garmin.queue(
            GarminHTTPResponse(status: 429), GarminHTTPResponse(status: 429), GarminHTTPResponse(status: 429)
        )
        await #expect(throws: GarminAccountError.rateLimited) {
            try await client.data(for: .vo2Max(day...day), key: "k")
        }
    }

    @Test func aRejectedTokenIsMintedAgainOnceThenTheKeyIsRejected() async throws {
        let garmin = FakeGarmin()
        let client = GarminClient(
            transport: garmin, token: GarminToken(value: "old", expiresAt: .distantFuture), clock: { fixtureNow },
            sleep: { _ in }
        )
        let day = CalendarDay(year: 2026, month: 1, day: 8)
        await garmin.queue(GarminHTTPResponse(status: 401))

        _ = try await client.data(for: .vo2Max(day...day), key: "valid-key-0123456789")
        #expect(await garmin.requests.map(\.method) == ["GET", "POST", "GET"])

        await garmin.setAcceptedKey("another-key-0123456789")
        await garmin.queue(GarminHTTPResponse(status: 401))
        await #expect(throws: GarminAccountError.keyRejected) {
            try await client.data(for: .vo2Max(day...day), key: "valid-key-0123456789")
        }
    }

    @Test func noConnectionIsOffline() async {
        let garmin = FakeGarmin()
        await garmin.setOffline(true)
        let client = GarminClient(transport: garmin, sleep: { _ in })
        await #expect(throws: GarminAccountError.offline) { try await client.mintToken(key: "k") }
    }
}

actor WaitRecorder {
    var waits: [TimeInterval] = []
    func record(_ seconds: TimeInterval) { waits.append(seconds) }
}

@Suite("Garmin account and sync")
struct GarminServiceTests {
    @Test func connectingChecksTheKeyWithGarminBeforeSavingIt() async throws {
        let secrets = MemorySecrets()
        let service = makeService(secrets: secrets)

        await #expect(throws: GarminAccountError.keyRejected) {
            try await service.connect(key: "wrong-key-0123456789", lifetime: .oneYear)
        }
        #expect(await secrets.key == nil)

        try await service.connect(key: "  \"valid-key-0123456789\"\n", lifetime: .days90)  // pasted with extras
        #expect(await secrets.key?.value == "valid-key-0123456789")
        #expect(await secrets.token != nil)
        let info = try #require(await service.connection())
        #expect(info.keyExpiresAt == fixtureNow.addingTimeInterval(90 * 86_400))
    }

    @Test func somethingThatIsNotAKeyIsRefusedWithoutAskingGarmin() async {
        let garmin = FakeGarmin()
        let service = makeService(garmin: garmin)
        for pasted in ["", "   ", "https://connect.garmin.com/app/settings", "copy the key here", "short"] {
            await #expect(throws: GarminAccountError.keyLooksWrong) {
                try await service.connect(key: pasted, lifetime: .oneYear)
            }
        }
        #expect(await garmin.requests.isEmpty)
    }

    @Test func aKeyThatCannotBeStoredIsReported() async {
        let service = makeService(secrets: MemorySecrets(failsToSave: true))
        await #expect(throws: GarminAccountError.storageFailed) {
            try await service.connect(key: "valid-key-0123456789", lifetime: .oneYear)
        }
    }

    @Test func theFirstSyncImportsSixtyDaysAndReportsProgress() async throws {
        let garmin = FakeGarmin()
        let cache = MemoryCache()
        let service = makeService(garmin: garmin, cache: cache)
        try await service.connect(key: "valid-key-0123456789", lifetime: .oneYear)
        let steps = ProgressRecorder()

        let summary = try await service.sync { progress in Task { await steps.record(progress) } }

        #expect(summary.days == 17)
        #expect(summary.hrvNights == 14)
        #expect(summary.sleepNights == 14)
        #expect(summary.runs == 4)
        #expect(summary.strengthWorkouts == 9)
        #expect(summary.skippedRecords == 0)
        let dataRequests = await garmin.requests.filter { $0.method == "GET" }
        #expect(dataRequests.count == 6)  // 60 days: HRV, summaries, VO2max, activities and two sleep windows
        let stored = try #require(await cache.cache)
        #expect(stored.lastSyncedDay == CalendarDay(year: 2026, month: 1, day: 8))
        #expect(stored.lastSync == fixtureNow)

        let day = CalendarDay(year: 2025, month: 12, day: 26)
        let metrics = try await service.dailyMetrics(in: day...day)
        #expect(metrics.first?.hrvNightlyAverageMs == 36)
        let runs = try await service.runs(from: .distantPast, to: .distantFuture)
        #expect(runs.count == 4)
        #expect(await service.strengthActivities(from: .distantPast, to: .distantFuture).count == 9)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await steps.last == GarminSyncProgress(completed: 6, total: 6))
    }

    @Test func overlappingActivityPagesImportEachIDOnce() async throws {
        let garmin = FakeGarmin()
        let pageSize = GarminEndpoint.activityPageSize
        let firstPage = (1...pageSize).map { activity(id: $0, heartRate: 140) }
        let secondPage = [activity(id: pageSize, heartRate: 145), activity(id: pageSize + 1, heartRate: 150)]
        await garmin.setActivityPage(start: 0, body: try JSONSerialization.data(withJSONObject: firstPage))
        await garmin.setActivityPage(start: pageSize, body: try JSONSerialization.data(withJSONObject: secondPage))
        let service = makeService(garmin: garmin)
        try await service.connect(key: "valid-key-0123456789", lifetime: .oneYear)

        let summary = try await service.sync { _ in }
        let runs = try await service.runs(from: .distantPast, to: .distantFuture)

        #expect(summary.runs == pageSize + 1)
        #expect(runs.count == pageSize + 1)
        #expect(Set(runs.map(\.id)) == Set((1...(pageSize + 1)).map(String.init)))
        #expect(runs.first { $0.id == String(pageSize) }?.averageHeartRate == 145)
    }

    private func activity(id: Int, heartRate: Int) -> [String: Any] {
        [
            "activityId": id,
            "activityType": ["typeKey": "running"],
            "startTimeGMT": "2026-01-08 08:00:00",
            "duration": 1_800,
            "averageHR": heartRate
        ]
    }

    @Test func olderCachesReturnOneCopyOfEachActivityEvenWhenOffline() async throws {
        let garmin = FakeGarmin()
        let cache = MemoryCache()
        let key = GarminStoredKey(value: "valid-key-0123456789", lifetime: .oneYear, savedAt: fixtureNow)
        let service = makeService(garmin: garmin, secrets: MemorySecrets(key: key), cache: cache)
        let olderRun = RunActivity(
            id: "1", source: .garmin, startedAt: fixtureNow, durationSeconds: 1_800, distanceMeters: 5_000
        )
        var newerRun = olderRun
        newerRun.averageHeartRate = 145
        let olderStrength = RecordedStrengthActivity(
            id: "2", source: .garmin, startedAt: fixtureNow, durationSeconds: 1_800
        )
        var newerStrength = olderStrength
        newerStrength.trainingLoad = 42
        await cache.save(GarminCache(runs: [olderRun, newerRun], strength: [olderStrength, newerStrength]))
        await garmin.setOffline(true)

        #expect(await service.strengthActivities(from: .distantPast, to: .distantFuture) == [newerStrength])
        #expect(try await service.runs(from: .distantPast, to: .distantFuture) == [newerRun])
    }

    @Test func readingMetricsSyncsOnlyWhenTheLastSyncIsOld() async throws {
        let garmin = FakeGarmin()
        let clock = TestClock(fixtureNow)
        let service = makeService(garmin: garmin, clock: clock)
        try await service.connect(key: "valid-key-0123456789", lifetime: .oneYear)
        _ = try await service.sync { _ in }
        let afterFirst = await garmin.requests.count
        let day = CalendarDay(year: 2026, month: 1, day: 8)

        _ = try await service.dailyMetrics(in: day...day)
        #expect(await garmin.requests.count == afterFirst)  // fresh: no request

        clock.advance(GarminService.autoSyncInterval + 1)
        _ = try await service.dailyMetrics(in: day...day)
        let later = await garmin.requests.dropFirst(afterFirst).filter { $0.method == "GET" }
        #expect(later.count == 5)  // only the last days again: one request per endpoint
        #expect(later.first?.path == "/hrv-service/hrv/daily/2026-01-07/2026-01-08")
    }

    @Test func syncingWithoutAKeySaysSo() async {
        let service = makeService()
        await #expect(throws: GarminAccountError.notConnected) { try await service.sync { _ in } }
        #expect(await service.isAvailable() == false)
    }

    @Test func disconnectingForgetsTheKeyButKeepsImportedData() async throws {
        let secrets = MemorySecrets()
        let service = makeService(secrets: secrets)
        try await service.connect(key: "valid-key-0123456789", lifetime: .oneYear)
        _ = try await service.sync { _ in }

        await service.disconnect()

        #expect(await secrets.key == nil)
        #expect(await secrets.token == nil)
        #expect(await service.connection() == nil)
        #expect(await service.isAvailable())
        let day = CalendarDay(year: 2025, month: 12, day: 26)
        #expect(try await service.dailyMetrics(in: day...day).count == 1)
    }

    @Test func aSecondLaunchReusesTheSavedToken() async throws {
        let garmin = FakeGarmin()
        let secrets = MemorySecrets()
        let cache = MemoryCache()
        let first = makeService(garmin: garmin, secrets: secrets, cache: cache)
        try await first.connect(key: "valid-key-0123456789", lifetime: .oneYear)

        let relaunched = makeService(garmin: garmin, secrets: secrets, cache: cache)
        _ = try await relaunched.sync { _ in }

        #expect(await garmin.requests.filter { $0.method == "POST" }.count == 1)  // only the one from connecting
    }
}

actor ProgressRecorder {
    var last: GarminSyncProgress?
    func record(_ progress: GarminSyncProgress) {
        if (last?.completed ?? -1) < progress.completed { last = progress }
    }
}

/// The key is personal (Supplemental Terms §1, ADR-0022): it lives only in the secret store and goes only to the
/// token endpoint. These tests fail if any other path starts carrying it.
@Suite("The Garmin key never leaves secure storage")
struct GarminKeyContainmentTests {
    private let key = "valid-key-0123456789"

    @Test func aCacheSavedBeforeSeparateHRVSeriesKeepsItsRMSSD() throws {
        // Before ADR-0025 each night held one value in `hrvNightlyAverageMs`, labelled since ADR-0024.
        let json = """
            {"lastSyncedDay":{"year":2026,"month":11,"day":19},"runs":[],"strength":[],"metrics":[
              {"day":{"year":2026,"month":11,"day":18},"sources":["garmin"],"hrvNightlyAverageMs":41},
              {"day":{"year":2026,"month":11,"day":19},"sources":["garmin"],"hrvNightlyAverageMs":38,"hrvMetric":"rmssd",
               "restingHeartRate":52}
            ]}
            """
        let cache = try JSONDecoder().decode(GarminCache.self, from: Data(json.utf8))

        #expect(cache.metrics.map { $0.hrv(.rmssd) } == [41, 38])
        #expect(cache.metrics.allSatisfy { $0.hrv(.sdnn) == nil })
        #expect(cache.metrics.last?.restingHeartRate == 52)

        let reloaded = try JSONDecoder().decode(GarminCache.self, from: JSONEncoder().encode(cache))
        #expect(reloaded == cache)
    }

    @Test func theCacheHoldsNeitherTheKeyNorTheToken() async throws {
        let garmin = FakeGarmin()
        let secrets = MemorySecrets()
        let cache = MemoryCache()
        let service = makeService(garmin: garmin, secrets: secrets, cache: cache)
        try await service.connect(key: key, lifetime: .oneYear)
        _ = try await service.sync { _ in }

        let stored = try #require(await cache.cache)
        let json = String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
        let token = try #require(await secrets.token?.value)
        #expect(!json.contains(key))
        #expect(!json.contains(token))
    }

    @Test func onlyTheTokenRequestCarriesTheKey() async throws {
        let garmin = FakeGarmin()
        let service = makeService(garmin: garmin)
        try await service.connect(key: key, lifetime: .oneYear)
        _ = try await service.sync { _ in }

        for request in await garmin.requests {
            let carriesKey = request.headers.values.contains { $0.contains(key) } || request.path.contains(key)
            #expect(carriesKey == (request.path == GarminEndpoint.tokenPath))
        }
    }

    @Test func importedDataAndErrorsNeverMentionTheKey() async throws {
        let garmin = FakeGarmin()
        let service = makeService(garmin: garmin)
        try await service.connect(key: key, lifetime: .oneYear)
        _ = try await service.sync { _ in }

        let years = CalendarDay(year: 2025, month: 1, day: 1)...CalendarDay(year: 2027, month: 1, day: 1)
        let metrics = try await service.dailyMetrics(in: years)
        let runs = try await service.runs(from: .distantPast, to: .distantFuture)
        let exported = String(decoding: try JSONEncoder().encode(metrics), as: UTF8.self)
            + String(decoding: try JSONEncoder().encode(runs), as: UTF8.self)
        #expect(!exported.contains(key))

        await garmin.setAcceptedKey("another-key-0123456789")
        do {
            try await service.connect(key: "wrong-key-abcdefghijk", lifetime: .oneYear)
        } catch {
            #expect(!String(describing: error).contains("wrong-key"))
        }
    }
}


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
        #expect(days.allSatisfy { $0.steps == nil })  // steps come from the daily metrics
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

import Domain
import Foundation
import Testing
import WeatherImport

struct OpenWeatherTests {
    @Test func requestContainsOnlyCoarseAreaAndUTCHour() throws {
        let area = try #require(WeatherArea(latitude: 42.573, longitude: -8.387))
        let date = Date(timeIntervalSince1970: 1_700_003_020)
        let url = try #require(OpenWeatherTimeline.url(for: area, start: date, key: "fixture"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "lat" }?.value == "42.6")
        #expect(query?.first { $0.name == "lon" }?.value == "-8.4")
        #expect(query?.first { $0.name == "start" }?.value == "1700002800")

        #expect(url.path == "/data/4.0/onecall/timeline/1h")
    }

    @Test func historyCacheCoalescesRequestsAndSurvivesServiceRestart() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let date = Date(timeIntervalSince1970: 1_700_003_020)
        let weather = service(cache: cache, fixture: fixture)
        async let first = weather.historical(for: area, at: date)
        async let second = weather.historical(for: area, at: date.addingTimeInterval(600))
        let (one, two) = await (first, second)
        #expect(one == two)
        #expect(one?.temperatureCelsius == 8)
        #expect(one?.isDaylight == true)
        #expect(await fixture.calls == 1)
        let reloaded = await service(cache: cache, fixture: fixture).historical(for: area, at: date)
        #expect(reloaded == one)
        #expect(await fixture.calls == 1)
    }

    @Test func forecastUsesOneRequestAndKeepsProbabilitySeparateFromCondition() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let weather = service(cache: temporaryCache(), fixture: fixture)
        let first = await weather.forecast(for: area)
        #expect(first.first?.precipitationProbability == 0.2)
        #expect(first.first?.conditionCode == 800)
        #expect(await weather.forecast(for: area) == first)
        #expect(await fixture.calls == 1)
    }

    @Test func historyAndForecastShareThePersistedDailyBudget() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let weather = service(cache: cache, fixture: fixture)
        let date = Date(timeIntervalSince1970: 1_700_003_020)
        for offset in 0..<200 {
            _ = await weather.historical(for: area, at: date.addingTimeInterval(Double(offset) * 3_600))
        }
        let restarted = service(cache: cache, fixture: fixture)
        #expect(await restarted.forecast(for: area).isEmpty)
        #expect(await fixture.calls == 200)
    }

    @Test func providerBackoffAppliesToBothHistoryAndForecast() async throws {
        let fixture = RequestFixture(shouldBackOff: true)
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let weather = service(cache: temporaryCache(), fixture: fixture)
        let date = Date(timeIntervalSince1970: 1_700_003_020)
        #expect(await weather.historical(for: area, at: date) == nil)
        #expect(await weather.forecast(for: area).isEmpty)
        #expect(await fixture.calls == 1)
    }

    @Test func freshForecastIsReusedByANewServiceInstance() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let clock = Clock()
        let first = await service(cache: cache, fixture: fixture, clock: clock).forecast(for: area, forceRefresh: false)
        #expect(first.fetchedAt == clock.date)
        clock.advance(10 * 60)
        let second = await service(cache: cache, fixture: fixture, clock: clock).forecast(for: area, forceRefresh: false)
        #expect(second == first)
        #expect(await fixture.calls == 1)
    }

    @Test func expiredForecastIsFetchedAgain() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let clock = Clock()
        _ = await service(cache: cache, fixture: fixture, clock: clock).forecast(for: area)
        clock.advance(31 * 60)
        let renewed = await service(cache: cache, fixture: fixture, clock: clock).forecast(for: area, forceRefresh: false)
        #expect(await fixture.calls == 2)
        #expect(renewed.fetchedAt == clock.date)
    }

    @Test func freshnessIsConfigurable() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let clock = Clock()
        let weather = service(cache: temporaryCache(), fixture: fixture, clock: clock, freshness: 5 * 60)
        _ = await weather.forecast(for: area)
        clock.advance(6 * 60)
        _ = await weather.forecast(for: area)
        #expect(await fixture.calls == 2)
    }

    @Test func forceRefreshBypassesAFreshCache() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let clock = Clock()
        let weather = service(cache: temporaryCache(), fixture: fixture, clock: clock)
        _ = await weather.forecast(for: area)
        clock.advance(60)
        let refreshed = await weather.forecast(for: area, forceRefresh: true)
        #expect(await fixture.calls == 2)
        #expect(refreshed.fetchedAt == clock.date)
    }

    @Test func cachedForecastNeverCallsTheNetworkAndKeepsStaleData() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let clock = Clock()
        let weather = service(cache: cache, fixture: fixture, clock: clock)
        #expect(await weather.cachedForecast(for: area) == nil)
        let stored = await weather.forecast(for: area, forceRefresh: false)
        clock.advance(5 * 3_600)
        let reopened = await service(cache: cache, fixture: fixture, clock: clock).cachedForecast(for: area)
        #expect(reopened == stored)
        #expect(await fixture.calls == 1)
    }

    @Test func exhaustedBudgetKeepsStaleDataEvenWhenForced() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let clock = Clock()
        let weather = service(cache: cache, fixture: fixture, clock: clock)
        let stored = await weather.forecast(for: area, forceRefresh: false)
        for offset in 0..<199 {
            _ = await weather.historical(for: area, at: clock.date.addingTimeInterval(-Double(offset + 1) * 3_600))
        }
        #expect(await fixture.calls == 200)
        clock.advance(60 * 60)
        let forced = await weather.forecast(for: area, forceRefresh: true)
        #expect(await fixture.calls == 200)
        #expect(forced == stored)
    }

    @Test func backOffKeepsStaleDataAndForceRefreshDoesNotRetryEarly() async throws {
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let clock = Clock()
        let seed = service(cache: cache, fixture: RequestFixture(), clock: clock)
        let stored = await seed.forecast(for: area, forceRefresh: false)
        let limited = RequestFixture(shouldBackOff: true)
        let weather = service(cache: cache, fixture: limited, clock: clock)
        clock.advance(60 * 60)
        #expect(await weather.forecast(for: area, forceRefresh: true) == stored)
        #expect(await weather.forecast(for: area, forceRefresh: true) == stored)
        #expect(await limited.calls == 1)
    }

    @Test func disconnectingClearsTheStoredForecast() async throws {
        let fixture = RequestFixture()
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        let clock = Clock()
        let key = KeyBox("fixture")
        let weather = service(cache: cache, fixture: fixture, clock: clock, key: key)
        _ = await weather.forecast(for: area)
        try await weather.disconnect()
        key.set("fixture")
        #expect(await weather.cachedForecast(for: area) == nil)
        #expect(await service(cache: cache, fixture: fixture, clock: clock).cachedForecast(for: area) == nil)
    }

    @Test func discardingAnAreaClearsOnlyItsForecast() async throws {
        let fixture = RequestFixture()
        let one = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let other = try #require(WeatherArea(latitude: 40.4, longitude: -3.7))
        let cache = temporaryCache()
        let weather = service(cache: cache, fixture: fixture, clock: Clock())
        _ = await weather.forecast(for: one)
        _ = await weather.forecast(for: other)
        await weather.discardForecast(for: one)
        #expect(await weather.cachedForecast(for: one) == nil)
        #expect(await service(cache: cache, fixture: fixture, clock: Clock()).cachedForecast(for: other) != nil)
    }

    @Test func cacheFilesWrittenBeforeForecastsWereStoredStillLoad() async throws {
        let area = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let cache = temporaryCache()
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(#"{"requestDay":19000,"attempts":7,"history":[]}"#.utf8).write(to: cache)
        let weather = service(cache: cache, fixture: RequestFixture(), clock: Clock())
        #expect(await weather.cachedForecast(for: area) == nil)
        #expect(await weather.forecast(for: area).first?.conditionCode == 800)
    }

    @Test func validatingAKeyDoesNotSaveItAndTellsRejectedFromUnavailable() async {
        let saved = SavedKey()
        func check(_ response: OpenWeatherService.Response) async -> WeatherKeyCheck {
            let weather = OpenWeatherService(
                cacheFile: temporaryCache(), readKey: { nil }, writeKey: { saved.set($0) },
                request: { _ in response }, now: { Date(timeIntervalSince1970: 1_710_000_000) }
            )
            return await weather.validate(key: "candidate")
        }
        let body = Data(#"{"data":[{"dt":1700002800,"temp":8}]}"#.utf8)
        #expect(await check(.data(body)) == .valid)
        #expect(await check(.rejected) == .rejected)
        #expect(await check(.unavailable) == .unavailable)
        #expect(await check(.backOff) == .unavailable)
        #expect(saved.value == nil)
    }

    private func temporaryCache() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "overreach-weather-test-" + UUID().uuidString)
            .appending(path: "cache.json")
    }

    private func service(
        cache: URL, fixture: RequestFixture, clock: Clock = Clock(), freshness: TimeInterval = 30 * 60,
        key: KeyBox = KeyBox("fixture")
    ) -> OpenWeatherService {
        OpenWeatherService(
            cacheFile: cache, readKey: { key.value }, writeKey: { key.set($0) },
            request: { await fixture.request($0) }, now: { clock.date }, forecastFreshness: freshness
        )
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_710_000_000)
    var date: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private final class KeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ key: String?) { stored = key }
    var value: String? { lock.withLock { stored } }
    func set(_ key: String?) { lock.withLock { stored = key } }
}

private actor RequestFixture {
    private(set) var calls = 0

    private let shouldBackOff: Bool

    init(shouldBackOff: Bool = false) {
        self.shouldBackOff = shouldBackOff
    }

    func request(_ url: URL) -> OpenWeatherService.Response {
        calls += 1
        guard !shouldBackOff else { return .backOff }
        return .data(Data("""
        {"data":[{"dt":1700002800,"temp":8,"humidity":75,"wind_speed":3,
        "pop":0.2,"weather":[{"id":800,"icon":"01d"}]}]}
        """.utf8))
    }
}

private final class SavedKey: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? { lock.withLock { stored } }
    func set(_ key: String?) { lock.withLock { stored = key } }
}

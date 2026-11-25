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
        #expect(query?.first { $0.name == "cnt" }?.value == "1")
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

    private func temporaryCache() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "overreach-weather-test-" + UUID().uuidString)
            .appending(path: "cache.json")
    }

    private func service(cache: URL, fixture: RequestFixture) -> OpenWeatherService {
        OpenWeatherService(
            cacheFile: cache, readKey: { "fixture" }, writeKey: { _ in },
            request: { await fixture.request($0) }, now: { Date(timeIntervalSince1970: 1_710_000_000) }
        )
    }
}

private actor RequestFixture {
    private(set) var calls = 0

    func request(_ url: URL) -> Data? {
        calls += 1
        return Data("""
        {"data":[{"dt":1700002800,"temp":8,"humidity":75,"wind_speed":3,
        "pop":0.2,"weather":[{"id":800,"icon":"01d"}]}]}
        """.utf8)
    }
}

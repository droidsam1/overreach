import Domain
import Foundation
import Testing
import WeatherImport

struct OpenWeatherFreeModeTests {
    private static let now = Date(timeIntervalSince1970: 1_710_000_000)
    private static let area = WeatherArea(latitude: 42.6, longitude: -8.4)

    private static let freeBody = Data("""
    {"list":[
    {"dt":1710000000,"main":{"temp":8.5,"humidity":70},"wind":{"speed":3},"pop":0.4,
     "weather":[{"id":500}],"sys":{"pod":"d"}},
    {"dt":1710010800,"main":{"temp":6},"pop":0,"weather":[{"id":800}],"sys":{"pod":"n"}}]}
    """.utf8)
    private static let oneCallBody = Data(#"{"data":[{"dt":1710000000,"temp":8}]}"#.utf8)

    @Test func freeForecastStepsLastThreeHours() throws {
        let hours = try OpenWeatherFreeForecast.decode(Self.freeBody)
        #expect(hours.count == 2)
        #expect(hours[0].temperatureCelsius == 8.5 && hours[0].humidityPercent == 70)
        #expect(hours[0].windMetersPerSecond == 3 && hours[0].precipitationProbability == 0.4)
        #expect(hours[0].conditionCode == 500 && hours[0].isDaylight == true && hours[1].isDaylight == false)
        #expect(hours[0].duration == 10_800 && hours[1].duration == 10_800)
        #expect(WeatherHour(date: Self.now).duration == 3_600)
    }

    @Test func freeRequestUsesTheFreeEndpointWithTheCoarseArea() throws {
        let area = try #require(Self.area)
        let url = try #require(OpenWeatherFreeForecast.url(for: area, key: "k"))
        #expect(url.path == "/data/2.5/forecast")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "lat" }?.value == "42.6")
        #expect(items?.first { $0.name == "units" }?.value == "metric")
    }

    @Test func aKeyWithoutOneCallFallsBackToTheFreeForecast() async {
        let calls = Calls()
        let weather = service(calls: calls) { url in
            url.path.contains("onecall") ? .rejected : .data(Self.freeBody)
        }
        #expect(await weather.validate(key: "free") == .validFree)
        #expect(calls.paths == ["/data/4.0/onecall/timeline/1h", "/data/2.5/forecast"])
    }

    @Test func fallbackAlsoCoversForbiddenAndStillRejectsBadKeys() async {
        let forbidden = service(calls: Calls()) { url in
            url.path.contains("onecall") ? .backOff : .data(Self.freeBody)
        }
        #expect(await forbidden.validate(key: "free") == .validFree)
        let bad = service(calls: Calls()) { _ in .rejected }
        #expect(await bad.validate(key: "bad") == .rejected)
        let full = service(calls: Calls()) { _ in .data(Self.oneCallBody) }
        #expect(await full.validate(key: "paid") == .valid)
        let offline = service(calls: Calls()) { _ in .unavailable }
        #expect(await offline.validate(key: "x") == .unavailable)
    }

    @Test func freeModeFetchesTheFreeForecastAndHasNoHistory() async throws {
        let calls = Calls()
        let weather = service(calls: calls) { _ in .data(Self.freeBody) }
        await weather.setMode(.free)
        #expect(await weather.provider() == .openWeatherFree)
        let area = try #require(Self.area)
        let forecast = await weather.forecast(for: area, forceRefresh: false)
        #expect(forecast.hours.count == 2 && forecast.hours[0].duration == 10_800)
        #expect(calls.paths == ["/data/2.5/forecast"])

        let past = await weather.historical(for: area, at: Self.now.addingTimeInterval(-7_200))
        #expect(past == nil)
        #expect(calls.paths.count == 1)
    }

    @Test func changingModeDropsStoredForecastsAndDisconnectingResetsIt() async throws {
        let weather = service(calls: Calls()) { url in
            url.path.contains("onecall") ? .data(Self.oneCallBody) : .data(Self.freeBody)
        }
        let area = try #require(Self.area)
        _ = await weather.forecast(for: area)
        #expect(await weather.cachedForecast(for: area) != nil)
        await weather.setMode(.free)
        #expect(await weather.cachedForecast(for: area) == nil)
        try await weather.disconnect()
        #expect(await weather.mode() == .oneCall)
    }

    private func service(
        calls: Calls, respond: @escaping @Sendable (URL) -> OpenWeatherService.Response
    ) -> OpenWeatherService {
        let cache = FileManager.default.temporaryDirectory.appending(path: "overreach-free-" + UUID().uuidString)
            .appending(path: "cache.json")
        return OpenWeatherService(
            cacheFile: cache, readKey: { "key" }, writeKey: { _ in },
            request: { calls.record($0); return respond($0) }, now: { Self.now }
        )
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var paths: [String] { lock.withLock { urls.map(\.path) } }
    func record(_ url: URL) { lock.withLock { urls.append(url) } }
}

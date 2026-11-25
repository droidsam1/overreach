import Domain
import Foundation
import Testing
import WeatherImport

struct OpenMeteoTests {
    private static let area = WeatherArea(latitude: 42.573, longitude: -8.387)
    private static let now = Date(timeIntervalSince1970: 1_710_000_000)

    private static let body = Data("""
    {"hourly":{"time":[1710000000,1710003600,1710007200],
    "temperature_2m":[8.4,null,9],"relative_humidity_2m":[70,71,72],"wind_speed_10m":[3,4,5],
    "precipitation_probability":[20,0,100],"weather_code":[0,61,95],"is_day":[1,1,0]}}
    """.utf8)

    @Test func wmoCodesMapToTheOpenWeatherConditionsTheAppUnderstands() {
        let expected: [Int: Int] = [
            0: 800, 1: 801, 2: 802, 3: 804, 45: 741, 48: 741, 51: 301, 55: 301, 56: 311, 61: 500, 63: 501, 65: 502,
            66: 511, 67: 511, 71: 600, 73: 601, 75: 602, 77: 600, 80: 520, 81: 521, 82: 522, 85: 620, 86: 621,
            95: 211, 96: 202, 97: 212, 99: 202,
        ]
        for (wmo, code) in expected {
            #expect(OpenMeteoForecast.conditionCode(wmo: wmo) == code, "WMO \(wmo)")
        }
        #expect(OpenMeteoForecast.conditionCode(wmo: 4) == nil)
        let groups = expected.filter { [0, 1, 2, 3].contains($0.key) }.values
        #expect(groups.allSatisfy { (800...804).contains($0) })
    }

    @Test func hourlyResponseKeepsNullsAndConvertsUnits() throws {
        let hours = try OpenMeteoForecast.decode(Self.body)
        #expect(hours.count == 3)
        #expect(hours[0].temperatureCelsius == 8.4)
        #expect(hours[1].temperatureCelsius == nil)
        #expect(hours[0].precipitationProbability == 0.2)
        #expect(hours[2].precipitationProbability == 1)
        #expect(hours[0].conditionCode == 800 && hours[1].conditionCode == 500 && hours[2].conditionCode == 211)
        #expect(hours[0].isDaylight == true && hours[2].isDaylight == false)
        #expect(hours[0].windMetersPerSecond == 3)
        #expect(hours[0].date == Date(timeIntervalSince1970: 1_710_000_000))
        #expect(hours[0].duration == 3_600)
    }

    @Test func archiveResponsesWithoutProbabilityDecode() throws {
        let archive = Data(
            #"{"hourly":{"time":[1700000000],"temperature_2m":[5],"weather_code":[3],"is_day":[0]}}"#.utf8
        )
        let hour = try #require(OpenMeteoForecast.decode(archive).first)
        #expect(hour.precipitationProbability == nil)
        #expect(hour.conditionCode == 804 && hour.isDaylight == false)
    }

    @Test func requestsCarryOnlyTheCoarseAreaAndWeatherVariables() throws {
        let area = try #require(Self.area)
        let forecast = try #require(OpenMeteoForecast.forecastURL(for: area))
        #expect(forecast.host == "api.open-meteo.com" && forecast.path == "/v1/forecast")
        let names = Set(URLComponents(url: forecast, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? [])
        #expect(names == [
            "latitude", "longitude", "hourly", "forecast_days", "timeformat", "wind_speed_unit", "timezone",
        ])
        let items = URLComponents(url: forecast, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "latitude" }?.value == "42.6")
        #expect(items?.first { $0.name == "longitude" }?.value == "-8.4")
        let hourly = items?.first { $0.name == "hourly" }?.value ?? ""
        for variable in ["temperature_2m", "precipitation_probability", "weather_code", "is_day"] {
            #expect(hourly.contains(variable))
        }
        #expect(!forecast.absoluteString.lowercased().contains("key"))

        let day = Date(timeIntervalSince1970: 1_700_003_020)
        let archive = try #require(OpenMeteoForecast.archiveURL(for: area, day: day))
        #expect(archive.host == "archive-api.open-meteo.com" && archive.path == "/v1/archive")
        let archiveItems = URLComponents(url: archive, resolvingAgainstBaseURL: false)?.queryItems
        #expect(archiveItems?.first { $0.name == "start_date" }?.value == "2023-11-14")
        #expect(archiveItems?.first { $0.name == "end_date" }?.value == "2023-11-14")
        #expect(archiveItems?.first { $0.name == "hourly" }?.value?.contains("precipitation_probability") == false)
    }

    @Test func forecastIsCachedAndSurvivesRestart() async throws {
        let area = try #require(Self.area)
        let log = URLLog(responses: [.data(Self.body)])
        let cache = temporaryCache()
        let service = makeService(cache: cache, log: log)
        let first = await service.forecast(for: area, forceRefresh: false)
        #expect(first.hours.count == 3 && first.fetchedAt == Self.now)
        _ = await service.forecast(for: area, forceRefresh: false)
        let reopened = makeService(cache: cache, log: log)
        #expect(await reopened.cachedForecast(for: area) == first)
        #expect(await reopened.forecast(for: area, forceRefresh: false) == first)
        #expect(log.urls.count == 1)
        _ = await reopened.forecast(for: area, forceRefresh: true)
        #expect(log.urls.count == 2)
    }

    @Test func recentRunsUsePastDaysAndOlderRunsUseTheArchive() async throws {
        let area = try #require(Self.area)
        let log = URLLog()
        let service = makeService(cache: temporaryCache(), log: log)
        let recent = await service.historical(for: area, at: Self.now.addingTimeInterval(-1_000))
        #expect(recent?.conditionCode == 800)
        #expect(log.urls.last?.path == "/v1/forecast")
        #expect(log.urls.last?.query?.contains("past_days=7") == true)

        let old = Date(timeIntervalSince1970: 1_700_000_000)
        _ = await service.historical(for: area, at: old)
        #expect(log.urls.last?.host == "archive-api.open-meteo.com")
        let again = await service.historical(for: area, at: Self.now.addingTimeInterval(-1_000))
        #expect(again == recent)
        #expect(log.urls.count == 2)
    }

    @Test func failuresBackOffAndKeepStoredForecast() async throws {
        let area = try #require(Self.area)
        let log = URLLog(responses: [.data(Self.body), .backOff, .backOff])
        let service = makeService(cache: temporaryCache(), log: log)
        let stored = await service.forecast(for: area, forceRefresh: false)
        #expect(await service.forecast(for: area, forceRefresh: true) == stored)
        #expect(await service.forecast(for: area, forceRefresh: true) == stored)
        #expect(log.urls.count == 2)
    }

    @Test func discardingForgetsTheStoredForecast() async throws {
        let area = try #require(Self.area)
        let service = makeService(cache: temporaryCache(), log: URLLog())
        _ = await service.forecast(for: area)
        await service.discardAllForecasts()
        #expect(await service.cachedForecast(for: area) == nil)
        #expect(await service.provider() == .openMeteo)
    }

    private func temporaryCache() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "overreach-meteo-test-" + UUID().uuidString)
            .appending(path: "cache.json")
    }

    private func makeService(cache: URL, log: URLLog) -> OpenMeteoService {
        OpenMeteoService(cacheFile: cache, request: { log.record($0) }, now: { Self.now })
    }
}

private final class URLLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    private var queue: [OpenWeatherService.Response]

    init(responses: [OpenWeatherService.Response] = []) { queue = responses }

    var urls: [URL] { lock.withLock { recorded } }

    func record(_ url: URL) -> OpenWeatherService.Response {
        lock.withLock {
            recorded.append(url)
            if !queue.isEmpty { return queue.removeFirst() }
            return .data(Data("""
            {"hourly":{"time":[1709996400,1710000000],"temperature_2m":[7,8],"weather_code":[0,0],"is_day":[1,1],
            "precipitation_probability":[0,0]}}
            """.utf8))
        }
    }
}

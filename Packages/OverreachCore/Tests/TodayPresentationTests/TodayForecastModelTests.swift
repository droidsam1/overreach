import Domain
import Foundation
import PresentationKit
import Testing
import TodayPresentation

@MainActor
@Suite("Weather today")
struct TodayForecastModelTests {
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .current

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar
    }

    private func date(_ hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test func groupsConsecutiveDryHoursWithoutPromisingSunAfterDark() async throws {
        let source = Source(hours: [
            WeatherHour(date: date(8), conditionCode: 800, precipitationProbability: 0, isDaylight: true),
            WeatherHour(date: date(9), temperatureCelsius: 12, conditionCode: 801,
                        precipitationProbability: 0.1, isDaylight: true),
            WeatherHour(date: date(10), conditionCode: 803, precipitationProbability: 0.25, isDaylight: true),
            WeatherHour(date: date(11), conditionCode: 500, precipitationProbability: 0, isDaylight: true),
            WeatherHour(date: date(12), conditionCode: 800, isDaylight: true),
            WeatherHour(date: date(21), conditionCode: 800, precipitationProbability: 0, isDaylight: false),
            WeatherHour(date: date(24), conditionCode: 800, precipitationProbability: 0, isDaylight: true),
        ])
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let model = TodayForecastModel(
            source: source, area: area, calendar: calendar, locate: { nil }, storeArea: { _ in }
        )
        let now = date(9, minute: 30)
        await model.load(now: now)

        #expect(model.hours.map(\.id) == [date(9), date(10), date(11), date(12), date(21)])
        #expect(model.toolbarTemperature == "12 °C")
        #expect(model.dryWindows.map(\.start) == [now, date(21)])
        #expect(model.dryWindows.map(\.end) == [date(11), date(22)])
        #expect(model.sunnyWindows.map(\.start) == [now])
        #expect(model.sunnyWindows.map(\.end) == [date(10)])
    }

    @Test func checksConsentAndOnlyLooksUpWeatherWithAStoredArea() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let source = Source(hours: [])
        var saved: WeatherArea?
        let model = TodayForecastModel(source: source, locate: { area }, storeArea: { saved = $0 })
        await model.load()
        #expect(model.isConfigured)
        #expect(await source.requests.isEmpty)

        await model.useCurrentArea()
        #expect(model.area == area)
        #expect(saved == area)
        #expect(await source.requests == [area])

        await model.removeArea()
        #expect(model.area == nil)
        #expect(saved == nil)
        await model.load()
        #expect(await source.requests == [area])
    }

    @Test func skipsForecastWhenAKeyHasNotBeenConfigured() async throws {
        let source = Source(hours: [], configured: false)
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let model = TodayForecastModel(source: source, area: area, locate: { nil }, storeArea: { _ in })
        await model.load()
        #expect(!model.isConfigured)
        #expect(await source.requests.isEmpty)
    }

    @Test func showsTheStoredForecastAtOnceThenReplacesItWithTheRefreshedOne() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let now = date(9, minute: 30)
        let stale = WeatherForecast(
            hours: [WeatherHour(date: date(9), temperatureCelsius: 10, conditionCode: 800)],
            fetchedAt: date(6)
        )
        let fresh = WeatherForecast(
            hours: [WeatherHour(date: date(9), temperatureCelsius: 14, conditionCode: 800)],
            fetchedAt: date(9, minute: 29)
        )
        let source = StoredSource(stored: stale, refreshed: fresh)
        let model = TodayForecastModel(
            source: source, area: area, calendar: calendar, format: Format(locale: Locale(identifier: "en_GB")),
            locate: { nil }, storeArea: { _ in }
        )
        await source.hold()
        let loading = Task { await model.load(now: now) }
        while await !source.isWaiting { await Task.yield() }
        #expect(model.toolbarTemperature == "10 °C")
        #expect(model.updatedAt == date(6))
        #expect(model.updatedText?.hasPrefix("Updated ") == true)
        #expect(model.updatedText?.contains(":00") == true)
        await source.release()
        await loading.value
        #expect(model.toolbarTemperature == "14 °C")
        #expect(model.updatedAt == date(9, minute: 29))
        #expect(model.updatedText?.contains(":29") == true)
    }

    @Test func pullToRefreshForcesTheSourceAndAPlainLoadDoesNot() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let forecast = WeatherForecast(hours: [WeatherHour(date: date(10), conditionCode: 800)], fetchedAt: date(9))
        let source = StoredSource(stored: nil, refreshed: forecast)
        let model = TodayForecastModel(
            source: source, area: area, calendar: calendar, locate: { nil }, storeArea: { _ in }
        )
        await model.load(now: date(9, minute: 30))
        await model.load(now: date(9, minute: 30), forceRefresh: true)
        #expect(await source.forceFlags == [false, true])
    }

    @Test func aFailedRefreshKeepsTheForecastOnScreen() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let forecast = WeatherForecast(hours: [WeatherHour(date: date(10), conditionCode: 800)], fetchedAt: date(9))
        let source = StoredSource(stored: forecast, refreshed: forecast)
        let model = TodayForecastModel(
            source: source, area: area, calendar: calendar, locate: { nil }, storeArea: { _ in }
        )
        await model.load(now: date(9, minute: 30))
        #expect(model.hours.count == 1)
        await source.setRefreshed(WeatherForecast(hours: []))
        await model.load(now: date(9, minute: 40), forceRefresh: true)
        #expect(model.hours.count == 1)
        #expect(model.updatedAt == date(9))
    }

    @Test func removingOrChangingTheAreaDiscardsItsStoredForecast() async throws {
        let first = try #require(WeatherArea(latitude: 40, longitude: -3))
        let second = try #require(WeatherArea(latitude: 42.6, longitude: -8.4))
        let forecast = WeatherForecast(hours: [WeatherHour(date: date(10), conditionCode: 800)], fetchedAt: date(9))
        let source = StoredSource(stored: nil, refreshed: forecast)
        let model = TodayForecastModel(
            source: source, area: first, calendar: calendar, locate: { second }, storeArea: { _ in }
        )
        await model.useCurrentArea()
        #expect(await source.discarded == [first])
        await model.removeArea()
        #expect(await source.discarded == [first, second])
        #expect(model.updatedAt == nil && model.hours.isEmpty)
    }

    @Test func toolbarStateFollowsKeyAreaAndForecast() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let forecast = WeatherForecast(
            hours: [WeatherHour(date: date(10), temperatureCelsius: 14, conditionCode: 801, isDaylight: true)],
            fetchedAt: date(9)
        )
        let now = date(9, minute: 30)

        let source = StoredSource(stored: nil, refreshed: forecast)
        let model = TodayForecastModel(
            source: source, calendar: calendar, locate: { area }, storeArea: { _ in }
        )
        #expect(model.toolbarState == .loading)
        await model.load(now: now)
        #expect(model.toolbarState == .needsArea)
        #expect(model.toolbarAccessibilityValue == "Weather area not set")

        await model.useCurrentArea()
        await model.load(now: now)
        #expect(model.toolbarState == .ready)
        #expect(model.toolbarSky == .partlyCloudy)
        #expect(model.toolbarSymbol == "cloud.sun")
        #expect(model.toolbarAccessibilityLabel == "Weather today")
        #expect(model.toolbarAccessibilityValue == "14 °C, Partly cloudy")

        await model.removeArea()
        #expect(model.toolbarState == .needsArea)
        #expect(model.toolbarSky == nil)
    }

    @Test func toolbarIsNotConnectedWithoutAKeyWhateverTheAreaIs() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let model = TodayForecastModel(
            source: Source(hours: [], configured: false), area: area, locate: { nil }, storeArea: { _ in }
        )
        await model.load()
        #expect(model.toolbarState == .notConnected)
        #expect(model.toolbarAccessibilityLabel == "Weather not connected")
        #expect(model.toolbarAccessibilityValue.isEmpty)
        #expect(model.toolbarSky == nil)
    }

    @Test func toolbarShowsLoadingThenUnavailableWhenTheForecastIsEmpty() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let source = StoredSource(stored: nil, refreshed: WeatherForecast(hours: []))
        let model = TodayForecastModel(source: source, area: area, locate: { nil }, storeArea: { _ in })
        await source.hold()
        let loading = Task { await model.load() }
        while await !source.isWaiting { await Task.yield() }
        #expect(model.toolbarState == .loading)
        #expect(model.toolbarAccessibilityValue == "Loading weather")
        await source.release()
        await loading.value
        #expect(model.toolbarState == .unavailable)
        #expect(model.toolbarAccessibilityValue == "Forecast unavailable")
    }

    @Test func toolbarSkyDistinguishesRainSnowStormAndNight() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let cases: [(Int, Bool, TodayForecastModel.Sky)] = [
            (800, true, .clear), (800, false, .clearNight), (802, false, .partlyCloudyNight),
            (804, true, .cloudy), (501, true, .rain), (211, true, .thunderstorm), (601, true, .snow),
            (741, true, .fog),
        ]
        for (code, daylight, expected) in cases {
            let forecast = WeatherForecast(
                hours: [WeatherHour(date: date(10), conditionCode: code, isDaylight: daylight)], fetchedAt: date(9)
            )
            let model = TodayForecastModel(
                source: StoredSource(stored: nil, refreshed: forecast), area: area, calendar: calendar,
                locate: { nil }, storeArea: { _ in }
            )
            await model.load(now: date(9, minute: 30))
            #expect(model.toolbarSky == expected)
        }
    }

    private actor StoredSource: WeatherSource {
        private let stored: WeatherForecast?
        private var refreshed: WeatherForecast
        private var holding = false
        private(set) var isWaiting = false
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var forceFlags: [Bool] = []
        private(set) var discarded: [WeatherArea] = []

        init(stored: WeatherForecast?, refreshed: WeatherForecast) {
            self.stored = stored
            self.refreshed = refreshed
        }

        func hold() { holding = true }
        func release() {
            holding = false
            gate?.resume()
            gate = nil
        }
        func setRefreshed(_ forecast: WeatherForecast) { refreshed = forecast }

        func cachedForecast(for area: WeatherArea) async -> WeatherForecast? { stored }

        func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast {
            forceFlags.append(forceRefresh)
            if holding {
                isWaiting = true
                await withCheckedContinuation { gate = $0 }
                isWaiting = false
            }
            return refreshed
        }

        func forecast(for area: WeatherArea) async -> [WeatherHour] { refreshed.hours }
        func discardForecast(for area: WeatherArea) async { discarded.append(area) }
        func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? { nil }
    }

    private actor Source: WeatherSource {
        private let hours: [WeatherHour]
        private let configured: Bool
        private(set) var requests: [WeatherArea] = []

        init(hours: [WeatherHour], configured: Bool = true) {
            self.hours = hours
            self.configured = configured
        }

        func isConfigured() async -> Bool { configured }

        func forecast(for area: WeatherArea) async -> [WeatherHour] {
            requests.append(area)
            return hours
        }

        func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? { nil }
    }
}

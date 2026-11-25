import Domain
import Foundation
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

        model.removeArea()
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

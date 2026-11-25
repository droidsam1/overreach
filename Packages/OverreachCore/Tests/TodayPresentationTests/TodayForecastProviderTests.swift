import Domain
import Foundation
import PresentationKit
import Testing
import TodayPresentation

@MainActor
@Suite("Weather today with each provider")
struct TodayForecastProviderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test func threeHourStepsCoverThreeHoursInTheDryWindows() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let step = 3 * 3_600.0
        let hours = [
            WeatherHour(date: date(9), conditionCode: 800, precipitationProbability: 0, isDaylight: true,
                        durationSeconds: step),
            WeatherHour(date: date(12), conditionCode: 500, precipitationProbability: 0.8, isDaylight: true,
                        durationSeconds: step),
            WeatherHour(date: date(15), conditionCode: 801, precipitationProbability: 0.1, isDaylight: true,
                        durationSeconds: step),
        ]
        let model = TodayForecastModel(
            source: ProviderSource(provider: .openWeatherFree, hours: hours), area: area, calendar: calendar,
            locate: { nil }, storeArea: { _ in }
        )
        await model.load(now: date(10, minute: 30))

        // The 09:00 step still runs until 12:00, so it stays; the stepped windows are three hours long.
        #expect(model.hours.map(\.id) == [date(9), date(12), date(15)])
        #expect(model.dryWindows.map(\.start) == [date(10, minute: 30), date(15)])
        #expect(model.dryWindows.map(\.end) == [date(12), date(18)])
        #expect(model.sunnyWindows.map(\.end) == [date(12), date(18)])
        #expect(model.resolutionNote != nil)
    }

    @Test func attributionAndStateFollowTheActiveProvider() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let hour = WeatherHour(date: date(10), temperatureCelsius: 10, conditionCode: 800, isDaylight: true)
        let meteo = TodayForecastModel(
            source: ProviderSource(provider: .openMeteo, hours: [hour]), area: area, calendar: calendar,
            locate: { nil }, storeArea: { _ in }
        )
        await meteo.load(now: date(9))
        #expect(meteo.provider == .openMeteo)
        #expect(meteo.attributionURL?.host == "open-meteo.com")
        #expect(meteo.attributionTitle.contains("Open-Meteo"))
        #expect(meteo.resolutionNote == nil)

        let openWeather = TodayForecastModel(
            source: ProviderSource(provider: .openWeatherOneCall, hours: [hour]), area: area, calendar: calendar,
            locate: { nil }, storeArea: { _ in }
        )
        await openWeather.load(now: date(9))
        #expect(openWeather.attributionURL?.host == "openweathermap.org")
    }

    @Test func switchingProviderDropsTheOldProvidersHours() async throws {
        let area = try #require(WeatherArea(latitude: 40, longitude: -3))
        let hour = WeatherHour(date: date(10), temperatureCelsius: 10, conditionCode: 800, isDaylight: true)
        let source = ProviderSource(provider: .openWeatherOneCall, hours: [hour])
        let model = TodayForecastModel(
            source: source, area: area, calendar: calendar, locate: { nil }, storeArea: { _ in }
        )
        await model.load(now: date(9))
        #expect(model.toolbarState == .ready)

        await source.change(provider: .openMeteo, hours: [], configured: false)
        await model.load(now: date(9))
        #expect(model.provider == .openMeteo)
        #expect(model.toolbarState == .notConnected && model.hours.isEmpty)
    }
}

private actor ProviderSource: WeatherSource {
    private var active: WeatherProvider
    private var hours: [WeatherHour]
    private var configured: Bool

    init(provider: WeatherProvider, hours: [WeatherHour], configured: Bool = true) {
        active = provider
        self.hours = hours
        self.configured = configured
    }

    func change(provider: WeatherProvider, hours: [WeatherHour], configured: Bool) {
        active = provider
        self.hours = hours
        self.configured = configured
    }

    func isConfigured() async -> Bool { configured }
    func provider() async -> WeatherProvider { active }
    func forecast(for area: WeatherArea) async -> [WeatherHour] { hours }
    func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? { nil }
}

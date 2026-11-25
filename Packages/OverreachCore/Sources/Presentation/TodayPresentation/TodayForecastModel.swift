import Domain
import Foundation
import Observation
import PresentationKit

@MainActor
@Observable
public final class TodayForecastModel {
    public struct Hour: Identifiable, Sendable {
        public let id: Date
        public let temperature: String?
        public let conditions: String?
        public let precipitation: String?
        public let symbol: String
    }

    public struct Window: Identifiable, Sendable {
        public let start: Date
        public let end: Date
        public var id: Date { start }
    }

    private struct Periods {
        let dry: [Window]
        let sunny: [Window]
    }

    public private(set) var isConfigured = false
    public private(set) var area: WeatherArea?
    public private(set) var hours: [Hour] = []
    public private(set) var dryWindows: [Window] = []
    public private(set) var sunnyWindows: [Window] = []
    public private(set) var isLoading = false
    /// When the shown forecast was fetched. It can be hours old while a refresh runs or the network is down.
    public private(set) var updatedAt: Date?
    public private(set) var isLocating = false
    public private(set) var locationUnavailable = false

    private let source: any WeatherSource
    private let locate: @MainActor () async -> WeatherArea?
    private let storeArea: @MainActor (WeatherArea?) -> Void
    private let calendar: Calendar
    private let format: Format
    private var loadID = UUID()

    public init(
        source: any WeatherSource, area: WeatherArea? = nil, calendar: Calendar = .current,
        format: Format = Format(), locate: @escaping @MainActor () async -> WeatherArea?,
        storeArea: @escaping @MainActor (WeatherArea?) -> Void
    ) {
        self.source = source
        self.area = area
        self.calendar = calendar
        self.format = format
        self.locate = locate
        self.storeArea = storeArea
    }

    public static let attributionURL = URL(string: "https://openweathermap.org/")
    /// "Updated 14:05" for the forecast on screen, nil when its age is unknown.
    public var updatedText: String? {
        guard let updatedAt, !hours.isEmpty else { return nil }
        let style = Date.FormatStyle(
            date: .omitted, time: .shortened, locale: format.locale, calendar: calendar, timeZone: calendar.timeZone
        )
        return L10n.format("Updated {1}", updatedAt.formatted(style))
    }

    public var toolbarSymbol: String { hours.first?.symbol ?? "cloud.sun" }
    public var toolbarTemperature: String? { hours.first?.temperature }

    public func useCurrentArea() async {
        guard !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        guard let area = await locate() else {
            locationUnavailable = true
            return
        }
        locationUnavailable = false
        if let previous = self.area, previous != area {
            clearHours()
            await source.discardForecast(for: previous)
        }
        self.area = area
        storeArea(area)
        await load()
    }

    public func removeArea() async {
        loadID = UUID()
        let removed = area
        area = nil
        isLoading = false
        locationUnavailable = false
        storeArea(nil)
        clearHours()
        if let removed { await source.discardForecast(for: removed) }
    }

    /// Shows the stored forecast first, then asks the source, which only goes to the network when the stored one
    /// is stale. `forceRefresh` (pull to refresh) skips that freshness check, not the source's request budget.
    public func load(now: Date = .now, forceRefresh: Bool = false) async {
        let id = UUID()
        loadID = id
        let configured = await source.isConfigured()
        guard loadID == id else { return }
        isConfigured = configured
        guard configured, let area else {
            isLoading = false
            clearHours()
            return
        }
        isLoading = true
        if hours.isEmpty, let stored = await source.cachedForecast(for: area) {
            guard loadID == id else { return }
            apply(stored, now: now)
        }
        let forecast = await source.forecast(for: area, forceRefresh: forceRefresh)
        guard loadID == id else { return }
        isLoading = false
        apply(forecast, now: now)
    }

    private func clearHours() {
        updatedAt = nil
        hours = []
        dryWindows = []
        sunnyWindows = []
    }

    private func apply(_ forecast: WeatherForecast, now: Date) {
        // A failed refresh returns nothing: keep what is shown rather than blanking the screen.
        if forecast.hours.isEmpty, !hours.isEmpty { return }
        updatedAt = forecast.fetchedAt
        apply(forecast.hours, now: now)
    }

    private func apply(_ forecast: [WeatherHour], now: Date) {
        guard let today = calendar.dateInterval(of: .day, for: now) else {
            clearHours()
            return
        }
        var seen: Set<Date> = []
        let remaining = forecast.sorted { $0.date < $1.date }.filter {
            $0.date.addingTimeInterval(3_600) > now && $0.date < today.end && seen.insert($0.date).inserted
        }
        hours = remaining.map(hour)
        let periods = periods(in: remaining, now: now, end: today.end)
        dryWindows = periods.dry
        sunnyWindows = periods.sunny
    }

    private func periods(in hours: [WeatherHour], now: Date, end: Date) -> Periods {
        let dry = hours.filter { isLikelyDry($0) }
        let sunny = dry.filter { $0.isDaylight == true && ($0.conditionCode == 800 || $0.conditionCode == 801) }
        return Periods(dry: windows(dry, now: now, end: end), sunny: windows(sunny, now: now, end: end))
    }

    private func isLikelyDry(_ hour: WeatherHour) -> Bool {
        guard let probability = hour.precipitationProbability, (0...0.25).contains(probability) else { return false }
        guard let code = hour.conditionCode else { return true }
        return (700...804).contains(code)
    }

    private func windows(_ hours: [WeatherHour], now: Date, end: Date) -> [Window] {
        var windows: [Window] = []
        for hour in hours {
            let start = max(now, hour.date)
            let stop = min(end, hour.date.addingTimeInterval(3_600))
            guard start < stop else { continue }
            if let previous = windows.last, previous.end == start {
                windows[windows.count - 1] = Window(start: previous.start, end: stop)
            } else {
                windows.append(Window(start: start, end: stop))
            }
        }
        return windows
    }

    private func hour(_ value: WeatherHour) -> Hour {
        let sky = sky(value.conditionCode, daylight: value.isDaylight)
        let temperature = value.temperatureCelsius.map { format.number($0, maxFractionDigits: 0) + " °C" }
        let precipitation = value.precipitationProbability
            .flatMap { (0...1).contains($0) ? $0 : nil }
            .map {
                let percentage = $0.formatted(.percent.precision(.fractionLength(0)).locale(format.locale))
                return L10n.format("Chance of precipitation {1}", percentage)
            }
        return Hour(
            id: value.date, temperature: temperature, conditions: sky?.text, precipitation: precipitation,
            symbol: sky?.symbol ?? "cloud"
        )
    }

    private func sky(_ code: Int?, daylight: Bool?) -> (text: String, symbol: String)? {
        guard let code else { return nil }
        switch code {
        case 200...299: return (L10n.text("Thunderstorms"), "cloud.bolt.rain")
        case 300...599: return (L10n.text("Rain or drizzle"), "cloud.rain")
        case 600...699: return (L10n.text("Snow"), "cloud.snow")
        case 700...799: return (L10n.text("Reduced visibility"), "cloud.fog")
        case 800: return (L10n.text("Clear sky"), daylight == false ? "moon.stars" : "sun.max")
        case 801...802: return (L10n.text("Partly cloudy"), daylight == false ? "cloud.moon" : "cloud.sun")
        case 803...804: return (L10n.text("Cloudy"), "cloud")
        default: return nil
        }
    }
}

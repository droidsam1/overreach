import Domain
import Foundation

/// Open-Meteo forecast and history with a persistent cache and a per-install daily request budget.
/// It needs no key, so it is always "configured"; whether the person agreed to use it is `WeatherProviders`' job.
public actor OpenMeteoService: WeatherSource {
    private struct Cache: Codable {
        var requestDay: TimeInterval = 0
        var attempts = 0
        var history: [HistoryEntry] = []
        var forecasts: [ForecastEntry] = []
    }

    private struct ForecastEntry: Codable {
        let area: WeatherArea
        let fetchedAt: Date
        let hours: [WeatherHour]
    }

    private struct HistoryEntry: Codable {
        let area: WeatherArea
        let hour: TimeInterval
        let value: WeatherHour
    }

    private let cacheFile: URL
    private let request: @Sendable (URL) async -> OpenWeatherService.Response
    private let now: @Sendable () -> Date
    private let forecastFreshness: TimeInterval
    private var cache: Cache
    private var nextRequestDate: Date?
    private var retryAfter: [String: Date] = [:]
    private static let dailyLimit = 200
    private static let maximumHistory = 512
    private static let maximumForecasts = 4

    public init(
        cacheFile: URL,
        request: @escaping @Sendable (URL) async -> OpenWeatherService.Response,
        now: @escaping @Sendable () -> Date = Date.init,
        forecastFreshness: TimeInterval = 30 * 60
    ) {
        self.cacheFile = cacheFile
        self.request = request
        self.now = now
        self.forecastFreshness = forecastFreshness
        let data = try? Data(contentsOf: cacheFile)
        self.cache = data.flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } ?? Cache()
    }

    public func provider() async -> WeatherProvider { .openMeteo }

    public func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? {
        let hour = OpenWeatherTimeline.hour(date)
        let current = now()
        guard hour.isFinite, date < current else { return nil }
        if let item = cache.history.first(where: { $0.area == area && $0.hour == hour }) { return item.value }
        let recent = current.timeIntervalSince(date) < OpenMeteoForecast.archiveDelay
        let url = recent ? OpenMeteoForecast.forecastURL(for: area, pastDays: 7)
            : OpenMeteoForecast.archiveURL(for: area, day: date)
        let hours = await fetch(url, label: "history \(area) \(hour)")
        guard let result = hours.first(where: { OpenWeatherTimeline.hour($0.date) == hour }),
              result.temperatureCelsius != nil || result.conditionCode != nil else { return nil }
        cache.history.append(HistoryEntry(area: area, hour: hour, value: result))
        if cache.history.count > Self.maximumHistory {
            cache.history.removeFirst(cache.history.count - Self.maximumHistory)
        }
        try? persist()
        return result
    }

    public func forecast(for area: WeatherArea) async -> [WeatherHour] {
        await forecast(for: area, forceRefresh: false).hours
    }

    public func cachedForecast(for area: WeatherArea) async -> WeatherForecast? {
        storedForecast(for: area).map { WeatherForecast(hours: $0.hours, fetchedAt: $0.fetchedAt) }
    }

    public func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast {
        let stored = storedForecast(for: area)
        let kept = stored.map { WeatherForecast(hours: $0.hours, fetchedAt: $0.fetchedAt) }
            ?? WeatherForecast(hours: [])
        if !forceRefresh, let stored, isFresh(stored) { return kept }
        let hours = await fetch(OpenMeteoForecast.forecastURL(for: area), label: "forecast \(area)")
        guard !hours.isEmpty else { return kept }
        let fetchedAt = now()
        cache.forecasts.removeAll { $0.area == area }
        cache.forecasts.append(ForecastEntry(area: area, fetchedAt: fetchedAt, hours: hours))
        if cache.forecasts.count > Self.maximumForecasts {
            cache.forecasts.removeFirst(cache.forecasts.count - Self.maximumForecasts)
        }
        try? persist()
        return WeatherForecast(hours: hours, fetchedAt: fetchedAt)
    }

    public func discardForecast(for area: WeatherArea) async {
        guard cache.forecasts.contains(where: { $0.area == area }) else { return }
        cache.forecasts.removeAll { $0.area == area }
        try? persist()
    }

    public func discardAllForecasts() async {
        guard !cache.forecasts.isEmpty else { return }
        cache.forecasts.removeAll()
        try? persist()
    }

    private func storedForecast(for area: WeatherArea) -> ForecastEntry? {
        cache.forecasts.first { $0.area == area }
    }

    private func isFresh(_ entry: ForecastEntry) -> Bool {
        let age = now().timeIntervalSince(entry.fetchedAt)
        return age >= 0 && age < forecastFreshness
    }

    private func fetch(_ url: URL?, label: String) async -> [WeatherHour] {
        let date = now()
        retryAfter = retryAfter.filter { $0.value > date }
        guard let url, nextRequestDate.map({ date >= $0 }) ?? true, retryAfter[label] == nil,
              reserveAttempt(at: date) else { return [] }
        let retry = date.addingTimeInterval(30 * 60)
        switch await request(url) {
        case let .data(data):
            let hours = (try? OpenMeteoForecast.decode(data)) ?? []
            if hours.isEmpty { retryAfter[label] = retry }
            return hours
        case .backOff, .rejected:
            nextRequestDate = retry
            return []
        case .unavailable:
            retryAfter[label] = retry
            return []
        }
    }

    private func reserveAttempt(at date: Date) -> Bool {
        let day = (date.timeIntervalSince1970 / 86_400).rounded(.down)
        if cache.requestDay < day {
            cache.requestDay = day
            cache.attempts = 0
        }
        guard cache.attempts < Self.dailyLimit else { return false }
        cache.attempts += 1
        return (try? persist()) != nil
    }

    private func persist() throws {
        var folder = cacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var options = URLResourceValues()
        options.isExcludedFromBackup = true
        try? folder.setResourceValues(options)
        try JSONEncoder().encode(cache).write(to: cacheFile, options: .atomic)
    }
}

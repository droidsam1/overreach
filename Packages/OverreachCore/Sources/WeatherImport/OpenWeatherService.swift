import Domain
import Foundation

/// Which OpenWeather endpoints a key can use.
public enum OpenWeatherMode: String, Codable, Sendable {
    /// One Call timeline: hourly forecast and history. Needs a One Call subscription.
    case oneCall
    /// Free 5-day forecast in 3-hour steps; no history.
    case free
}

/// Shared client for historical and forecast requests, including their persistent per-install budget.
public actor OpenWeatherService: WeatherSource, WeatherCredentials {
    public enum Response: Sendable {
        case data(Data)
        case backOff
        /// The provider refused the key (HTTP 401). Backs off like `backOff`.
        case rejected
        case unavailable
    }

    private struct Reply: Sendable {
        var hours: [WeatherHour] = []
        var shouldBackOff = false
    }
    private enum ClientError: Error {
        case emptyKey
    }

    private struct Cache: Codable {
        var requestDay: TimeInterval = 0
        var attempts = 0
        var history: [HistoryEntry] = []
        var forecasts: [ForecastEntry] = []
        var mode = OpenWeatherMode.oneCall

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requestDay = try container.decodeIfPresent(TimeInterval.self, forKey: .requestDay) ?? 0
            attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
            history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
            forecasts = try container.decodeIfPresent([ForecastEntry].self, forKey: .forecasts) ?? []
            mode = try container.decodeIfPresent(OpenWeatherMode.self, forKey: .mode) ?? .oneCall
        }
    }

    private struct ForecastEntry: Codable {
        let area: WeatherArea
        let fetchedAt: Date
        let hours: [WeatherHour]
    }

    private struct HistoryEntry: Codable {
        let query: Query
        let hour: WeatherHour
    }

    private struct Query: Hashable, Codable, Sendable {
        let area: WeatherArea
        let hour: TimeInterval?
    }

    private let cacheFile: URL
    private let readKey: @Sendable () -> String?
    private let writeKey: @Sendable (String?) throws -> Void
    private let request: @Sendable (URL) async -> Response
    private let now: @Sendable () -> Date
    private let forecastFreshness: TimeInterval
    private var cache: Cache
    private var pending: [Query: Task<Reply, Never>] = [:]
    private var nextRequestDate: Date?
    private var retryAfter: [Query: Date] = [:]
    private var generation = 0
    private static let dailyLimit = 200
    private static let maximumHistory = 512
    private static let maximumForecasts = 4

    public init(
        cacheFile: URL,
        readKey: @escaping @Sendable () -> String?,
        writeKey: @escaping @Sendable (String?) throws -> Void,
        request: @escaping @Sendable (URL) async -> Response,
        now: @escaping @Sendable () -> Date = Date.init,
        forecastFreshness: TimeInterval = 30 * 60
    ) {
        self.forecastFreshness = forecastFreshness
        self.cacheFile = cacheFile
        self.readKey = readKey
        self.writeKey = writeKey
        self.request = request
        self.now = now
        let data = try? Data(contentsOf: cacheFile)
        self.cache = data.flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } ?? Cache()
    }

    public func isConfigured() async -> Bool { readKey() != nil }

    public func mode() -> OpenWeatherMode { cache.mode }

    public func provider() async -> WeatherProvider {
        cache.mode == .free ? .openWeatherFree : .openWeatherOneCall
    }

    /// Switches endpoints. Stored forecasts belong to the old mode, so they go.
    public func setMode(_ mode: OpenWeatherMode) {
        guard mode != cache.mode else { return }
        cache.mode = mode
        cache.forecasts.removeAll()
        resetRequests()
        try? persist()
    }

    public func discardAllForecasts() async {
        guard !cache.forecasts.isEmpty else { return }
        cache.forecasts.removeAll()
        try? persist()
    }

    public func configure(key: String) throws {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ClientError.emptyKey }
        try writeKey(cleaned)
        resetRequests()
    }

    public func disconnect() throws {
        try writeKey(nil)
        resetRequests()
        cache.forecasts.removeAll()
        cache.history.removeAll()
        cache.mode = .oneCall
        try persist()
    }

    public func validate(key: String) async -> WeatherKeyCheck {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let area = WeatherArea(latitude: 0, longitude: 0),
              let url = OpenWeatherTimeline.url(for: area, start: nil, key: cleaned),
              reserveAttempt(at: now()) else { return .unavailable }
        switch await request(url) {
        case let .data(data): return (try? OpenWeatherTimeline.decode(data)) == nil ? .unavailable : .valid
        case .rejected, .backOff:
            // One Call refuses keys without its subscription (401/403); the free forecast may still accept it.
            return await validateFree(key: cleaned, area: area)
        case .unavailable: return .unavailable
        }
    }

    private func validateFree(key: String, area: WeatherArea) async -> WeatherKeyCheck {
        guard let url = OpenWeatherFreeForecast.url(for: area, key: key), reserveAttempt(at: now()) else {
            return .unavailable
        }
        switch await request(url) {
        case let .data(data): return (try? OpenWeatherFreeForecast.decode(data)) == nil ? .unavailable : .validFree
        case .rejected: return .rejected
        case .backOff, .unavailable: return .unavailable
        }
    }

    public func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? {
        let hour = OpenWeatherTimeline.hour(date)
        guard readKey() != nil, cache.mode == .oneCall, hour.isFinite, date < now() else { return nil }
        let query = Query(area: area, hour: hour)
        if let item = cache.history.first(where: { $0.query == query }) { return item.hour }
        let revision = generation
        let hours = await fetch(query, start: date)
        guard revision == generation,
              let result = hours.first(where: { OpenWeatherTimeline.hour($0.date) == hour }) else {
            return nil
        }
        if !cache.history.contains(where: { $0.query == query }) {
            cache.history.append(HistoryEntry(query: query, hour: result))
            if cache.history.count > Self.maximumHistory {
                cache.history.removeFirst(cache.history.count - Self.maximumHistory)
            }
            try? persist()
        }
        return result
    }

    public func forecast(for area: WeatherArea) async -> [WeatherHour] {
        await forecast(for: area, forceRefresh: false).hours
    }

    public func cachedForecast(for area: WeatherArea) async -> WeatherForecast? {
        guard readKey() != nil else { return nil }
        return storedForecast(for: area).map { WeatherForecast(hours: $0.hours, fetchedAt: $0.fetchedAt) }
    }

    public func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast {
        guard readKey() != nil else { return WeatherForecast(hours: []) }
        let stored = storedForecast(for: area)
        let date = now()
        if !forceRefresh, let stored, isFresh(stored, at: date) {
            return WeatherForecast(hours: stored.hours, fetchedAt: stored.fetchedAt)
        }
        let revision = generation
        let hours = await fetch(Query(area: area, hour: nil), start: nil)
        guard revision == generation else { return WeatherForecast(hours: []) }
        if hours.isEmpty {
            // Refused (budget, back-off) or failed: keep showing what is stored.
            return stored.map { WeatherForecast(hours: $0.hours, fetchedAt: $0.fetchedAt) }
                ?? WeatherForecast(hours: [])
        }
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

    private func storedForecast(for area: WeatherArea) -> ForecastEntry? {
        cache.forecasts.first { $0.area == area }
    }

    private func isFresh(_ entry: ForecastEntry, at date: Date) -> Bool {
        let age = date.timeIntervalSince(entry.fetchedAt)
        return age >= 0 && age < forecastFreshness
    }

    private func fetch(_ query: Query, start: Date?) async -> [WeatherHour] {
        if let existing = pending[query] { return await existing.value.hours }
        let date = now()
        retryAfter = retryAfter.filter { $0.value > date }
        let mode = cache.mode
        guard nextRequestDate.map({ date >= $0 }) ?? true, retryAfter[query] == nil, let key = readKey(),
              let url = mode == .free
                ? OpenWeatherFreeForecast.url(for: query.area, key: key)
                : OpenWeatherTimeline.url(for: query.area, start: start, key: key),
              reserveAttempt(at: date) else { return [] }

        let revision = generation
        let task = Task { [request] in
            switch await request(url) {
            case let .data(data):
                let decoded = mode == .free ? try? OpenWeatherFreeForecast.decode(data)
                    : try? OpenWeatherTimeline.decode(data)
                return Reply(hours: decoded ?? [])
            case .backOff, .rejected:
                return Reply(shouldBackOff: true)
            case .unavailable:
                return Reply()
            }
        }
        pending[query] = task
        let result = await task.value
        guard revision == generation else { return [] }
        pending[query] = nil
        let retry = now().addingTimeInterval(30 * 60)
        if result.hours.isEmpty { retryAfter[query] = retry }
        if result.shouldBackOff { nextRequestDate = retry }
        return result.hours
    }

    private func reserveAttempt(at date: Date) -> Bool {
        let day = (date.timeIntervalSince1970 / 86_400).rounded(.down)
        if cache.requestDay < day {
            cache.requestDay = day
            cache.attempts = 0
        }
        guard cache.attempts < Self.dailyLimit else { return false }
        cache.attempts += 1
        do {
            try persist()
            return true
        } catch {
            return false
        }
    }

    private func persist() throws {
        var folder = cacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var options = URLResourceValues()
        options.isExcludedFromBackup = true
        try? folder.setResourceValues(options)
        try JSONEncoder().encode(cache).write(to: cacheFile, options: .atomic)
    }

    private func resetRequests() {
        generation += 1
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        retryAfter.removeAll()
        nextRequestDate = nil
    }
}

import Domain
import Foundation

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
    }

    private struct HistoryEntry: Codable {
        let query: Query
        let hour: WeatherHour
    }

    private struct Query: Hashable, Codable, Sendable {
        let area: WeatherArea
        let hour: TimeInterval?
    }

    private struct Forecast {
        let fetchedAt: Date
        let hours: [WeatherHour]
    }

    private let cacheFile: URL
    private let readKey: @Sendable () -> String?
    private let writeKey: @Sendable (String?) throws -> Void
    private let request: @Sendable (URL) async -> Response
    private let now: @Sendable () -> Date
    private var cache: Cache
    private var forecasts: [WeatherArea: Forecast] = [:]
    private var pending: [Query: Task<Reply, Never>] = [:]
    private var nextRequestDate: Date?
    private var retryAfter: [Query: Date] = [:]
    private var generation = 0
    private static let dailyLimit = 200
    private static let maximumHistory = 512

    public init(
        cacheFile: URL,
        readKey: @escaping @Sendable () -> String?,
        writeKey: @escaping @Sendable (String?) throws -> Void,
        request: @escaping @Sendable (URL) async -> Response,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.cacheFile = cacheFile
        self.readKey = readKey
        self.writeKey = writeKey
        self.request = request
        self.now = now
        let data = try? Data(contentsOf: cacheFile)
        self.cache = data.flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } ?? Cache()
    }

    public func isConfigured() async -> Bool { readKey() != nil }

    public func configure(key: String) throws {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ClientError.emptyKey }
        try writeKey(cleaned)
        resetRequests()
    }

    public func disconnect() throws {
        try writeKey(nil)
        resetRequests()
        forecasts.removeAll()
        cache.history.removeAll()
        try persist()
    }

    public func validate(key: String) async -> WeatherKeyCheck {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let area = WeatherArea(latitude: 0, longitude: 0),
              let url = OpenWeatherTimeline.url(for: area, start: nil, key: cleaned),
              reserveAttempt(at: now()) else { return .unavailable }
        switch await request(url) {
        case let .data(data): return (try? OpenWeatherTimeline.decode(data)) == nil ? .unavailable : .valid
        case .rejected: return .rejected
        case .backOff, .unavailable: return .unavailable
        }
    }

    public func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? {
        let hour = OpenWeatherTimeline.hour(date)
        guard readKey() != nil, hour.isFinite, date < now() else { return nil }
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
        guard readKey() != nil else { return [] }
        let date = now()
        if let forecast = forecasts[area], date.timeIntervalSince(forecast.fetchedAt) < 30 * 60 {
            return forecast.hours
        }
        let revision = generation
        let hours = await fetch(Query(area: area, hour: nil), start: nil)
        guard revision == generation else { return [] }
        if !hours.isEmpty {
            forecasts[area] = Forecast(fetchedAt: date, hours: hours)
        }
        return hours.isEmpty ? forecasts[area]?.hours ?? [] : hours
    }

    private func fetch(_ query: Query, start: Date?) async -> [WeatherHour] {
        if let existing = pending[query] { return await existing.value.hours }
        let date = now()
        retryAfter = retryAfter.filter { $0.value > date }
        guard nextRequestDate.map({ date >= $0 }) ?? true, retryAfter[query] == nil,
              let key = readKey(), let url = OpenWeatherTimeline.url(for: query.area, start: start, key: key),
              reserveAttempt(at: date) else { return [] }

        let revision = generation
        let task = Task { [request] in
            switch await request(url) {
            case let .data(data):
                return Reply(hours: (try? OpenWeatherTimeline.decode(data)) ?? [])
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

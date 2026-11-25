import Foundation

/// Approximate 0.1° grid cell shared with the weather provider.
public struct WeatherArea: Hashable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
    }
}

public struct WeatherHour: Equatable, Codable, Sendable {
    public let date: Date
    public let temperatureCelsius: Double?
    public let humidityPercent: Double?
    public let windMetersPerSecond: Double?
    public let conditionCode: Int?
    public let precipitationProbability: Double?
    public let isDaylight: Bool?

    public init(
        date: Date, temperatureCelsius: Double? = nil, humidityPercent: Double? = nil,
        windMetersPerSecond: Double? = nil, conditionCode: Int? = nil,
        precipitationProbability: Double? = nil, isDaylight: Bool? = nil
    ) {
        self.date = date
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.windMetersPerSecond = windMetersPerSecond
        self.conditionCode = conditionCode
        self.precipitationProbability = precipitationProbability
        self.isDaylight = isDaylight
    }
}

/// A forecast with the moment the provider answered. `fetchedAt` is nil when the source cannot say.
public struct WeatherForecast: Equatable, Sendable {
    public let hours: [WeatherHour]
    public let fetchedAt: Date?

    public init(hours: [WeatherHour], fetchedAt: Date? = nil) {
        self.hours = hours
        self.fetchedAt = fetchedAt
    }
}

public protocol WeatherSource: Sendable {
    func isConfigured() async -> Bool
    func historical(for area: WeatherArea, at date: Date) async -> WeatherHour?
    func forecast(for area: WeatherArea) async -> [WeatherHour]
    /// The stored forecast for `area` whatever its age, without any request. Nil when none is stored.
    func cachedForecast(for area: WeatherArea) async -> WeatherForecast?
    /// A fresh stored forecast, or a new request when it is missing or stale (always when `forceRefresh`).
    /// A refused or failed request returns the stored forecast, however old, rather than nothing.
    func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast
    /// Forgets the stored forecast for `area`.
    func discardForecast(for area: WeatherArea) async
}

public extension WeatherSource {
    func isConfigured() async -> Bool { true }
    func cachedForecast(for area: WeatherArea) async -> WeatherForecast? { nil }
    func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast {
        WeatherForecast(hours: await forecast(for: area))
    }
    func discardForecast(for area: WeatherArea) async {}
}

/// What OpenWeather said about a key that has not been saved yet.
public enum WeatherKeyCheck: Equatable, Sendable {
    case valid
    case rejected
    case unavailable
}

/// The UI can replace or remove a credential without reading it back.
public protocol WeatherCredentials: Sendable {
    func isConfigured() async -> Bool
    func configure(key: String) async throws
    func disconnect() async throws
    /// Asks OpenWeather whether `key` works, without saving it. The key goes nowhere else.
    func validate(key: String) async -> WeatherKeyCheck
}

public extension WeatherCredentials {
    func validate(key: String) async -> WeatherKeyCheck { .valid }
}

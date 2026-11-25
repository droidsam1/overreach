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
    /// How long the values hold from `date`, in seconds. Nil means one hour; a 3-hour provider step says 10 800.
    public let durationSeconds: TimeInterval?

    /// How long the values hold from `date`.
    public var duration: TimeInterval { durationSeconds ?? 3_600 }

    /// `conditionCode` is an OpenWeather condition id whatever the provider; other providers map their own codes to it.
    public init(
        date: Date, temperatureCelsius: Double? = nil, humidityPercent: Double? = nil,
        windMetersPerSecond: Double? = nil, conditionCode: Int? = nil,
        precipitationProbability: Double? = nil, isDaylight: Bool? = nil, durationSeconds: TimeInterval? = nil
    ) {
        self.date = date
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.windMetersPerSecond = windMetersPerSecond
        self.conditionCode = conditionCode
        self.precipitationProbability = precipitationProbability
        self.isDaylight = isDaylight
        self.durationSeconds = durationSeconds
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

/// Where the forecast and the weather of past runs come from.
public enum WeatherProvider: String, CaseIterable, Codable, Sendable {
    /// No key, no account; free for non-commercial use with attribution.
    case openMeteo
    /// The user's own OpenWeather key with a One Call subscription (hourly, history).
    case openWeatherOneCall
    /// The user's own free OpenWeather key: 3-hour steps, no history.
    case openWeatherFree

    public var isOpenWeather: Bool { self != .openMeteo }
    public var hasHistory: Bool { self != .openWeatherFree }
}

/// Which provider is active and whether it can be used, kept by the app. Switching clears the stored forecast and
/// keeps any saved OpenWeather key.
public protocol WeatherProviderSelection: Sendable {
    func selectedProvider() async -> WeatherProvider
    func select(_ provider: WeatherProvider) async
    /// Whether `provider` can serve requests now: Open-Meteo once the person confirmed it, OpenWeather with a key.
    func isReady(_ provider: WeatherProvider) async -> Bool
    /// The person agreed to send the coarse area to Open-Meteo.
    func confirmOpenMeteo() async
}

public protocol WeatherSource: Sendable {
    func isConfigured() async -> Bool
    /// The provider answering requests, for attribution and limitations.
    func provider() async -> WeatherProvider
    func historical(for area: WeatherArea, at date: Date) async -> WeatherHour?
    func forecast(for area: WeatherArea) async -> [WeatherHour]
    /// The stored forecast for `area` whatever its age, without any request. Nil when none is stored.
    func cachedForecast(for area: WeatherArea) async -> WeatherForecast?
    /// A fresh stored forecast, or a new request when it is missing or stale (always when `forceRefresh`).
    /// A refused or failed request returns the stored forecast, however old, rather than nothing.
    func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast
    /// Forgets the stored forecast for `area`.
    func discardForecast(for area: WeatherArea) async
    /// Forgets every stored forecast.
    func discardAllForecasts() async
}

public extension WeatherSource {
    func isConfigured() async -> Bool { true }
    func provider() async -> WeatherProvider { .openWeatherOneCall }
    func cachedForecast(for area: WeatherArea) async -> WeatherForecast? { nil }
    func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast {
        WeatherForecast(hours: await forecast(for: area))
    }
    func discardForecast(for area: WeatherArea) async {}
    func discardAllForecasts() async {}
}

/// What OpenWeather said about a key that has not been saved yet.
public enum WeatherKeyCheck: Equatable, Sendable {
    /// Works with One Call (hourly and history).
    case valid
    /// A real key without a One Call subscription: only the free 3-hour forecast works.
    case validFree
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

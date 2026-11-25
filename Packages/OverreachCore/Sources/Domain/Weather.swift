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

public protocol WeatherSource: Sendable {
    func isConfigured() async -> Bool
    func historical(for area: WeatherArea, at date: Date) async -> WeatherHour?
    func forecast(for area: WeatherArea) async -> [WeatherHour]
}

public extension WeatherSource {
    func isConfigured() async -> Bool { true }
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

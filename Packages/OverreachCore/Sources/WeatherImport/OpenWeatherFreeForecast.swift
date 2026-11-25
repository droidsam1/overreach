import Domain
import Foundation

/// The free-plan 5-day forecast (`/data/2.5/forecast`): 3-hour steps, no history. Works with any valid key.
public enum OpenWeatherFreeForecast {
    public static let stepSeconds: TimeInterval = 3 * 3_600

    public static func url(for area: WeatherArea, key: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openweathermap.org"
        components.path = "/data/2.5/forecast"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(area.latitude)),
            URLQueryItem(name: "lon", value: String(area.longitude)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: key),
        ]
        return components.url
    }

    /// Each step becomes one `WeatherHour` that lasts three hours.
    public static func decode(_ data: Data) throws -> [WeatherHour] {
        try JSONDecoder().decode(Forecast.self, from: data).list.map { entry in
            WeatherHour(
                date: Date(timeIntervalSince1970: entry.timestamp),
                temperatureCelsius: entry.main?.temp,
                humidityPercent: entry.main?.humidity,
                windMetersPerSecond: entry.wind?.speed,
                conditionCode: entry.weather?.first?.id,
                precipitationProbability: entry.pop,
                isDaylight: entry.sys?.pod.flatMap { $0 == "d" ? true : $0 == "n" ? false : nil },
                durationSeconds: stepSeconds
            )
        }.sorted { $0.date < $1.date }
    }
}

private struct Forecast: Decodable {
    let list: [Entry]
}

private struct Entry: Decodable {
    struct Main: Decodable {
        let temp: Double?
        let humidity: Double?
    }
    struct Wind: Decodable {
        let speed: Double?
    }
    struct Condition: Decodable {
        let id: Int?
    }
    struct Sys: Decodable {
        let pod: String?
    }

    let timestamp: Double
    let main: Main?
    let wind: Wind?
    let weather: [Condition]?
    let pop: Double?
    let sys: Sys?

    enum CodingKeys: String, CodingKey {
        case timestamp = "dt", main, wind, weather, pop, sys
    }
}

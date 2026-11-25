import Domain
import Foundation

/// Open-Meteo requests and responses. No key and no account: only the coarse area and the requested hours are sent.
public enum OpenMeteoForecast {
    public static let attributionURL = URL(string: "https://open-meteo.com/")
    static let forecastHost = "api.open-meteo.com"
    static let archiveHost = "archive-api.open-meteo.com"
    private static let variables = [
        "temperature_2m", "relative_humidity_2m", "wind_speed_10m", "precipitation_probability", "weather_code",
        "is_day",
    ]
    /// The archive has no precipitation probability.
    private static let archiveVariables = variables.filter { $0 != "precipitation_probability" }
    /// Archive data lags by days; newer past hours come from the forecast API's `past_days`.
    static let archiveDelay: TimeInterval = 7 * 86_400

    /// Today and tomorrow, or the last `pastDays` days up to now.
    public static func forecastURL(for area: WeatherArea, pastDays: Int = 0) -> URL? {
        var items = [
            URLQueryItem(name: "hourly", value: variables.joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: pastDays > 0 ? "1" : "2"),
        ]
        if pastDays > 0 { items.append(URLQueryItem(name: "past_days", value: String(pastDays))) }
        return url(host: forecastHost, path: "/v1/forecast", area: area, items: items)
    }

    /// The UTC day containing `date`, from the historical archive.
    public static func archiveURL(for area: WeatherArea, day date: Date) -> URL? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let text = String(format: "%04d-%02d-%02d", year, month, day)
        return url(host: archiveHost, path: "/v1/archive", area: area, items: [
            URLQueryItem(name: "start_date", value: text),
            URLQueryItem(name: "end_date", value: text),
            URLQueryItem(name: "hourly", value: archiveVariables.joined(separator: ",")),
        ])
    }

    private static func url(host: String, path: String, area: WeatherArea, items: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(area.latitude)),
            URLQueryItem(name: "longitude", value: String(area.longitude)),
        ] + items + [
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "GMT"),
        ]
        return components.url
    }

    public static func decode(_ data: Data) throws -> [WeatherHour] {
        let hourly = try JSONDecoder().decode(Response.self, from: data).hourly
        return hourly.time.enumerated().map { index, time in
            WeatherHour(
                date: Date(timeIntervalSince1970: time),
                temperatureCelsius: hourly.temperature?.value(at: index),
                humidityPercent: hourly.humidity?.value(at: index),
                windMetersPerSecond: hourly.wind?.value(at: index),
                conditionCode: hourly.weatherCode?.value(at: index).flatMap { conditionCode(wmo: Int($0)) },
                precipitationProbability: hourly.precipitationProbability?.value(at: index).map { $0 / 100 },
                isDaylight: hourly.isDay?.value(at: index).map { $0 >= 1 }
            )
        }.sorted { $0.date < $1.date }
    }

    /// Maps a WMO weather interpretation code to the OpenWeather condition id the rest of the app understands.
    public static func conditionCode(wmo code: Int) -> Int? { wmoToOpenWeather[code] }

    private static let wmoToOpenWeather: [Int: Int] = [
        0: 800, 1: 801, 2: 802, 3: 804,
        45: 741, 48: 741,
        51: 301, 53: 301, 55: 301, 56: 311, 57: 311,
        61: 500, 63: 501, 65: 502, 66: 511, 67: 511,
        71: 600, 73: 601, 75: 602, 77: 600,
        80: 520, 81: 521, 82: 522, 85: 620, 86: 621,
        95: 211, 96: 202, 97: 212, 99: 202,
    ]
}

private extension Array where Element == Double? {
    func value(at index: Int) -> Double? { indices.contains(index) ? self[index] : nil }
}

private struct Response: Decodable {
    let hourly: Hourly
}

private struct Hourly: Decodable {
    let time: [TimeInterval]
    let temperature: [Double?]?
    let humidity: [Double?]?
    let wind: [Double?]?
    let precipitationProbability: [Double?]?
    let weatherCode: [Double?]?
    let isDay: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time, temperature = "temperature_2m", humidity = "relative_humidity_2m", wind = "wind_speed_10m"
        case precipitationProbability = "precipitation_probability", weatherCode = "weather_code"
        case isDay = "is_day"
    }
}

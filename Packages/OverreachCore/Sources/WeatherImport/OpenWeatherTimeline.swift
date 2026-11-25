import Domain
import Foundation

/// One Call 4.0 hourly timeline. Historical requests ask for the UTC hour containing the activity.
public enum OpenWeatherTimeline {
    public static func url(for area: WeatherArea, start: Date?, key: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openweathermap.org"
        components.path = "/data/4.0/onecall/timeline/1h"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(area.latitude)),
            URLQueryItem(name: "lon", value: String(area.longitude)),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: key),
        ]
        if let start {
            guard let timestamp = Int(exactly: hour(start)) else { return nil }
            components.queryItems?.append(URLQueryItem(name: "start", value: String(timestamp)))
        }
        return components.url
    }

    public static func hour(_ date: Date) -> TimeInterval {
        (date.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600
    }

    public static func decode(_ data: Data) throws -> [WeatherHour] {
        try JSONDecoder().decode(Timeline.self, from: data).data.map { entry in
            WeatherHour(
                date: Date(timeIntervalSince1970: entry.timestamp),
                temperatureCelsius: entry.temp,
                humidityPercent: entry.humidity,
                windMetersPerSecond: entry.windSpeed,
                conditionCode: entry.weather?.first?.id,
                precipitationProbability: entry.pop,
                isDaylight: entry.weather?.first?.isDaylight
            )
        }.sorted { $0.date < $1.date }
    }
}

private struct Timeline: Decodable {
    let data: [Entry]
}

private struct Entry: Decodable {
    let timestamp: Double
    let temp: Double?
    let humidity: Double?
    let windSpeed: Double?
    let weather: [Condition]?
    let pop: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp = "dt", temp, humidity, windSpeed = "wind_speed", weather, pop
    }
}

private struct Condition: Decodable {
    let id: Int?
    let icon: String?

    var isDaylight: Bool? {
        switch icon?.last {
        case "d": true
        case "n": false
        default: nil
        }
    }
}

import Domain
import Foundation
import PresentationKit

extension HistoryMetric {
    static func weather(_ hour: WeatherHour, format: Format) -> [Self] {
        [
            hour.temperatureCelsius.map {
                Self(label: L10n.text("Temperature"), value: format.number($0, maxFractionDigits: 0) + " °C")
            },
            hour.humidityPercent.map {
                Self(label: L10n.text("Humidity"), value: format.number($0, maxFractionDigits: 0) + "%")
            },
            hour.windMetersPerSecond.map {
                Self(label: L10n.text("Wind"), value: format.number($0 * 3.6, maxFractionDigits: 0) + " km/h")
            },
            hour.conditionCode.flatMap(weatherCondition).map {
                Self(label: L10n.text("Conditions"), value: $0)
            },
        ].compactMap { $0 }
    }

    private static func weatherCondition(_ code: Int) -> String? {
        switch code {
        case 200..<300: L10n.text("Thunderstorms")
        case 300..<400: L10n.text("Drizzle")
        case 500..<600: L10n.text("Rain")
        case 600..<700: L10n.text("Snow")
        case 700..<800: L10n.text("Reduced visibility")
        case 800: L10n.text("Clear sky")
        case 801...804: L10n.text("Clouds")
        default: nil
        }
    }
}

import Domain
import Foundation

/// One line of the "what you get" comparison between weather providers.
public struct WeatherLimitation: Equatable, Identifiable, Sendable {
    public let title: String
    public let detail: String
    public var id: String { title }
}

/// Plain-language names, limitations and attribution of each weather provider.
public extension WeatherProvider {
    var displayName: String {
        switch self {
        case .openMeteo: L10n.text("Open-Meteo")
        case .openWeatherOneCall: L10n.text("OpenWeather One Call")
        case .openWeatherFree: L10n.text("OpenWeather free key")
        }
    }

    /// One sentence that says what the choice costs.
    var summary: String {
        switch self {
        case .openMeteo: L10n.text("No key or account. Hourly forecast and past-run weather.")
        case .openWeatherOneCall: L10n.text("Your own key with a One Call subscription. Needs a card.")
        case .openWeatherFree: L10n.text("Your own free key, no card. 3-hour steps and no past-run weather.")
        }
    }

    var limitations: [WeatherLimitation] {
        switch self {
        case .openMeteo:
            [
                WeatherLimitation(title: L10n.text("Setup"), detail: L10n.text("None. No account or key.")),
                WeatherLimitation(title: L10n.text("Card"), detail: L10n.text("Not required.")),
                WeatherLimitation(title: L10n.text("Resolution"), detail: L10n.text("Hourly.")),
                WeatherLimitation(title: L10n.text("Past runs"), detail: L10n.text("Weather near the start of runs.")),
                WeatherLimitation(
                    title: L10n.text("Terms"),
                    detail: L10n.text("Free for non-commercial use. Data by Open-Meteo.com under CC BY 4.0.")
                ),
            ]
        case .openWeatherOneCall:
            [
                WeatherLimitation(
                    title: L10n.text("Setup"),
                    detail: L10n.text("Your OpenWeather key and a One Call subscription.")
                ),
                WeatherLimitation(title: L10n.text("Card"), detail: L10n.text("Required. 1,000 calls a day are free.")),
                WeatherLimitation(title: L10n.text("Resolution"), detail: L10n.text("Hourly.")),
                WeatherLimitation(title: L10n.text("Past runs"), detail: L10n.text("Weather near the start of runs.")),
                WeatherLimitation(
                    title: L10n.text("Terms"),
                    detail: L10n.text("Your OpenWeather plan. Charges apply above the daily limit.")
                ),
            ]
        case .openWeatherFree:
            [
                WeatherLimitation(title: L10n.text("Setup"), detail: L10n.text("Your free OpenWeather key.")),
                WeatherLimitation(title: L10n.text("Card"), detail: L10n.text("Not required.")),
                WeatherLimitation(
                    title: L10n.text("Resolution"),
                    detail: L10n.text("3-hour steps, so dry and sunny windows are coarser.")
                ),
                WeatherLimitation(title: L10n.text("Past runs"), detail: L10n.text("No weather for past runs.")),
                WeatherLimitation(title: L10n.text("Terms"), detail: L10n.text("Your OpenWeather free plan.")),
            ]
        }
    }

    var attributionTitle: String {
        isOpenWeather ? L10n.text("Weather data from OpenWeather") : L10n.text("Weather data by Open-Meteo.com")
    }

    var attributionURL: URL? {
        URL(string: isOpenWeather ? "https://openweathermap.org/" : "https://open-meteo.com/")
    }
}

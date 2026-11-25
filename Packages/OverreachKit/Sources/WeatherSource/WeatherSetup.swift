import Domain
import Foundation
import WeatherImport

/// The weather providers the app can use, behind one source that follows the person's choice.
public struct WeatherSetup: Sendable {
    public let source: any Domain.WeatherSource
    public let selection: any WeatherProviderSelection
    public let credentials: any WeatherCredentials

    private static let choiceKey = "weather.provider.choice"

    /// Open-Meteo is the default; an install that already saved an OpenWeather key keeps OpenWeather.
    public static func make() -> WeatherSetup {
        let openWeather = OpenWeather.makeService()
        let openMeteo = OpenMeteoService(
            cacheFile: OpenWeather.cacheFolder().appending(path: "open-meteo-cache.json"),
            request: { url in
                // Open-Meteo sends a 429 when limits are exceeded; it has no keys to reject.
                await OpenWeather.request(url)
            }
        )
        let providers = WeatherProviders(
            openMeteo: openMeteo, openWeather: openWeather,
            read: {
                UserDefaults.standard.data(forKey: choiceKey)
                    .flatMap { try? JSONDecoder().decode(WeatherProviderChoice.self, from: $0) }
                    ?? WeatherProviderChoice()
            },
            write: { choice in
                if let data = try? JSONEncoder().encode(choice) { UserDefaults.standard.set(data, forKey: choiceKey) }
            }
        )
        return WeatherSetup(source: providers, selection: providers, credentials: openWeather)
    }
}

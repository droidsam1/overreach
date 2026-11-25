import Domain
import Foundation

/// What the app remembers about the provider choice. A nil `family` means "never chosen".
public struct WeatherProviderChoice: Codable, Equatable, Sendable {
    public enum Family: String, Codable, Sendable {
        case openMeteo
        case openWeather
    }

    public var family: Family?
    public var openMeteoConfirmed = false

    public init(family: Family? = nil, openMeteoConfirmed: Bool = false) {
        self.family = family
        self.openMeteoConfirmed = openMeteoConfirmed
    }
}

/// Routes weather requests to the selected provider. Open-Meteo is the default for new installs; an install with a
/// saved OpenWeather key that never chose keeps OpenWeather. Switching forgets stored forecasts, never the key.
public actor WeatherProviders: WeatherSource, WeatherProviderSelection {
    private let openMeteo: OpenMeteoService
    private let openWeather: OpenWeatherService
    private let read: @Sendable () -> WeatherProviderChoice
    private let write: @Sendable (WeatherProviderChoice) -> Void

    public init(
        openMeteo: OpenMeteoService, openWeather: OpenWeatherService,
        read: @escaping @Sendable () -> WeatherProviderChoice,
        write: @escaping @Sendable (WeatherProviderChoice) -> Void
    ) {
        self.openMeteo = openMeteo
        self.openWeather = openWeather
        self.read = read
        self.write = write
    }

    private func family() async -> WeatherProviderChoice.Family {
        if let family = read().family { return family }
        return await openWeather.isConfigured() ? .openWeather : .openMeteo
    }

    // MARK: Selection

    public func selectedProvider() async -> WeatherProvider {
        guard await family() == .openWeather else { return .openMeteo }
        return await openWeather.provider()
    }

    public func select(_ provider: WeatherProvider) async {
        let before = await selectedProvider()
        var choice = read()
        choice.family = provider.isOpenWeather ? .openWeather : .openMeteo
        write(choice)
        if provider.isOpenWeather {
            await openWeather.setMode(provider == .openWeatherFree ? .free : .oneCall)
        }
        if before != provider {
            await openMeteo.discardAllForecasts()
            await openWeather.discardAllForecasts()
        }
    }

    public func isReady(_ provider: WeatherProvider) async -> Bool {
        provider.isOpenWeather ? await openWeather.isConfigured() : read().openMeteoConfirmed
    }

    public func confirmOpenMeteo() async {
        var choice = read()
        choice.openMeteoConfirmed = true
        write(choice)
    }

    // MARK: Source

    private func active() async -> any WeatherSource {
        await family() == .openWeather ? openWeather : openMeteo
    }

    public func isConfigured() async -> Bool {
        await family() == .openWeather ? await openWeather.isConfigured() : read().openMeteoConfirmed
    }

    public func provider() async -> WeatherProvider { await selectedProvider() }

    public func historical(for area: WeatherArea, at date: Date) async -> WeatherHour? {
        guard await isConfigured() else { return nil }
        return await active().historical(for: area, at: date)
    }

    public func forecast(for area: WeatherArea) async -> [WeatherHour] {
        await forecast(for: area, forceRefresh: false).hours
    }

    public func cachedForecast(for area: WeatherArea) async -> WeatherForecast? {
        guard await isConfigured() else { return nil }
        return await active().cachedForecast(for: area)
    }

    public func forecast(for area: WeatherArea, forceRefresh: Bool) async -> WeatherForecast {
        guard await isConfigured() else { return WeatherForecast(hours: []) }
        return await active().forecast(for: area, forceRefresh: forceRefresh)
    }

    public func discardForecast(for area: WeatherArea) async {
        await openMeteo.discardForecast(for: area)
        await openWeather.discardForecast(for: area)
    }

    public func discardAllForecasts() async {
        await openMeteo.discardAllForecasts()
        await openWeather.discardAllForecasts()
    }
}

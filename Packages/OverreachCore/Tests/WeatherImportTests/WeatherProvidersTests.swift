import Domain
import Foundation
import Testing
import WeatherImport

struct WeatherProvidersTests {
    private static let now = Date(timeIntervalSince1970: 1_710_000_000)
    private static let area = WeatherArea(latitude: 42.6, longitude: -8.4)

    @Test func newInstallsDefaultToOpenMeteoAndWaitForConfirmation() async throws {
        let setup = Setup(key: nil)
        #expect(await setup.providers.selectedProvider() == .openMeteo)
        #expect(await !setup.providers.isConfigured())
        let area = try #require(Self.area)
        #expect(await setup.providers.forecast(for: area, forceRefresh: false).hours.isEmpty)
        #expect(setup.requests.paths.isEmpty)

        await setup.providers.confirmOpenMeteo()
        #expect(await setup.providers.isConfigured())
        #expect(await setup.providers.forecast(for: area, forceRefresh: false).hours.count == 1)
        #expect(setup.requests.hosts == ["api.open-meteo.com"])
    }

    @Test func installsWithAnOpenWeatherKeyKeepOpenWeather() async throws {
        let setup = Setup(key: "stored")
        #expect(await setup.providers.selectedProvider() == .openWeatherOneCall)
        #expect(await setup.providers.isConfigured())
        let area = try #require(Self.area)
        _ = await setup.providers.forecast(for: area, forceRefresh: false)
        #expect(setup.requests.hosts == ["api.openweathermap.org"])
    }

    @Test func switchingClearsTheForecastAndKeepsTheKey() async throws {
        let setup = Setup(key: "stored")
        let area = try #require(Self.area)
        _ = await setup.providers.forecast(for: area, forceRefresh: false)
        #expect(await setup.providers.cachedForecast(for: area) != nil)

        await setup.providers.select(.openMeteo)
        #expect(await setup.providers.selectedProvider() == .openMeteo)
        #expect(setup.keys.value == "stored")
        #expect(await setup.openWeather.cachedForecast(for: area) == nil)
        #expect(await !setup.providers.isConfigured())
        #expect(await setup.providers.isReady(.openWeatherOneCall))

        await setup.providers.select(.openWeatherOneCall)
        #expect(await setup.providers.isConfigured())
        #expect(await setup.providers.cachedForecast(for: area) == nil)
    }

    @Test func openWeatherFreeIsAProviderOfItsOwn() async {
        let setup = Setup(key: "stored")
        await setup.providers.select(.openWeatherFree)
        #expect(await setup.providers.selectedProvider() == .openWeatherFree)
        #expect(await setup.providers.provider() == .openWeatherFree)
        await setup.providers.select(.openWeatherOneCall)
        #expect(await setup.providers.selectedProvider() == .openWeatherOneCall)
    }

    @Test func theChoiceIsRememberedAcrossInstances() async {
        let store = ChoiceStore()
        let first = Setup(key: nil, store: store)
        await first.providers.confirmOpenMeteo()
        await first.providers.select(.openWeatherFree)
        let second = Setup(key: nil, store: store, folder: first.folder)
        #expect(await second.providers.selectedProvider() == .openWeatherFree)
        #expect(await second.providers.isReady(.openMeteo))
    }
}

private final class ChoiceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var choice = WeatherProviderChoice()
    var value: WeatherProviderChoice { lock.withLock { choice } }
    func set(_ new: WeatherProviderChoice) { lock.withLock { choice = new } }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var paths: [String] { lock.withLock { urls.map(\.path) } }
    var hosts: [String] { lock.withLock { urls.compactMap(\.host) } }
    func record(_ url: URL) { lock.withLock { urls.append(url) } }
}

private struct Setup {
    let providers: WeatherProviders
    let openWeather: OpenWeatherService
    let requests = RequestLog()
    let keys: LockedKey
    let folder: URL

    init(key: String?, store: ChoiceStore = ChoiceStore(), folder: URL? = nil) {
        let folder = folder ?? FileManager.default.temporaryDirectory
            .appending(path: "overreach-providers-" + UUID().uuidString)
        self.folder = folder
        let log = requests
        let box = LockedKey(key)
        keys = box
        openWeather = OpenWeatherService(
            cacheFile: folder.appending(path: "ow.json"), readKey: { box.value }, writeKey: { box.set($0) },
            request: { url in
                log.record(url)
                return .data(Data(#"{"data":[{"dt":1710000000,"temp":8}]}"#.utf8))
            },
            now: { WeatherProvidersTests.nowValue }
        )
        let openMeteo = OpenMeteoService(
            cacheFile: folder.appending(path: "om.json"),
            request: { url in
                log.record(url)
                return .data(Data(#"{"hourly":{"time":[1710000000],"temperature_2m":[9]}}"#.utf8))
            },
            now: { WeatherProvidersTests.nowValue }
        )
        providers = WeatherProviders(
            openMeteo: openMeteo, openWeather: openWeather, read: { store.value }, write: { store.set($0) }
        )
    }
}

private final class LockedKey: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ key: String?) { stored = key }
    var value: String? { lock.withLock { stored } }
    func set(_ key: String?) { lock.withLock { stored = key } }
}

private extension WeatherProvidersTests {
    static var nowValue: Date { now }
}

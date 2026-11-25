import Domain
import Foundation
import Observation
import PresentationKit

@MainActor
@Observable
public final class WeatherSettingsModel {
    /// What the key section shows. The stored key is never read back, so `connected` only shows a mask.
    public enum Connection: Equatable, Sendable {
        case disconnected
        case connected
        case replacing
    }

    /// One row of the provider picker.
    public struct ProviderOption: Identifiable, Equatable, Sendable {
        public let provider: WeatherProvider
        public let title: String
        public let summary: String
        public let isSelected: Bool
        public var id: WeatherProvider { provider }
    }

    public private(set) var isConfigured = false
    public private(set) var isReplacing = false
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    /// The selected provider. Without a selection store the model behaves as the One Call key screen it started as.
    public private(set) var provider: WeatherProvider = .openWeatherOneCall
    /// Whether the selected provider can serve requests (Open-Meteo confirmed, or an OpenWeather key saved).
    public private(set) var isProviderReady = false
    private let credentials: any WeatherCredentials
    private let selection: (any WeatherProviderSelection)?

    public init(credentials: any WeatherCredentials, selection: (any WeatherProviderSelection)? = nil) {
        self.credentials = credentials
        self.selection = selection
    }

    /// Fixed placeholder for the saved key; it has no relation to the key's length or characters.
    public static let maskedKey = "••••••••"

    public var connection: Connection {
        guard isConfigured else { return .disconnected }
        return isReplacing ? .replacing : .connected
    }

    /// The key field is for a first key or a replacement, never next to a saved key.
    public var showsKeyField: Bool { connection != .connected }

    public var canCancelReplacing: Bool { connection == .replacing }

    public var canChooseProvider: Bool { selection != nil }

    public var providerOptions: [ProviderOption] {
        WeatherProvider.allCases.map {
            ProviderOption(provider: $0, title: $0.displayName, summary: $0.summary, isSelected: $0 == provider)
        }
    }

    /// What the selected provider needs, costs and cannot do.
    public var limitations: [WeatherLimitation] { provider.limitations }
    public var attributionTitle: String { provider.attributionTitle }
    public var attributionURL: URL? { provider.attributionURL }

    /// The key section belongs to OpenWeather only.
    public var showsKeySection: Bool { provider.isOpenWeather }

    /// Open-Meteo needs no key, only the person's agreement to send the approximate area.
    public var needsOpenMeteoConfirmation: Bool { provider == .openMeteo && !isProviderReady }
    public var isOpenMeteoActive: Bool { provider == .openMeteo && isProviderReady }

    /// Which OpenWeather mode the saved key runs in, with a hint to upgrade when it is the free one.
    public var modeNote: String? {
        guard provider.isOpenWeather, isConfigured else { return nil }
        switch provider {
        case .openWeatherFree:
            return L10n.text(
                "Using your free key: 3-hour steps and no past-run weather. Subscribe to One Call for hourly data."
            )
        default:
            return L10n.text("Using One Call: hourly forecast and past-run weather.")
        }
    }

    /// A fresh guide for the selected provider that saves the key through the same credentials.
    public func makeOnboarding() -> WeatherOnboardingModel {
        WeatherOnboardingModel(credentials: credentials, selection: selection, provider: provider)
    }

    public func load() async {
        isConfigured = await credentials.isConfigured()
        if !isConfigured { isReplacing = false }
        if let selection {
            provider = await selection.selectedProvider()
            isProviderReady = await selection.isReady(provider)
        } else {
            isProviderReady = isConfigured
        }
    }

    /// Switches provider. Stored forecasts are dropped by the selection; a saved OpenWeather key stays.
    public func selectProvider(_ choice: WeatherProvider) async {
        guard let selection, choice != provider, !isSaving else { return }
        errorMessage = nil
        isReplacing = false
        await selection.select(choice)
        await load()
    }

    public func confirmOpenMeteo() async {
        guard let selection, provider == .openMeteo else { return }
        await selection.confirmOpenMeteo()
        await load()
    }

    public func beginReplacing() {
        guard isConfigured else { return }
        errorMessage = nil
        isReplacing = true
    }

    public func cancelReplacing() {
        errorMessage = nil
        isReplacing = false
    }

    public func save(_ key: String) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let check = await credentials.validate(key: key)
            if check == .rejected {
                errorMessage = L10n.text("OpenWeather rejected this key. Check you copied all of it.")
                await load()
                return
            }
            try await credentials.configure(key: key)
            if check == .validFree { await selection?.select(.openWeatherFree) }
            if check == .valid, provider == .openWeatherFree { await selection?.select(.openWeatherOneCall) }
            errorMessage = nil
            isReplacing = false
        } catch {
            errorMessage = L10n.text("Could not save the weather key.")
        }
        await load()
    }

    public func disconnect() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await credentials.disconnect()
            errorMessage = nil
            isReplacing = false
        } catch {
            errorMessage = L10n.text("Could not clear the weather connection.")
        }
        await load()
    }
}

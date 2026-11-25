import Domain
import Foundation
import Observation
import PresentationKit

/// Short steps that take a person to a working weather provider: a confirmation for Open-Meteo, or a saved and
/// checked OpenWeather key. The steps depend on the provider (what it costs and needs differs).
@MainActor
@Observable
public final class WeatherOnboardingModel: Identifiable {
    public enum Step: Int, CaseIterable, Sendable {
        case why
        case account
        case limit
        case key
        case confirm
    }

    /// The one thing a step asks the person to do besides reading.
    public enum Action: Equatable, Sendable {
        case none
        case openLink(title: String, url: URL)
        case pasteAndSave
        case confirmOpenMeteo
    }

    public enum Outcome: Equatable, Sendable {
        case idle
        case validating
        case succeeded
        case failed(message: String)
    }

    public static let apiURL = URL(string: "https://openweathermap.org/api")

    public nonisolated let id = UUID()
    public let provider: WeatherProvider
    public private(set) var step: Step = .why
    public private(set) var outcome: Outcome = .idle
    /// Says which OpenWeather mode the saved key ended up with, when it differs from what the person chose.
    public private(set) var note: String?
    /// What the person typed or pasted. It is cleared once saved and never read back from storage.
    public var key = ""
    private let credentials: any WeatherCredentials
    private let selection: (any WeatherProviderSelection)?

    public init(
        credentials: any WeatherCredentials, selection: (any WeatherProviderSelection)? = nil,
        provider: WeatherProvider = .openWeatherOneCall
    ) {
        self.credentials = credentials
        self.selection = selection
        self.provider = provider
    }

    public var steps: [Step] {
        switch provider {
        case .openMeteo: [.why, .confirm]
        case .openWeatherOneCall: [.why, .account, .limit, .key]
        case .openWeatherFree: [.why, .account, .key]
        }
    }

    public var stepCount: Int { steps.count }
    public var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }
    public var progress: Double { Double(stepNumber) / Double(stepCount) }
    public var progressText: String { L10n.format("Step {1} of {2}", stepNumber, stepCount) }
    public var isFirstStep: Bool { step == steps.first }
    public var isLastStep: Bool { step == steps.last }
    public var canGoBack: Bool { !isFirstStep && outcome != .validating && outcome != .succeeded }
    public var canGoNext: Bool { !isLastStep }
    public var isValidating: Bool { outcome == .validating }
    public var isConnected: Bool { outcome == .succeeded }
    public var canSubmit: Bool { step == .key && !trimmedKey.isEmpty && !isValidating && !isConnected }
    public var canConfirm: Bool { step == .confirm && !isConnected }
    public var attributionTitle: String { provider.attributionTitle }
    public var attributionURL: URL? { provider.attributionURL }

    public var title: String {
        switch step {
        case .why:
            switch provider {
            case .openMeteo: L10n.text("Use Open-Meteo")
            case .openWeatherOneCall: L10n.text("Why Overreach needs a key")
            case .openWeatherFree: L10n.text("Use a free OpenWeather key")
            }
        case .account: L10n.text("Create your OpenWeather account")
        case .limit: L10n.text("Keep the daily limit low")
        case .key: L10n.text("Paste your key")
        case .confirm: L10n.text("Confirm Open-Meteo")
        }
    }

    public var message: String {
        switch step {
        case .why: whyMessage
        case .account: accountMessage
        case .limit:
            L10n.text("In OpenWeather, set the One Call API 3.0 daily limit to 1,000 or fewer to avoid charges.")
        case .key:
            L10n.text("Copy the key from your OpenWeather API keys tab, paste it here and save. Overreach checks it.")
        case .confirm:
            L10n.text(
                "Overreach asks Open-Meteo for the forecast of your approximate area and sends nothing else. "
                    + "Data by Open-Meteo.com under CC BY 4.0."
            )
        }
    }

    private var whyMessage: String {
        switch provider {
        case .openMeteo:
            L10n.text("Open-Meteo needs no key, no account and no card. It is free for non-commercial use.")
        case .openWeatherOneCall:
            L10n.text(
                "One Call needs your own OpenWeather key and a One Call subscription. OpenWeather asks for a card; "
                    + "the first 1,000 calls a day are free. The key stays here and only goes to OpenWeather."
            )
        case .openWeatherFree:
            L10n.text(
                "A free OpenWeather key needs no card. The forecast has 3-hour steps and there is no weather for "
                    + "past runs. The key stays here and only goes to OpenWeather."
            )
        }
    }

    private var accountMessage: String {
        if provider == .openWeatherFree {
            L10n.text(
                "Create a free OpenWeather account and copy your key. A new key can take a while to start working."
            )
        } else {
            L10n.text("Create a free OpenWeather account, then subscribe to One Call API 3.0 from the API page.")
        }
    }

    public var action: Action {
        switch step {
        case .why, .limit: .none
        case .account:
            Self.apiURL.map { .openLink(title: L10n.text("Open OpenWeather"), url: $0) } ?? .none
        case .key: .pasteAndSave
        case .confirm: .confirmOpenMeteo
        }
    }

    public func next() {
        guard canGoNext, let index = steps.firstIndex(of: step) else { return }
        step = steps[index + 1]
    }

    public func back() {
        guard canGoBack, let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
        outcome = .idle
        note = nil
    }

    /// Puts pasted text in the key field.
    public func paste(_ text: String) {
        guard !isValidating, !isConnected else { return }
        key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        outcome = .idle
    }

    /// The person agrees to send the coarse area to Open-Meteo.
    public func confirmOpenMeteo() async {
        guard canConfirm else { return }
        await selection?.confirmOpenMeteo()
        await selection?.select(.openMeteo)
        outcome = .succeeded
    }

    /// Checks the key with OpenWeather and saves it only when it works. A key without One Call is saved in free mode.
    public func submit() async {
        guard canSubmit else { return }
        let candidate = trimmedKey
        outcome = .validating
        note = nil
        let check = await credentials.validate(key: candidate)
        switch check {
        case .valid, .validFree:
            do {
                try await credentials.configure(key: candidate)
                let detected: WeatherProvider = check == .validFree ? .openWeatherFree : .openWeatherOneCall
                await selection?.select(detected)
                note = Self.note(chosen: provider, detected: detected)
                key = ""
                outcome = .succeeded
            } catch {
                outcome = .failed(message: L10n.text("Could not save the weather key."))
            }
        case .rejected:
            outcome = .failed(message: rejectedMessage)
        case .unavailable:
            outcome = .failed(message: L10n.text("Could not reach OpenWeather. Check your connection and try again."))
        }
    }

    private var rejectedMessage: String {
        if provider == .openWeatherFree {
            L10n.text("OpenWeather rejected this key. Check you copied all of it; a new key can take a while.")
        } else {
            L10n.text("OpenWeather rejected this key. Check you copied all of it and subscribed to One Call API 3.0.")
        }
    }

    private static func note(chosen: WeatherProvider, detected: WeatherProvider) -> String? {
        switch (chosen, detected) {
        case (.openWeatherOneCall, .openWeatherFree):
            L10n.text("This key has no One Call subscription, so Overreach uses the free forecast in 3-hour steps.")
        case (.openWeatherFree, .openWeatherOneCall):
            L10n.text("This key also has One Call, so Overreach uses the hourly forecast and past-run weather.")
        default: nil
        }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
}

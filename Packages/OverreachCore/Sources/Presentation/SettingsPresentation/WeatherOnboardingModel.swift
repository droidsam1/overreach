import Domain
import Foundation
import Observation
import PresentationKit

/// Four short steps that take a person from "no key" to a saved, checked OpenWeather key.
@MainActor
@Observable
public final class WeatherOnboardingModel: Identifiable {
    public enum Step: Int, CaseIterable, Sendable {
        case why
        case account
        case limit
        case key
    }

    /// The one thing a step asks the person to do besides reading.
    public enum Action: Equatable, Sendable {
        case none
        case openLink(title: String, url: URL)
        case pasteAndSave
    }

    public enum Outcome: Equatable, Sendable {
        case idle
        case validating
        case succeeded
        case failed(message: String)
    }

    public static let apiURL = URL(string: "https://openweathermap.org/api")

    public nonisolated let id = UUID()
    public private(set) var step: Step = .why
    public private(set) var outcome: Outcome = .idle
    /// What the person typed or pasted. It is cleared once saved and never read back from storage.
    public var key = ""
    private let credentials: any WeatherCredentials

    public init(credentials: any WeatherCredentials) {
        self.credentials = credentials
    }

    public var stepCount: Int { Step.allCases.count }
    public var stepNumber: Int { step.rawValue + 1 }
    public var progress: Double { Double(stepNumber) / Double(stepCount) }
    public var progressText: String { L10n.format("Step {1} of {2}", stepNumber, stepCount) }
    public var isFirstStep: Bool { step == .why }
    public var isLastStep: Bool { step == .key }
    public var canGoBack: Bool { !isFirstStep && outcome != .validating && outcome != .succeeded }
    public var canGoNext: Bool { !isLastStep }
    public var isValidating: Bool { outcome == .validating }
    public var isConnected: Bool { outcome == .succeeded }
    public var canSubmit: Bool { isLastStep && !trimmedKey.isEmpty && !isValidating && !isConnected }

    public var title: String {
        switch step {
        case .why: L10n.text("Why Overreach needs a key")
        case .account: L10n.text("Create your OpenWeather account")
        case .limit: L10n.text("Keep the daily limit low")
        case .key: L10n.text("Paste your key")
        }
    }

    public var message: String {
        switch step {
        case .why:
            L10n.text("Overreach needs your own free OpenWeather key. It stays here and only goes to OpenWeather.")
        case .account:
            L10n.text("Create a free OpenWeather account, then subscribe to One Call API 3.0 from the API page.")
        case .limit:
            L10n.text("In OpenWeather, set the One Call API 3.0 daily limit to 1,000 or fewer to avoid charges.")
        case .key:
            L10n.text("Copy the key from your OpenWeather API keys tab, paste it here and save. Overreach checks it.")
        }
    }

    public var action: Action {
        switch step {
        case .why, .limit: .none
        case .account:
            Self.apiURL.map { .openLink(title: L10n.text("Open OpenWeather"), url: $0) } ?? .none
        case .key: .pasteAndSave
        }
    }

    public func next() {
        guard canGoNext, let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    public func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        outcome = .idle
    }

    /// Puts pasted text in the key field.
    public func paste(_ text: String) {
        guard !isValidating, !isConnected else { return }
        key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        outcome = .idle
    }

    /// Checks the key with OpenWeather and saves it only when it works.
    public func submit() async {
        guard canSubmit else { return }
        let candidate = trimmedKey
        outcome = .validating
        switch await credentials.validate(key: candidate) {
        case .valid:
            do {
                try await credentials.configure(key: candidate)
                key = ""
                outcome = .succeeded
            } catch {
                outcome = .failed(message: L10n.text("Could not save the weather key."))
            }
        case .rejected:
            outcome = .failed(message: L10n.text(
                "OpenWeather rejected this key. Check you copied all of it and subscribed to One Call API 3.0."
            ))
        case .unavailable:
            outcome = .failed(message: L10n.text("Could not reach OpenWeather. Check your connection and try again."))
        }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
}

import Domain
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

    public private(set) var isConfigured = false
    public private(set) var isReplacing = false
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    private let credentials: any WeatherCredentials

    public init(credentials: any WeatherCredentials) {
        self.credentials = credentials
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

    /// A fresh guide that saves the key through the same credentials.
    public func makeOnboarding() -> WeatherOnboardingModel {
        WeatherOnboardingModel(credentials: credentials)
    }

    public func load() async {
        isConfigured = await credentials.isConfigured()
        if !isConfigured { isReplacing = false }
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
            try await credentials.configure(key: key)
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

import Domain
import Observation
import PresentationKit

@MainActor
@Observable
public final class WeatherSettingsModel {
    public private(set) var isConfigured = false
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    private let credentials: any WeatherCredentials

    public init(credentials: any WeatherCredentials) {
        self.credentials = credentials
    }

    public func load() async {
        isConfigured = await credentials.isConfigured()
    }

    public func save(_ key: String) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await credentials.configure(key: key)
            errorMessage = nil
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
        } catch {
            errorMessage = L10n.text("Could not clear the weather connection.")
        }
        await load()
    }
}

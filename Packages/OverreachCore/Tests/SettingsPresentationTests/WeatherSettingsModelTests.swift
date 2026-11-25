import Domain
import Foundation
import SettingsPresentation
import Testing

@MainActor
@Suite("Weather settings")
struct WeatherSettingsModelTests {
    @Test func startsDisconnectedWithTheKeyField() async {
        let credentials = WeatherCredentialsFixture()
        let model = WeatherSettingsModel(credentials: credentials)
        await model.load()
        #expect(model.connection == .disconnected)
        #expect(model.showsKeyField)
        #expect(!model.canCancelReplacing)
    }

    @Test func savingAKeyShowsTheConnectedStateWithoutTheField() async {
        let credentials = WeatherCredentialsFixture()
        let model = WeatherSettingsModel(credentials: credentials)
        await model.load()
        await model.save("  secret-key  ")
        #expect(await credentials.storedKey == "secret-key")
        #expect(model.connection == .connected)
        #expect(!model.showsKeyField)
        #expect(model.errorMessage == nil)
        #expect(WeatherSettingsModel.maskedKey.allSatisfy { $0 == "•" })
        #expect(!WeatherSettingsModel.maskedKey.contains("secret"))
    }

    @Test func aSavedKeyIsConnectedAfterLoading() async {
        let model = WeatherSettingsModel(credentials: WeatherCredentialsFixture(key: "stored"))
        await model.load()
        #expect(model.connection == .connected)
    }

    @Test func replacingReopensTheFieldUntilTheNewKeyIsSavedOrCancelled() async {
        let credentials = WeatherCredentialsFixture(key: "old")
        let model = WeatherSettingsModel(credentials: credentials)
        await model.load()

        model.beginReplacing()
        #expect(model.connection == .replacing)
        #expect(model.showsKeyField && model.canCancelReplacing)

        model.cancelReplacing()
        #expect(model.connection == .connected)
        #expect(await credentials.storedKey == "old")

        model.beginReplacing()
        await model.save("new")
        #expect(await credentials.storedKey == "new")
        #expect(model.connection == .connected)
    }

    @Test func aFailedReplacementKeepsTheFieldAndTheOldKey() async {
        let credentials = WeatherCredentialsFixture(key: "old", failsToSave: true)
        let model = WeatherSettingsModel(credentials: credentials)
        await model.load()
        model.beginReplacing()
        await model.save("new")
        #expect(model.connection == .replacing)
        #expect(model.errorMessage != nil)
        #expect(await credentials.storedKey == "old")
    }

    @Test func disconnectingReturnsToTheFieldAndLeavesReplacingMode() async {
        let credentials = WeatherCredentialsFixture(key: "old")
        let model = WeatherSettingsModel(credentials: credentials)
        await model.load()
        model.beginReplacing()
        await model.disconnect()
        #expect(model.connection == .disconnected)
        #expect(model.showsKeyField)
        #expect(await credentials.storedKey == nil)
    }

    @Test func replacingIsIgnoredWithoutAKey() async {
        let model = WeatherSettingsModel(credentials: WeatherCredentialsFixture())
        await model.load()
        model.beginReplacing()
        #expect(model.connection == .disconnected)
    }
}

actor WeatherCredentialsFixture: WeatherCredentials {
    struct Failure: Error {}

    private(set) var storedKey: String?
    private let failsToSave: Bool

    init(key: String? = nil, failsToSave: Bool = false) {
        self.storedKey = key
        self.failsToSave = failsToSave
    }

    func isConfigured() async -> Bool { storedKey != nil }

    func configure(key: String) async throws {
        if failsToSave { throw Failure() }
        storedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func disconnect() async throws { storedKey = nil }
}

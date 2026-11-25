import Domain
import Foundation
import PresentationKit
import SettingsPresentation
import Testing

@MainActor
@Suite("Weather providers")
struct WeatherProviderTests {
    @Test func theSettingsListEveryProviderWithTheSelectedOneMarked() async {
        let model = WeatherSettingsModel(
            credentials: WeatherCredentialsFixture(), selection: WeatherSelectionFixture(selected: .openMeteo)
        )
        await model.load()
        #expect(model.canChooseProvider)
        #expect(model.providerOptions.map(\.provider) == [.openMeteo, .openWeatherOneCall, .openWeatherFree])
        #expect(model.providerOptions.filter(\.isSelected).map(\.provider) == [.openMeteo])
        #expect(model.providerOptions.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
        #expect(!model.showsKeySection && model.needsOpenMeteoConfirmation)
        #expect(model.attributionURL?.host == "open-meteo.com")
    }

    @Test func everyProviderStatesSetupCardResolutionHistoryAndTerms() {
        for provider in WeatherProvider.allCases {
            #expect(provider.limitations.map(\.title) == ["Setup", "Card", "Resolution", "Past runs", "Terms"])
            #expect(provider.limitations.allSatisfy { !$0.detail.isEmpty })
        }
        func detail(_ provider: WeatherProvider, _ title: String) -> String {
            provider.limitations.first { $0.title == title }?.detail ?? ""
        }
        #expect(detail(.openMeteo, "Card") == "Not required.")
        #expect(detail(.openMeteo, "Terms").contains("non-commercial"))
        #expect(detail(.openWeatherOneCall, "Card").hasPrefix("Required"))
        #expect(detail(.openWeatherFree, "Card") == "Not required.")
        #expect(detail(.openWeatherFree, "Resolution").contains("3-hour"))
        #expect(detail(.openWeatherFree, "Past runs").hasPrefix("No weather"))
    }

    @Test func attributionFollowsTheProvider() {
        #expect(WeatherProvider.openMeteo.attributionURL?.absoluteString == "https://open-meteo.com/")
        #expect(WeatherProvider.openWeatherFree.attributionURL?.absoluteString == "https://openweathermap.org/")
        #expect(WeatherProvider.openWeatherOneCall.attributionTitle.contains("OpenWeather"))
        #expect(WeatherProvider.openMeteo.attributionTitle.contains("Open-Meteo"))
    }

    @Test func confirmingOpenMeteoMakesItReady() async {
        let selection = WeatherSelectionFixture(selected: .openMeteo)
        let model = WeatherSettingsModel(credentials: WeatherCredentialsFixture(), selection: selection)
        await model.load()
        await model.confirmOpenMeteo()
        #expect(model.isOpenMeteoActive && !model.needsOpenMeteoConfirmation)
    }

    @Test func switchingProviderKeepsTheSavedKeyAndShowsTheKeySection() async {
        let credentials = WeatherCredentialsFixture(key: "kept")
        let selection = WeatherSelectionFixture(selected: .openMeteo)
        let model = WeatherSettingsModel(credentials: credentials, selection: selection)
        await model.load()
        await model.selectProvider(.openWeatherOneCall)
        #expect(model.provider == .openWeatherOneCall && model.showsKeySection)
        #expect(model.connection == .connected)
        #expect(await credentials.storedKey == "kept")
        #expect(await selection.selections == [.openWeatherOneCall])

        await model.selectProvider(.openMeteo)
        #expect(await credentials.storedKey == "kept")
        #expect(!model.showsKeySection)
    }

    @Test func aFreeKeyShowsTheModeAndAnUpgradeHint() async {
        let selection = WeatherSelectionFixture(selected: .openWeatherFree)
        let model = WeatherSettingsModel(credentials: WeatherCredentialsFixture(key: "free"), selection: selection)
        await model.load()
        let note = model.modeNote ?? ""
        #expect(note.contains("3-hour") && note.contains("One Call"))
        let oneCall = WeatherSettingsModel(
            credentials: WeatherCredentialsFixture(key: "paid"),
            selection: WeatherSelectionFixture(selected: .openWeatherOneCall)
        )
        await oneCall.load()
        #expect(oneCall.modeNote?.contains("hourly") == true)
    }

    @Test func savingAKeyDetectsTheModeAndSelectsTheMatchingProvider() async {
        let selection = WeatherSelectionFixture(selected: .openWeatherOneCall)
        let model = WeatherSettingsModel(
            credentials: WeatherCredentialsFixture(check: .validFree), selection: selection
        )
        await model.load()
        await model.save("free-key")
        #expect(await selection.selections == [.openWeatherFree])
        #expect(model.provider == .openWeatherFree)
    }

    @Test func aRejectedKeyIsNotSavedFromSettings() async {
        let credentials = WeatherCredentialsFixture(check: .rejected)
        let model = WeatherSettingsModel(credentials: credentials, selection: WeatherSelectionFixture())
        await model.load()
        await model.save("wrong")
        #expect(await credentials.storedKey == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func openMeteoOnboardingIsAConfirmationWithAttributionAndNoKey() async {
        let selection = WeatherSelectionFixture(selected: .openWeatherOneCall)
        let credentials = WeatherCredentialsFixture()
        let model = WeatherOnboardingModel(credentials: credentials, selection: selection, provider: .openMeteo)
        #expect(model.steps == [.why, .confirm] && model.stepCount == 2)
        #expect(model.message.contains("no key"))
        model.next()
        #expect(model.step == .confirm && model.isLastStep && model.action == .confirmOpenMeteo)
        #expect(model.attributionURL?.host == "open-meteo.com")
        #expect(model.message.contains("CC BY 4.0"))
        await model.confirmOpenMeteo()
        #expect(model.isConnected)
        #expect(await selection.confirmed)
        #expect(await selection.selections == [.openMeteo])
        #expect(await credentials.validatedKeys.isEmpty)
    }

    @Test func freeKeyOnboardingSkipsTheDailyLimitStepAndSaysNoCardIsNeeded() {
        let model = WeatherOnboardingModel(credentials: WeatherCredentialsFixture(), provider: .openWeatherFree)
        #expect(model.steps == [.why, .account, .key])
        #expect(model.message.contains("no card") && model.message.contains("3-hour"))
        model.next()
        #expect(model.step == .account)
        model.next()
        #expect(model.step == .key && model.isLastStep && model.action == .pasteAndSave)
    }

    @Test func oneCallOnboardingSaysACardIsRequiredFirst() {
        let model = WeatherOnboardingModel(credentials: WeatherCredentialsFixture(), provider: .openWeatherOneCall)
        #expect(model.steps == [.why, .account, .limit, .key])
        #expect(model.message.contains("card"))
    }

    @Test func aKeyWithoutOneCallIsSavedInFreeModeWithAnExplanation() async {
        let selection = WeatherSelectionFixture(selected: .openMeteo)
        let credentials = WeatherCredentialsFixture(check: .validFree)
        let model = WeatherOnboardingModel(
            credentials: credentials, selection: selection, provider: .openWeatherOneCall
        )
        for _ in 0..<3 { model.next() }
        model.paste("free-key")
        await model.submit()
        #expect(model.outcome == .succeeded)
        #expect(await credentials.storedKey == "free-key")
        #expect(await selection.selections == [.openWeatherFree])
        #expect(model.note?.contains("free forecast") == true)
    }

    @Test func aFreeKeyThatAlsoHasOneCallUsesOneCall() async {
        let selection = WeatherSelectionFixture(selected: .openMeteo)
        let model = WeatherOnboardingModel(
            credentials: WeatherCredentialsFixture(check: .valid), selection: selection, provider: .openWeatherFree
        )
        for _ in 0..<2 { model.next() }
        model.paste("paid-key")
        await model.submit()
        #expect(await selection.selections == [.openWeatherOneCall])
        #expect(model.note?.contains("One Call") == true)
    }
}

actor WeatherSelectionFixture: WeatherProviderSelection {
    private var current: WeatherProvider
    private(set) var selections: [WeatherProvider] = []
    private(set) var confirmed = false

    init(selected: WeatherProvider = .openMeteo) { current = selected }

    func selectedProvider() async -> WeatherProvider { current }

    func select(_ provider: WeatherProvider) async {
        current = provider
        selections.append(provider)
    }

    func isReady(_ provider: WeatherProvider) async -> Bool { provider == .openMeteo ? confirmed : true }

    func confirmOpenMeteo() async { confirmed = true }
}

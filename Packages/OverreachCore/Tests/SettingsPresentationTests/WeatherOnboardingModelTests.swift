import Domain
import Foundation
import SettingsPresentation
import Testing

@MainActor
@Suite("Weather onboarding")
struct WeatherOnboardingModelTests {
    @Test func walksThroughFourStepsWithProgress() {
        let model = WeatherOnboardingModel(credentials: WeatherCredentialsFixture())
        #expect(model.step == .why && model.isFirstStep && !model.canGoBack)
        #expect(model.stepCount == 4 && model.stepNumber == 1 && model.progress == 0.25)
        #expect(model.progressText == "Step 1 of 4")

        model.next()
        #expect(model.step == .account && model.stepNumber == 2 && model.progress == 0.5)
        model.next()
        #expect(model.step == .limit)
        model.next()
        #expect(model.step == .key && model.isLastStep && !model.canGoNext && model.progress == 1)

        model.next()
        #expect(model.step == .key)
        model.back()
        #expect(model.step == .limit && model.canGoBack)
    }

    @Test func everyStepHasATitleAndMessageAndTheLimitStepStatesThe1000Cap() {
        let model = WeatherOnboardingModel(credentials: WeatherCredentialsFixture())
        var titles: Set<String> = []
        for _ in WeatherOnboardingModel.Step.allCases {
            #expect(!model.title.isEmpty && !model.message.isEmpty)
            titles.insert(model.title)
            if model.step == .limit { #expect(model.message.contains("1,000")) }
            model.next()
        }
        #expect(titles.count == 4)
    }

    @Test func onlyTheAccountStepOpensTheOpenWeatherPageAndTheKeyStepPastes() throws {
        let model = WeatherOnboardingModel(credentials: WeatherCredentialsFixture())
        #expect(model.action == .none)
        model.next()
        let url = try #require(URL(string: "https://openweathermap.org/api"))
        #expect(model.action == .openLink(title: "Open OpenWeather", url: url))
        model.next()
        #expect(model.action == .none)
        model.next()
        #expect(model.action == .pasteAndSave)
    }

    @Test func aWorkingKeyIsCheckedThenSavedAndClearedFromTheModel() async {
        let credentials = WeatherCredentialsFixture()
        let model = WeatherOnboardingModel(credentials: credentials)
        advanceToKeyStep(model)
        #expect(!model.canSubmit)

        model.paste("  abc123\n")
        #expect(model.key == "abc123" && model.canSubmit)
        await model.submit()

        #expect(model.outcome == .succeeded && model.isConnected)
        #expect(await credentials.validatedKeys == ["abc123"])
        #expect(await credentials.storedKey == "abc123")
        #expect(model.key.isEmpty)
        #expect(!model.canSubmit && !model.canGoBack)
    }

    @Test func aRejectedKeyIsNotSavedAndExplainsWhatToCheck() async {
        let credentials = WeatherCredentialsFixture(check: .rejected)
        let model = WeatherOnboardingModel(credentials: credentials)
        advanceToKeyStep(model)
        model.paste("wrong")
        await model.submit()

        guard case let .failed(message) = model.outcome else {
            Issue.record("Expected a failure")
            return
        }
        #expect(message.contains("One Call API 3.0"))
        #expect(await credentials.storedKey == nil)
        #expect(model.key == "wrong" && model.canSubmit)
    }

    @Test func anUnreachableProviderIsADifferentErrorAndNothingIsSaved() async {
        let credentials = WeatherCredentialsFixture(check: .unavailable)
        let model = WeatherOnboardingModel(credentials: credentials)
        advanceToKeyStep(model)
        model.paste("maybe")
        await model.submit()

        guard case let .failed(message) = model.outcome else {
            Issue.record("Expected a failure")
            return
        }
        #expect(message.contains("Could not reach OpenWeather"))
        #expect(await credentials.storedKey == nil)
    }

    @Test func aStorageFailureAfterAValidCheckIsReported() async {
        let credentials = WeatherCredentialsFixture(failsToSave: true)
        let model = WeatherOnboardingModel(credentials: credentials)
        advanceToKeyStep(model)
        model.paste("fine")
        await model.submit()
        #expect(model.outcome == .failed(message: "Could not save the weather key."))
        #expect(!model.isConnected)
    }

    @Test func editingTheKeyClearsAnEarlierError() async {
        let model = WeatherOnboardingModel(credentials: WeatherCredentialsFixture(check: .rejected))
        advanceToKeyStep(model)
        model.paste("wrong")
        await model.submit()
        model.paste("better")
        #expect(model.outcome == .idle)
    }

    @Test func submitDoesNothingBeforeTheKeyStep() async {
        let credentials = WeatherCredentialsFixture()
        let model = WeatherOnboardingModel(credentials: credentials)
        model.key = "early"
        await model.submit()
        #expect(model.outcome == .idle)
        #expect(await credentials.validatedKeys.isEmpty)
    }

    private func advanceToKeyStep(_ model: WeatherOnboardingModel) {
        for _ in 0..<3 { model.next() }
    }
}

import Foundation
import Persistence
import Testing

@Suite("Onboarding status")
struct OnboardingStatusTests {
    @Test func staysCompletedOnceMarked() throws {
        let suite = "onboarding-tests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let status = DefaultsOnboardingStatus(suiteName: suite)
        #expect(!status.isOnboardingCompleted())
        status.markOnboardingCompleted()
        #expect(DefaultsOnboardingStatus(suiteName: suite).isOnboardingCompleted())
    }
}

import Domain
import Foundation

/// Remembers on this device that the setup was handled. It is kept out of `AthleteProfile` so that finishing or
/// skipping the setup does not make the profile look customised, which would stop a restore from taking the backup's.
public struct DefaultsOnboardingStatus: OnboardingStatusStore {
    private static let key = "onboarding.completed"
    private let suiteName: String?

    /// `suiteName` selects a separate store for tests.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func isOnboardingCompleted() -> Bool {
        defaults.bool(forKey: Self.key)
    }

    public func markOnboardingCompleted() {
        defaults.set(true, forKey: Self.key)
    }
}

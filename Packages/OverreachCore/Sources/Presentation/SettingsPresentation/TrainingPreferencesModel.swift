import Domain
import Foundation
import Observation
import PresentationKit

/// Training preferences in Settings. For now: whether a week or more without lifting or running counts as rest
/// automatically (`training-breaks`), which changes when Today and Plan suggest the next deload.
@MainActor
@Observable
public final class TrainingPreferencesModel {
    public private(set) var countsBreaksAutomatically = true
    public private(set) var errorMessage: String?
    private let profiles: any ProfileRepository

    public init(profiles: any ProfileRepository) {
        self.profiles = profiles
    }

    public func load() async {
        do {
            countsBreaksAutomatically = try await profiles.profile().countsBreaksAutomatically
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not load your training preferences.")
        }
    }

    public func setCountsBreaksAutomatically(_ value: Bool) async {
        let previous = countsBreaksAutomatically
        countsBreaksAutomatically = value
        do {
            var profile = try await profiles.profile()
            profile.countsBreaksAutomatically = value
            try await profiles.save(profile)
            errorMessage = nil
        } catch {
            countsBreaksAutomatically = previous
            errorMessage = L10n.text("Could not save your training preferences. Try again.")
        }
    }
}

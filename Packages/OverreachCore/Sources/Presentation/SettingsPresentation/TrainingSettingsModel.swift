import Domain
import Observation
import PresentationKit

@MainActor
@Observable
public final class TrainingSettingsModel {
    public private(set) var countsBreaksAutomatically = true
    public private(set) var canEditBreaks = false
    public private(set) var errorMessage: String?

    public var sectionTitle: String { L10n.text("Training") }
    public var breaksTitle: String { L10n.text("Count breaks as rest automatically") }
    public var breaksDetail: String {
        L10n.text("A week without recorded strength workouts or runs counts as rest for that discipline.")
    }

    private var isWorking = false
    private let profiles: any ProfileRepository

    public init(profiles: any ProfileRepository) {
        self.profiles = profiles
    }

    public func load() async {
        guard !isWorking else { return }
        isWorking = true
        canEditBreaks = false
        defer { isWorking = false }
        do {
            countsBreaksAutomatically = try await profiles.profile().countsBreaksAutomatically
            errorMessage = nil
            canEditBreaks = true
        } catch {
            errorMessage = L10n.text("Could not load training settings.")
        }
    }

    public func setCountsBreaksAutomatically(_ enabled: Bool) async {
        guard canEditBreaks, enabled != countsBreaksAutomatically else { return }
        isWorking = true
        canEditBreaks = false
        defer {
            isWorking = false
            canEditBreaks = true
        }
        do {
            var profile = try await profiles.profile()
            profile.countsBreaksAutomatically = enabled
            try await profiles.save(profile)
            countsBreaksAutomatically = enabled
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not save training settings. Try again.")
        }
    }
}

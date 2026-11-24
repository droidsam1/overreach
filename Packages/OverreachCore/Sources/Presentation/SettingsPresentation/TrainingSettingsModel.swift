import Domain
import Observation
import PresentationKit

@MainActor
@Observable
public final class TrainingSettingsModel {
    public private(set) var weightUnit = WeightUnit.kilograms
    public private(set) var countsBreaksAutomatically = true
    public private(set) var canEditSettings = false
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
        canEditSettings = false
        defer { isWorking = false }
        do {
            let profile = try await profiles.profile()
            countsBreaksAutomatically = profile.countsBreaksAutomatically
            weightUnit = profile.weightUnit
            errorMessage = nil
            canEditSettings = true
        } catch {
            errorMessage = L10n.text("Could not load training settings.")
        }
    }

    public func setCountsBreaksAutomatically(_ enabled: Bool) async {
        guard enabled != countsBreaksAutomatically else { return }
        await save(\.countsBreaksAutomatically, enabled)
    }

    public func setWeightUnit(_ unit: WeightUnit) async {
        guard unit != weightUnit else { return }
        await save(\.weightUnit, unit)
    }

    private func save<Value>(_ key: WritableKeyPath<AthleteProfile, Value>, _ value: Value) async {
        guard canEditSettings else { return }
        isWorking = true
        canEditSettings = false
        defer {
            isWorking = false
            canEditSettings = true
        }
        do {
            var profile = try await profiles.profile()
            profile[keyPath: key] = value
            try await profiles.save(profile)
            countsBreaksAutomatically = profile.countsBreaksAutomatically
            weightUnit = profile.weightUnit
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not save training settings. Try again.")
        }
    }
}

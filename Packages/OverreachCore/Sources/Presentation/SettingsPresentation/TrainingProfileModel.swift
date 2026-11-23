import Domain
import Foundation
import Observation
import PresentationKit

@MainActor
@Observable
public final class TrainingProfileModel {
    private let profiles: any ProfileRepository
    private var original: AthleteProfile?
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public var goalKind: TrainingGoal.Kind?
    public var sex: BiologicalSex? {
        didSet {
            if sex != oldValue && (sex == .male || sex == .unspecified) { cycleTracking = .off }
        }
    }
    public var cycleTracking: CycleTrackingMode = .off
    public var walkingRoutine = WalkingRoutine()
    public private(set) var wearables: Set<Wearable> = []

    public let goalOptions = TrainingGoal.Kind.allCases.map { Option(value: $0, name: $0.displayName) }
    public let sexOptions = BiologicalSex.allCases.map { Option(value: $0, name: $0.displayName) }
    public let cycleOptions = CycleTrackingMode.allCases.map { Option(value: $0, name: $0.displayName) }

    public init(profiles: any ProfileRepository) {
        self.profiles = profiles
    }

    public var isLoaded: Bool { original != nil }
    public var canSave: Bool { isLoaded && !isSaving }
    public var showsCycleTracking: Bool { sex == .female || sex == nil }
    public var showsWalkDetails: Bool { walkingRoutine.hasDog || (walkingRoutine.usualWalksPerDay ?? 0) > 0 }

    public var walkOptions: [Int] {
        let options = Array(0...5)
        guard let count = original?.walkingRoutine.usualWalksPerDay, !options.contains(count) else { return options }
        return options + [count]
    }

    public var dogName: String {
        get { walkingRoutine.dogName ?? "" }
        set { walkingRoutine.dogName = newValue }
    }

    public func isSelected(_ wearable: Wearable) -> Bool { wearables.contains(wearable) }

    public func setWearable(_ wearable: Wearable, isSelected: Bool) {
        if isSelected {
            wearables.insert(wearable)
        } else {
            wearables.remove(wearable)
        }
    }

    public func load() async {
        guard !isLoaded else { return }
        do {
            let stored = try await profiles.profile()
            guard !Task.isCancelled else { return }
            original = stored
            goalKind = stored.goal?.kind
            sex = stored.sex
            cycleTracking = stored.cycleTracking
            walkingRoutine = stored.walkingRoutine
            wearables = stored.wearables
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not load your profile.")
        }
    }

    /// Applies edits to the current profile so plan details and other settings written meanwhile are preserved.
    public func save() async -> Bool {
        guard let original, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let current = try await profiles.profile()
            var updated = current
            if let goalKind, goalKind != original.goal?.kind {
                var goal = current.goal ?? TrainingGoal(kind: goalKind)
                goal.kind = goalKind
                updated.goal = goal
            }
            if sex != original.sex { updated.sex = sex }
            if cycleTracking != original.cycleTracking || (sex != original.sex && !showsCycleTracking) {
                updated.cycleTracking = cycleTracking
            }
            if wearables != original.wearables { updated.wearables = wearables }
            applyWalkingChanges(from: original.walkingRoutine, to: &updated.walkingRoutine)
            if updated != current { try await profiles.save(updated) }
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.text("Could not save your profile. Try again.")
            return false
        }
    }

    private func applyWalkingChanges(from original: WalkingRoutine, to updated: inout WalkingRoutine) {
        guard walkingRoutine != original else { return }
        if walkingRoutine.hasDog != original.hasDog { updated.hasDog = walkingRoutine.hasDog }
        if walkingRoutine.dogName != original.dogName || !updated.hasDog {
            let trimmedName = dogName.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.dogName = updated.hasDog && !trimmedName.isEmpty ? trimmedName : nil
        }
        if walkingRoutine.usualWalksPerDay != original.usualWalksPerDay {
            updated.usualWalksPerDay = walkingRoutine.usualWalksPerDay
        }
        let showsDetails = updated.hasDog || (updated.usualWalksPerDay ?? 0) > 0
        if walkingRoutine.walksAreFixed != original.walksAreFixed || !showsDetails {
            updated.walksAreFixed = showsDetails && walkingRoutine.walksAreFixed
        }
        if walkingRoutine.canRunDuringWalks != original.canRunDuringWalks || !showsDetails {
            updated.canRunDuringWalks = showsDetails && walkingRoutine.canRunDuringWalks
        }
    }
}

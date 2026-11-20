import Domain

/// Presets and safeguards for choosing a progression from one logged session.
public enum FirstProgression {
    public enum Strategy: String, Hashable, Codable, Sendable {
        case repetitions, load, wave
    }

    public struct Choice: Hashable, Codable, Sendable {
        public let strategy: Strategy
        public let settings: ProgressionSettings
        public let target: ExerciseTarget
    }

    public static func choices(from last: ExerciseExposure, settings: ProgressionSettings) -> [Choice] {
        guard isUsable(last) else { return [] }
        let reps = last.sets.compactMap(\.reps)
        let weight = last.workingWeightKg
        guard let minimum = reps.min(), let maximum = reps.max(),
              maximum <= 48, reps.count <= 10, maximum - minimum <= 3,
              last.setsAtWorkingWeight.count == last.sets.count,
              weight > 0 || settings.incrementKg == 0 else { return [] }

        let count = reps.count
        let rpe = settings.scheme.targetRPE
        let upperBound = maximum + 2
        var choices = [choice(.repetitions, scheme: .doubleProgression(
            sets: count, minReps: minimum, maxReps: upperBound, targetRPE: rpe
        ), from: last, settings: settings)]

        guard minimum == maximum, weight > 0, settings.incrementKg > 0 else { return choices }
        if settings.incrementKg <= weight * 0.05 {
            choices.append(choice(.load, scheme: .linearLoad(sets: count, reps: minimum, targetRPE: rpe),
                                  from: last, settings: settings))
        }

        if (4...10).contains(minimum) {
            let wave = choice(.wave, scheme: .repCycle(
                sets: count, repBlocks: [minimum + 2, minimum, minimum - 2], targetRPE: rpe
            ), from: last, settings: settings)
            if let nextWeight = wave.target.sets.first?.weightKg, nextWeight > weight {
                choices.append(wave)
            }
        }
        return choices
    }

    static func isUsable(_ exposure: ExerciseExposure) -> Bool {
        !exposure.sets.isEmpty && exposure.sets.allSatisfy {
            let weight = $0.weightKg ?? 0
            return weight.isFinite && weight >= 0
        }
    }

    static func repeatSets(from exposure: ExerciseExposure, rpe: Double, reason: ProgressionReason) -> ExerciseTarget {
        ExerciseTarget(
            sets: exposure.sets.compactMap { set in
                set.reps.map { PlannedSet(weightKg: set.weightKg, reps: $0, targetRPE: rpe) }
            },
            reasons: [reason]
        )
    }

    static func hold(from last: ExerciseExposure, settings: ProgressionSettings) -> ExerciseTarget? {
        guard isUsable(last) else { return nil }
        let rpe = settings.scheme.targetRPE
        if last.sets.contains(where: { $0.kind == .failure || ($0.rpe ?? 0) > rpe }) {
            return repeatSets(from: last, rpe: rpe, reason: .repeatAfterHighEffort)
        }
        let minimumRPE: Double
        switch settings.scheme {
        case .repCycle, .rpeBased: minimumRPE = LoadPrescription.minimumReliableRPE
        default: minimumRPE = 1
        }
        if last.sets.contains(where: { ($0.rpe ?? 0) < minimumRPE || $0.rpe?.isFinite == false }) {
            return repeatSets(from: last, rpe: rpe, reason: .repeatWithoutEffort)
        }
        return nil
    }

    static func isOversizedLoadStep(
        _ target: ExerciseTarget, from last: ExerciseExposure, scheme: ProgressionScheme
    ) -> Bool {
        let weight = last.workingWeightKg
        guard weight > 0, let proposed = target.sets.first?.weightKg else { return false }
        let limit: Double
        if case .repCycle = scheme { limit = 0.10 } else { limit = 0.05 }
        return proposed - weight > weight * limit + 0.0001
    }

    private static func choice(
        _ strategy: Strategy, scheme: ProgressionScheme, from exposure: ExerciseExposure,
        settings: ProgressionSettings
    ) -> Choice {
        var updated = settings
        updated.scheme = scheme
        updated.requiresLoggedEffort = true
        let target = ProgressionTargets.next(history: [exposure], settings: updated)
        return Choice(strategy: strategy, settings: updated, target: target)
    }
}

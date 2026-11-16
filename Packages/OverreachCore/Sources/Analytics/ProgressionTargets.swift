import Domain
import Foundation

/// One planned set. `weightKg` is `nil` when there is no history to base it on.
public struct PlannedSet: Hashable, Sendable {
    public var weightKg: Double?
    public var reps: Int
    public var targetRPE: Double

    public init(weightKg: Double?, reps: Int, targetRPE: Double) {
        self.weightKg = weightKg
        self.reps = reps
        self.targetRPE = targetRPE
    }
}

/// Why a target is what it is. Each reason carries its evidence (ADR-0012).
public enum ProgressionReason: Hashable, Sendable {
    case noHistory
    case topOfRangeReached(reps: Int)
    case addRepsBeforeLoad
    case belowRangeTwice
    case allRepsCompleted
    case repeatAfterMiss(consecutiveMisses: Int)
    case resetAfterMisses(consecutiveMisses: Int)
    case nextRepBlock(reps: Int)
    case loadFromEstimatedOneRepMax(estimateKg: Double, percent: Double)
    case noLoadIncrementAvailable

    public var evidence: EvidenceReference {
        switch self {
        case .noHistory, .repeatAfterMiss, .resetAfterMisses, .belowRangeTwice, .nextRepBlock:
            ProgressionEvidence.stallHeuristics
        case .topOfRangeReached, .addRepsBeforeLoad, .allRepsCompleted, .noLoadIncrementAvailable:
            ProgressionEvidence.loadOrRepProgression
        case .loadFromEstimatedOneRepMax:
            ProgressionEvidence.rirBasedRPE
        }
    }
}

/// The next session for one exercise.
public struct ExerciseTarget: Hashable, Sendable {
    public var sets: [PlannedSet]
    public var reasons: [ProgressionReason]

    public init(sets: [PlannedSet], reasons: [ProgressionReason]) {
        self.sets = sets
        self.reasons = reasons
    }
}

/// Next-session targets from history (`docs/design/progression-engine.md`). Pure and deterministic.
public enum ProgressionTargets {
    /// Tolerance on RPE when deciding whether a set was "easy enough" to progress.
    static let rpeTolerance = 0.5
    /// Consecutive misses at the same load before a linear-load reset.
    static let missesBeforeReset = 3
    /// Load kept after a linear-load reset.
    static let resetFactor = 0.9

    /// Target for the next exposure, given past exposures (oldest first).
    public static func next(history: [ExerciseExposure], settings: ProgressionSettings) -> ExerciseTarget {
        let scheme = settings.scheme
        guard let last = history.last else {
            let reps = firstTargetReps(of: scheme)
            let sets = Array(repeating: PlannedSet(weightKg: nil, reps: reps, targetRPE: scheme.targetRPE), count: scheme.sets)
            return ExerciseTarget(sets: sets, reasons: [.noHistory])
        }

        switch scheme {
        case let .doubleProgression(sets, minReps, maxReps, rpe):
            return doubleProgression(
                history: history, last: last, sets: max(1, sets),
                range: min(minReps, maxReps)...max(minReps, maxReps), rpe: rpe, increment: settings.incrementKg
            )
        case let .linearLoad(sets, reps, rpe):
            return linearLoad(history: history, last: last, sets: max(1, sets), reps: reps, rpe: rpe,
                              increment: settings.incrementKg)
        case let .repCycle(sets, blocks, rpe):
            return repCycle(history: history, last: last, sets: max(1, sets), blocks: blocks, rpe: rpe,
                            increment: settings.incrementKg)
        case let .rpeBased(sets, reps, rpe):
            return estimateBased(history: history, last: last, sets: max(1, sets), reps: reps, rpe: rpe,
                                 increment: settings.incrementKg, extraReasons: [])
        }
    }

    /// Whether `exposure` met `target`: every planned set done at ≥ the planned load and ≥ the planned reps.
    /// `nil` when the target had no loads (no history yet).
    public static func didMeet(_ target: ExerciseTarget, in exposure: ExerciseExposure) -> Bool? {
        guard target.sets.allSatisfy({ $0.weightKg != nil }) else { return nil }
        for (index, planned) in target.sets.enumerated() {
            guard index < exposure.sets.count else { return false }
            let done = exposure.sets[index]
            if (done.weightKg ?? 0) < (planned.weightKg ?? 0) - 0.001 { return false }
            if (done.reps ?? 0) < planned.reps { return false }
        }
        return true
    }

    // MARK: - Schemes

    private static func doubleProgression(
        history: [ExerciseExposure], last: ExerciseExposure, sets: Int,
        range: ClosedRange<Int>, rpe: Double, increment: Double
    ) -> ExerciseTarget {
        let weight = last.workingWeightKg
        let done = last.setsAtWorkingWeight
        let reachedTop = done.count >= sets && done.allSatisfy { set in
            (set.reps ?? 0) >= range.upperBound && rpeAllowsProgress(set.rpe, target: rpe)
        }

        if reachedTop {
            guard increment > 0 else {
                return uniform(sets: sets, weight: weight, reps: range.upperBound, rpe: rpe,
                               reasons: [.topOfRangeReached(reps: range.upperBound), .noLoadIncrementAvailable])
            }
            return uniform(sets: sets, weight: weight + increment, reps: range.lowerBound, rpe: rpe,
                           reasons: [.topOfRangeReached(reps: range.upperBound)])
        }

        let belowRange = { (exposure: ExerciseExposure) in
            exposure.setsAtWorkingWeight.contains { ($0.reps ?? 0) < range.lowerBound }
        }
        if history.count >= 2, increment > 0, belowRange(last),
           belowRange(history[history.count - 2]),
           abs(history[history.count - 2].workingWeightKg - weight) < 0.001 {
            return uniform(sets: sets, weight: max(0, weight - increment), reps: range.lowerBound, rpe: rpe,
                           reasons: [.belowRangeTwice])
        }

        let planned = (0..<sets).map { index -> PlannedSet in
            let previous = index < done.count ? (done[index].reps ?? range.lowerBound) : range.lowerBound
            let reps = min(range.upperBound, max(range.lowerBound, previous + 1))
            return PlannedSet(weightKg: weight, reps: reps, targetRPE: rpe)
        }
        return ExerciseTarget(sets: planned, reasons: [.addRepsBeforeLoad])
    }

    private static func linearLoad(
        history: [ExerciseExposure], last: ExerciseExposure, sets: Int, reps: Int, rpe: Double, increment: Double
    ) -> ExerciseTarget {
        let weight = last.workingWeightKg
        let succeeded = { (exposure: ExerciseExposure) -> Bool in
            let done = exposure.setsAtWorkingWeight
            return done.count >= sets && done.allSatisfy { ($0.reps ?? 0) >= reps && rpeAllowsProgress($0.rpe, target: rpe) }
        }

        if succeeded(last) {
            guard increment > 0 else {
                return uniform(sets: sets, weight: weight, reps: reps, rpe: rpe,
                               reasons: [.allRepsCompleted, .noLoadIncrementAvailable])
            }
            return uniform(sets: sets, weight: weight + increment, reps: reps, rpe: rpe, reasons: [.allRepsCompleted])
        }

        var misses = 0
        for exposure in history.reversed() {
            guard abs(exposure.workingWeightKg - weight) < 0.001, !succeeded(exposure) else { break }
            misses += 1
        }
        if misses >= missesBeforeReset {
            let reset = LoadPrescription.round(weight * resetFactor, toIncrement: increment)
            return uniform(sets: sets, weight: reset, reps: reps, rpe: rpe, reasons: [.resetAfterMisses(consecutiveMisses: misses)])
        }
        return uniform(sets: sets, weight: weight, reps: reps, rpe: rpe, reasons: [.repeatAfterMiss(consecutiveMisses: misses)])
    }

    private static func repCycle(
        history: [ExerciseExposure], last: ExerciseExposure, sets: Int, blocks: [Int], rpe: Double, increment: Double
    ) -> ExerciseTarget {
        let blocks = blocks.filter { $0 > 0 }
        guard !blocks.isEmpty else {
            return estimateBased(history: history, last: last, sets: sets, reps: 8, rpe: rpe, increment: increment,
                                 extraReasons: [])
        }
        let lastReps = last.setsAtWorkingWeight.compactMap(\.reps).sorted()
        let typical = lastReps.isEmpty ? blocks[0] : lastReps[lastReps.count / 2]
        let current = blocks.indices.min { abs(blocks[$0] - typical) < abs(blocks[$1] - typical) } ?? 0
        let nextReps = blocks[(current + 1) % blocks.count]
        return estimateBased(history: history, last: last, sets: sets, reps: nextReps, rpe: rpe, increment: increment,
                             extraReasons: [.nextRepBlock(reps: nextReps)])
    }

    /// Load = latest estimated 1RM × fraction for reps @ RPE. Falls back to repeating the last load.
    private static func estimateBased(
        history: [ExerciseExposure], last: ExerciseExposure, sets: Int, reps: Int, rpe: Double,
        increment: Double, extraReasons: [ProgressionReason]
    ) -> ExerciseTarget {
        let reps = max(1, reps)
        let estimate = last.bestEstimatedOneRepMax ?? history.reversed().lazy.compactMap(\.bestEstimatedOneRepMax).first
        guard let estimate, let fraction = LoadPrescription.fractionOfOneRepMax(reps: reps, rpe: rpe) else {
            return uniform(sets: sets, weight: last.workingWeightKg, reps: reps, rpe: rpe, reasons: extraReasons)
        }
        let weight = LoadPrescription.round(estimate * fraction, toIncrement: increment)
        let reason = ProgressionReason.loadFromEstimatedOneRepMax(estimateKg: estimate, percent: fraction * 100)
        return uniform(sets: sets, weight: weight, reps: reps, rpe: rpe, reasons: extraReasons + [reason])
    }

    // MARK: - Helpers

    private static func rpeAllowsProgress(_ rpe: Double?, target: Double) -> Bool {
        guard let rpe else { return true }
        return rpe <= target + rpeTolerance
    }

    private static func uniform(
        sets: Int, weight: Double, reps: Int, rpe: Double, reasons: [ProgressionReason]
    ) -> ExerciseTarget {
        ExerciseTarget(
            sets: Array(repeating: PlannedSet(weightKg: weight, reps: reps, targetRPE: rpe), count: sets),
            reasons: reasons
        )
    }

    private static func firstTargetReps(of scheme: ProgressionScheme) -> Int {
        switch scheme {
        case let .doubleProgression(_, minReps, _, _): minReps
        case let .linearLoad(_, reps, _), let .rpeBased(_, reps, _): reps
        case let .repCycle(_, blocks, _): blocks.first ?? 8
        }
    }
}

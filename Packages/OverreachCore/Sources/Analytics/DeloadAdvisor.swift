import Domain
import Foundation

/// A signal that contributed to a deload proposal.
public enum DeloadSignal: Hashable, Sendable {
    case liftsStalled(count: Int)
    case rpeCreep(lifts: Int)
    case performanceDrop(lifts: Int)
    case weeksSinceDeload(Int)
    /// Last 7 days' load as a multiple of the usual week (e.g. 1.6 = 60 % above).
    case weeklyLoadSpike(ratio: Double)
    /// Recovery over the last 7 days (`deload-recovery-signals`): they only reinforce training signals.
    case hrvSuppressed(days: Int)
    case restingHeartRateElevated(days: Int)
    case shortSleep(nights: Int)
    case poorWellbeing(checkIns: Int)

    public var evidence: EvidenceReference {
        switch self {
        case .liftsStalled, .performanceDrop: ProgressionEvidence.deloadDesign
        case .rpeCreep: ProgressionEvidence.rpeCreep
        case .weeksSinceDeload: ProgressionEvidence.deloadPractice
        case .weeklyLoadSpike: ProgressionEvidence.weeklyLoadChange
        case .hrvSuppressed, .restingHeartRateElevated, .shortSleep, .poorWellbeing:
            ProgressionEvidence.deloadRecoverySignals
        }
    }

    /// Stalls, an e1RM drop or RPE creep: evidence from training itself, which a proposal always needs.
    public var isPerformanceSignal: Bool {
        switch self {
        case .liftsStalled, .performanceDrop, .rpeCreep: true
        default: false
        }
    }
}

/// A deload week: same exercises, fewer sets, a bit less load, easier efforts. Training is reduced, not stopped:
/// a full week off mid-programme cost some strength in the one RCT available (Coleman et al. 2024).
public struct DeloadPlan: Hashable, Sendable {
    public var durationDays: Int
    /// Multiply the number of working sets by this.
    public var setMultiplier: Double
    /// Multiply working loads by this.
    public var loadMultiplier: Double
    public var maximumRPE: Double

    public static let standard = DeloadPlan(durationDays: 7, setMultiplier: 0.5, loadMultiplier: 0.9, maximumRPE: 7)

    /// `target` reduced for a deload week: the same exercise with fewer sets (at least one), less load rounded to the
    /// exercise's increment, and RPE capped. Rep targets stay. The deload reason comes first.
    public func applied(to target: ExerciseTarget, incrementKg: Double) -> ExerciseTarget {
        guard !target.sets.isEmpty else { return target }
        let count = max(1, Int((Double(target.sets.count) * setMultiplier).rounded()))
        let sets = target.sets.prefix(count).map { planned in
            PlannedSet(
                weightKg: planned.weightKg.map { LoadPrescription.round($0 * loadMultiplier, toIncrement: incrementKg) },
                reps: planned.reps,
                targetRPE: min(planned.targetRPE, maximumRPE)
            )
        }
        let reason = ProgressionReason.deloadWeek(
            sets: count, loadReduction: ((1 - loadMultiplier) * 1_000).rounded() / 1_000, maximumRPE: maximumRPE
        )
        return ExerciseTarget(sets: Array(sets), reasons: [reason] + target.reasons)
    }

    public init(durationDays: Int, setMultiplier: Double, loadMultiplier: Double, maximumRPE: Double) {
        self.durationDays = durationDays
        self.setMultiplier = setMultiplier
        self.loadMultiplier = loadMultiplier
        self.maximumRPE = maximumRPE
    }
}

public struct DeloadProposal: Hashable, Sendable {
    public var signals: [DeloadSignal]
    public var score: Double
    public var plan: DeloadPlan
}

/// Proposes a whole-programme deload from training signals, reinforced by sustained recovery signals.
///
/// Deloads are proposed from evidence of accumulated fatigue, not on a timer alone: the Delphi consensus defines
/// them as reduced training stress to manage fatigue (Bell et al. 2023), and the only RCT found a cost to strength
/// from a routine 1-week break (Coleman et al. 2024). No recovery marker is decisive on its own (Meeusen et al.
/// 2013; Bellenger et al. 2016), so recovery adds at most `recoveryWeightCap` and a proposal always needs a
/// performance signal. Being sick recently gives no proposal: return to training gradually instead
/// (`illness-return`). Weights and thresholds are heuristics and configurable.
public enum DeloadAdvisor {
    public struct Settings: Hashable, Sendable {
        public var plannedIntervalWeeks = 6
        public var threshold = 3.0
        public var stalledWeight = 2.0
        public var performanceDropWeight = 2.0
        public var rpeCreepWeight = 1.0
        public var intervalWeight = 1.0
        /// A weak signal: the evidence does not support load ratios as injury or fatigue predictors.
        public var loadSpikeWeight = 1.0
        /// Last week above this multiple of the usual week counts as a spike.
        public var loadSpikeLimit = 1.5
        /// e1RM below the recent best by more than this counts as a drop.
        public var performanceDropFraction = 0.03
        /// Window for RPE creep and performance drops.
        public var lookbackDays = 28
        /// Points per sustained recovery signal, and the most they add together.
        public var recoveryWeight = 1.0
        public var recoveryWeightCap = 2.0
        /// Days of the last 7 each recovery signal needs to count.
        public var hrvLowDays = 5
        public var restingHeartRateHighDays = 4
        public var shortSleepNights = 4
        public var poorWellbeingCheckIns = 3
        public var plan = DeloadPlan.standard

        public init() {}
    }

    public struct Lift: Hashable, Sendable {
        public var history: [ExerciseExposure]
        public var settings: ProgressionSettings

        public init(history: [ExerciseExposure], settings: ProgressionSettings) {
            self.history = history
            self.settings = settings
        }
    }

    public static func proposal(
        lifts: [Lift],
        lastDeload: Date?,
        weeklyLoad: WeeklyLoadChange? = nil,
        recovery: RecoveryTrend? = nil,
        now: Date,
        settings: Settings = Settings()
    ) -> DeloadProposal? {
        if recovery?.sickRecently == true { return nil }
        let mainLifts = lifts.filter(\.settings.isMainLift)
        let considered = mainLifts.isEmpty ? lifts : mainLifts
        var signals: [DeloadSignal] = []
        var score = 0.0

        let stalled = considered.filter {
            StallDetection.status(history: $0.history, settings: $0.settings).isStalled
        }.count
        if stalled >= 2 {
            signals.append(.liftsStalled(count: stalled))
            score += settings.stalledWeight
        }

        let since = now.addingTimeInterval(-Double(settings.lookbackDays) * 86_400)
        let dropped = considered.filter {
            hasPerformanceDrop($0.history, since: since, fraction: settings.performanceDropFraction)
        }.count
        if dropped >= 2 {
            signals.append(.performanceDrop(lifts: dropped))
            score += settings.performanceDropWeight
        }

        let creeping = considered.filter { hasRPECreep($0.history, since: since) }.count
        if creeping >= 2 {
            signals.append(.rpeCreep(lifts: creeping))
            score += settings.rpeCreepWeight
        }

        let firstSession = lifts.compactMap { $0.history.first?.date }.min()
        if let reference = lastDeload ?? firstSession {
            let weeks = Int(now.timeIntervalSince(reference) / (7 * 86_400))
            if weeks >= settings.plannedIntervalWeeks {
                signals.append(.weeksSinceDeload(weeks))
                score += settings.intervalWeight
            }
        }

        if let weeklyLoad, weeklyLoad.ratio > settings.loadSpikeLimit {
            signals.append(.weeklyLoadSpike(ratio: weeklyLoad.ratio))
            score += settings.loadSpikeWeight
        }

        if let recovery {
            var recoverySignals: [DeloadSignal] = []
            if recovery.hrvLowDays >= settings.hrvLowDays {
                recoverySignals.append(.hrvSuppressed(days: recovery.hrvLowDays))
            }
            if recovery.restingHeartRateHighDays >= settings.restingHeartRateHighDays {
                recoverySignals.append(.restingHeartRateElevated(days: recovery.restingHeartRateHighDays))
            }
            if recovery.shortSleepNights >= settings.shortSleepNights {
                recoverySignals.append(.shortSleep(nights: recovery.shortSleepNights))
            }
            if recovery.poorWellbeingCheckIns >= settings.poorWellbeingCheckIns {
                recoverySignals.append(.poorWellbeing(checkIns: recovery.poorWellbeingCheckIns))
            }
            signals += recoverySignals
            score += min(settings.recoveryWeightCap, Double(recoverySignals.count) * settings.recoveryWeight)
        }

        guard score >= settings.threshold, signals.contains(where: \.isPerformanceSignal) else { return nil }
        return DeloadProposal(signals: signals, score: score, plan: settings.plan)
    }

    /// Latest e1RM more than `fraction` below the best of the earlier exposures in the window.
    static func hasPerformanceDrop(_ history: [ExerciseExposure], since: Date, fraction: Double) -> Bool {
        let window = history.filter { $0.date >= since }
        guard window.count >= 2, let latest = window.last?.bestEstimatedOneRepMax,
              let best = window.dropLast().compactMap(\.bestEstimatedOneRepMax).max() else { return false }
        return latest < best * (1 - fraction)
    }

    /// Same load and at least the same reps across the last 3 exposures in the window, with RPE rising ≥ 1 point.
    static func hasRPECreep(_ history: [ExerciseExposure], since: Date) -> Bool {
        let window = history.filter { $0.date >= since }.suffix(3)
        guard window.count == 3, let first = window.first else { return false }
        let weight = first.workingWeightKg
        guard window.allSatisfy({ abs($0.workingWeightKg - weight) < 0.001 }) else { return false }

        let averages = window.map { exposure -> (reps: Double, rpe: Double?) in
            let sets = exposure.setsAtWorkingWeight
            let reps = Double(sets.compactMap(\.reps).reduce(0, +)) / Double(max(1, sets.count))
            let rpes = sets.compactMap(\.rpe)
            return (reps, rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count))
        }
        guard let firstRPE = averages.first?.rpe, let lastRPE = averages.last?.rpe,
              let firstReps = averages.first?.reps, let lastReps = averages.last?.reps else { return false }
        return lastReps >= firstReps && lastRPE - firstRPE >= 1
    }
}

import Domain
import Foundation

/// A signal that contributed to a deload proposal.
public enum DeloadSignal: Hashable, Sendable {
    case liftsStalled(count: Int, mainLifts: Bool)
    case rpeCreep(lifts: Int)
    case performanceDrop(lifts: Int)
    case weeksSinceDeload(Int)
    /// No deload or break in the whole history read, which spans this many weeks.
    case noDeloadInHistory(weeks: Int)
    /// Last 7 days' load as a multiple of the usual week (e.g. 1.6 = 60 % above).
    case weeklyLoadSpike(ratio: Double)
    /// Recovery over the last 7 days (`deload-recovery-signals`): they only reinforce training signals.
    case hrvSuppressed(days: Int)
    case restingHeartRateElevated(days: Int)
    case shortSleep(nights: Int)
    case poorWellbeing(checkIns: Int)
    /// The athlete reported more stress than usual in the last two weeks. It is context for the recovery signals
    /// and changes the week proposed; it adds no points (`deload-life-stress`).
    case lifeStressReported

    public var evidence: EvidenceReference {
        switch self {
        case .liftsStalled, .performanceDrop: ProgressionEvidence.deloadDesign
        case .rpeCreep: ProgressionEvidence.rpeCreep
        case .weeksSinceDeload, .noDeloadInHistory: ProgressionEvidence.deloadPractice
        case .weeklyLoadSpike: ProgressionEvidence.weeklyLoadChange
        case .hrvSuppressed, .restingHeartRateElevated, .shortSleep, .poorWellbeing:
            ProgressionEvidence.deloadRecoverySignals
        case .lifeStressReported: ProgressionEvidence.deloadLifeStress
        }
    }

    /// Stalls, an e1RM drop or RPE creep: evidence from training itself, which a proposal always needs.
    public var isPerformanceSignal: Bool {
        switch self {
        case .liftsStalled, .performanceDrop, .rpeCreep: true
        default: false
        }
    }

    var isFatigueSignal: Bool {
        switch self {
        case .liftsStalled, .weeksSinceDeload, .noDeloadInHistory, .lifeStressReported: false
        default: true
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

    /// A steadier week for an athlete who reports unusual stress (`deload-life-stress`): the same training days
    /// at a comfortable effort, a quarter fewer sets and almost the same loads. Stress adds to the load the body
    /// recovers from, but moving still helps how people feel, so this reduces demand less than `standard`.
    public static let stressAware = DeloadPlan(
        durationDays: 7, setMultiplier: 0.75, loadMultiplier: 0.95, maximumRPE: 8
    )

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
    public var stalledExerciseIDs: [UUID]
    public var score: Double
    public var plan: DeloadPlan
    /// What the athlete said about stress. `.unanswered` lets Today ask before it proposes a week.
    public var lifeStress: RecoveryTrend.LifeStress = .unanswered
}

/// Proposes a whole-programme deload from training signals, reinforced by sustained recovery signals.
///
/// Deloads are proposed from evidence of accumulated fatigue, not on a timer alone: the Delphi consensus defines
/// them as reduced training stress to manage fatigue (Bell et al. 2023), and the only RCT found a cost to strength
/// from a routine 1-week break (Coleman et al. 2024). No recovery marker is decisive on its own (Meeusen et al.
/// 2013; Bellenger et al. 2016), so recovery adds at most `recoveryWeightCap` and a proposal always needs a
/// performance signal and a sign of fatigue. After recent illness the rules suppress deload advice
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
        public var lookbackDays = LiftStatus.recentDays
        /// Points per sustained recovery signal, and the most they add together.
        public var recoveryWeight = 1.0
        public var recoveryWeightCap = 2.0
        /// Days of the last 7 each recovery signal needs to count.
        public var hrvTrendLowDays = 5
        public var restingHeartRateHighDays = 4
        public var shortSleepNights = 4
        public var poorWellbeingCheckIns = 3
        public var plan = DeloadPlan.standard
        /// Used instead of `plan` when the athlete reports unusual stress.
        public var stressPlan = DeloadPlan.stressAware

        public init() {}
    }

    /// - Parameter lastRecovery: from `RecoveryHistory.lastRecovery`, so every screen counts from the same day.
    public static func proposal(
        lifts: [LiftStatus],
        lastRecovery: LastRecovery?,
        weeklyLoad: WeeklyLoadChange? = nil,
        recovery: RecoveryTrend? = nil,
        now: Date,
        settings: Settings = Settings(),
        calendar: Calendar = .current,
        currentExerciseIDs: Set<UUID>? = nil
    ) -> DeloadProposal? {
        if recovery?.sickRecently == true { return nil }
        let today = CalendarDay(now, calendar: calendar)
        // No repeat advice in the week after a deload or a break (ADR-0029).
        if let lastRecovery, PlanReviewer.days(from: lastRecovery.lastDay, to: today, calendar: calendar) <= 7 {
            return nil
        }
        let recoveryEnd = lastRecovery.map { $0.lastDay.adding(days: 1, calendar: calendar).startDate(in: calendar) }
        let current = lifts.filter { lift in
            lift.trainedRecently && (currentExerciseIDs?.contains(lift.exerciseID) ?? true)
        }
        let mainLifts = current.filter(\.settings.isMainLift)
        let considered = mainLifts.isEmpty ? current : mainLifts
        var signals: [DeloadSignal] = []
        var score = 0.0

        let stalled = considered.filter(\.isStalled).map(\.exerciseID)
        if stalled.count >= 2 {
            signals.append(.liftsStalled(count: stalled.count, mainLifts: !mainLifts.isEmpty))
            score += settings.stalledWeight
        }

        // Lighter sessions during and right after a deload or a break are detraining, not accumulated fatigue:
        // drops and RPE creep only compare sessions since the last recovery period.
        let since = max(now.addingTimeInterval(-Double(settings.lookbackDays) * 86_400), recoveryEnd ?? .distantPast)
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

        if let lastRecovery {
            let weeks = PlanReviewer.days(from: lastRecovery.lastDay, to: today, calendar: calendar) / 7
            if weeks >= settings.plannedIntervalWeeks {
                signals.append(.weeksSinceDeload(weeks))
                score += settings.intervalWeight
            }
        } else if let first = lifts.compactMap({ $0.history.first?.date }).min() {
            let firstDay = CalendarDay(first, calendar: calendar)
            let weeks = PlanReviewer.days(from: firstDay, to: today, calendar: calendar) / 7
            if weeks >= settings.plannedIntervalWeeks {
                signals.append(.noDeloadInHistory(weeks: weeks))
                score += settings.intervalWeight
            }
        }

        if let weeklyLoad, weeklyLoad.ratio > settings.loadSpikeLimit {
            signals.append(.weeklyLoadSpike(ratio: weeklyLoad.ratio))
            score += settings.loadSpikeWeight
        }

        if let recovery {
            var recoverySignals: [DeloadSignal] = []
            if recovery.hrvTrendLowDays >= settings.hrvTrendLowDays {
                recoverySignals.append(.hrvSuppressed(days: recovery.hrvTrendLowDays))
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
            if recovery.lifeStress == .reported { signals.append(.lifeStressReported) }
            score += min(settings.recoveryWeightCap, Double(recoverySignals.count) * settings.recoveryWeight)
        }

        guard score >= settings.threshold, signals.contains(where: \.isPerformanceSignal),
              signals.contains(where: \.isFatigueSignal) else { return nil }
        let lifeStress = recovery?.lifeStress ?? .unanswered
        return DeloadProposal(
            signals: signals, stalledExerciseIDs: stalled.count >= 2 ? stalled : [], score: score,
            plan: lifeStress == .reported ? settings.stressPlan : settings.plan, lifeStress: lifeStress
        )
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

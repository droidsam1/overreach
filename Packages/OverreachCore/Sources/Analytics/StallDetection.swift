import Domain
import Foundation

/// Ways to get a stalled exercise moving again, in order of preference.
public enum StallSuggestion: Hashable, Codable, Sendable {
    /// The last miss was by one rep: use a smaller load jump.
    case microload(incrementKg: Double)
    /// Linear load stopped working: switch to double progression (rep progression works as well; Plotkin 2022).
    case switchToDoubleProgression
    /// Change the rep range (e.g. 8–12 → 6–10) to vary the stimulus.
    case changeRepRange
    /// Weekly fractional sets for the target muscle are below the range.
    case addSet(weeklySets: Double)
    /// Weekly fractional sets for the target muscle are above the range.
    case removeSet(weeklySets: Double)
    /// Swap to a close variation for a few weeks.
    case swapVariation(weeks: ClosedRange<Int>)
    /// Reduce this lift's load for a week.
    case deloadLift(loadReduction: Double)

    public var evidence: EvidenceReference {
        switch self {
        case .switchToDoubleProgression: ProgressionEvidence.loadOrRepProgression
        case .addSet, .removeSet: ProgressionEvidence.volumeDoseResponse
        case .deloadLift: ProgressionEvidence.deloadDesign
        case .microload, .changeRepRange, .swapVariation: ProgressionEvidence.stallHeuristics
        }
    }
}

public enum ExerciseStatus: Hashable, Codable, Sendable {
    case notEnoughData
    case progressing
    case holding
    case stalled(suggestions: [StallSuggestion])

    public var isStalled: Bool {
        if case .stalled = self { return true }
        return false
    }
}

/// Stall detection (heuristic thresholds, configurable; see `docs/evidence.md#stall-heuristics`).
public enum StallDetection {
    public struct Thresholds: Hashable, Sendable {
        /// Exposures looked at to decide whether the lift is stalled.
        public var recentExposures = 3
        /// Earlier exposures used as the comparison baseline.
        public var baselineExposures = 6
        /// e1RM improvement below this fraction counts as "no progress".
        public var minimumImprovement = 0.01
        /// Missed targets (within the recent exposures) needed to call a stall.
        public var minimumMisses = 2
        /// Weekly fractional sets per muscle considered adequate (dose-response with diminishing returns).
        public var weeklySetRange: ClosedRange<Double> = 10...20

        public init() {}
    }

    public static func status(
        history: [ExerciseExposure],
        settings: ProgressionSettings,
        weeklyFractionalSets: Double? = nil,
        thresholds: Thresholds = Thresholds()
    ) -> ExerciseStatus {
        assessment(history: history, settings: settings, weeklyFractionalSets: weeklyFractionalSets,
                   thresholds: thresholds).status
    }

    static func assessment(
        history: [ExerciseExposure], settings: ProgressionSettings, weeklyFractionalSets: Double? = nil,
        thresholds: Thresholds = Thresholds()
    ) -> (status: ExerciseStatus, facts: StallFacts?) {
        guard let facts = facts(history: history, settings: settings, thresholds: thresholds) else {
            return (.notEnoughData, nil)
        }
        return (status(facts: facts, settings: settings, weeklyFractionalSets: weeklyFractionalSets,
                       thresholds: thresholds), facts)
    }

    private static func status(
        facts: StallFacts, settings: ProgressionSettings, weeklyFractionalSets: Double?, thresholds: Thresholds
    ) -> ExerciseStatus {
        if facts.recentBestKg > facts.previousBestKg * (1 + thresholds.minimumImprovement) { return .progressing }
        guard facts.misses >= thresholds.minimumMisses else { return .holding }

        return .stalled(suggestions: suggestions(
            settings: settings, lastShortfall: facts.lastShortfall,
            weeklyFractionalSets: weeklyFractionalSets, range: thresholds.weeklySetRange
        ))
    }

    /// Details of the flat window that caused the stall, with the working set behind its best estimate.
    static func explanation(
        exerciseID: UUID, history: [ExerciseExposure], status: ExerciseStatus, facts: StallFacts?
    ) -> StallExplanation? {
        guard case let .stalled(suggestions) = status, let facts else { return nil }
        let recent = history.suffix(facts.recentSessions)
        guard let first = recent.first, let last = recent.last,
              let best = recent.compactMap(\.bestEstimatedSet).max(by: { $0.kg < $1.kg }) else { return nil }
        return StallExplanation(
            exerciseID: exerciseID, stalledSince: first.date, bestEstimatedOneRepMax: best.kg,
            bestSet: best.set, lastExposure: last.date, suggestions: suggestions
        )
    }

    /// The numbers behind the status, to explain it; `nil` without enough history.
    public static func facts(
        history: [ExerciseExposure], settings: ProgressionSettings, thresholds: Thresholds = Thresholds()
    ) -> StallFacts? {
        let recentCount = max(1, thresholds.recentExposures)
        guard history.count > recentCount else { return nil }

        let recentStart = history.count - recentCount
        let baselineStart = max(0, recentStart - thresholds.baselineExposures)
        guard let bestRecent = history[recentStart...].compactMap(\.bestEstimatedOneRepMax).max(),
              let bestBefore = history[baselineStart..<recentStart].compactMap(\.bestEstimatedOneRepMax).max() else {
            return nil
        }

        var misses = 0
        var lastShortfall: Int?
        for index in recentStart..<history.count {
            let target = ProgressionTargets.next(history: Array(history[..<index]), settings: settings)
            guard ProgressionTargets.didMeet(target, in: history[index]) == false else { continue }
            misses += 1
            lastShortfall = shortfall(of: target, in: history[index])
        }
        return StallFacts(
            recentBestKg: bestRecent, previousBestKg: bestBefore, recentSessions: recentCount,
            previousSessions: recentStart - baselineStart, misses: misses, lastShortfall: lastShortfall
        )
    }

    /// Largest rep gap between the plan and what was done.
    static func shortfall(of target: ExerciseTarget, in exposure: ExerciseExposure) -> Int {
        var worst = 0
        for (index, planned) in target.sets.enumerated() {
            let done = index < exposure.sets.count ? (exposure.sets[index].reps ?? 0) : 0
            worst = max(worst, planned.reps - done)
        }
        return worst
    }

    private static func suggestions(
        settings: ProgressionSettings, lastShortfall: Int?,
        weeklyFractionalSets: Double?, range: ClosedRange<Double>
    ) -> [StallSuggestion] {
        var result: [StallSuggestion] = []
        if let lastShortfall, lastShortfall <= 1, settings.incrementKg > 0 {
            result.append(.microload(incrementKg: settings.incrementKg / 2))
        }
        if case .linearLoad = settings.scheme {
            result.append(.switchToDoubleProgression)
        } else {
            result.append(.changeRepRange)
        }
        if let weeklyFractionalSets {
            if weeklyFractionalSets < range.lowerBound {
                result.append(.addSet(weeklySets: weeklyFractionalSets))
            } else if weeklyFractionalSets > range.upperBound {
                result.append(.removeSet(weeklySets: weeklyFractionalSets))
            }
        }
        result.append(.swapVariation(weeks: 3...4))
        result.append(.deloadLift(loadReduction: 0.1))
        return result
    }
}

/// What the stall status is based on (`stall-heuristics`): best estimated 1RM of the recent sessions against the
/// ones before, and how many recent sessions missed their target.
public struct StallFacts: Hashable, Codable, Sendable {
    public let recentBestKg: Double
    public let previousBestKg: Double
    public let recentSessions: Int
    public let previousSessions: Int
    /// Recent sessions that did not meet their target.
    public let misses: Int
    /// Reps missing in the last missed session.
    public let lastShortfall: Int?
}

public struct StallExplanation: Hashable, Sendable {
    public let exerciseID: UUID
    public let stalledSince: Date
    public let bestEstimatedOneRepMax: Double
    public let bestSet: WorkoutSet
    public let lastExposure: Date
    public let suggestions: [StallSuggestion]
}

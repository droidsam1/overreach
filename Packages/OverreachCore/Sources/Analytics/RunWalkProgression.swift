import Domain
import Foundation

/// A small run/walk progression towards a distance goal, from the athlete's own runs and pain answers.
/// The dose defaults are `run-walk-progression` in the evidence register. Blocks are distances, never paces.
public enum RunWalkProgression {
    public static let evidence = EvidenceReference(key: "run-walk-progression", level: .heuristic)

    public struct Settings: Sendable {
        public var historyDays = 28
        /// A run older than this means the athlete missed a fortnight: repeat, do not progress.
        public var gapDays = 14
        public var startRunMeters = 500
        public var startWalkMeters = 500
        public var stepMeters = 500
        public var minimumStepMeters = 250
        /// One step adds at most this share of the longest recent pain-free run.
        public var maximumStepFraction = 0.25
        public var walkBreakMeters = 500
        public var shortWalkBreakMeters = 250
        public var roundingMeters = 250

        public init() {}
    }

    public enum Block: Hashable, Sendable {
        case run(meters: Int)
        case walk(meters: Int)

        public var meters: Int {
            switch self {
            case .run(let meters), .walk(let meters): meters
            }
        }
    }

    public enum Phase: Hashable, Sendable {
        /// No usable run yet: begin with short running blocks.
        case start
        /// The last run had no reported pain: add one small step.
        case progress
        /// Pain after the last run, or a missed fortnight: repeat the last pain-free distance.
        case hold(afterGap: Bool)
        /// Pain after two runs in a row: go back one step.
        case stepBack
        case goalReached
    }

    public struct Result: Hashable, Sendable {
        public let phase: Phase
        public let blocks: [Block]
        /// Pain-free distance the blocks start from, when known.
        public let baseMeters: Int?

        public var runningMeters: Int {
            blocks.reduce(0) { total, block in
                if case .run(let meters) = block { total + meters } else { total }
            }
        }
    }

    /// `outcomes` are the confirmed runs of the goal with the athlete's pain answers; a run without an answer is not
    /// treated as painful. Returns nil without a distance goal.
    public static func advise(
        goal: RunningGoal?, runs: [RunActivity], outcomes: [PlannedRunCompletion], now: Date,
        calendar: Calendar = .current, settings: Settings = .init()
    ) -> Result? {
        guard let goal, goal.distanceMeters > 0 else { return nil }
        if outcomes.contains(where: goal.isMet(by:)) {
            return Result(phase: .goalReached, blocks: [], baseMeters: nil)
        }
        let today = CalendarDay(now, calendar: calendar)
        let start = today.adding(days: -(settings.historyDays - 1), calendar: calendar).startDate(in: calendar)
        let history = RunDeduplication.removingDuplicates(runs.filter { run in
            run.startedAt <= now && run.startedAt >= start && run.distanceMeters.isFinite && run.distanceMeters > 0
                && run.durationSeconds.isFinite && run.durationSeconds > 0
        }).sorted { $0.startedAt < $1.startedAt }
        let painful = { (run: RunActivity) -> Bool in
            outcomes.contains { $0.matches(run) && ($0.painDuring == true || $0.painAfter == true) }
        }
        let painFree = history.filter { !painful($0) }
        guard let last = history.last, let longest = painFree.map(\.distanceMeters).max() else {
            // Nothing recent, or only runs that hurt: begin gently.
            return Result(phase: .start, blocks: starterBlocks(settings), baseMeters: nil)
        }
        let goalMeters = goal.distanceMeters
        let base = min(goalMeters, rounded(longest, to: settings.roundingMeters))
        guard base >= settings.roundingMeters else {
            return Result(phase: .start, blocks: starterBlocks(settings), baseMeters: nil)
        }
        let step = stepSize(base: base, settings: settings)

        let lastTwoPainful = history.suffix(2).count == 2 && history.suffix(2).allSatisfy(painful)
        if lastTwoPainful {
            let back = max(settings.startRunMeters, base - step)
            return Result(phase: .stepBack, blocks: [.run(meters: back)], baseMeters: base)
        }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.startedAt),
                                          to: calendar.startOfDay(for: now)).day ?? 0
        if painful(last) || gap > settings.gapDays {
            return Result(phase: .hold(afterGap: !painful(last)), blocks: [.run(meters: base)], baseMeters: base)
        }
        let next = min(goalMeters, base + step)
        guard next > base else {
            return Result(phase: .progress, blocks: [.run(meters: base)], baseMeters: base)
        }
        let added = next - base
        let walk = next >= goalMeters ? 0
            : (base * 2 >= goalMeters ? settings.shortWalkBreakMeters : settings.walkBreakMeters)
        // Reaching the goal distance removes the walk break; before that the extra running follows a break.
        let blocks: [Block] = walk == 0 ? [.run(meters: next)]
            : [.run(meters: base), .walk(meters: walk), .run(meters: added)]
        return Result(phase: .progress, blocks: blocks, baseMeters: base)
    }

    private static func starterBlocks(_ settings: Settings) -> [Block] {
        [.run(meters: settings.startRunMeters), .walk(meters: settings.startWalkMeters),
         .run(meters: settings.startRunMeters)]
    }

    private static func stepSize(base: Int, settings: Settings) -> Int {
        let capped = Int((Double(base) * settings.maximumStepFraction).rounded(.down))
        let rounded = capped / settings.roundingMeters * settings.roundingMeters
        return max(settings.minimumStepMeters, min(settings.stepMeters, rounded))
    }

    private static func rounded(_ meters: Double, to unit: Int) -> Int {
        Int((meters / Double(unit)).rounded(.down)) * unit
    }
}

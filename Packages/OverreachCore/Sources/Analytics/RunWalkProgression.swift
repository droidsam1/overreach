import Domain
import Foundation

/// A small run/walk progression towards a distance goal, from the athlete's own runs and pain answers.
/// The dose defaults are `run-walk-progression` in the evidence register. Blocks are distances, never paces.
///
/// The whole session, walking included, stays within 10% of the longest run of the last 30 days: the single-session
/// spike with the clearest link to overuse injury. Inside that cap, progress turns walking into running.
public enum RunWalkProgression {
    public static let evidence = EvidenceReference(key: "run-walk-progression", level: .heuristic)

    public struct Settings: Sendable {
        /// Window for the longest recent run, as in the single-session study.
        public var historyDays = 30
        /// A run older than this means the athlete missed a fortnight: repeat, do not progress.
        public var gapDays = 14
        /// A session stays within this increase over the longest run of the window.
        public var sessionIncreaseFraction = 0.10
        public var startRunMeters = 500
        public var startWalkMeters = 500
        public var startRepeats = 2
        /// How much a continuous running stretch grows after a run without pain.
        public var segmentStepMeters = 250
        /// Walk break when the watch has not measured the athlete's own.
        public var defaultWalkMeters = 250
        public var minimumWalkMeters = 100
        public var maximumWalkMeters = 500
        /// A step back shortens the session to this share of the longest pain-free run.
        public var stepBackFraction = 0.9
        public var roundingMeters = 100

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
        /// The last run had no reported pain: one small step.
        case progress
        /// Pain after the last run, or a missed fortnight: repeat the last pain-free session.
        case hold(afterGap: Bool)
        /// Pain after two runs in a row: go back one step.
        case stepBack
        case goalReached
    }

    public struct Result: Hashable, Sendable {
        public let phase: Phase
        public let blocks: [Block]
        /// Longest continuous running stretch without reported pain, when known.
        public let continuousMeters: Int?
        /// The session ceiling: 10% over the longest run of the last 30 days, or the goal distance.
        public let ceilingMeters: Int?
        /// The watch separated running from walking in the runs used.
        public let usesWatchSplits: Bool

        public var totalMeters: Int { blocks.reduce(0) { $0 + $1.meters } }
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
            return Result(phase: .goalReached, blocks: [], continuousMeters: nil, ceilingMeters: nil,
                          usesWatchSplits: false)
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
        let unit = settings.roundingMeters
        // Every recent run counts for the ceiling, painful or not: it measures exposure, not tolerance.
        let longest = history.map(\.distanceMeters).max()
        let ceiling = longest.map { min(goal.distanceMeters, down($0 * (1 + settings.sessionIncreaseFraction), unit)) }
        let continuous = down(painFree.map(\.longestContinuousRunMeters).max() ?? 0, unit)
        let session = down(painFree.map(\.distanceMeters).max() ?? 0, unit)
        let splits = painFree.contains { $0.runWalk != nil }
        let result = { (phase: Phase, blocks: [Block]) in
            Result(phase: phase, blocks: blocks, continuousMeters: continuous > 0 ? continuous : nil,
                   ceilingMeters: ceiling, usesWatchSplits: splits)
        }
        guard let last = history.last, let ceiling, session >= unit else {
            let blocks = layout(run: settings.startRunMeters, walk: settings.startWalkMeters,
                                repeats: settings.startRepeats)
            return result(.start, blocks)
        }
        let walk = walkBreak(painFree, settings: settings)
        let run = max(continuous, settings.segmentStepMeters)

        if history.suffix(2).count == 2, history.suffix(2).allSatisfy(painful) {
            let shorter = max(settings.startRunMeters, run - settings.segmentStepMeters)
            let total = min(ceiling, down(Double(session) * settings.stepBackFraction, unit))
            return result(.stepBack, layout(run: shorter, walk: walk, total: total))
        }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.startedAt),
                                          to: calendar.startOfDay(for: now)).day ?? 0
        if painful(last) || gap > settings.gapDays {
            let afterGap = !painful(last)
            return result(.hold(afterGap: afterGap), layout(run: run, walk: walk, total: min(ceiling, session)))
        }
        // Within one step of the ceiling, the walk break goes: the session is already within the 10% cap.
        let longer = run + settings.segmentStepMeters
        let stretch = longer + settings.segmentStepMeters >= ceiling ? ceiling : longer
        return result(.progress, layout(run: stretch, walk: walk, total: ceiling))
    }

    /// Repeats of a running stretch with walk breaks between, up to `total`. A shorter last run fills what is left.
    static func layout(run: Int, walk: Int, total: Int, minimumRun: Int = 100) -> [Block] {
        guard total > 0 else { return [] }
        guard run < total, walk > 0 else { return [.run(meters: min(run, total))] }
        var blocks: [Block] = []
        var covered = 0
        while covered + (blocks.isEmpty ? 0 : walk) + run <= total {
            if !blocks.isEmpty {
                blocks.append(.walk(meters: walk))
                covered += walk
            }
            blocks.append(.run(meters: run))
            covered += run
        }
        let left = total - covered - walk
        if left >= minimumRun {
            blocks += [.walk(meters: walk), .run(meters: left)]
        }
        return blocks
    }

    private static func layout(run: Int, walk: Int, repeats: Int) -> [Block] {
        (0..<repeats).flatMap { index in
            index == 0 ? [Block.run(meters: run)] : [.walk(meters: walk), .run(meters: run)]
        }
    }

    /// The athlete's own typical walk break, measured by the watch, or the default.
    private static func walkBreak(_ runs: [RunActivity], settings: Settings) -> Int {
        guard let measured = runs.last(where: { $0.runWalk?.walking != nil })?.runWalk?.walking?.averageSegmentMeters
        else { return settings.defaultWalkMeters }
        let rounded = Int((measured / 50).rounded()) * 50
        return min(settings.maximumWalkMeters, max(settings.minimumWalkMeters, rounded))
    }

    private static func down(_ meters: Double, _ unit: Int) -> Int {
        meters.isFinite && meters > 0 ? Int((meters / Double(unit)).rounded(.down)) * unit : 0
    }
}

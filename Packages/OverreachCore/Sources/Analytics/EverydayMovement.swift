import Domain
import Foundation

/// Evidence behind the everyday-movement rules (ADR-0010, `docs/evidence.md`, Daily activity).
public enum MovementEvidence {
    /// Active recovery gives a small-to-moderate reduction in soreness and perceived fatigue (Dupuy et al. 2018).
    public static let activeRecovery = EvidenceReference(key: "walking-active-recovery", level: .moderate)
    /// ≈ 5,000 steps a day or fewer blunted the metabolic response to exercise (Burton & Coyle 2021).
    public static let lowSteps = EvidenceReference(key: "low-steps-exercise-resistance", level: .moderate)
    /// Only walking above the personal baseline counts as extra load; thresholds are product heuristics.
    public static let walkingAboveBaseline = EvidenceReference(key: "walking-load-baseline", level: .heuristic)
}

/// Steps and walks against the athlete's own usual day (ADR-0010, `docs/design/daily-activity.md`). Habitual walking
/// is the baseline and costs nothing; only clear departures from it become signals.
public enum EverydayMovement {
    public struct Settings: Hashable, Sendable {
        /// Days before the evaluated day that form the usual day (`walking-load-baseline`).
        public var baselineDays: Int
        /// Days with data needed before a baseline is used.
        public var minimumBaselineDays: Int
        /// A day is far below the usual steps when it is under both this fraction of the baseline…
        public var lowStepsFraction: Double
        /// …and this many steps (`low-steps-exercise-resistance`: ≈ 5,000 a day blunted the response to exercise).
        public var lowStepsCeiling: Int
        /// Consecutive complete days far below the baseline before it becomes a signal.
        public var lowStepsDays: Int
        /// Walking minutes above the usual day that count as a spike (heuristic: roughly a long hike).
        public var spikeExtraMinutes: Double

        public init(
            baselineDays: Int = 28, minimumBaselineDays: Int = 14, lowStepsFraction: Double = 0.5,
            lowStepsCeiling: Int = 5_000, lowStepsDays: Int = 3, spikeExtraMinutes: Double = 60
        ) {
            self.baselineDays = baselineDays
            self.minimumBaselineDays = minimumBaselineDays
            self.lowStepsFraction = lowStepsFraction
            self.lowStepsCeiling = lowStepsCeiling
            self.lowStepsDays = lowStepsDays
            self.spikeExtraMinutes = spikeExtraMinutes
        }
    }

    /// The athlete's usual day: medians over the baseline window. A value is `nil` until enough days have it.
    public struct Baseline: Hashable, Sendable {
        public var steps: Double?
        public var walkingMinutes: Double?

        public init(steps: Double? = nil, walkingMinutes: Double? = nil) {
            self.steps = steps
            self.walkingMinutes = walkingMinutes
        }
    }

    public enum Signal: Hashable, Sendable {
        /// The last `days` complete days were each far below the usual steps. Context only: never changes readiness.
        case stepsFarBelowBaseline(days: Int, averageSteps: Double, baselineSteps: Double)
        /// Walking on `day` well above the usual day, e.g. a long hike: leg-fatigue context for the next session.
        case walkingSpike(day: CalendarDay, minutes: Double, baselineMinutes: Double)

        public var evidence: EvidenceReference {
            switch self {
            case .stepsFarBelowBaseline: MovementEvidence.lowSteps
            case .walkingSpike: MovementEvidence.walkingAboveBaseline
            }
        }
    }

    /// The usual day before `day` (excluded): the median of the days in the window that have the value.
    ///
    /// Walking minutes need a source that records walks: without any walk in the window there is no walking
    /// baseline. With one, every day with activity data counts, and a day without walks counts as zero minutes.
    public static func baseline(
        _ activity: [DailyActivity], before day: CalendarDay, settings: Settings = Settings(),
        calendar: Calendar = .current
    ) -> Baseline {
        let start = day.adding(days: -settings.baselineDays, calendar: calendar)
        let window = latestPerDay(activity).filter { $0.day >= start && $0.day < day }
        let steps = window.compactMap { $0.steps.map(Double.init) }
        let recordsWalks = window.contains { !$0.walks.isEmpty }
        let minutes = recordsWalks ? window.filter { $0.steps != nil || !$0.walks.isEmpty }.map(walkingMinutes) : []
        return Baseline(
            steps: steps.count >= settings.minimumBaselineDays ? median(steps) : nil,
            walkingMinutes: minutes.count >= settings.minimumBaselineDays ? median(minutes) : nil
        )
    }

    /// Walking minutes on a day above its usual day (`walking-load-baseline`). Habitual walking, the dog's walks
    /// included, is part of the baseline and adds nothing. Zero without a walking baseline.
    public static func extraWalkingMinutes(_ day: DailyActivity, baseline: Baseline) -> Double {
        guard let usual = baseline.walkingMinutes else { return 0 }
        return max(0, walkingMinutes(day) - usual)
    }

    /// Movement signals for `today`. Today's steps are still counting, so the step signal reads complete days only;
    /// a walking spike can come from yesterday or from a long walk already done today (the latest wins).
    public static func signals(
        _ activity: [DailyActivity], today: CalendarDay, settings: Settings = Settings(), calendar: Calendar = .current
    ) -> [Signal] {
        let byDay = Dictionary(latestPerDay(activity).map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        var signals: [Signal] = []

        for offset in [0, -1] {
            let day = today.adding(days: offset, calendar: calendar)
            guard let entry = byDay[day] else { continue }
            let baseline = baseline(activity, before: day, settings: settings, calendar: calendar)
            guard let usual = baseline.walkingMinutes,
                  extraWalkingMinutes(entry, baseline: baseline) >= settings.spikeExtraMinutes else { continue }
            signals.append(.walkingSpike(day: day, minutes: walkingMinutes(entry), baselineMinutes: usual))
            break
        }

        let usualSteps = baseline(activity, before: today, settings: settings, calendar: calendar).steps
        if let usualSteps, settings.lowStepsDays > 0 {
            let limit = min(usualSteps * settings.lowStepsFraction, Double(settings.lowStepsCeiling))
            let recent = (1...settings.lowStepsDays).map { byDay[today.adding(days: -$0, calendar: calendar)]?.steps }
            let values = recent.compactMap { $0.map(Double.init) }
            if values.count == settings.lowStepsDays, values.allSatisfy({ $0 < limit }) {
                signals.append(.stepsFarBelowBaseline(
                    days: values.count, averageSteps: values.reduce(0, +) / Double(values.count),
                    baselineSteps: usualSteps
                ))
            }
        }
        return signals
    }

    public static func walkingMinutes(_ day: DailyActivity) -> Double { day.walkingSeconds / 60 }

    /// Walks from several sources, each walk once: when two overlap in time, the one from the source listed first
    /// in `priority` stays (Garmin before Apple Health, as for runs and strength).
    public static func removingDuplicateWalks(
        _ walks: [WalkBout], priority: [DataSourceKind] = [.garmin, .appleHealth]
    ) -> [WalkBout] {
        let rank = { (walk: WalkBout) in priority.firstIndex(of: walk.source) ?? priority.count }
        var kept: [WalkBout] = []
        for walk in walks.sorted(by: { (rank($0), $0.start) < (rank($1), $1.start) })
            where !kept.contains(where: { $0.source != walk.source && $0.start < walk.end && walk.start < $0.end }) {
            kept.append(walk)
        }
        return kept.sorted { $0.start < $1.start }
    }

    private static func latestPerDay(_ activity: [DailyActivity]) -> [DailyActivity] {
        Dictionary(activity.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }).values
            .sorted { $0.day < $1.day }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

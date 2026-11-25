import Domain
import Foundation

/// Descriptive labels for comparable performance observations. These labels do not change training targets.
public enum PerformanceTrend {
    public static let evidence = EvidenceReference(key: "performance-trend-pilot", level: .heuristic)
    public static let version = 1

    public enum Label: Hashable, Sendable {
        case insufficientEvidence
        case improving
        case withinVariability
        case declining
        case possiblePlateau
    }

    public struct Observation: Hashable, Sendable {
        public let sessionID: String
        public let date: Date
        public let value: Double
        /// Same exercise, load convention and equation, or same running conditions and HR source.
        public let comparisonKey: String

        public init(sessionID: String, date: Date, value: Double, comparisonKey: String) {
            self.sessionID = sessionID
            self.date = date
            self.value = value
            self.comparisonKey = comparisonKey
        }
    }

    public struct StrengthContext: Sendable {
        public let through: Date
        public let disrupted: [DateInterval]
        public let blockChanges: [Date]
        public let calendar: Calendar

        public init(
            through: Date, disrupted: [DateInterval] = [], blockChanges: [Date] = [],
            calendar: Calendar = .current
        ) {
            self.through = through
            self.disrupted = disrupted
            self.blockChanges = blockChanges
            self.calendar = calendar
        }

        public init(through: Date, profile: AthleteProfile?, calendar: Calendar = .current) {
            guard let profile else {
                self.init(through: through, calendar: calendar)
                return
            }
            let declared = profile.deloads.map { record in
                record.start..<record.start.adding(days: max(1, record.days), calendar: calendar)
            }
            let accepted = profile.deloadDecisions.compactMap { decision -> Range<CalendarDay>? in
                guard decision.accepted, decision.discipline != .running, decision.start <= decision.end else {
                    return nil
                }
                return decision.start..<decision.end.adding(days: 1, calendar: calendar)
            }
            let disruptions = (declared + accepted).map {
                DateInterval(start: $0.lowerBound.startDate(in: calendar), end: $0.upperBound.startDate(in: calendar))
            }
            let changes = profile.declaredBlocks.filter(\.isDeclared).flatMap { block in
                [block.start, block.end(calendar: calendar)].compactMap { $0 }
            }
            self.init(
                through: through, disrupted: disruptions,
                blockChanges: changes.map { $0.startDate(in: calendar) }, calendar: calendar
            )
        }

        fileprivate func isDisrupted(since first: Date) -> Bool {
            disrupted.contains { $0.start <= through && $0.end > first }
                || blockChanges.contains { $0 > first && $0 <= through }
        }
    }

    public static func runningHeartRate(
        _ observations: [Observation], through: Date, windowDays: Int, calendar: Calendar = .current
    ) -> Label {
        guard let windows = windows(observations, through: through, days: windowDays, calendar: calendar) else {
            return .insufficientEvidence
        }
        let tolerance = max(2, 2 * windows.variability)
        if windows.delta < -tolerance { return .improving }
        if windows.delta > tolerance { return .declining }
        return .withinVariability
    }

    public static func strength(_ observations: [Observation], context: StrengthContext) -> Label {
        guard let windows = windows(observations, through: context.through, days: 28, calendar: context.calendar),
              let first = windows.points.map(\.date).min(), let last = windows.points.map(\.date).max(),
              context.calendar.date(byAdding: .day, value: 42, to: first).map({ last >= $0 }) == true,
              !context.isDisrupted(since: first), windows.variability > 0 else {
            return .insufficientEvidence
        }
        let tolerance = max(0.02 * windows.baseline, 2 * windows.variability)
        if windows.delta > tolerance { return .improving }
        if windows.delta < -tolerance { return .declining }
        let narrowSpread = windows.maximumDeviation <= 0.04 * windows.baseline
        if narrowSpread, abs(windows.delta) <= 0.02 * windows.baseline { return .possiblePlateau }
        return .withinVariability
    }

    private struct Windows {
        let points: [Observation]
        let baseline: Double
        let delta: Double
        let variability: Double
        let maximumDeviation: Double
    }

    private static func windows(
        _ observations: [Observation], through: Date, days: Int, calendar: Calendar
    ) -> Windows? {
        guard (1...366).contains(days) else { return nil }
        let comparison = PerformanceComparison(through: CalendarDay(through, calendar: calendar),
                                               days: days, calendar: calendar)
        let points = Set(observations.filter {
            let day = CalendarDay($0.date, calendar: calendar)
            return $0.date <= through && $0.value.isFinite && $0.value > 0
                && (comparison.current.contains(day) || comparison.previous.contains(day))
        })
        guard Set(points.map(\.comparisonKey)).count == 1, points.first?.comparisonKey.isEmpty == false,
              Set(points.map(\.sessionID)).count == points.count else { return nil }

        let recent = points.filter { comparison.includes($0.date) }
        let earlier = points.subtracting(recent)
        guard distinctDays(recent, calendar: calendar) >= 3, distinctDays(earlier, calendar: calendar) >= 3,
              let recentMedian = PerformanceComparison.median(recent.map(\.value)),
              let earlierMedian = PerformanceComparison.median(earlier.map(\.value)) else { return nil }

        let recentDeviations = recent.map { abs($0.value - recentMedian) }
        let earlierDeviations = earlier.map { abs($0.value - earlierMedian) }
        let variability = max(PerformanceComparison.median(recentDeviations) ?? 0,
                              PerformanceComparison.median(earlierDeviations) ?? 0)
        return Windows(
            points: Array(points), baseline: earlierMedian, delta: recentMedian - earlierMedian,
            variability: variability, maximumDeviation: (recentDeviations + earlierDeviations).max() ?? 0
        )
    }

    private static func distinctDays(_ points: Set<Observation>, calendar: Calendar) -> Int {
        Set(points.map { CalendarDay($0.date, calendar: calendar) }).count
    }
}

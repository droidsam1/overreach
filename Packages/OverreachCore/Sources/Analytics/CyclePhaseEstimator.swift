import Domain
import Foundation

/// Estimates coarse cycle windows from period starts (`cycle-phase-estimation`, ADR-0009). A calendar cannot place
/// ovulation, so there is no ovulatory window and nothing here speaks of fertility. Pure function.
public enum CyclePhaseEstimator {
    /// Days without flow before a flow day counts as a new cycle.
    public static let gapBeforeStart = 10
    /// Complete cycles used for the expected length.
    public static let recentCycles = 6
    /// Expected length until 2 complete cycles are known.
    public static let defaultLength = 28
    /// Cycle lengths that count as regular for a high-confidence estimate.
    public static let regularLengths = 21...35
    /// Largest spread (max − min) of recent cycle lengths for a high-confidence estimate.
    public static let maximumSpread = 7
    /// Days past the expected start before the estimate is overdue.
    public static let overdueAfter = 3
    /// Longest menstrual window, in cycle days.
    public static let maximumMenstrualDays = 7

    /// - Parameters:
    ///   - day: the day to estimate. Events after it are ignored, so a past day gets the estimate known then.
    ///   - events: menstrual flow days, in any order.
    ///   - mode: only `.naturalCycle` gets a phase (`cycle-hormonal-contraception`).
    /// - Returns: `nil` for other modes or before the first known period.
    public static func estimate(
        on day: CalendarDay, events: [MenstrualEvent], mode: CycleTrackingMode, calendar: Calendar = .current
    ) -> CyclePhaseEstimate? {
        guard mode == .naturalCycle else { return nil }
        let starts = cycleStarts(events: events.filter { $0.day <= day }, calendar: calendar)
        guard let start = starts.last else { return nil }

        let lengths = zip(starts, starts.dropFirst()).map { days(from: $0, to: $1, calendar: calendar) }
        let recent = Array(lengths.suffix(recentCycles))
        let expectedLength = recent.count >= 2 ? median(recent) : defaultLength
        let cycleDay = days(from: start, to: day, calendar: calendar) + 1
        // Days until the next expected start N: 1 on N − 1, 0 on N, negative once late.
        let daysToNext = expectedLength - (cycleDay - 1)

        var reasons: [CyclePhaseEstimate.Reason] = []
        if recent.count < 2 { reasons.append(.fewCycles) }
        if let shortest = recent.min(), let longest = recent.max(),
           !recent.allSatisfy(regularLengths.contains) || longest - shortest > maximumSpread {
            reasons.append(.irregularCycles)
        }
        let overdue = daysToNext < -overdueAfter
        if overdue { reasons.append(.overdue) }

        let phase: CyclePhase
        if overdue {
            phase = .unknown
        } else if cycleDay <= maximumMenstrualDays && events.contains(where: { $0.day == day }) {
            phase = .menstrual
        } else if daysToNext >= 15 {
            phase = .follicular
        } else if daysToNext >= 6 {
            phase = .luteal
        } else {
            phase = .lateLuteal
        }
        return CyclePhaseEstimate(
            phase: phase, cycleDay: cycleDay, expectedLength: expectedLength,
            confidence: reasons.isEmpty ? .high : .low, reasons: reasons
        )
    }

    /// First days of each cycle, oldest first: an explicit start, or the first flow day after ≥ 10 days without flow.
    public static func cycleStarts(events: [MenstrualEvent], calendar: Calendar = .current) -> [CalendarDay] {
        let sorted = events.sorted { $0.day < $1.day }
        var starts: [CalendarDay] = []
        var previousFlow: CalendarDay?
        for event in sorted where event.day != previousFlow {
            let gap = previousFlow.map { days(from: $0, to: event.day, calendar: calendar) - 1 } ?? .max
            let explicit = event.isCycleStart
                && starts.last.map { days(from: $0, to: event.day, calendar: calendar) >= gapBeforeStart } ?? true
            if gap >= gapBeforeStart || explicit {
                starts.append(event.day)
            }
            previousFlow = event.day
        }
        return starts
    }

    static func days(from start: CalendarDay, to end: CalendarDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start.startDate(in: calendar), to: end.startDate(in: calendar)).day ?? 0
    }

    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Int((Double(sorted[middle - 1] + sorted[middle]) / 2).rounded())
        }
        return sorted[middle]
    }
}

/// Menstrual events and tracking mode, for rules that read the cycle as context (`cycle-phase-baselines`).
public struct CycleContext: Hashable, Sendable {
    public var mode: CycleTrackingMode
    public var events: [MenstrualEvent]

    public init(mode: CycleTrackingMode, events: [MenstrualEvent]) {
        self.mode = mode
        self.events = events
    }

    public func estimate(on day: CalendarDay, calendar: Calendar = .current) -> CyclePhaseEstimate? {
        CyclePhaseEstimator.estimate(on: day, events: events, mode: mode, calendar: calendar)
    }
}

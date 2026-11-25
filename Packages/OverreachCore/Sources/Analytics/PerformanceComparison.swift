import Domain
import Foundation

/// Equal calendar windows ending on the selected day. The current window includes today.
public struct PerformanceComparison: Sendable {
    public struct Summary: Equatable, Sendable {
        public let currentCount: Int
        public let previousCount: Int
        public let currentMedian: Double?
        public let previousMedian: Double?

        public var delta: Double? {
            guard let currentMedian, let previousMedian else { return nil }
            return currentMedian - previousMedian
        }
    }

    public let days: Int
    public let current: ClosedRange<CalendarDay>
    public let previous: ClosedRange<CalendarDay>
    private let calendar: Calendar

    public init(through today: CalendarDay, days: Int, calendar: Calendar) {
        precondition(days > 0)
        self.days = days
        self.calendar = calendar
        current = today.adding(days: 1 - days, calendar: calendar)...today
        let previousStart = today.adding(days: 1 - 2 * days, calendar: calendar)
        previous = previousStart...today.adding(days: -days, calendar: calendar)
    }

    public func includes(_ date: Date) -> Bool {
        current.contains(CalendarDay(date, calendar: calendar))
    }

    /// Callers supply one comparable result per session.
    public func summarize<Point>(
        _ points: [Point], date: KeyPath<Point, Date>, value: KeyPath<Point, Double>
    ) -> Summary {
        var recent: [Double] = []
        var earlier: [Double] = []
        for point in points {
            let number = point[keyPath: value]
            guard number.isFinite else { continue }
            let day = CalendarDay(point[keyPath: date], calendar: calendar)
            if current.contains(day) { recent.append(number) }
            if previous.contains(day) { earlier.append(number) }
        }
        return Summary(
            currentCount: recent.count, previousCount: earlier.count,
            currentMedian: Self.median(recent), previousMedian: Self.median(earlier)
        )
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        guard sorted.count.isMultiple(of: 2) else { return sorted[middle] }
        return sorted[middle - 1] / 2 + sorted[middle] / 2
    }
}

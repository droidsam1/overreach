import Foundation

/// A day in the user's calendar, independent of time zone and time of day.
///
/// All daily data (metrics, check-ins, loads) is keyed by `CalendarDay`, never by a raw `Date`,
/// so a night of sleep or an HRV reading always lands on the same day regardless of time zones.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day that contains `date` in `calendar`.
    public init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Start of this day in `calendar`.
    public func startDate(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// The day `days` days after (or before, if negative) this one.
    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        let start = startDate(in: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return CalendarDay(shifted, calendar: calendar)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// ISO 8601 date, e.g. `2026-11-16`.
    public var description: String {
        "\(Self.pad(year, to: 4))-\(Self.pad(month, to: 2))-\(Self.pad(day, to: 2))"
    }

    private static func pad(_ value: Int, to width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

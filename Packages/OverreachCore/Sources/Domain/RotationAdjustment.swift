import Foundation

/// A change the athlete accepted to the order or the days of the strength rotation (ADR-0044, decision 4).
///
/// Rotation detection tolerates a recorded adjustment, so Today keeps the rotation known after a swap or a one-day
/// postponement. A pick made by hand for one day is not recorded (ADR-0033). Slots are identified by the id of
/// `SessionRotation.Slot`, which Domain does not know.
public struct RotationAdjustment: Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        /// The session planned for `day` was replaced by `to`; `from` took its place in the following session.
        case swap(from: String, to: String)  // swiftlint:disable:this identifier_name
        /// The session planned for `day` moved this many days later; the rest of the cycle followed.
        case postpone(days: Int)
    }

    /// Why the adjustment was suggested.
    public enum Reason: String, Codable, Sendable {
        case runCarryover, readiness, heavyLegsBeforeRun
        case other
    }

    /// The day the adjusted session was planned for.
    public var day: CalendarDay
    public var kind: Kind
    public var reason: Reason?
    /// The projected day the heavy session trades places with. Older swaps used the next slot.
    public var swapDay: CalendarDay?

    /// Adjustments kept per profile; older ones no longer match any recent history.
    public static let keptCount = 30

    public init(day: CalendarDay, kind: Kind, reason: Reason? = nil, swapDay: CalendarDay? = nil) {
        self.day = day
        self.kind = kind
        self.reason = reason
        self.swapDay = swapDay
    }
}

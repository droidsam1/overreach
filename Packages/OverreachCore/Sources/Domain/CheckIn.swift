import Foundation

/// The user's daily subjective check-in (about 10 seconds to fill in).
public struct CheckIn: Hashable, Codable, Sendable {
    public var day: CalendarDay
    public var isSick: Bool
    /// 1 (exhausted) … 5 (great).
    public var energy: Int?
    /// 0 (none) … 3 (very sore).
    public var soreness: Int?
    public var note: String?

    public init(day: CalendarDay, isSick: Bool = false, energy: Int? = nil, soreness: Int? = nil, note: String? = nil) {
        self.day = day
        self.isSick = isSick
        self.energy = energy
        self.soreness = soreness
        self.note = note
    }
}

import Foundation

/// The run the athlete wants to achieve. Target pace is a goal, independent of current training pace.
public struct RunningGoal: Hashable, Codable, Sendable {
    public let distanceMeters: Int
    public let targetSeconds: Int?
    public let aimsForPainFree: Bool

    public init(distanceMeters: Int, targetSeconds: Int? = nil, aimsForPainFree: Bool = false) {
        self.distanceMeters = distanceMeters
        self.targetSeconds = targetSeconds
        self.aimsForPainFree = aimsForPainFree
    }

    public var targetPaceSecondsPerKm: Double? {
        guard distanceMeters > 0, let targetSeconds, targetSeconds > 0 else { return nil }
        return 1_000 * Double(targetSeconds) / Double(distanceMeters)
    }
}

/// A single next calendar commitment, entered by the athlete. It remains separate from completed run history.
public struct PlannedRun: Hashable, Codable, Sendable {
    public enum Purpose: String, CaseIterable, Codable, Sendable { case easy, intervals, tempo, long, race, rest }

    public let day: CalendarDay
    public let purpose: Purpose
    public let durationMinutes: Int?

    public init(day: CalendarDay, purpose: Purpose, durationMinutes: Int? = nil) {
        self.day = day
        self.purpose = purpose
        self.durationMinutes = purpose == .rest ? nil : durationMinutes
    }
}

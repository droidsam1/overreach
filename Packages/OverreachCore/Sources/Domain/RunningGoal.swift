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

/// A dated entry entered by the athlete. It remains separate from recorded run history.
public struct PlannedRun: Identifiable, Hashable, Codable, Sendable {
    public enum Purpose: String, CaseIterable, Codable, Sendable { case easy, intervals, tempo, long, race, rest }

    public let id: UUID
    public let day: CalendarDay
    public let purpose: Purpose
    public let durationMinutes: Int?
    public let distanceMeters: Int?
    public let completion: PlannedRunCompletion?

    public init(
        id: UUID = UUID(), day: CalendarDay, purpose: Purpose, durationMinutes: Int? = nil, distanceMeters: Int? = nil,
        completion: PlannedRunCompletion? = nil
    ) {
        self.id = id
        self.day = day
        self.purpose = purpose
        self.durationMinutes = purpose == .rest ? nil : durationMinutes
        self.distanceMeters = purpose == .rest ? nil : distanceMeters
        self.completion = purpose == .rest ? nil : completion
    }

    private enum CodingKeys: String, CodingKey { case id, day, purpose, durationMinutes, distanceMeters, completion }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let day = try values.decode(CalendarDay.self, forKey: .day)
        let purpose = try values.decode(Purpose.self, forKey: .purpose)
        let minutes = try values.decodeIfPresent(Int.self, forKey: .durationMinutes)
        let distance = try values.decodeIfPresent(Int.self, forKey: .distanceMeters)
        let id = try values.decodeIfPresent(UUID.self, forKey: .id)
            ?? UUID.stable("planned-run/\(day)/\(purpose.rawValue)/\(minutes ?? 0)")
        self.init(id: id, day: day, purpose: purpose, durationMinutes: minutes, distanceMeters: distance,
                  completion: try values.decodeIfPresent(PlannedRunCompletion.self, forKey: .completion))
    }
}

/// An explicit user confirmation. Keep just enough data to recognize a mirrored recording later.
public struct PlannedRunCompletion: Hashable, Codable, Sendable {
    public let activityID: String
    public let source: DataSourceKind
    public let startedAt: Date
    public let durationSeconds: Double

    public init(_ activity: RunActivity) {
        activityID = activity.id
        source = activity.source
        startedAt = activity.startedAt
        durationSeconds = activity.durationSeconds
    }

    public func matches(_ activity: RunActivity) -> Bool {
        if activity.source == source { return activity.id == activityID }
        let reference = RunActivity(id: activityID, source: source, startedAt: startedAt,
                                    durationSeconds: durationSeconds, distanceMeters: 0)
        return RunDeduplication.isSameRun(reference, activity)
    }

    public func matches(_ other: PlannedRunCompletion) -> Bool {
        matches(RunActivity(id: other.activityID, source: other.source, startedAt: other.startedAt,
                            durationSeconds: other.durationSeconds, distanceMeters: 0))
    }
}

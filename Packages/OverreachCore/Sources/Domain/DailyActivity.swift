import Foundation

/// A continuous walk: a walking workout, a Garmin walking activity, or ≥ 10 min of continuous steps
/// (ADR-0010, `docs/design/daily-activity.md`).
public struct WalkBout: Hashable, Codable, Sendable {
    public var start: Date
    public var durationSeconds: Double
    public var steps: Int?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var elevationGainMeters: Double?
    public var source: DataSourceKind

    public init(
        start: Date,
        durationSeconds: Double,
        steps: Int? = nil,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        elevationGainMeters: Double? = nil,
        source: DataSourceKind
    ) {
        self.start = start
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.elevationGainMeters = elevationGainMeters
        self.source = source
    }

    public var end: Date { start.addingTimeInterval(durationSeconds) }
}

/// Everyday movement outside training for one day.
public struct DailyActivity: Hashable, Codable, Sendable {
    public var day: CalendarDay
    public var steps: Int?
    public var walks: [WalkBout]

    public init(day: CalendarDay, steps: Int? = nil, walks: [WalkBout] = []) {
        self.day = day
        self.steps = steps
        self.walks = walks
    }

    public var walkingSeconds: Double { walks.reduce(0) { $0 + $1.durationSeconds } }
}

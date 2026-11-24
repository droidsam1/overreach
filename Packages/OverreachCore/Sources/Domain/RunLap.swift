import Foundation

/// One lap of a run as the watch recorded it (manual or auto lap). Every value is optional but the distance and
/// the time: a lap without them says nothing about the run.
public struct RunLap: Hashable, Codable, Sendable {
    public var distanceMeters: Double
    public var durationSeconds: Double
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var averageCadence: Double?
    public var elevationGainMeters: Double?
    public var elevationLossMeters: Double?

    public init(
        distanceMeters: Double,
        durationSeconds: Double,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        averageCadence: Double? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil
    ) {
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.averageCadence = averageCadence
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
    }

    /// Pace in seconds per kilometre, if the lap covers a distance.
    public var paceSecondsPerKm: Double? {
        distanceMeters > 0 ? durationSeconds / (distanceMeters / 1000) : nil
    }
}

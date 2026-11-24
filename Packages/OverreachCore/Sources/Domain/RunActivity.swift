import Foundation

/// Where a piece of data came from.
public enum DataSourceKind: String, Codable, Sendable, CaseIterable {
    case app, appleHealth, garmin, strongImport, manual
}

/// A run, imported from Apple Health or Garmin Connect. All metrics beyond the basics are optional
/// because they depend on the watch model and the source.
public struct RunActivity: Identifiable, Hashable, Codable, Sendable {
    /// Identifier from the source (e.g. Garmin activity id or HealthKit UUID string).
    public let id: String
    public var source: DataSourceKind
    public var name: String?
    public var startedAt: Date
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var elevationGainMeters: Double?
    public var elevationLossMeters: Double?
    public var averageCadence: Double?
    /// Source-specific training load (e.g. Garmin "load").
    public var trainingLoad: Double?
    public var aerobicTrainingEffect: Double?
    public var anaerobicTrainingEffect: Double?
    /// Laps the watch recorded (manual or auto laps).
    public var lapCount: Int?
    /// Time in motion, without pauses and stops.
    public var movingDurationSeconds: Double?
    /// Running, walking and standing parts as the watch detected them.
    public var runWalk: RunWalkSplits?
    /// Each lap's values, oldest first. nil: not fetched yet. Empty: the source has none for this run.
    public var laps: [RunLap]?

    public init(
        id: String,
        source: DataSourceKind,
        name: String? = nil,
        startedAt: Date,
        durationSeconds: Double,
        distanceMeters: Double,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil,
        averageCadence: Double? = nil,
        trainingLoad: Double? = nil,
        aerobicTrainingEffect: Double? = nil,
        anaerobicTrainingEffect: Double? = nil,
        lapCount: Int? = nil,
        movingDurationSeconds: Double? = nil,
        runWalk: RunWalkSplits? = nil,
        laps: [RunLap]? = nil
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.averageCadence = averageCadence
        self.trainingLoad = trainingLoad
        self.aerobicTrainingEffect = aerobicTrainingEffect
        self.anaerobicTrainingEffect = anaerobicTrainingEffect
        self.lapCount = lapCount
        self.movingDurationSeconds = movingDurationSeconds
        self.runWalk = runWalk
        self.laps = laps
    }

    /// Average pace in seconds per kilometre, if distance is known.
    public var paceSecondsPerKm: Double? {
        distanceMeters > 0 ? durationSeconds / (distanceMeters / 1000) : nil
    }

    /// Pace of the running segments only, when the watch separated running from walking.
    public var runningPaceSecondsPerKm: Double? { runWalk?.running?.paceSecondsPerKm }

    /// The longest continuous running stretch: the watch's longest running segment, or the whole run when the
    /// source does not split it.
    public var longestContinuousRunMeters: Double {
        guard let runWalk else { return distanceMeters.isFinite ? max(0, distanceMeters) : 0 }
        return runWalk.running?.longestSegmentMeters ?? runWalk.running?.distanceMeters ?? 0
    }
}

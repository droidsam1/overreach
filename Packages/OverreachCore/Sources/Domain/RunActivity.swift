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
    public var averageCadence: Double?
    /// Source-specific training load (e.g. Garmin "load").
    public var trainingLoad: Double?
    public var aerobicTrainingEffect: Double?
    public var anaerobicTrainingEffect: Double?

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
        averageCadence: Double? = nil,
        trainingLoad: Double? = nil,
        aerobicTrainingEffect: Double? = nil,
        anaerobicTrainingEffect: Double? = nil
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
        self.averageCadence = averageCadence
        self.trainingLoad = trainingLoad
        self.aerobicTrainingEffect = aerobicTrainingEffect
        self.anaerobicTrainingEffect = anaerobicTrainingEffect
    }

    /// Average pace in seconds per kilometre, if distance is known.
    public var paceSecondsPerKm: Double? {
        distanceMeters > 0 ? durationSeconds / (distanceMeters / 1000) : nil
    }
}

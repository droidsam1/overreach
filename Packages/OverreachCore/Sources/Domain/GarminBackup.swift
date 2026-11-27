import Foundation

/// Processed data from Garmin preserved in the portable backup.
public struct GarminBackup: Hashable, Codable, Sendable {
    public var metrics: [DailyMetrics]
    public var runs: [RunActivity]
    public var strength: [RecordedStrengthActivity]
    public var walks: [GarminWalk]

    public init(
        metrics: [DailyMetrics] = [], runs: [RunActivity] = [],
        strength: [RecordedStrengthActivity] = [], walks: [GarminWalk] = []
    ) {
        self.metrics = metrics
        self.runs = runs
        self.strength = strength
        self.walks = walks
    }

    public var activityCount: Int { runs.count + strength.count + walks.count }
    public var isEmpty: Bool { metrics.isEmpty && activityCount == 0 }
}

public protocol GarminBackupStore: Sendable {
    func backupSnapshot() async -> GarminBackup
    func restoreBackup(_ backup: GarminBackup) async throws
}

/// A Garmin walking or hiking activity, kept with its activity id so a later sync replaces it instead of adding it
/// twice.
public struct GarminWalk: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var walk: WalkBout

    public init(id: String, walk: WalkBout) {
        self.id = id
        self.walk = walk
    }
}

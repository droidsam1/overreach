import Foundation

/// The same run often reaches the app twice: Garmin's own record, and the copy Garmin Connect writes to Apple Health.
/// This keeps one of each (docs/design/garmin-integration.md).
///
/// Time matching, not a training rule: two runs from different sources are the same run when their intervals overlap
/// by at least half of the shorter one. Two runs from the same source are always kept (a double session is real).
/// The richer source wins: Garmin (load, training effect, FIT file) over Apple Health; missing details are filled from
/// the copy that is dropped.
public enum RunDeduplication {
    public static let minimumOverlapFraction = 0.5

    /// Preference when two sources recorded the same run: lower is kept.
    static func rank(_ source: DataSourceKind) -> Int {
        switch source {
        case .garmin: 0
        case .appleHealth: 1
        case .app, .strongImport, .manual: 2
        }
    }

    /// One record per run, oldest first.
    public static func removingDuplicates(_ runs: [RunActivity]) -> [RunActivity] {
        // Best source first, so the first copy of a run that is kept is the one to keep.
        let ordered = runs.sorted { (rank($0.source), $0.startedAt, $0.id) < (rank($1.source), $1.startedAt, $1.id) }
        var kept: [RunActivity] = []
        for run in ordered {
            if let index = kept.firstIndex(where: { $0.source != run.source && isSameRun($0, run) }) {
                kept[index] = filling(kept[index], from: run)
            } else {
                kept.append(run)
            }
        }
        return kept.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    static func isSameRun(_ lhs: RunActivity, _ rhs: RunActivity) -> Bool {
        let lhsEnd = lhs.startedAt.addingTimeInterval(max(0, lhs.durationSeconds))
        let rhsEnd = rhs.startedAt.addingTimeInterval(max(0, rhs.durationSeconds))
        let overlap = min(lhsEnd, rhsEnd).timeIntervalSince(max(lhs.startedAt, rhs.startedAt))
        let shorter = min(lhs.durationSeconds, rhs.durationSeconds)
        guard shorter > 0 else { return abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) < 120 }
        return overlap / shorter >= minimumOverlapFraction
    }

    private static func filling(_ kept: RunActivity, from other: RunActivity) -> RunActivity {
        var run = kept
        run.name = run.name ?? other.name
        run.averageHeartRate = run.averageHeartRate ?? other.averageHeartRate
        run.maxHeartRate = run.maxHeartRate ?? other.maxHeartRate
        run.elevationGainMeters = run.elevationGainMeters ?? other.elevationGainMeters
        run.averageCadence = run.averageCadence ?? other.averageCadence
        if run.distanceMeters <= 0 { run.distanceMeters = other.distanceMeters }
        return run
    }
}

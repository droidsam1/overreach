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

    /// The canonical record and the sources that contributed to it, preferred source first.
    public struct CombinedRun: Hashable, Sendable {
        public internal(set) var activity: RunActivity
        public internal(set) var sources: [DataSourceKind]
        public internal(set) var match: RunMatchPair?
    }

    /// One record per run, oldest first.
    public static func removingDuplicates(_ runs: [RunActivity]) -> [RunActivity] {
        combiningSources(runs).map(\.activity)
    }

    public static func combiningSources(_ runs: [RunActivity]) -> [CombinedRun] {
        let ordered = runs.sorted(by: preferredFirst)
        var seen: [DataSourceKind: Set<String>] = [:]
        var kept: [CombinedRun] = []
        for run in ordered {
            guard seen[run.source, default: []].insert(run.id).inserted else { continue }
            // Pair at most one recording from each source. Two overlapping runs from one source remain separate.
            let match = kept.indices.lazy.filter { index in
                !kept[index].sources.contains(run.source) && isSameRun(kept[index].activity, run)
            }.min { lhs, rhs in
                abs(kept[lhs].activity.startedAt.timeIntervalSince(run.startedAt))
                    < abs(kept[rhs].activity.startedAt.timeIntervalSince(run.startedAt))
            }
            if let match {
                kept[match].activity = filling(kept[match].activity, from: run)
                kept[match].sources.append(run.source)
            } else {
                kept.append(CombinedRun(activity: run, sources: [run.source]))
            }
        }
        return kept.sorted(by: chronological)
    }

    static func chronological(_ lhs: CombinedRun, _ rhs: CombinedRun) -> Bool {
        (lhs.activity.startedAt, lhs.activity.id, lhs.activity.source.rawValue)
            < (rhs.activity.startedAt, rhs.activity.id, rhs.activity.source.rawValue)
    }

    static func preferredFirst(_ lhs: RunActivity, _ rhs: RunActivity) -> Bool {
        let leftRank = rank(lhs.source)
        let rightRank = rank(rhs.source)
        if leftRank != rightRank { return leftRank < rightRank }
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        return lhs.source.rawValue < rhs.source.rawValue
    }

    static func isSameRun(_ lhs: RunActivity, _ rhs: RunActivity) -> Bool {
        let lhsEnd = lhs.startedAt.addingTimeInterval(max(0, lhs.durationSeconds))
        let rhsEnd = rhs.startedAt.addingTimeInterval(max(0, rhs.durationSeconds))
        let overlap = min(lhsEnd, rhsEnd).timeIntervalSince(max(lhs.startedAt, rhs.startedAt))
        let shorter = min(lhs.durationSeconds, rhs.durationSeconds)
        guard shorter > 0 else { return abs(lhs.startedAt.timeIntervalSince(rhs.startedAt)) < 120 }
        return overlap / shorter >= minimumOverlapFraction
    }

    static func filling(_ kept: RunActivity, from other: RunActivity) -> RunActivity {
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

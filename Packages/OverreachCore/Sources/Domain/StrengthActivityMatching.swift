import Foundation

/// A strength workout recorded by a watch, e.g. a Garmin `strength_training` activity. It holds what the watch
/// measures (time, heart rate, load), not what was lifted: sets, reps and weights come from the session logged in the
/// app, which is the source of truth (docs/design/garmin-integration.md).
public struct RecordedStrengthActivity: Identifiable, Hashable, Codable, Sendable {
    /// Identifier from the source (e.g. the Garmin activity id).
    public let id: String
    public var source: DataSourceKind
    public var startedAt: Date
    public var durationSeconds: Double
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    /// Source-specific training load (e.g. Garmin `activityTrainingLoad`). Not comparable with sRPE load.
    public var trainingLoad: Double?
    public var aerobicTrainingEffect: Double?
    public var anaerobicTrainingEffect: Double?
    /// Sets and reps the watch counted. Informative only: the watch often miscounts.
    public var totalSets: Int?
    public var totalReps: Int?

    public init(
        id: String,
        source: DataSourceKind,
        startedAt: Date,
        durationSeconds: Double,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        trainingLoad: Double? = nil,
        aerobicTrainingEffect: Double? = nil,
        anaerobicTrainingEffect: Double? = nil,
        totalSets: Int? = nil,
        totalReps: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.trainingLoad = trainingLoad
        self.aerobicTrainingEffect = aerobicTrainingEffect
        self.anaerobicTrainingEffect = anaerobicTrainingEffect
        self.totalSets = totalSets
        self.totalReps = totalReps
    }

    public var endedAt: Date { startedAt.addingTimeInterval(max(0, durationSeconds)) }
}

/// Which recorded activity belongs to which logged session.
public struct StrengthActivityMatches: Hashable, Sendable {
    /// The watch recording of each logged session that has one.
    public var bySession: [UUID: RecordedStrengthActivity]
    /// Recordings with no logged session (trained without logging in the app), oldest first. They are never turned
    /// into sessions: there is nothing reliable to log from them.
    public var unmatched: [RecordedStrengthActivity]

    public init(bySession: [UUID: RecordedStrengthActivity] = [:], unmatched: [RecordedStrengthActivity] = []) {
        self.bySession = bySession
        self.unmatched = unmatched
    }

    public func activity(for sessionID: UUID) -> RecordedStrengthActivity? {
        bySession[sessionID]
    }
}

/// Pairs strength sessions logged in the app with the same workout recorded by a watch, so one workout never counts
/// twice and the two never disagree: the session keeps its sets, the recording only adds heart rate and load.
///
/// This is time matching, not a training rule: no evidence applies.
/// - A pair needs its time intervals to overlap by at least `minimumOverlapFraction` of the shorter one. Starting the
///   watch a few minutes early or stopping it late still matches; a workout later the same day does not.
/// - A session without an end time (or with zero length) matches a recording that starts within `startTolerance`.
/// - Pairing is one to one, best overlap first, so two sessions on the same day each get their own recording.
public enum StrengthActivityMatching {
    public static let minimumOverlapFraction = 0.5
    public static let startTolerance: TimeInterval = 15 * 60

    public static func match(
        sessions: [StrengthSession], activities: [RecordedStrengthActivity]
    ) -> StrengthActivityMatches {
        var candidates: [Candidate] = []
        for session in sessions {
            for activity in activities {
                if let score = score(session, activity) {
                    candidates.append(Candidate(session: session, activity: activity, score: score))
                }
            }
        }
        candidates.sort(by: Candidate.isBetter)

        var bySession: [UUID: RecordedStrengthActivity] = [:]
        var usedActivities: Set<String> = []
        for candidate in candidates
        where bySession[candidate.session.id] == nil && !usedActivities.contains(candidate.activity.id) {
            bySession[candidate.session.id] = candidate.activity
            usedActivities.insert(candidate.activity.id)
        }

        let unmatched = activities
            .filter { !usedActivities.contains($0.id) }
            .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
        return StrengthActivityMatches(bySession: bySession, unmatched: unmatched)
    }

    /// 0.5…1 for overlapping intervals (the overlapped fraction of the shorter one); below 0.5 for a start-time match.
    private static func score(_ session: StrengthSession, _ activity: RecordedStrengthActivity) -> Double? {
        let startGap = abs(session.startedAt.timeIntervalSince(activity.startedAt))
        if let end = session.endedAt, end > session.startedAt, activity.durationSeconds > 0 {
            let sessionInterval = DateInterval(start: session.startedAt, end: end)
            let activityInterval = DateInterval(start: activity.startedAt, end: activity.endedAt)
            let overlap = sessionInterval.intersection(with: activityInterval)?.duration ?? 0
            let fraction = overlap / min(sessionInterval.duration, activityInterval.duration)
            return fraction >= minimumOverlapFraction ? fraction : nil
        }
        guard startGap <= startTolerance else { return nil }
        return 0.5 * (1 - startGap / startTolerance) * 0.99
    }

    private struct Candidate {
        let session: StrengthSession
        let activity: RecordedStrengthActivity
        let score: Double

        var startGap: TimeInterval { abs(session.startedAt.timeIntervalSince(activity.startedAt)) }

        /// Higher score first, then the closer start, then ids, so the result never depends on input order.
        static func isBetter(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.startGap != rhs.startGap { return lhs.startGap < rhs.startGap }
            if lhs.session.id != rhs.session.id { return lhs.session.id.uuidString < rhs.session.id.uuidString }
            return lhs.activity.id < rhs.activity.id
        }
    }
}

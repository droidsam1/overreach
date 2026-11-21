import Foundation

public struct StrengthRecordingID: Codable, Hashable, Sendable {
    public let source: DataSourceKind
    public let id: String

    public init(_ activity: RecordedStrengthActivity) {
        source = activity.source
        id = activity.id
    }
}

public struct StrengthMatchPair: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let recordingID: StrengthRecordingID

    public init(sessionID: UUID, recordingID: StrengthRecordingID) {
        self.sessionID = sessionID
        self.recordingID = recordingID
    }
}

public enum StrengthMatchChoice: String, Codable, Sendable {
    case linked, separate
}

public struct StrengthMatchCandidate: Sendable {
    public let pair: StrengthMatchPair
    public let session: StrengthSession
    public let recording: RecordedStrengthActivity
    public let isSeparate: Bool
}

public struct StrengthMatchResolution: Sendable {
    public let matches: StrengthActivityMatches
    public let candidates: [StrengthMatchCandidate]
}

private struct StrengthMatchSelection {
    var matches: [UUID: RecordedStrengthActivity] = [:]
    var used: Set<StrengthRecordingID> = []

    mutating func link(_ candidate: StrengthMatchCandidate) {
        guard matches[candidate.pair.sessionID] == nil, used.insert(candidate.pair.recordingID).inserted else {
            return
        }
        matches[candidate.pair.sessionID] = candidate.recording
    }
}

extension StrengthActivityMatching {
    /// History resolves ambiguous matches explicitly. The HealthKit writer keeps its own reconciliation rules.
    public static func resolve(
        sessions: [StrengthSession], activities: [RecordedStrengthActivity],
        choices: [StrengthMatchPair: StrengthMatchChoice]
    ) -> StrengthMatchResolution {
        var seen: Set<StrengthRecordingID> = []
        let originals = activities.filter { seen.insert(StrengthRecordingID($0)).inserted }
            .sorted { ($0.startedAt, $0.source.rawValue, $0.id) < ($1.startedAt, $1.source.rawValue, $1.id) }
        let sessionIDs = Set(sessions.map(\.id))
        let activeChoices = choices.filter { sessionIDs.contains($0.key.sessionID) }
        let (recordings, mirrors) = mergeMirrors(originals, choices: activeChoices)
        let links = activeChoices.keys.filter { activeChoices[$0] == .linked }
        let reservedSessions = Set(links.map(\.sessionID))
        let reservedRecordings = Set(links.map(\.recordingID))
        let separatedRecordings = Set(activeChoices.keys.filter { activeChoices[$0] == .separate }.map(\.recordingID))
        var selection = StrengthMatchSelection()
        var review: [StrengthMatchCandidate] = []
        for candidate in savedCandidates(sessions: sessions, recordings: recordings, choices: activeChoices) {
            if !candidate.isSeparate {
                selection.link(candidate)
            } else if !reservedSessions.contains(candidate.pair.sessionID),
                      !reservedRecordings.contains(candidate.pair.recordingID) {
                review.append(candidate)
            }
        }

        let available = recordings.filter { !reservedRecordings.contains(StrengthRecordingID($0)) }
        let maxLookback = max(available.map(\.durationSeconds).max() ?? 0, startTolerance)
        let eligible = sessions
            .filter { !reservedSessions.contains($0.id) }
            .flatMap { nearbyCandidates(for: $0, in: available, maxLookback: maxLookback, choices: activeChoices) }

        let bySession = Dictionary(grouping: eligible, by: \.pair.sessionID)
        let byRecording = Dictionary(grouping: eligible, by: \.pair.recordingID)
        for candidate in eligible {
            if bySession[candidate.pair.sessionID]?.count == 1, byRecording[candidate.pair.recordingID]?.count == 1,
               !separatedRecordings.contains(candidate.pair.recordingID) {
                selection.link(candidate)
            } else {
                review.append(candidate)
            }
        }
        return StrengthMatchResolution(
            matches: StrengthActivityMatches(
                bySession: selection.matches,
                unmatched: recordings.filter { !selection.used.contains(StrengthRecordingID($0)) },
                mirrors: mirrors
            ),
            candidates: review
        )
    }

    /// Only isolated cross-source pairs are merged. Both originals remain available to History on the next resolve.
    private static func mergeMirrors(
        _ originals: [RecordedStrengthActivity], choices: [StrengthMatchPair: StrengthMatchChoice]
    ) -> ([RecordedStrengthActivity], [StrengthRecordingID: StrengthRecordingID]) {
        let health = originals.filter { $0.source == .appleHealth }
        let lookback = max(health.map(\.durationSeconds).max() ?? 0, startTolerance)
        let pairs = originals.filter { $0.source == .garmin }.flatMap { garmin in
            let start = firstRecording(onOrAfter: garmin.startedAt.addingTimeInterval(-lookback), in: health)
            let end = max(garmin.endedAt, garmin.startedAt.addingTimeInterval(startTolerance))
            return health[start...].prefix { $0.startedAt <= end }.filter { overlaps(garmin, $0) }
                .map { (garmin: garmin, health: $0) }
        }
        let byGarmin = Dictionary(grouping: pairs, by: { $0.garmin.id })
        let byHealth = Dictionary(grouping: pairs, by: { $0.health.id })
        let decided = Set(choices.keys.map(\.recordingID))
        var mirrors: [StrengthRecordingID: StrengthRecordingID] = [:]
        var merged: [StrengthRecordingID: RecordedStrengthActivity] = [:]
        for pair in pairs where byGarmin[pair.garmin.id]?.count == 1 && byHealth[pair.health.id]?.count == 1 {
            let garminID = StrengthRecordingID(pair.garmin)
            let healthID = StrengthRecordingID(pair.health)
            // Preserve independent choices about both originals, including an explicit separation.
            if decided.contains(garminID) && decided.contains(healthID) { continue }
            let (primary, other) = decided.contains(healthID) ? (healthID, garminID) : (garminID, healthID)
            var preferred = pair.garmin
            if primary == healthID {
                preferred = pair.health
                preferred.trainingLoad = pair.garmin.trainingLoad
                preferred.aerobicTrainingEffect = pair.garmin.aerobicTrainingEffect
                preferred.anaerobicTrainingEffect = pair.garmin.anaerobicTrainingEffect
            }
            preferred.averageHeartRate = pair.garmin.averageHeartRate ?? pair.health.averageHeartRate
            preferred.maxHeartRate = pair.garmin.maxHeartRate ?? pair.health.maxHeartRate
            mirrors[primary] = other
            merged[primary] = preferred
        }
        let hidden = Set(mirrors.values)
        let recordings = originals.compactMap { activity -> RecordedStrengthActivity? in
            let id = StrengthRecordingID(activity)
            return hidden.contains(id) ? nil : (merged[id] ?? activity)
        }
        return (recordings, mirrors)
    }

    private static func savedCandidates(
        sessions: [StrengthSession], recordings: [RecordedStrengthActivity],
        choices: [StrengthMatchPair: StrengthMatchChoice]
    ) -> [StrengthMatchCandidate] {
        let bySession = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byRecording = Dictionary(uniqueKeysWithValues: recordings.map { (StrengthRecordingID($0), $0) })
        return choices.compactMap { pair, choice -> StrengthMatchCandidate? in
            guard let session = bySession[pair.sessionID], let recording = byRecording[pair.recordingID] else {
                return nil
            }
            return StrengthMatchCandidate(
                pair: pair, session: session, recording: recording, isSeparate: choice == .separate
            )
        }.sorted {
            ($0.pair.sessionID.uuidString, $0.recording.source.rawValue, $0.recording.id) <
                ($1.pair.sessionID.uuidString, $1.recording.source.rawValue, $1.recording.id)
        }
    }

    private static func nearbyCandidates(
        for session: StrengthSession, in recordings: [RecordedStrengthActivity], maxLookback: TimeInterval,
        choices: [StrengthMatchPair: StrengthMatchChoice]
    ) -> [StrengthMatchCandidate] {
        let earliest = session.startedAt.addingTimeInterval(-maxLookback)
        let latest = max(session.endedAt ?? session.startedAt, session.startedAt.addingTimeInterval(startTolerance))
        let start = firstRecording(onOrAfter: earliest, in: recordings)
        return recordings[start...].prefix { $0.startedAt <= latest }.compactMap { recording in
            let pair = StrengthMatchPair(sessionID: session.id, recordingID: StrengthRecordingID(recording))
            guard choices[pair] == nil, score(session, recording) != nil else { return nil }
            return StrengthMatchCandidate(pair: pair, session: session, recording: recording, isSeparate: false)
        }
    }

    private static func firstRecording(onOrAfter date: Date, in recordings: [RecordedStrengthActivity]) -> Int {
        var start = recordings.startIndex
        var end = recordings.endIndex
        while start < end {
            let middle = start + (end - start) / 2
            if recordings[middle].startedAt < date {
                start = middle + 1
            } else {
                end = middle
            }
        }
        return start
    }
}

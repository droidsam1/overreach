import Foundation

/// A Garmin and Apple Health recording, identified independently of the current sync result.
public struct RunMatchPair: Codable, Hashable, Sendable {
    public let garminID: String
    public let appleHealthID: String

    public init(garminID: String, appleHealthID: String) {
        self.garminID = garminID
        self.appleHealthID = appleHealthID
    }
}

public enum RunMatchChoice: String, Codable, Sendable {
    case linked, separate
}

public struct RunMatchCandidate: Sendable {
    public let pair: RunMatchPair
    public let garmin: RunActivity
    public let appleHealth: RunActivity
    public let isSeparate: Bool
}

public struct RunMatchResolution: Sendable {
    public let runs: [RunDeduplication.CombinedRun]
    public let candidates: [RunMatchCandidate]

    /// Runs suitable for totals. Ambiguous pairs may contain duplicate recordings until reviewed.
    public var unambiguousRuns: [RunActivity] {
        let ambiguous = candidates.filter { !$0.isSeparate }
        let garmin = Set(ambiguous.map(\.pair.garminID))
        let health = Set(ambiguous.map(\.pair.appleHealthID))
        return runs.map(\.activity).filter { run in
            switch run.source {
            case .garmin: return !garmin.contains(run.id)
            case .appleHealth: return !health.contains(run.id)
            default: return true
            }
        }
    }
}

extension RunDeduplication {
    /// History only links isolated candidate pairs automatically. Explicit links reserve both IDs even
    /// while one source is unavailable. Explicit separations remain available for reconsideration.
    public static func resolve(
        _ originals: [RunActivity], choices: [RunMatchPair: RunMatchChoice]
    ) -> RunMatchResolution {
        var seen: [DataSourceKind: Set<String>] = [:]
        let runs = originals.sorted(by: preferredFirst).filter {
            seen[$0.source, default: []].insert($0.id).inserted
        }
        let garmin = runs.filter { $0.source == .garmin }
        let health = runs.filter { $0.source == .appleHealth }
        let matches = candidates(garmin: garmin, health: health, choices: choices)
        let eligible = matches.eligible
        var linked = matches.linked
        var review = matches.separated
        let byGarmin = Dictionary(grouping: eligible, by: \.pair.garminID)
        let byHealth = Dictionary(grouping: eligible, by: \.pair.appleHealthID)
        for candidate in eligible {
            let pair = candidate.pair
            if byGarmin[pair.garminID]?.count == 1, byHealth[pair.appleHealthID]?.count == 1 {
                linked[pair.garminID] = candidate.appleHealth
            } else {
                review.append(candidate)
            }
        }

        let usedHealth = Set(linked.values.map(\.id))
        let combined = runs.compactMap { run -> CombinedRun? in
            switch run.source {
            case .appleHealth where usedHealth.contains(run.id):
                return nil
            case .garmin:
                guard let copy = linked[run.id] else { return CombinedRun(activity: run, sources: [run.source]) }
                return CombinedRun(
                    activity: filling(run, from: copy), sources: [.garmin, .appleHealth],
                    match: RunMatchPair(garminID: run.id, appleHealthID: copy.id)
                )
            default:
                return CombinedRun(activity: run, sources: [run.source])
            }
        }
        return RunMatchResolution(runs: combined.sorted(by: chronological), candidates: review)
    }

    private struct Candidates {
        var linked: [String: RunActivity] = [:]
        var eligible: [RunMatchCandidate] = []
        var separated: [RunMatchCandidate] = []
    }

    private static func candidates(
        garmin: [RunActivity], health: [RunActivity], choices: [RunMatchPair: RunMatchChoice]
    ) -> Candidates {
        let links = choices.filter { $0.value == .linked }.keys
        let reservedGarmin = Set(links.map(\.garminID))
        let reservedHealth = Set(links.map(\.appleHealthID))
        var matches = Candidates()
        var usedHealth: Set<String> = []

        for watch in garmin {
            for copy in health {
                let pair = RunMatchPair(garminID: watch.id, appleHealthID: copy.id)
                if choices[pair] == .linked, matches.linked[watch.id] == nil, usedHealth.insert(copy.id).inserted {
                    matches.linked[watch.id] = copy
                    continue
                }
                guard !reservedGarmin.contains(watch.id), !reservedHealth.contains(copy.id),
                      isSameRun(watch, copy) || choices[pair] == .separate else { continue }
                let separate = choices[pair] == .separate
                let candidate = RunMatchCandidate(pair: pair, garmin: watch, appleHealth: copy, isSeparate: separate)
                if separate {
                    matches.separated.append(candidate)
                } else {
                    matches.eligible.append(candidate)
                }
            }
        }

        return matches
    }
}

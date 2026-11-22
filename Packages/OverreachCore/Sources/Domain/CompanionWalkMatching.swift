import Foundation

/// Who walked with the athlete. Only the dog today (ADR-0039).
public enum WalkCompanion: String, Codable, Sendable, CaseIterable {
    case dog
}

/// How a walk got its companion tag.
public enum WalkCompanionSource: String, Codable, Sendable {
    /// The athlete confirmed a suggestion or edited the walk in History.
    case manual
}

/// The identity of a walk for stored answers: its source and start, to the second.
public struct WalkKey: Hashable, Codable, Sendable {
    public var source: DataSourceKind
    public var startSeconds: Int

    public init(source: DataSourceKind, startSeconds: Int) {
        self.source = source
        self.startSeconds = startSeconds
    }

    public init(_ walk: WalkBout) {
        self.init(source: walk.source, startSeconds: Int(walk.start.timeIntervalSince1970.rounded()))
    }
}

/// The athlete's answer to "with the dog?" for one walk. "No" is stored too, so the walk is not asked again.
public struct WalkCompanionAnswer: Hashable, Codable, Sendable {
    public var key: WalkKey
    public var withCompanion: Bool

    public init(key: WalkKey, withCompanion: Bool) {
        self.key = key
        self.withCompanion = withCompanion
    }

    public init(walk: WalkBout, withCompanion: Bool) {
        self.init(key: WalkKey(walk), withCompanion: withCompanion)
    }
}

/// Applies the athlete's own answers to the walks (`docs/design/companion-walks.md`).
///
/// Pure, idempotent and independent of input order. Run it on the walks of all sources **before** deduplication: an
/// answer then covers every copy of the same walk, and the dedupe keeps the tag on the walk it keeps.
public enum CompanionWalkMatching {
    /// Two walks from different sources are the same walk when they overlap by this fraction of the shorter one
    /// (as `RunDeduplication`).
    public static let minimumOverlapFraction = 0.5

    public static func tagging(_ walks: [WalkBout], answers: [WalkCompanionAnswer] = []) -> [WalkBout] {
        var result = walks
        let answered = answerLookup(answers)

        // A walk and its copies from other sources share one answer.
        func answer(for index: Int) -> Bool? {
            for other in result.indices where other == index || isSameWalk(result[other], result[index]) {
                if let value = answered[WalkKey(result[other])] { return value }
            }
            return nil
        }

        for index in result.indices {
            guard let value = answer(for: index) else { continue }
            if value {
                result[index].companion = .dog
                result[index].companionSource = .manual
            } else {
                result[index].companion = nil
                result[index].companionSource = nil
            }
        }

        return result
    }

    /// The athlete's answer for each walk, shared with the copies of the same walk from other sources.
    /// Walks nobody answered are left out.
    public static func answers(for walks: [WalkBout], answers: [WalkCompanionAnswer]) -> [WalkKey: Bool] {
        let answered = answerLookup(answers)
        var result: [WalkKey: Bool] = [:]
        for walk in walks {
            let twins = walks.filter { $0.source == walk.source ? $0 == walk : isSameWalk($0, walk) }
            if let value = twins.lazy.compactMap({ answered[WalkKey($0)] }).first { result[WalkKey(walk)] = value }
        }
        return result
    }

    /// Apply an edit to every available copy so it survives source changes and replaces older answers.
    public static func answerKeys(for walk: WalkBout, among walks: [WalkBout]) -> Set<WalkKey> {
        Set(walks.lazy.filter { isSameWalk(walk, $0) }.map(WalkKey.init)).union([WalkKey(walk)])
    }

    // MARK: - Details

    private static func answerLookup(_ answers: [WalkCompanionAnswer]) -> [WalkKey: Bool] {
        // On conflicting answers for one walk, "yes" wins so the result does not depend on order.
        answers.reduce(into: [:]) { $0[$1.key] = ($0[$1.key] ?? false) || $1.withCompanion }
    }

    private static func isSameWalk(_ lhs: WalkBout, _ rhs: WalkBout) -> Bool {
        guard lhs.source != rhs.source, lhs.durationSeconds > 0, rhs.durationSeconds > 0 else { return false }
        let overlap = overlapSeconds(lhs.start, lhs.end, rhs.start, rhs.end)
        return overlap / min(lhs.durationSeconds, rhs.durationSeconds) >= minimumOverlapFraction
    }

    private static func overlapSeconds(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> TimeInterval {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }

    /// Earlier start first, then a fixed source order, so ties never depend on input order.
    private static func order(_ lhs: WalkBout, _ rhs: WalkBout) -> Bool {
        (lhs.start, lhs.source.rawValue, lhs.durationSeconds) < (rhs.start, rhs.source.rawValue, rhs.durationSeconds)
    }
}

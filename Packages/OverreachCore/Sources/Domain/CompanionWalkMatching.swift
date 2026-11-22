import Foundation

/// Who walked with the athlete. Only the dog today (ADR-0039).
public enum WalkCompanion: String, Codable, Sendable, CaseIterable {
    case dog
}

/// How a walk got its companion tag.
public enum WalkCompanionSource: String, Codable, Sendable {
    /// The athlete confirmed a suggestion or edited the walk in History.
    case manual
    /// A movement window from a tracker export (GPX/KML) matched the walk.
    case trackerExport
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

/// A period of movement found in a tracker export. Coordinates are never kept.
public struct CompanionWindow: Hashable, Codable, Sendable {
    public enum Confidence: String, Codable, Sendable { case normal, low }

    public var start: Date
    public var end: Date
    public var confidence: Confidence

    public init(start: Date, end: Date, confidence: Confidence = .normal) {
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// Tags the walks a tracker's movement windows overlap, and applies the athlete's own answers
/// (`docs/design/companion-walks.md#matching`, evidence `walk-companion-matching`).
///
/// Time matching only, on absolute `Date`s. Pure, idempotent and independent of input order. Run it on the walks of
/// all sources **before** deduplication: an answer or a tag then covers every copy of the same walk, and the dedupe
/// keeps it on the walk it keeps. A window never creates a walk.
public enum CompanionWalkMatching {
    /// A window and a walk match when they overlap by this fraction of the shorter one (as `RunDeduplication`).
    public static let minimumOverlapFraction = 0.5
    /// A window of low confidence (sparse collar track) needs this fraction.
    public static let lowConfidenceOverlapFraction = 0.7
    /// The starts may differ by up to this long: the phone is started late and clocks differ.
    public static let maximumStartDifference: TimeInterval = 600

    public static func tagging(
        _ walks: [WalkBout], answers: [WalkCompanionAnswer] = [], windows: [CompanionWindow] = []
    ) -> [WalkBout] {
        var result = walks
        let answered = answerLookup(answers)

        // A walk and its copies from other sources share one answer.
        func answer(for index: Int) -> Bool? {
            for other in result.indices where other == index || isSameWalk(result[other], result[index]) {
                if let value = answered[WalkKey(result[other])] { return value }
            }
            return nil
        }

        var decided: [Int: Bool] = [:]
        for index in result.indices {
            guard let value = answer(for: index) else { continue }
            decided[index] = value
            if value {
                result[index].companion = .dog
                result[index].companionSource = .manual
            } else {
                result[index].companion = nil
                result[index].companionSource = nil
            }
        }

        for window in normalised(windows) {
            let candidates = result.indices.compactMap { index -> (index: Int, overlap: TimeInterval)? in
                guard let overlap = matchOverlap(window, result[index]) else { return nil }
                return (index, overlap)
            }
            guard let best = candidates.min(by: { lhs, rhs in
                if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
                return order(result[lhs.index], result[rhs.index])
            }) else { continue }
            // An answered walk keeps it, and the window is spent.
            for index in result.indices
            where index == best.index || isSameWalk(result[index], result[best.index]) {
                guard decided[index] == nil, result[index].companion == nil else { continue }
                result[index].companion = .dog
                result[index].companionSource = .trackerExport
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

    // MARK: - Details

    private static func answerLookup(_ answers: [WalkCompanionAnswer]) -> [WalkKey: Bool] {
        // On conflicting answers for one walk, "yes" wins so the result does not depend on order.
        answers.reduce(into: [:]) { $0[$1.key] = ($0[$1.key] ?? false) || $1.withCompanion }
    }

    /// Duplicate windows (same start and end to the minute) count once; the more confident one stays.
    private static func normalised(_ windows: [CompanionWindow]) -> [CompanionWindow] {
        var byKey: [[Int]: CompanionWindow] = [:]
        for window in windows where window.end > window.start {
            let key = [minute(window.start), minute(window.end)]
            if let existing = byKey[key], existing.confidence == .normal { continue }
            byKey[key] = window
        }
        return byKey.keys.sorted { $0.lexicographicallyPrecedes($1) }.compactMap { byKey[$0] }
    }

    private static func minute(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded()) }

    private static func matchOverlap(_ window: CompanionWindow, _ walk: WalkBout) -> TimeInterval? {
        guard walk.durationSeconds.isFinite, walk.durationSeconds > 0 else { return nil }
        guard abs(window.start.timeIntervalSince(walk.start)) <= maximumStartDifference else { return nil }
        let overlap = overlapSeconds(window.start, window.end, walk.start, walk.end)
        let shorter = min(window.end.timeIntervalSince(window.start), walk.durationSeconds)
        let needed = window.confidence == .low ? lowConfidenceOverlapFraction : minimumOverlapFraction
        return overlap / shorter >= needed ? overlap : nil
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

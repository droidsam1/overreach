import Domain
import Foundation

/// What an import would do, shown before anything is saved (the guided import, #165).
public struct TrackImportPreview: Equatable, Sendable {
    /// The period the file covers.
    public var coveredRange: ClosedRange<Date>
    /// Every movement window found.
    public var windows: [MovementWindow]
    /// The walks the windows would newly tag. Walks the athlete answered keep their answer and are never listed.
    public var walksToTag: [WalkKey]
    /// Walks inside the covered period that already carry the tag, from an earlier import or an answer.
    public var alreadyTaggedCount: Int
    /// Windows that match a walk, new or already tagged.
    public var matchingWindowCount: Int

    /// True when saving would change nothing.
    public var isEmpty: Bool { walksToTag.isEmpty }

    /// Compares the walks as stored (`walks`, with their current tags and the athlete's `answers`) with the same
    /// walks after the windows are applied. Run on the walks of all sources before deduplication, like the matcher.
    public init(result: TrackImportResult, walks: [WalkBout], answers: [WalkCompanionAnswer] = []) {
        let before = CompanionWalkMatching.tagging(walks, answers: answers)
        let after = CompanionWalkMatching.tagging(walks, answers: answers, windows: result.companionWindows)

        var newlyTagged = Set<WalkKey>()
        var alreadyTagged = Set<WalkKey>()
        for (old, new) in zip(before, after) where result.coveredRange.contains(old.start) {
            guard new.companion != nil else { continue }
            if old.companion == nil { newlyTagged.insert(WalkKey(new)) } else { alreadyTagged.insert(WalkKey(old)) }
        }

        coveredRange = result.coveredRange
        windows = result.windows
        walksToTag = newlyTagged.sorted {
            ($0.startSeconds, $0.source.rawValue) < ($1.startSeconds, $1.source.rawValue)
        }
        alreadyTaggedCount = alreadyTagged.count
        matchingWindowCount =
            result.windows.filter { window in
                CompanionWalkMatching.tagging(walks, windows: [window.companionWindow]).contains { $0.companion != nil }
                    || before.contains { $0.companion != nil && Self.overlaps(window, $0) }
            }.count
    }

    private static func overlaps(_ window: MovementWindow, _ walk: WalkBout) -> Bool {
        walk.start < window.end && walk.end > window.start
    }
}

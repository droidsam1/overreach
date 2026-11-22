import Domain
import Foundation

/// Decides which walks to ask "With <dog>?" about (docs/design/companion-walks.md#suggest-and-confirm).
///
/// Product heuristics, no training rule (evidence `dog-walk-suggestion`). A walk is asked about when it lasts 10
/// minutes or more and nobody has answered it. With few answers the app asks on every such walk. Once it has learned,
/// it asks only near a usual slot: a time of day with at least 3 confirmed dog walks in the last 28 days.
/// A "No" teaches too: a slot whose last 5 answers are all "No" stops asking.
/// Pure: times of day come from the `Calendar` passed in, so DST and midnight are the caller's calendar's business.
public enum DogWalkSuggestion {
    public struct Settings: Hashable, Sendable {
        public var minimumWalkSeconds: TimeInterval = 600
        /// Fewer answered walks than this: ask on every walk.
        public var coldStartAnswers = 10
        /// A walk is near a usual slot when its time of day is within this many minutes of it.
        public var slotWindowMinutes = 45
        public var minimumConfirmations = 3
        public var lookbackDays = 28
        public var stopAfterConsecutiveNo = 5

        public init() {}
    }

    private struct Answered {
        let walk: WalkBout
        let withDog: Bool
    }

    /// The walks to ask about, oldest first. Pass the walks of every source: copies of one walk count and are asked
    /// once, and an answer on any copy covers the others.
    public static func walksToAsk(
        walks: [WalkBout],
        answers: [WalkCompanionAnswer],
        now: Date,
        calendar: Calendar,
        settings: Settings = Settings()
    ) -> [WalkBout] {
        let resolved = CompanionWalkMatching.answers(for: walks, answers: answers)
        let kept = EverydayMovement.removingDuplicateWalks(CompanionWalkMatching.tagging(walks, answers: answers))
        let history: [Answered] = kept.compactMap { walk in
            if let value = resolved[WalkKey(walk)] { return Answered(walk: walk, withDog: value) }
            return walk.companion == .dog ? Answered(walk: walk, withDog: true) : nil
        }
        let answeredKeys = Set(history.map { WalkKey($0.walk) })
        let from = calendar.date(byAdding: .day, value: -settings.lookbackDays, to: now) ?? .distantPast
        let recent = history.filter { $0.walk.start >= from && $0.walk.start <= now }

        return kept.filter { walk in
            walk.durationSeconds >= settings.minimumWalkSeconds
                && !answeredKeys.contains(WalkKey(walk))
                && shouldAsk(walk, history: history, recent: recent, calendar: calendar, settings: settings)
        }
    }

    // MARK: - Details

    private static func shouldAsk(
        _ walk: WalkBout, history: [Answered], recent: [Answered], calendar: Calendar, settings: Settings
    ) -> Bool {
        let weekend = calendar.isDateInWeekend(walk.start)
        // Weekend and weekday slots are learned apart once that kind of day has enough answers of its own.
        let sameKind = { (list: [Answered]) in list.filter { calendar.isDateInWeekend($0.walk.start) == weekend } }
        let separate = sameKind(history).count >= settings.coldStartAnswers
        let answered = separate ? sameKind(history) : history
        let slotAnswers = (separate ? sameKind(recent) : recent).filter {
            distance(minuteOfDay($0.walk, calendar), minuteOfDay(walk, calendar)) <= settings.slotWindowMinutes
        }
        // The last answers of this slot all "No": stop asking, whatever else was learned.
        let latest = slotAnswers.sorted { $0.walk.start > $1.walk.start }.prefix(settings.stopAfterConsecutiveNo)
        if latest.count == settings.stopAfterConsecutiveNo, latest.allSatisfy({ !$0.withDog }) { return false }
        if answered.count < settings.coldStartAnswers { return true }
        return isNearUsualSlot(walk, confirmed: slotAnswers.filter(\.withDog), calendar: calendar, settings: settings)
    }

    /// A usual slot is a time of day with enough confirmed walks around it. The walk is asked about when it lies
    /// within the window of such a slot.
    private static func isNearUsualSlot(
        _ walk: WalkBout, confirmed: [Answered], calendar: Calendar, settings: Settings
    ) -> Bool {
        let times = confirmed.map { minuteOfDay($0.walk, calendar) }
        return times.contains { slot in
            times.filter { distance($0, slot) <= settings.slotWindowMinutes }.count >= settings.minimumConfirmations
        }
    }

    private static func minuteOfDay(_ walk: WalkBout, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: walk.start)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Distance between two times of day, across midnight.
    private static func distance(_ lhs: Int, _ rhs: Int) -> Int {
        let gap = abs(lhs - rhs)
        return min(gap, 1_440 - gap)
    }
}

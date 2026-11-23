import Domain
import Foundation

/// The workouts someone repeats in a fixed order (A, B, C, D, then A again) without a declared plan.
///
/// A rotation is only reported after the same order has repeated twice, so one stray session or a short history
/// gives no guess. It makes no evidence claim: it only reads the order the athlete already follows (ADR-0033).
public struct SessionRotation: Hashable, Sendable {
    /// One workout of the rotation: the routine it was started from, or else its name.
    public struct Slot: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// The rotation in order, starting with the workout that comes next.
    public let order: [Slot]
    /// The workout that comes next instead of `order[0]` when a recorded swap is half done: the first workout of the
    /// pair is done, the second follows, and the original order resumes after it (ADR-0044).
    public var swappedNext: Slot?
    public var next: Slot { swappedNext ?? order[0] }

    public static let longestRotation = 6
    /// Full repetitions of the order needed before the rotation is trusted.
    public static let requiredCycles = 2

    private static let duplicateWindow: TimeInterval = 12 * 3_600

    /// - Parameters:
    ///   - sessions: completed strength sessions, in any order. The same workout recorded twice within a few hours
    ///     (a split or duplicated record) counts once.
    ///   - adjustments: swaps and postponements the athlete accepted. A cycle matches when its order differs only
    ///     by a recorded swap; without a record the order must repeat exactly.
    public static func detect(
        in sessions: [StrengthSession], adjustments: [RotationAdjustment] = [], calendar: Calendar = .current
    ) -> SessionRotation? {
        let planned = plannedSlots(timeline(sessions), adjustments: adjustments, calendar: calendar)
        let sequence = planned.slots
        for length in 1...longestRotation {
            let cycle = Array(sequence.suffix(length))
            guard cycle.count == length, Set(cycle.map(\.id)).count == length else { continue }
            var repeated = 0
            var index = sequence.count - 1
            while index - length >= 0, sequence[index].id == sequence[index - length].id {
                repeated += 1
                index -= 1
            }
            // A single workout repeated needs three sessions in a row; longer rotations need two full cycles.
            let needed = length == 1 ? 2 : length * (requiredCycles - 1)
            if repeated >= needed { return SessionRotation(order: cycle, swappedNext: planned.pendingNext) }
        }
        return nil
    }

    /// Distinct workouts of `sessions`, most recent first, at most `limit`.
    public static func recentWorkouts(in sessions: [StrengthSession], limit: Int = longestRotation) -> [Slot] {
        var seen: Set<String> = []
        return Array(slots(sessions).reversed().filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    /// The key that identifies the workout of `session`.
    public static func slot(for session: StrengthSession) -> Slot {
        let name = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let routineID = session.routineID { return Slot(id: routineID.uuidString, name: name) }
        let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Slot(id: "name:" + key, name: name)
    }

    /// The slots in planned order: every recorded swap that was carried out is undone. A swap whose second session has
    /// not happened yet reads as the planned workout, and `pendingNext` names the one that really comes next.
    static func plannedSlots(
        _ timeline: [(slot: Slot, session: StrengthSession)], adjustments: [RotationAdjustment], calendar: Calendar
    ) -> (slots: [Slot], pendingNext: Slot?) {
        var slots = timeline.map(\.slot)
        var pendingNext: Slot?
        for adjustment in adjustments {
            guard case let .swap(from, target) = adjustment.kind,
                  let index = timeline.firstIndex(where: {
                      CalendarDay($0.session.startedAt, calendar: calendar) == adjustment.day
                  }), slots[index].id == target else { continue }
            if index + 1 < slots.count {
                if slots[index + 1].id == from { slots.swapAt(index, index + 1) }
            } else if let planned = slots.last(where: { $0.id == from }) {
                pendingNext = planned
                slots[index] = planned
            }
        }
        return (slots, pendingNext)
    }

    private static func slots(_ sessions: [StrengthSession]) -> [Slot] {
        timeline(sessions).map(\.slot)
    }

    /// The sessions that make up the sequence, oldest first, with their workout. Duplicates count once (the first).
    static func timeline(_ sessions: [StrengthSession]) -> [(slot: Slot, session: StrengthSession)] {
        var result: [(slot: Slot, session: StrengthSession)] = []
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) where !session.entries.isEmpty {
            let slot = slot(for: session)
            guard !slot.name.isEmpty || session.routineID != nil else { continue }
            // The same workout twice within a few hours is one session recorded twice or split in two.
            if let last = result.last, last.slot.id == slot.id,
               session.startedAt.timeIntervalSince(last.session.startedAt) < duplicateWindow {
                continue
            }
            result.append((slot, session))
        }
        return result
    }
}

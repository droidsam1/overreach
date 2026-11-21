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
    public var next: Slot { order[0] }

    public static let longestRotation = 6
    /// Full repetitions of the order needed before the rotation is trusted.
    public static let requiredCycles = 2

    private static let duplicateWindow: TimeInterval = 12 * 3_600

    /// - Parameter sessions: completed strength sessions, in any order. The same workout recorded twice within a few
    ///   hours (a split or duplicated record) counts once.
    public static func detect(in sessions: [StrengthSession]) -> SessionRotation? {
        let sequence = slots(sessions)
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
            if repeated >= needed { return SessionRotation(order: cycle) }
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

    private static func slots(_ sessions: [StrengthSession]) -> [Slot] {
        var result: [Slot] = []
        var lastStart: Date?
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) where !session.entries.isEmpty {
            let slot = slot(for: session)
            guard !slot.name.isEmpty || session.routineID != nil else { continue }
            // The same workout twice within a few hours is one session recorded twice or split in two.
            if result.last?.id == slot.id, let lastStart, session.startedAt.timeIntervalSince(lastStart) < duplicateWindow {
                continue
            }
            result.append(slot)
            lastStart = session.startedAt
        }
        return result
    }
}

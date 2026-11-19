import Domain
import Foundation

/// The session a training plan has next: which block is running, which week of it, and which routine follows.
public struct PlannedSession: Hashable, Sendable {
    public let block: TrainingBlock
    public let routine: Routine
    /// 1-based week of the block that contains today.
    public let week: Int
    /// The block's length in weeks, when known.
    public let totalWeeks: Int?
}

/// Finds the next planned session (issue #34). Pure, no evidence involved: it only follows the order the user (or
/// their AI) wrote. A block runs from its start for its planned weeks, or until the next block starts. Its routines
/// rotate: the next one follows the routine of the last session started from the block, so a missed day does not
/// skip a session.
public enum PlanSchedule {
    public static func next(
        blocks: [TrainingBlock], routines: [Routine], sessions: [StrengthSession], today: CalendarDay,
        calendar: Calendar = .current
    ) -> PlannedSession? {
        guard let block = runningBlock(blocks, today: today, calendar: calendar) else { return nil }
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rotation = block.routineIDs.filter { byID[$0] != nil }
        guard let first = rotation.first else { return nil }

        let blockStart = block.start.startDate(in: calendar)
        let last = sessions
            .filter { $0.startedAt >= blockStart }
            .filter { session in session.routineID.map(rotation.contains) ?? false }
            .max { $0.startedAt < $1.startedAt }
        var nextID = first
        if let lastID = last?.routineID, let position = rotation.firstIndex(of: lastID) {
            nextID = rotation[(position + 1) % rotation.count]
        }
        guard let routine = byID[nextID] else { return nil }

        let days = calendar.dateComponents([.day], from: blockStart, to: today.startDate(in: calendar)).day ?? 0
        return PlannedSession(block: block, routine: routine, week: days / 7 + 1, totalWeeks: block.plannedWeeks)
    }

    /// The declared block that contains `today`: the last one started on or before it, unless it has ended.
    public static func runningBlock(
        _ blocks: [TrainingBlock], today: CalendarDay, calendar: Calendar = .current
    ) -> TrainingBlock? {
        let declared = blocks.filter(\.isDeclared).sorted { $0.start < $1.start }
        guard let block = declared.last(where: { $0.start <= today }) else { return nil }
        if let end = block.end(calendar: calendar), end <= today { return nil }
        return block
    }
}

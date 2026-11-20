import Domain
import Foundation

/// Evidence behind the plan follow-up (issue #34, `docs/evidence.md`).
public enum PlanEvidence {
    /// With weekly volume equated, training frequency makes no difference to hypertrophy and a small one to strength
    /// (Schoenfeld et al. 2019, Grgic et al. 2018, Pelland et al. 2026, meta-analyses).
    public static let frequency = EvidenceReference(key: "frequency-volume-equated", level: .strong)
    /// Strength and size lost during a break of up to ~10 weeks come back quickly with retraining, and end up
    /// like continuous training (Halonen et al. 2024, RCT; Ogasawara et al. 2011).
    public static let retraining = EvidenceReference(key: "retraining-after-break", level: .moderate)
    /// Return to training after an acute illness is decided by symptoms and severity, not by a fixed timeline
    /// (IOC consensus, Schwellnus et al. 2022).
    public static let illness = EvidenceReference(key: "illness-return", level: .limited)
    /// Thresholds: a break is 14 days, low adherence is under two thirds of planned sessions over two weeks,
    /// and a block is extended by at most 4 weeks in all.
    public static let heuristics = EvidenceReference(key: "plan-adherence", level: .heuristic)
}

/// Planned and completed sessions in one week of a block.
public struct PlanWeek: Hashable, Sendable {
    /// 1-based week of the block.
    public let week: Int
    public let planned: Int
    public let done: Int
    /// The week that contains today, still in progress.
    public let isCurrent: Bool
}

/// A change the follow-up proposes. Proposals only: the user decides (ADR-0013).
public enum PlanAdjustment: Hashable, Sendable {
    /// A recent check-in says the athlete is ill: rest until symptoms ease, then return gradually.
    case restWhileIll
    /// No strength session for `daysOff` days: keep the plan and ease back in.
    case easeBackIn(daysOff: Int)
    /// Sessions keep being missed: plan fewer, fuller sessions a week.
    case fewerSessions(from: Int, perWeek: Int)
    /// Missed sessions add up to whole weeks: lengthen the block by that much.
    case extendBlock(weeks: Int)

    public var evidence: EvidenceReference {
        switch self {
        case .restWhileIll: PlanEvidence.illness
        case .easeBackIn: PlanEvidence.retraining
        case .fewerSessions: PlanEvidence.frequency
        case .extendBlock: PlanEvidence.heuristics
        }
    }

    /// Whether `PlanReviewer.applying` can carry it out on the plan.
    public var changesThePlan: Bool {
        switch self {
        case .fewerSessions, .extendBlock: true
        case .restWhileIll, .easeBackIn: false
        }
    }
}

/// How the running block is going: planned against completed sessions, and what to change.
public struct PlanReview: Hashable, Sendable {
    public let block: TrainingBlock
    /// Weeks from the first to the current one.
    public let weeks: [PlanWeek]
    public let adjustments: [PlanAdjustment]

    public var currentWeek: PlanWeek? { weeks.last }
    /// Sessions done in the weeks already over, and how many were planned for them.
    public var completedWeeksDone: Int { weeks.filter { !$0.isCurrent }.reduce(0) { $0 + $1.done } }
    public var completedWeeksPlanned: Int { weeks.filter { !$0.isCurrent }.reduce(0) { $0 + $1.planned } }
}

/// Compares the running block with the sessions done and proposes adjustments after missed sessions, a break or
/// an illness (issue #34). Pure. Sessions count for the plan when they were started from one of its routines (or,
/// in a block without routines, any strength session).
public enum PlanReviewer {
    public static let breakDays = 14
    public static let lowAdherence = 2.0 / 3.0
    public static let lookbackWeeks = 2
    public static let maxExtensionWeeks = 4

    public static func review(
        blocks: [TrainingBlock], sessions: [StrengthSession], checkIns: [CheckIn] = [], today: CalendarDay,
        calendar: Calendar = .current
    ) -> PlanReview? {
        guard let block = PlanSchedule.runningBlock(blocks, today: today, calendar: calendar) else { return nil }
        let rotation = Set(block.routineIDs)
        let counted = sessions.filter { session in
            rotation.isEmpty || session.routineID.map(rotation.contains) ?? false
        }
        let currentWeek = week(of: today, in: block, calendar: calendar)
        let planned = block.plannedSessionsPerWeek
        var doneByWeek: [Int: Int] = [:]
        for session in counted {
            let day = CalendarDay(session.startedAt, calendar: calendar)
            guard day >= block.start, day <= today else { continue }
            doneByWeek[week(of: day, in: block, calendar: calendar), default: 0] += 1
        }
        let weeks = (1...currentWeek).map { number in
            PlanWeek(week: number, planned: planned, done: doneByWeek[number] ?? 0, isCurrent: number == currentWeek)
        }
        let yesterday = today.adding(days: -1, calendar: calendar)
        let isIll = checkIns.contains { $0.isSick && $0.day >= yesterday && $0.day <= today }
        let lastDay = sessions.map { CalendarDay($0.startedAt, calendar: calendar) }.filter { $0 <= today }.max()
        let daysOff = lastDay.map { days(from: $0, to: today, calendar: calendar) }
        let adjustments = self.adjustments(block: block, weeks: weeks, daysOff: daysOff, isIll: isIll)
        return PlanReview(block: block, weeks: weeks, adjustments: adjustments)
    }

    /// The plan after accepting `adjustment` for `block`. Extending a block moves the declared blocks after it.
    public static func applying(
        _ adjustment: PlanAdjustment, to block: TrainingBlock, in blocks: [TrainingBlock],
        calendar: Calendar = .current
    ) -> [TrainingBlock] {
        switch adjustment {
        case let .fewerSessions(_, perWeek):
            return blocks.map { candidate in
                guard candidate == block else { return candidate }
                var changed = candidate
                changed.sessionsPerWeek = perWeek
                return changed
            }
        case let .extendBlock(extra):
            return blocks.map { candidate in
                var changed = candidate
                if candidate == block {
                    changed.plannedWeeks = (candidate.plannedWeeks ?? 0) + extra
                    changed.extendedWeeks += extra
                } else if candidate.isDeclared, candidate.start > block.start {
                    changed.start = candidate.start.adding(days: extra * 7, calendar: calendar)
                }
                return changed
            }
        case .restWhileIll, .easeBackIn:
            return blocks
        }
    }

    // MARK: - Rules

    /// - Parameter daysOff: days since the last strength session, if there was one.
    private static func adjustments(
        block: TrainingBlock, weeks: [PlanWeek], daysOff: Int?, isIll: Bool
    ) -> [PlanAdjustment] {
        // Illness wins: nothing else matters until symptoms ease.
        if isIll {
            return [.restWhileIll]
        }
        // A break is not a pattern of missed sessions: ease back in and keep the plan.
        if let daysOff, daysOff >= breakDays {
            return [.easeBackIn(daysOff: daysOff)]
        }

        var result: [PlanAdjustment] = []
        let finished = weeks.filter { !$0.isCurrent }
        let recent = finished.suffix(lookbackWeeks)
        guard recent.count == lookbackWeeks else { return result }
        let planned = recent.reduce(0) { $0 + $1.planned }
        let done = recent.reduce(0) { $0 + $1.done }
        guard Double(done) < Double(planned) * lowAdherence else { return result }

        let perWeek = block.plannedSessionsPerWeek
        let realistic = Int((Double(done) / Double(lookbackWeeks)).rounded(.up))
        if realistic >= 1, realistic < perWeek {
            result.append(.fewerSessions(from: perWeek, perWeek: realistic))
        }
        let missed = finished.reduce(0) { $0 + max(0, $1.planned - $1.done) }
        let missedWeeks = min(maxExtensionWeeks, missed / perWeek) - block.extendedWeeks
        if block.plannedWeeks != nil, missedWeeks >= 1 {
            result.append(.extendBlock(weeks: missedWeeks))
        }
        return result
    }

    // MARK: - Helpers

    static func week(of day: CalendarDay, in block: TrainingBlock, calendar: Calendar) -> Int {
        days(from: block.start, to: day, calendar: calendar) / 7 + 1
    }

    static func days(from start: CalendarDay, to end: CalendarDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start.startDate(in: calendar), to: end.startDate(in: calendar)).day ?? 0
    }
}

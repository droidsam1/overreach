import Domain
import Foundation

/// A block in the forward plan. `focus == nil` is a deload week.
public struct PlannedBlock: Hashable, Sendable {
    public var focus: TrainingFocus?
    public var start: CalendarDay
    public var weeks: Int

    public var isDeload: Bool { focus == nil }
}

public enum BlockReason: Hashable, Sendable {
    /// Periodising volume/intensity improves 1RM more than not periodising (strength goals).
    case periodizationHelpsStrength
    /// For muscle growth, periodisation model matters little; volume and effort do. Change for variety or stalls.
    case periodizationOptionalForHypertrophy
    case blockLengthReached(weeks: Int)
    case stallsInBlock(lifts: Int)
    case peakForTargetDate(weeksLeft: Int)
    case balanceStrengthAndSize

    public var evidence: EvidenceReference {
        switch self {
        case .periodizationHelpsStrength, .periodizationOptionalForHypertrophy, .peakForTargetDate:
            FocusEvidence.periodization
        case .blockLengthReached, .balanceStrengthAndSize: FocusEvidence.focusHeuristics
        case .stallsInBlock: ProgressionEvidence.stallHeuristics
        }
    }
}

public struct BlockSuggestion: Hashable, Sendable {
    public var current: TrainingFocus?
    public var weeksInCurrent: Int
    public var next: TrainingFocus
    /// Weeks from now until the switch (0 = now).
    public var switchInWeeks: Int
    public var nextLengthWeeks: ClosedRange<Int>
    public var reasons: [BlockReason]
}

/// Long-term view: infers past blocks from history, suggests when and to what to switch, and drafts a plan
/// for the coming months (up to a year or the goal's target date).
///
/// Evidence: periodised training improves 1RM more than non-periodised, not hypertrophy; undulating ≥ linear for
/// strength in trained lifters (Moesgaard 2022); LP vs DUP similar for hypertrophy (Grgic 2017). Block lengths
/// (4–8 weeks) and the templates are heuristics.
public enum BlockAdvisor {
    // MARK: Inferred history

    /// Groups training into weeks, takes each week's dominant focus, and merges consecutive equal weeks.
    public static func inferBlocks(sessions: [StrengthSession], calendar: Calendar = .current) -> [TrainingBlock] {
        inferBlocks(index: ExposureIndex(sessions: sessions), calendar: calendar)
    }

    /// Same as `inferBlocks(sessions:calendar:)`, reusing an index built once.
    public static func inferBlocks(index: ExposureIndex, calendar: Calendar = .current) -> [TrainingBlock] {
        let sorted = index.sessions
        guard let first = sorted.first else { return [] }
        let origin = calendar.startOfDay(for: first.startedAt)

        var weekly: [Int: [TrainingFocus]] = [:]
        for session in sorted {
            guard let focus = FocusClassifier.focus(of: session, index: index) else { continue }
            let days = calendar.dateComponents([.day], from: origin, to: session.startedAt).day ?? 0
            weekly[days / 7, default: []].append(focus)
        }

        var blocks: [TrainingBlock] = []
        for week in weekly.keys.sorted() {
            guard let focus = FocusClassifier.dominant(weekly[week] ?? []) else { continue }
            if let last = blocks.last, last.focus == focus { continue }
            let start = CalendarDay(origin, calendar: calendar).adding(days: week * 7, calendar: calendar)
            blocks.append(TrainingBlock(focus: focus, start: start, isDeclared: false))
        }
        return blocks
    }

    // MARK: Next block

    public static func suggestion(
        goal: TrainingGoal?,
        current: TrainingBlock?,
        today: CalendarDay,
        stalledLifts: Int = 0,
        calendar: Calendar = .current
    ) -> BlockSuggestion {
        let kind = goal?.kind ?? .general
        let weeksIn = current.map { weeks(from: $0.start, to: today, calendar: calendar) } ?? 0
        let focus = current?.focus

        if kind == .strength, let target = goal?.targetDate {
            let left = weeks(from: today, to: target, calendar: calendar)
            if left >= 0, left <= 5 {
                return BlockSuggestion(
                    current: focus, weeksInCurrent: weeksIn, next: .strength, switchInWeeks: 0,
                    nextLengthWeeks: max(1, left - 1)...max(1, left - 1),
                    reasons: [.peakForTargetDate(weeksLeft: left), .periodizationHelpsStrength]
                )
            }
        }

        let stalls: [BlockReason] = stalledLifts >= 2 ? [.stallsInBlock(lifts: stalledLifts)] : []
        switch kind {
        case .strength:
            if focus == .strength {
                let due = weeksIn >= 5 || !stalls.isEmpty
                return BlockSuggestion(
                    current: focus, weeksInCurrent: weeksIn, next: .hypertrophy,
                    switchInWeeks: due ? 0 : 5 - weeksIn, nextLengthWeeks: 4...8,
                    reasons: reasons(.periodizationHelpsStrength, due: due, weeksIn: weeksIn, stalls: stalls)
                )
            }
            let due = weeksIn >= 6 || !stalls.isEmpty
            return BlockSuggestion(
                current: focus, weeksInCurrent: weeksIn, next: .strength,
                switchInWeeks: due ? 0 : 6 - weeksIn, nextLengthWeeks: 3...6,
                reasons: reasons(.periodizationHelpsStrength, due: due, weeksIn: weeksIn, stalls: stalls)
            )
        case .hypertrophy:
            if focus == .hypertrophy || focus == nil {
                let due = weeksIn >= 10 || !stalls.isEmpty
                return BlockSuggestion(
                    current: focus, weeksInCurrent: weeksIn, next: due ? .mixed : .hypertrophy,
                    switchInWeeks: due ? 0 : 10 - weeksIn, nextLengthWeeks: due ? 3...4 : 6...10,
                    reasons: [.periodizationOptionalForHypertrophy] + stalls
                )
            }
            return BlockSuggestion(
                current: focus, weeksInCurrent: weeksIn, next: .hypertrophy,
                switchInWeeks: weeksIn >= 4 ? 0 : 4 - weeksIn, nextLengthWeeks: 6...10,
                reasons: [.periodizationOptionalForHypertrophy]
            )
        case .general, .hybrid:
            let next: TrainingFocus = focus == .hypertrophy ? .strength : .hypertrophy
            let length = focus == .strength ? 4 : 6
            let due = weeksIn >= length || !stalls.isEmpty
            return BlockSuggestion(
                current: focus, weeksInCurrent: weeksIn, next: next,
                switchInWeeks: due ? 0 : length - weeksIn, nextLengthWeeks: next == .strength ? 3...5 : 4...8,
                reasons: reasons(.balanceStrengthAndSize, due: due, weeksIn: weeksIn, stalls: stalls)
            )
        }
    }

    // MARK: Forward plan

    /// Drafts blocks from `today` for `horizonWeeks` (default a year), separated by deload weeks. With a strength
    /// goal and a target date inside the horizon, the plan ends with a strength block and a taper week before it.
    public static func plan(
        goal: TrainingGoal?,
        current: TrainingBlock?,
        today: CalendarDay,
        horizonWeeks: Int = 52,
        recentlyDeloaded: Bool = false,
        calendar: Calendar = .current
    ) -> [PlannedBlock] {
        let kind = goal?.kind ?? .general
        let template = cycle(for: kind)
        var blocks: [PlannedBlock] = []
        var cursor = today

        func append(_ focus: TrainingFocus?, _ weeks: Int) {
            guard weeks > 0 else { return }
            if let last = blocks.last, last.focus == focus {
                blocks[blocks.count - 1].weeks += weeks  // merge consecutive blocks of the same kind
            } else {
                blocks.append(PlannedBlock(focus: focus, start: cursor, weeks: weeks))
            }
            cursor = cursor.adding(days: weeks * 7, calendar: calendar)
        }

        let first = suggestion(goal: goal, current: current, today: today, calendar: calendar)
        if let focus = current?.focus, first.switchInWeeks > 0 {
            append(focus, first.switchInWeeks)
        }
        if first.switchInWeeks == 0, current != nil, !recentlyDeloaded { append(nil, 1) }

        var horizon = horizonWeeks
        var peak: (target: CalendarDay, strengthWeeks: Int)?
        if kind == .strength, let target = goal?.targetDate {
            let left = weeks(from: today, to: target, calendar: calendar)
            if left > 0, left <= horizonWeeks {
                horizon = left
                peak = (target, min(4, max(1, left - 1)))
            }
        }

        let rotation = rotated(template, startingAt: first.next)
        var index = 0
        while true {
            let used = weeks(from: today, to: cursor, calendar: calendar)
            let reserve = peak.map { $0.strengthWeeks + 1 } ?? 0
            let remaining = horizon - used - reserve
            guard remaining > 0 else { break }
            let (blockFocus, length) = rotation[index % rotation.count]
            var focus = blockFocus
            let blockWeeks = min(length, remaining)
            if peak != nil, blockWeeks == remaining, focus == .strength {
                focus = .mixed  // the peak block follows; don't stack two strength blocks
            }
            append(focus, blockWeeks)
            index += 1
        }
        if let peak {
            append(.strength, peak.strengthWeeks)
            append(nil, 1)  // taper into the target date
        }
        return blocks
    }

    // MARK: Helpers

    private static func reasons(_ base: BlockReason, due: Bool, weeksIn: Int, stalls: [BlockReason]) -> [BlockReason] {
        var result = [base]
        if due { result.append(.blockLengthReached(weeks: weeksIn)) }
        return result + stalls
    }

    /// One cycle of the template for a goal: (focus or deload, weeks).
    private static func cycle(for kind: TrainingGoal.Kind) -> [(TrainingFocus?, Int)] {
        switch kind {
        case .strength: [(.hypertrophy, 6), (nil, 1), (.strength, 4), (nil, 1)]
        case .hypertrophy: [(.hypertrophy, 8), (nil, 1), (.mixed, 4), (nil, 1)]
        case .general, .hybrid: [(.hypertrophy, 6), (nil, 1), (.strength, 4), (nil, 1)]
        }
    }

    private static func rotated(
        _ template: [(TrainingFocus?, Int)], startingAt focus: TrainingFocus
    ) -> [(TrainingFocus?, Int)] {
        guard let start = template.firstIndex(where: { $0.0 == focus }) else { return template }
        return Array(template[start...] + template[..<start])
    }

    static func weeks(from start: CalendarDay, to end: CalendarDay, calendar: Calendar) -> Int {
        let from = start.startDate(in: calendar)
        let days = calendar.dateComponents([.day], from: from, to: end.startDate(in: calendar)).day ?? 0
        return days >= 0 ? days / 7 : -((-days + 6) / 7)
    }
}

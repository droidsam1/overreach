import Domain
import Foundation
import PresentationKit
import TrainingServices

/// Display values of the "Your week" card on Today (ADR-0042, `docs/design/today-visual.md`): seven days, the
/// progress and its segments, one summary line and today's session. The counts come from `WeekProgress`, the answer
/// Plan shares.
public struct TodayWeek: Hashable, Sendable {
    public enum DayKind: Hashable, Sendable {
        /// Filled circle: a strength session, a run or both were done.
        case strength, run, both
        /// Green outline with a moon: rest was logged.
        case restLogged
        /// Outline: something is planned and not done yet.
        case planned
        /// Dashed: nothing planned, nothing done.
        case nothing
    }

    public struct DayCell: Identifiable, Hashable, Sendable {
        public let id: CalendarDay
        /// Narrow weekday: "M", "T", "W"…
        public let label: String
        public let kind: DayKind
        public let isToday: Bool
        public let accessibilityLabel: String
    }

    public enum SessionKind: Hashable, Sendable { case strength, run }
    public enum SessionTag: Hashable, Sendable { case today, adjusted }

    public struct Session: Hashable, Sendable {
        public let kind: SessionKind
        public let title: String
        /// "6 exercises · Bench press 80 kg × 5".
        public let detail: String?
        public let tag: SessionTag
        /// The planned run, struck through, when the advice changed it.
        public let originalTitle: String?
    }

    public let days: [DayCell]
    /// "Strength block · week 2 of 4"; `nil` without a declared block.
    public let blockTitle: String?
    /// 0…1, done against planned.
    public let fraction: Double
    /// Strength and run shares of the bar, each 0…1 of the planned sessions; together at most `fraction`.
    public let strengthSegment: Double
    public let runSegment: Double
    /// "4 of 6 sessions · today completes this week's strength".
    public let summary: String
    /// Today's session; `nil` when today is done, rest, or has nothing planned.
    public let session: Session?
}

extension TodayWeek {
    /// The facts of today the card adds to the week.
    struct Today {
        var strength: ScheduledTrainingRow?
        var strengthDetail: String?
        var strengthMinutes: Int?
        var runs: [ScheduledTrainingRow] = []
        var adjustedRun: RunningOption.Adjustment?
    }

    static func make(_ progress: WeekProgress?, today: Today, calendar: Calendar, format: Format) -> Self? {
        guard let progress else { return nil }
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let days = progress.days.map { day in
            let label = day.day.startDate(in: calendar).formatted(style.weekday(.narrow))
            let full = day.day.startDate(in: calendar).formatted(style.weekday(.wide))
            return DayCell(
                id: day.day, label: label, kind: kind(of: day), isToday: day.isToday,
                accessibilityLabel: accessibility(full, day)
            )
        }
        let planned = progress.sessionsPlanned
        let fraction = planned > 0 ? min(1, Double(progress.sessionsDone) / Double(planned)) : 0
        let split = progress.strengthPlanned + progress.runsPlanned
        let (strengthSegment, runSegment): (Double, Double) = if split > 0, planned > 0 {
            (min(1, Double(progress.strengthDone) / Double(planned)),
             min(1, Double(progress.runsDone) / Double(planned)))
        } else {
            (fraction, 0)
        }
        return Self(
            days: days,
            blockTitle: progress.block.map { block in
                block.name.map { L10n.format("{1} · week {2} of {3}", $0, block.week, block.weeks) }
                    ?? L10n.format("{1} block · week {2} of {3}", block.focus.displayName, block.week, block.weeks)
            },
            fraction: fraction, strengthSegment: strengthSegment, runSegment: runSegment,
            summary: summary(progress),
            session: session(today, progress: progress, format: format)
        )
    }

    private static func kind(of day: WeekProgress.Day) -> DayKind {
        switch day.done {
        case .strength: .strength
        case .run: .run
        case .both: .both
        case .restLogged: .restLogged
        case .nothing: day.isPlanned ? .planned : .nothing
        }
    }

    private static func accessibility(_ weekday: String, _ day: WeekProgress.Day) -> String {
        let state = switch day.done {
        case .strength: L10n.text("Strength done")
        case .run: L10n.text("Run done")
        case .both: L10n.text("Strength and run done")
        case .restLogged: L10n.text("Rest logged")
        case .nothing where day.isPlanned: L10n.text("Planned")
        case .nothing: L10n.text("Nothing planned")
        }
        return day.isToday ? L10n.format("{1}, today: {2}", weekday, state) : L10n.format("{1}: {2}", weekday, state)
    }

    private static func summary(_ progress: WeekProgress) -> String {
        guard progress.sessionsPlanned > 0 else {
            let done = progress.days.filter { [.strength, .run, .both].contains($0.done) }.count
            return done > 0 ? L10n.format("Days trained this week: {1}", done) : L10n.text("Nothing planned this week")
        }
        let count = L10n.format("{1} of {2} sessions", progress.sessionsDone, progress.sessionsPlanned)
        guard let today = progress.days.first(where: \.isToday) else { return count }
        let strengthPending = today.plannedStrength && ![.strength, .both].contains(today.done)
        let runPending = today.plannedRun && ![.run, .both].contains(today.done)
        let pending = (strengthPending ? 1 : 0) + (runPending ? 1 : 0)
        guard pending > 0, pending == progress.sessionsPlanned - progress.sessionsDone else { return count }
        return switch (strengthPending, runPending) {
        case (true, true): L10n.format("{1} · today completes this week", count)
        case (true, false): L10n.format("{1} · today completes this week's strength", count)
        default: L10n.format("{1} · today completes this week's running", count)
        }
    }

    private static func session(_ today: Today, progress: WeekProgress, format: Format) -> Session? {
        if let strength = today.strength, strength.status == nil {
            let minutes = today.strengthMinutes.map { L10n.format("~{1} min", $0) }
            let detail = [today.strengthDetail.flatMap { $0.isEmpty ? nil : $0 }, minutes].compactMap { $0 }
            return Session(
                kind: .strength, title: strength.title, detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
                tag: .today, originalTitle: nil
            )
        }
        guard let run = today.runs.first(where: { $0.status == nil }) else { return nil }
        guard let adjustment = today.adjustedRun else {
            return Session(kind: .run, title: run.title, detail: nil, tag: .today, originalTitle: nil)
        }
        return Session(
            kind: .run, title: L10n.format("Easy run · {1} min", adjustment.minutes), detail: nil, tag: .adjusted,
            originalTitle: adjustment.original.calendarTitle(format: format)
        )
    }
}

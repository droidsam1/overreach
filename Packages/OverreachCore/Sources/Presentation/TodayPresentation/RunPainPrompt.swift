import Domain
import Foundation
import PresentationKit

/// A recorded run Today asks about when the goal aims for pain-free running (#256): after the run for its severity,
/// and the next day for whether the pain settled by morning.
public struct RunPainPrompt: Identifiable, Hashable, Sendable {
    public enum Question: Hashable, Sendable {
        /// How strong was the pain during and after the run, and has it settled?
        case severity
        /// The severity is known and was above zero: did it settle by the next morning?
        case settled
    }

    public var id: String { report.source.rawValue + "/" + report.activityID }
    public let report: RunPainReport
    public let question: Question
    public let summary: String
    public let title: String

    init(report: RunPainReport, question: Question, distanceMeters: Double, calendar: Calendar, format: Format) {
        self.report = report
        self.question = question
        let distance = distanceMeters.isFinite && distanceMeters > 0
            ? format.number(distanceMeters / 1_000, maxFractionDigits: 2) + " km" : nil
        let day = report.startedAt.formatted(
            Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide).hour().minute())
        summary = [distance, day].compactMap { $0 }.joined(separator: " · ")
        title = question == .severity ? L10n.text("How did your last run feel?")
            : L10n.text("Was the pain gone this morning?")
    }

    /// The newest recorded run of the last two days without an answer, or with pain whose morning is unanswered.
    static func next(
        runs: [RunActivity], reports: [RunPainReport], now: Date, calendar: Calendar, format: Format
    ) -> Self? {
        let earliest = CalendarDay(now, calendar: calendar).adding(days: -1, calendar: calendar).startDate(in: calendar)
        let candidates = RunDeduplication.removingDuplicates(runs).filter { run in
            run.startedAt >= earliest && run.startedAt <= now && run.distanceMeters.isFinite && run.distanceMeters > 0
                && run.durationSeconds.isFinite && run.durationSeconds > 0
        }.sorted { $0.startedAt > $1.startedAt }
        for run in candidates {
            let known = reports.first { $0.matches(run) }
            if known == nil || (known?.painDuring == nil && known?.painAfter == nil) {
                return Self(report: known ?? RunPainReport(run), question: .severity,
                            distanceMeters: run.distanceMeters, calendar: calendar, format: format)
            }
            if let known, known.reportsPain, known.worstSeverity != nil, known.settledByMorning == nil,
               calendar.startOfDay(for: run.startedAt) < calendar.startOfDay(for: now) {
                return Self(report: known, question: .settled, distanceMeters: run.distanceMeters,
                            calendar: calendar, format: format)
            }
        }
        return nil
    }
}

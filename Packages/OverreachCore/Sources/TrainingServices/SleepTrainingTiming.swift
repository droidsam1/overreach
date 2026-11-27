import Analytics
import Domain
import Foundation

/// When the athlete sleeps and trains, read once for Recovery & Progress and the AI context (ADR-0035, ADR-0045).
/// Observations only: nothing here changes load, readiness or the plan.
public enum SleepTrainingTiming {
    /// Days of nights and sessions the timing is judged on.
    public static let windowDays = 28

    /// The timing report from merged nights, logged sessions, runs and watch strength recordings.
    /// A session is hard when its session RPE is ≥ 8, a run when it is a race or its training effect says so
    /// (`RunCarryover`), and a watch recording when its anaerobic training effect does.
    public static func report(
        metrics: [DailyMetrics], sessions: [StrengthSession], runs: [RunActivity],
        recordings: [RecordedStrengthActivity], now: Date, calendar: Calendar = .current,
        settings: CircadianTiming.Settings = .init(), runSettings: RunCarryover.Settings = .init()
    ) -> CircadianTiming.Report {
        let today = CalendarDay(now, calendar: calendar)
        let start = today.adding(days: 1 - windowDays, calendar: calendar).startDate(in: calendar)
        let window = start...now

        let nights = metrics.compactMap(\.sleepInterval).filter { window.contains($0.upperBound) }
            .map { CircadianTiming.Span(start: $0.lowerBound, end: $0.upperBound) }

        let logged = sessions.compactMap { session -> CircadianTiming.Span? in
            guard let end = session.endedAt, session.startedAt < end, window.contains(session.startedAt) else {
                return nil
            }
            return .init(start: session.startedAt, end: end, isHard: (session.sessionRPE ?? 0) >= 8)
        }
        // A watch recording of a logged session is the same session.
        let recorded = recordings.compactMap { recording -> CircadianTiming.Span? in
            let end = recording.startedAt.addingTimeInterval(recording.durationSeconds)
            guard recording.durationSeconds.isFinite, recording.durationSeconds > 0,
                window.contains(recording.startedAt),
                !logged.contains(where: { $0.start < end && $0.end > recording.startedAt })
            else { return nil }
            let hard = (recording.anaerobicTrainingEffect ?? 0) >= runSettings.hardAnaerobicTrainingEffect
            return .init(start: recording.startedAt, end: end, isHard: hard)
        }
        let running = RunDeduplication.removingDuplicates(runs).compactMap { run -> CircadianTiming.Span? in
            guard run.durationSeconds.isFinite, run.durationSeconds > 0, window.contains(run.startedAt) else {
                return nil
            }
            let hard = run.kind == .race
                || (run.anaerobicTrainingEffect ?? 0) >= runSettings.hardAnaerobicTrainingEffect
                || (run.aerobicTrainingEffect ?? 0) >= runSettings.hardAerobicTrainingEffect
            return .init(start: run.startedAt, end: run.startedAt.addingTimeInterval(run.durationSeconds), isHard: hard)
        }

        return CircadianTiming.analyze(
            nights: nights, sessions: logged + recorded + running, calendar: calendar, settings: settings
        )
    }
}

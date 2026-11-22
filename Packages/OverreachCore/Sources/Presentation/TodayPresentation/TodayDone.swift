import Analytics
import Domain
import Foundation
import PresentationKit
import TrainingServices

/// The completed state of Today's hero.
public struct TodayDone: Hashable, Sendable {
    public enum SessionID: Hashable, Sendable {
        case strength(UUID)
        case recording(DataSourceKind, String)
        case run(DataSourceKind, String)
    }

    public struct Session: Identifiable, Hashable, Sendable {
        public let id: SessionID
        public let title: String
        public let startedAt: Date
        public let duration: String?
        public let sets: Int?
        public let volume: String?
        public let distance: String?
        public let pace: String?
        public let records: [String]

        init(
            id: SessionID, title: String, startedAt: Date, duration: String?, sets: Int? = nil,
            volume: String? = nil, distance: String? = nil, pace: String? = nil, records: [String] = []
        ) {
            self.id = id
            self.title = title
            self.startedAt = startedAt
            self.duration = duration
            self.sets = sets
            self.volume = volume
            self.distance = distance
            self.pace = pace
            self.records = records
        }
    }

    public struct NextSession: Hashable, Sendable {
        public let title: String
        public let detail: String?
    }

    public let title: String
    public let sessions: [Session]
    public let tomorrow: [NextSession]
}

extension TodayDone {
    static func completedSessions(
        _ record: TrainingRecord, plannedRuns: [PlannedRun], effortScale: EffortScale,
        today: ClosedRange<Date>, format: Format
    ) -> [Session] {
        let lifts = record.sessions.filter { today.contains($0.endedAt ?? $0.startedAt) }
        let recordings = record.recordings.filter { $0.durationSeconds.isFinite && today.contains($0.endedAt) }
        let matches = StrengthActivityMatching.match(sessions: lifts, activities: recordings)
        var sessions = lifts.map { strength($0, record: record, effortScale: effortScale, format: format) }
        sessions += matches.unmatched.map { recording in
            Session(
                id: .recording(recording.source, recording.id), title: completed(L10n.text("Strength workout")),
                startedAt: recording.startedAt, duration: SessionReport.durationText(recording.durationSeconds),
                sets: recording.totalSets.flatMap { $0 > 0 ? $0 : nil }
            )
        }
        var runs = record.runs
        for planned in plannedRuns {
            guard let completion = planned.completion, !runs.contains(where: completion.matches) else { continue }
            runs.append(RunActivity(
                id: completion.activityID, source: completion.source, name: planned.purpose.displayName,
                startedAt: completion.startedAt, durationSeconds: completion.durationSeconds,
                distanceMeters: completion.distanceMeters ?? 0
            ))
        }
        sessions += runs.filter {
            $0.durationSeconds.isFinite && today.contains($0.startedAt.addingTimeInterval($0.durationSeconds))
        }.map { run($0, format: format) }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    private static func strength(
        _ session: StrengthSession, record: TrainingRecord, effortScale: EffortScale, format: Format
    ) -> Session {
        let historyStart = session.startedAt.addingTimeInterval(-ProgressionTargets.historyWindow)
        let review = SessionReviewer.review(
            session, targets: [:], history: record.sessions.filter { $0.startedAt >= historyStart },
            exercises: record.exercises, settings: record.settings,
            routine: record.routines.first { $0.id == session.routineID }
        )
        let report = SessionReport(review: review, effortScale: effortScale, format: format)
        return Session(
            id: .strength(session.id), title: completed(report.title), startedAt: session.startedAt,
            duration: report.duration, sets: report.workingSets, volume: report.volume, records: report.achievements
        )
    }

    private static func run(_ activity: RunActivity, format: Format) -> Session {
        let meters = activity.distanceMeters
        let distance = meters.isFinite && meters > 0 ? format.number(meters / 1_000, maxFractionDigits: 3) + " km" : nil
        let pace = activity.paceSecondsPerKm.flatMap { Int(exactly: $0.rounded()) }
        return Session(
            id: .run(activity.source, activity.id), title: completed(activity.name ?? L10n.text("Run")),
            startedAt: activity.startedAt, duration: SessionReport.durationText(activity.durationSeconds),
            distance: distance, pace: pace.flatMap { $0 > 0 ? format.minutesAndSeconds($0) + " /km" : nil }
        )
    }

    private static func completed(_ title: String) -> String {
        L10n.format("{1} completed", title)
    }

    static func outlook(
        goal: TrainingGoal?, tomorrow: CalendarDay, routines: [Routine], format: Format
    ) -> [NextSession] {
        let strength = (goal?.scheduledStrength ?? []).filter { $0.day == tomorrow }.map { assignment in
            let routine = routines.first { $0.id == assignment.routineID }
            guard let routine else {
                return NextSession(title: assignment.displayName(routineName: nil), detail: nil)
            }
            return NextSession(title: L10n.text("Strength"), detail: routine.name)
        }
        let runs = (goal?.scheduledRuns ?? []).filter { $0.day == tomorrow && !$0.isPostponed && $0.purpose != .rest }
        return strength + runs.map { run in
            let title = run.racePriority?.displayName ?? run.purpose.displayName
            return NextSession(title: title, detail: run.plannedTotals(format: format))
        }
    }
}

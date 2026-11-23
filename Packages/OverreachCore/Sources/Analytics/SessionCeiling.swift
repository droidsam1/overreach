import Domain
import Foundation

/// The single-session ceiling for dated runs (ADR-0043): a session more than 10% longer than the longest session of
/// the previous 30 days is flagged. A warning, never a block. Runs that start less than 15 minutes after the previous
/// one ended count as one session, as in the cohort study.
public enum SessionCeiling {
    public static let evidence = EvidenceReference(key: "single-session-ceiling", level: .limited)

    public struct Settings: Sendable {
        /// Window for the longest recent session, as in the cohort study.
        public var historyDays = 30
        public var increaseFraction = 0.10
        /// Runs closer than this, from the end of one to the start of the next, are one session.
        public var mergeGapSeconds: TimeInterval = 15 * 60
        /// A shortened session is rounded down to this.
        public var roundingMeters = 100

        public init() {}
    }

    /// One session for the ceiling: a recorded run, or runs merged into one.
    public struct Session: Hashable, Sendable {
        public let start: Date
        public let end: Date
        public let distanceMeters: Double
        public let durationSeconds: Double
    }

    /// A dated run planned past the ceiling of its day.
    public struct Warning: Hashable, Sendable {
        public let entryID: UUID
        /// Planned distance, or the planned duration converted with the recent pace.
        public let plannedMeters: Int
        /// The longest session of the 30 days before the run, recorded or planned earlier in the calendar.
        public let longestMeters: Int
        /// The suggested shorter distance: 10% over the longest session, rounded down.
        public let ceilingMeters: Int
        /// The planned distance was estimated from a duration.
        public let isEstimated: Bool
        /// Recent pace used to convert durations, when there was one.
        public let paceSecondsPerKm: Double?
    }

    /// Recorded runs as sessions, oldest first: duplicates across sources removed, then runs less than 15 minutes
    /// apart merged.
    public static func sessions(_ runs: [RunActivity], settings: Settings = .init()) -> [Session] {
        let valid = RunDeduplication.removingDuplicates(runs).filter {
            $0.distanceMeters.isFinite && $0.distanceMeters > 0 && $0.durationSeconds.isFinite && $0.durationSeconds > 0
        }.sorted { $0.startedAt < $1.startedAt }
        var merged: [Session] = []
        for run in valid {
            let end = run.startedAt.addingTimeInterval(run.durationSeconds)
            if let last = merged.last, run.startedAt.timeIntervalSince(last.end) < settings.mergeGapSeconds {
                merged[merged.count - 1] = Session(
                    start: last.start, end: max(last.end, end),
                    distanceMeters: last.distanceMeters + run.distanceMeters,
                    durationSeconds: last.durationSeconds + run.durationSeconds
                )
            } else {
                merged.append(Session(start: run.startedAt, end: end, distanceMeters: run.distanceMeters,
                                      durationSeconds: run.durationSeconds))
            }
        }
        return merged
    }

    /// Warnings for the runs planned from `today` on, keyed by entry. Each day's window holds the recorded sessions
    /// and the runs planned before it in the calendar, so a plan that grows within 10% per session passes. A flagged
    /// run counts at its ceiling for later days. Rest days, races, postponed and completed entries are not checked;
    /// a race keeps its distance but counts for later days. Without any session in the window there is no ceiling.
    public static func warnings(
        schedule: [PlannedRun], runs: [RunActivity], today: CalendarDay, calendar: Calendar = .current,
        settings: Settings = .init()
    ) -> [UUID: Warning] {
        let recorded = sessions(runs, settings: settings)
        let todayStart = today.startDate(in: calendar)
        let recentStart = today.adding(days: -settings.historyDays, calendar: calendar).startDate(in: calendar)
        let recent = recorded.filter { $0.start >= recentStart && $0.start < todayStart }
        let recentDistance = recent.reduce(0) { $0 + $1.distanceMeters }
        let pace = recentDistance > 0 ? recent.reduce(0) { $0 + $1.durationSeconds } / (recentDistance / 1_000) : nil

        let upcoming = schedule.filter {
            $0.day >= today && $0.purpose != .rest && !$0.isPostponed && $0.completion == nil
        }.sorted { $0.day < $1.day }
        var projected: [(day: CalendarDay, meters: Double)] = []
        var warnings: [UUID: Warning] = [:]
        for entry in upcoming {
            guard let planned = plannedMeters(entry, pace: pace) else { continue }
            let meters = planned.meters
            let start = entry.day.adding(days: -settings.historyDays, calendar: calendar)
            let windowStart = start.startDate(in: calendar)
            let dayStart = entry.day.startDate(in: calendar)
            let longest = (recorded.filter { $0.start >= windowStart && $0.start < dayStart }.map(\.distanceMeters)
                + projected.filter { $0.day >= start && $0.day < entry.day }.map(\.meters)).max()
            guard let longest, longest > 0 else {
                projected.append((entry.day, meters))
                continue
            }
            let limit = longest * (1 + settings.increaseFraction)
            guard entry.purpose != .race, meters > limit else {
                projected.append((entry.day, meters))
                continue
            }
            let unit = Double(settings.roundingMeters)
            let ceiling = Int((limit / unit).rounded(.down) * unit)
            warnings[entry.id] = Warning(
                entryID: entry.id, plannedMeters: Int(meters.rounded()), longestMeters: Int(longest.rounded()),
                ceilingMeters: ceiling, isEstimated: planned.isEstimated, paceSecondsPerKm: pace
            )
            projected.append((entry.day, Double(ceiling)))
        }
        return warnings
    }

    private static func plannedMeters(_ entry: PlannedRun, pace: Double?) -> (meters: Double, isEstimated: Bool)? {
        if let distance = entry.distanceMeters, distance > 0 { return (Double(distance), false) }
        guard let minutes = entry.durationMinutes, minutes > 0, let pace, pace > 0 else { return nil }
        return (Double(minutes * 60) / pace * 1_000, true)
    }
}

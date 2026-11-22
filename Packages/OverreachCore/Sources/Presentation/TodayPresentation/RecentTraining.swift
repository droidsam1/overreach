import Domain
import Foundation
import PresentationKit

public struct RecentTrainingDay: Identifiable, Hashable, Sendable {
    public let id: CalendarDay
    public let date: String
    public let recovery: String?
    public let workouts: [String]
    /// The same workouts with their timing, for comparisons with the moment a reading was taken (ADR-0034).
    let activities: [RecentTraining.Activity]
}

/// Align observed recovery and completed exercise by local calendar day. This is a record of what happened.
struct RecentTraining {
    struct Activity: Hashable, Sendable {
        let startedAt: Date
        /// The recorded end, or the start when the duration is unknown.
        let endedAt: Date
        let text: String
        /// A recorded run the athlete linked to a planned race. Names and pace never make a race (ADR-0034).
        var isRace = false
    }

    let calendar: Calendar
    let format: Format

    /// `races` are the athlete's confirmed links between a planned race and a recording.
    func days(
        in range: ClosedRange<CalendarDay>, through now: Date, metrics: [DailyMetrics], checkIns: [CheckIn],
        runs: [RunActivity], sessions: [StrengthSession], recordings: [RecordedStrengthActivity], exercises: [Exercise],
        choices: ActivityMatchChoices = .init(), races: [PlannedRunCompletion] = []
    ) -> [RecentTrainingDay] {
        let workouts = completedActivities(through: now, runs: runs, sessions: sessions, recordings: recordings,
                                            exercises: exercises, choices: choices, races: races)
        let byDay = Dictionary(grouping: workouts) { CalendarDay($0.startedAt, calendar: calendar) }
        let metricsByDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let checkInsByDay = Dictionary(checkIns.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let dates = Set(byDay.keys).union(metricsByDay.keys).union(checkInsByDay.keys)
        return dates.filter(range.contains).sorted(by: >).compactMap { day in
            let activities = byDay[day, default: []]
            let workouts = activities.map(\.text)
            let recovery = recoverySummary(metricsByDay[day], checkIn: checkInsByDay[day])
            guard !workouts.isEmpty || recovery != nil else { return nil }
            return RecentTrainingDay(
                id: day, date: day.startDate(in: calendar).formatted(style.weekday(.abbreviated).day().month(.abbreviated)),
                recovery: recovery, workouts: workouts, activities: activities
            )
        }
    }

    private func completedActivities(
        through now: Date, runs: [RunActivity], sessions: [StrengthSession], recordings: [RecordedStrengthActivity],
        exercises: [Exercise], choices: ActivityMatchChoices, races: [PlannedRunCompletion]
    ) -> [Activity] {
        // Match across the window boundary before grouping. Logged sets are authoritative for matched lifts.
        let completedSessions = sessions.filter { $0.isCompleted(through: now) }
        let completedRecordings = recordings.filter { $0.durationSeconds.isFinite && $0.endedAt <= now }
        let matched = StrengthActivityMatching.resolve(
            sessions: completedSessions, activities: completedRecordings, choices: choices.strength
        ).matches
        let exerciseByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let completedRuns = runs.filter {
            $0.durationSeconds.isFinite && $0.startedAt.addingTimeInterval(max(0, $0.durationSeconds)) <= now
        }
        let runActivities = RunDeduplication.resolve(completedRuns, choices: choices.runs).runs.map { combined in
            let run = combined.activity
            let isRace = races.contains { $0.matches(run) }
            let name = run.name ?? L10n.text("Run")
            var activity = activity(
                startedAt: run.startedAt, title: isRace ? L10n.format("Race: {1}", name) : name,
                duration: run.durationSeconds,
                details: [
                    run.distanceMeters.finitePositive.map { format.number($0 / 1_000) + " km" },
                    run.averageHeartRate.flatMap(\.finitePositive).map { format.number($0, maxFractionDigits: 0) + " bpm" },
                ]
            )
            activity.isRace = isRace
            return activity
        }
        let loggedStrength = completedSessions.map { session in
            let recording = matched.activity(for: session.id)
            let legSets = session.entries.reduce(0) { count, entry in
                guard exerciseByID[entry.exerciseID]?.primaryMuscles.contains(where: { $0.region == .lower }) == true
                else { return count }
                return count + entry.sets.filter(\.isWorking).count
            }
            return activity(
                startedAt: session.startedAt, title: session.name,
                duration: session.durationSeconds ?? recording?.durationSeconds,
                details: [
                    legSets > 0 ? L10n.format("Leg working sets {1}", String(legSets)) : nil,
                    session.sessionRPE.flatMap(\.finitePositive).map { "RPE " + format.number($0, maxFractionDigits: 1) },
                ]
            )
        }
        let watchOnly = matched.unmatched.map {
            activity(startedAt: $0.startedAt, title: L10n.text("Strength"), duration: $0.durationSeconds,
                     details: [$0.source.displayName])
        }
        return (runActivities + loggedStrength + watchOnly).sorted { ($0.startedAt, $0.text) < ($1.startedAt, $1.text) }
    }

    private func activity(startedAt: Date, title: String, duration: Double?, details: [String?]) -> Activity {
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = startedAt.formatted(style.hour().minute())
        let minutes = duration.flatMap(\.finitePositive).map { format.number($0 / 60, maxFractionDigits: 1) + " min" }
        let text = ([time, title] + ([minutes] + details).compactMap { $0 }).joined(separator: " · ")
        let end = duration.flatMap(\.finitePositive).map { startedAt.addingTimeInterval($0) } ?? startedAt
        return Activity(startedAt: startedAt, endedAt: end, text: text)
    }

    private func recoverySummary(_ metrics: DailyMetrics?, checkIn: CheckIn?) -> String? {
        var parts: [String] = []
        if let hrv = metrics?.hrvNightlyAverageMs.flatMap(\.finitePositive) {
            let statistic = metrics?.hrvMetric.map { " (\($0.rawValue.uppercased()))" } ?? ""
            parts.append(L10n.text("HRV") + statistic + " \(format.number(hrv, maxFractionDigits: 0)) ms")
        }
        if let hr = metrics?.restingHeartRate.flatMap(\.finitePositive) {
            parts.append(L10n.text("Resting HR") + " \(format.number(hr, maxFractionDigits: 0)) bpm")
        }
        if let sleep = metrics?.sleepSeconds.flatMap(\.finitePositive) {
            parts.append(L10n.text("Sleep") + " \(format.number(sleep / 3_600, maxFractionDigits: 1)) h")
        }
        if let checkIn {
            if checkIn.isSick { parts.append(L10n.text("Sick")) }
            if let energy = checkIn.energy { parts.append(L10n.format("Energy {1}/5", String(energy))) }
            if let soreness = checkIn.soreness { parts.append(L10n.format("Soreness {1}/3", String(soreness))) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension Double {
    var finitePositive: Double? { isFinite && self > 0 ? self : nil }
}

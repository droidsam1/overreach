import Domain
import Foundation

public struct DetectedDeload: Hashable, Sendable {
    public let start: CalendarDay
    public let end: CalendarDay
    public let reason: DeloadReason
    public let needsConfirmation: Bool
    public let discipline: TrainingDiscipline?

    public var evidence: EvidenceReference {
        EvidenceReference(
            key: reason == .noTraining && discipline != nil ? "training-breaks" : "unplanned-deload",
            level: .heuristic
        )
    }

    public init(
        start: CalendarDay, end: CalendarDay, reason: DeloadReason, needsConfirmation: Bool,
        discipline: TrainingDiscipline? = nil
    ) {
        self.start = start
        self.end = end
        self.reason = reason
        self.needsConfirmation = needsConfirmation
        self.discipline = discipline
    }
}

/// Detects recovery from complete local days. Strength and running are assessed separately so continued
/// training in one discipline cannot be hidden by a drop in the other.
public enum DeloadDetection {
    public static let historyDays = 365
    public struct BreakSettings: Sendable {
        public var minimumDays = 7
        public var returnDays = 14
        public var strengthReturnWeeks = 4
        public var runningReturnRuns = 2

        public init() {}
    }

    private static let week = 7
    private static let low = 0.5
    private static let possible = 0.65

    private struct ReducedWeekPolicy {
        let maxHeartRate: Double?
        let requireConfirmation: Bool
        let separateDisciplines: Bool
    }

    private struct Strength {
        let sets: Int
        let hasEffort: Bool
        let hard: Bool
        let planFraction: Double?
    }

    private struct Day {
        var strength: [Strength] = []
        var runs: [RunActivity] = []
    }

    public static func periods(
        sessions: [StrengthSession], runs: [RunActivity], profile: AthleteProfile,
        routines: [Routine] = [], exercises: [UUID: Exercise] = [:],
        settings: [UUID: ProgressionSettings] = [:], runReadFailed: Bool = false,
        recordings: [RecordedStrengthActivity] = [],
        today: CalendarDay, calendar: Calendar = .current, breakSettings: BreakSettings = .init()
    ) -> [DetectedDeload] {
        let firstRecentDay = today.adding(days: -historyDays, calendar: calendar)
        let firstRecentDate = firstRecentDay.startDate(in: calendar)
        let recent = days(
            sessions: sessions.filter { $0.startedAt >= firstRecentDate },
            runs: runs.filter { $0.startedAt >= firstRecentDate }, routines: routines, exercises: exercises,
            settings: settings, recordings: recordings.filter { $0.startedAt >= firstRecentDate },
            today: today, calendar: calendar
        )
        let missingRuns = runReadFailed || (profile.goal?.kind == .hybrid && runs.isEmpty)
        var breaks: [DetectedDeload]
        if profile.countsBreaksAutomatically {
            let strength = sessions.filter { session in
                (session.durationSeconds ?? 0) > 0 || session.entries.contains { $0.sets.contains(where: \.isWorking) }
            }.map { ($0.startedAt, $0.endedAt ?? $0.startedAt) }
            let watch = recordings.filter { $0.durationSeconds.isFinite && $0.durationSeconds > 0 }
                .map { ($0.startedAt, $0.endedAt) }
            breaks = disciplineBreaks(
                occupiedDays(strength + watch, before: today, calendar: calendar), discipline: .strength,
                today: today, calendar: calendar, settings: breakSettings
            )
            if !runReadFailed {
                let hasGoal = (profile.goal?.running?.distanceMeters ?? 0) > 0
                breaks += runningBreaks(
                    runs, hasGoal: hasGoal, today: today, calendar: calendar, settings: breakSettings
                )
            }
        } else {
            breaks = legacyBreaks(recent.keys.sorted(), missingRuns: missingRuns, today: today, calendar: calendar)
        }
        let lightWeeks = reducedWeeks(
            history: recent, breaks: breaks, policy: ReducedWeekPolicy(
                maxHeartRate: profile.maxHeartRate,
                requireConfirmation: profile.countsBreaksAutomatically || missingRuns,
                separateDisciplines: profile.countsBreaksAutomatically
            ), today: today, calendar: calendar
        )
        return reviewed(breaks + lightWeeks, profile: profile, today: today, calendar: calendar)
    }

    private static func runningBreaks(
        _ runs: [RunActivity], hasGoal: Bool, today: CalendarDay, calendar: Calendar, settings: BreakSettings
    ) -> [DetectedDeload] {
        let intervals = RunDeduplication.removingDuplicates(runs.filter {
            $0.durationSeconds.isFinite && $0.durationSeconds >= 0
        }).map { ($0.startedAt, $0.startedAt.addingTimeInterval($0.durationSeconds)) }
        return disciplineBreaks(
            occupiedDays(intervals, before: today, calendar: calendar), discipline: .running,
            hasRunningGoal: hasGoal, today: today, calendar: calendar,
            settings: settings
        )
    }

    private static func occupiedDays(
        _ intervals: [(Date, Date)], before today: CalendarDay, calendar: Calendar
    ) -> [CalendarDay] {
        let yesterday = today.adding(days: -1, calendar: calendar)
        var days: Set<CalendarDay> = []
        for (start, end) in intervals {
            var day = CalendarDay(start, calendar: calendar)
            // An activity ending at midnight does not occupy any of the following day.
            let last = min(yesterday, CalendarDay(max(start, end.addingTimeInterval(-0.001)), calendar: calendar))
            while day <= last {
                days.insert(day)
                day = day.adding(days: 1, calendar: calendar)
            }
        }
        return days.sorted()
    }

    private static func disciplineBreaks(
        _ days: [CalendarDay], discipline: TrainingDiscipline, hasRunningGoal: Bool = false,
        today: CalendarDay, calendar: Calendar, settings: BreakSettings
    ) -> [DetectedDeload] {
        zip(days.indices, days.dropFirst() + [today]).compactMap { index, next in
            let last = days[index]
            let start = last.adding(days: 1, calendar: calendar)
            guard start.adding(days: max(1, settings.minimumDays), calendar: calendar) <= next else { return nil }
            if discipline == .running, !hasRunningGoal {
                let baseline = last.adding(days: -(4 * week - 1), calendar: calendar)
                let weeks = Set(days[...index].reversed().prefix { $0 >= baseline }.map {
                    PlanReviewer.days(from: $0, to: last, calendar: calendar) / week
                })
                guard weeks.count >= 2 else { return nil }
            }
            return DetectedDeload(
                start: start, end: next.adding(days: -1, calendar: calendar),
                reason: .noTraining, needsConfirmation: false, discipline: discipline
            )
        }
    }

    private static func legacyBreaks(
        _ activeDays: [CalendarDay], missingRuns: Bool, today: CalendarDay, calendar: Calendar
    ) -> [DetectedDeload] {
        zip(activeDays, activeDays.dropFirst() + [today]).compactMap { last, next in
            let start = last.adding(days: 1, calendar: calendar)
            guard start.adding(days: week, calendar: calendar) <= next else { return nil }
            let recent = last.adding(days: -27, calendar: calendar)
            let hasPattern = activeDays.lazy.filter { $0 >= recent && $0 < last }.prefix(3).count == 3
            return DetectedDeload(
                start: start, end: next.adding(days: -1, calendar: calendar),
                reason: .noTraining, needsConfirmation: missingRuns || !hasPattern
            )
        }
    }

    private static func reducedWeeks(
        history: [CalendarDay: Day], breaks: [DetectedDeload], policy: ReducedWeekPolicy,
        today: CalendarDay, calendar: Calendar
    ) -> [DetectedDeload] {
        guard let first = history.keys.min() else { return [] }
        var periods: [DetectedDeload] = []
        var start = first.adding(days: 1, calendar: calendar)
        var end = start.adding(days: week - 1, calendar: calendar)
        while end < today {
            if let candidate = lowWeek(
                history: history, start: start, end: end, policy: policy, calendar: calendar
            ), !breaks.contains(where: { overlaps(candidate, $0) }) {
                if let last = periods.last, last.needsConfirmation == candidate.needsConfirmation,
                   last.discipline == candidate.discipline, start <= last.end {
                    let reason = last.reason == .reducedStrength ? last.reason : candidate.reason
                    periods[periods.count - 1] = DetectedDeload(
                        start: last.start, end: end, reason: reason, needsConfirmation: last.needsConfirmation,
                        discipline: last.discipline
                    )
                } else {
                    periods.append(candidate)
                }
            }
            start = start.adding(days: 1, calendar: calendar)
            end = end.adding(days: 1, calendar: calendar)
        }
        return periods
    }

    private static func overlaps(_ first: DetectedDeload, _ second: DetectedDeload) -> Bool {
        (first.discipline == nil || second.discipline == nil || first.discipline == second.discipline)
            && first.start <= second.end && second.start <= first.end
    }

    private static func reviewed(
        _ periods: [DetectedDeload], profile: AthleteProfile, today: CalendarDay, calendar: Calendar
    ) -> [DetectedDeload] {
        let reviewed: [DetectedDeload] = periods.compactMap { period in
            let insideDeload = profile.deloads.contains {
                $0.contains(period.start, calendar: calendar) && $0.contains(period.end, calendar: calendar)
            }
            guard !insideDeload || period.reason == .noTraining && period.discipline != nil else { return nil }
            let answer = profile.deloadDecisions.last {
                guard $0.discipline == nil || $0.discipline == period.discipline else { return false }
                if $0.start == period.start && $0.end <= period.end { return true }
                return $0.discipline == nil && $0.reason == .noTraining && period.reason == .noTraining
                    && period.start <= $0.start && $0.end <= period.end
            }
            guard answer?.accepted != false else { return nil }
            return DetectedDeload(
                start: period.start, end: period.end, reason: period.reason,
                needsConfirmation: period.needsConfirmation && answer == nil, discipline: period.discipline
            )
        }
        let saved = confirmed(profile, before: today).filter { decision in
            !reviewed.contains {
                !$0.needsConfirmation && $0.discipline == decision.discipline
                    && $0.start == decision.start && $0.end >= decision.end
            }
        }
        let accepted = saved + reviewed.filter { period in
            !period.needsConfirmation && !saved.contains {
                $0.discipline == nil && $0.start == period.start && $0.end == period.end && $0.reason == period.reason
            }
        }
        var result = accepted
        for period in reviewed where period.needsConfirmation {
            if !result.contains(where: { overlaps($0, period) }) {
                result.append(period)
            }
        }
        return result.sorted {
            ($0.end, $0.start, $0.discipline?.rawValue ?? "") < ($1.end, $1.start, $1.discipline?.rawValue ?? "")
        }
    }

    private static func confirmed(_ profile: AthleteProfile, before today: CalendarDay) -> [DetectedDeload] {
        profile.deloadDecisions.filter { $0.accepted && $0.start <= $0.end && $0.end < today }.map {
            DetectedDeload(
                start: $0.start, end: $0.end, reason: $0.reason, needsConfirmation: false, discipline: $0.discipline
            )
        }
    }

    private static func lowWeek(
        history: [CalendarDay: Day], start: CalendarDay, end: CalendarDay, policy: ReducedWeekPolicy,
        calendar: Calendar
    ) -> DetectedDeload? {
        func entries(weeksAgo: Int) -> [Day] {
            (0..<week).compactMap { history[start.adding(days: $0 - weeksAgo * week, calendar: calendar)] }
        }
        let active = entries(weeksAgo: 0)
        let strength = active.flatMap(\.strength)
        let runs = active.flatMap(\.runs)
        guard !active.isEmpty, !strength.contains(where: \.hard) else { return nil }
        let prior = (1...4).map(entries)
        let usualSets = baseline(prior.map { Double($0.flatMap(\.strength).reduce(0) { $0 + $1.sets }) })
        let usualRunSeconds = baseline(prior.map { $0.flatMap(\.runs).reduce(0) { $0 + $1.durationSeconds } })
        let relativeSets = usualSets.map { Double(strength.reduce(0) { $0 + $1.sets }) / $0 }
        let fractions = strength.compactMap(\.planFraction)
        let relativePlan = !fractions.isEmpty && fractions.count == strength.count
            ? fractions.reduce(0, +) / Double(fractions.count) : nil
        let strengthRatio = [relativeSets, relativePlan].compactMap { $0 }.min()
        guard strength.isEmpty || (strengthRatio ?? 1) <= possible else { return nil }

        let runSeconds = runs.reduce(0) { $0 + $1.durationSeconds }
        let runRatio = usualRunSeconds.map { runSeconds / $0 }
        let easy = runs.map { easyRun($0, maxHeartRate: policy.maxHeartRate) }
        let usuallyRunsHard = prior.filter { days in
            days.flatMap(\.runs).contains { easyRun($0, maxHeartRate: policy.maxHeartRate) == false }
        }.count >= 2
        let droppedIntensity = usuallyRunsHard && easy.allSatisfy { $0 == true } && (runRatio ?? 2) <= 1
        let droppedRunVolume = runRatio.map { $0 <= possible } ?? (runSeconds <= 45 * 60)
        guard !easy.contains(false), runs.isEmpty || droppedRunVolume || droppedIntensity,
              !strength.isEmpty || usualSets != nil || usualRunSeconds != nil else { return nil }

        let strengthIsClearlyLow = strength.isEmpty || (
            (strengthRatio ?? 1) <= low && (
                (relativePlan ?? 1) <= low || strength.allSatisfy(\.hasEffort)
            )
        )
        let runsAreClearlyLow = runs.isEmpty || (easy.allSatisfy { $0 == true } && (runRatio ?? 0) <= low)
        return DetectedDeload(
            start: start, end: end, reason: strength.isEmpty ? .easyRuns : .reducedStrength,
            needsConfirmation: policy.requireConfirmation || !strengthIsClearlyLow || !runsAreClearlyLow,
            discipline: policy.separateDisciplines ? (strength.isEmpty ? .running : .strength) : nil
        )
    }

    private static func baseline(_ values: [Double]) -> Double? {
        let active = values.filter { $0 > 0 }.sorted()
        guard active.count >= 2 else { return nil }
        let middle = active.count / 2
        return (active[(active.count - 1) / 2] + active[middle]) / 2
    }

    private static func easyRun(_ run: RunActivity, maxHeartRate: Double?) -> Bool? {
        if let anaerobic = run.anaerobicTrainingEffect, anaerobic >= 1 { return false }
        if let average = run.averageHeartRate, let maximum = maxHeartRate, maximum > 0 {
            if average > 0.75 * maximum { return false }
            if let peak = run.maxHeartRate, peak >= 0.90 * maximum { return false }
            if let effect = run.aerobicTrainingEffect, effect > 2.5 { return false }
            return average > 0 ? true : nil
        }
        return run.aerobicTrainingEffect.map { $0 <= 2.5 }
    }

    private static func days(
        sessions: [StrengthSession], runs: [RunActivity], routines: [Routine],
        exercises: [UUID: Exercise], settings: [UUID: ProgressionSettings], recordings: [RecordedStrengthActivity],
        today: CalendarDay, calendar: Calendar
    ) -> [CalendarDay: Day] {
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var history: [UUID: [ExerciseExposure]] = [:]
        var days: [CalendarDay: Day] = [:]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let day = CalendarDay(session.startedAt, calendar: calendar)
            guard day < today else { continue }
            let working = session.entries.flatMap(\.sets).filter(\.isWorking)
            guard !working.isEmpty || (session.durationSeconds ?? 0) > 0 else { continue }
            let effort = session.sessionRPE.map { [$0] } ?? working.compactMap(\.rpe)
            let ratio = session.routineID.flatMap { byID[$0] }.flatMap {
                planFraction(session: session, routine: $0, history: history, exercises: exercises, settings: settings)
            }
            days[day, default: Day()].strength.append(Strength(
                sets: max(1, working.count),
                hasEffort: session.sessionRPE != nil || (!working.isEmpty && working.allSatisfy { $0.rpe != nil }),
                hard: effort.contains { $0 > 7 } || working.contains { $0.kind == .failure || ($0.rpe ?? 0) > 7 },
                planFraction: ratio
            ))
            for entry in session.entries where entry.countsForProgression {
                let exposure = ExerciseExposure(date: session.startedAt, sets: entry.sets)
                if !exposure.sets.isEmpty {
                    history[entry.exerciseID, default: []].append(exposure)
                }
            }
        }
        let validRecordings = recordings.filter { $0.durationSeconds.isFinite && $0.durationSeconds > 0 }
        let unmatched = StrengthActivityMatching.match(sessions: sessions, activities: validRecordings).unmatched
        for recording in unmatched {
            let day = CalendarDay(recording.startedAt, calendar: calendar)
            guard day < today else { continue }
            // A watch-only session proves training took place. Its lifting effort and volume are unknown.
            days[day, default: Day()].strength.append(Strength(sets: 0, hasEffort: false, hard: true, planFraction: nil))
        }
        let validRuns = runs.filter { $0.durationSeconds.isFinite && $0.durationSeconds > 0 }
        for run in RunDeduplication.removingDuplicates(validRuns) {
            let day = CalendarDay(run.startedAt, calendar: calendar)
            if day < today { days[day, default: Day()].runs.append(run) }
        }
        return days
    }

    /// Rebuilds the routine targets from earlier exposures and the current prescriptions.
    private static func planFraction(
        session: StrengthSession, routine: Routine, history: [UUID: [ExerciseExposure]],
        exercises: [UUID: Exercise], settings: [UUID: ProgressionSettings]
    ) -> Double? {
        let entries = Dictionary(grouping: session.entries, by: \.exerciseID)
        guard Set(entries.keys).isSubset(of: Set(routine.exerciseIDs)), !routine.exerciseIDs.isEmpty else { return nil }
        var fraction = 0.0
        for id in routine.exerciseIDs {
            let config = ProgressionTargets.settings(
                for: exercises[id], stored: settings[id], focus: session.focus ?? routine.focus,
                prescription: routine.prescription(for: id)
            )
            let expected = ProgressionTargets.next(history: history[id] ?? [], settings: config).sets
            let actual = (entries[id] ?? []).flatMap(\.sets).filter(\.isWorking)
            let weight = expected.first?.weightKg ?? 0
            let reps = expected.reduce(0.0) { $0 + Double(max(1, $1.reps)) }
            guard actual.allSatisfy({ ($0.reps ?? 0) > 0 && (weight <= 0 || $0.weightKg != nil) }) else { return nil }
            let performed = actual.reduce(0.0) { total, set in
                let weightRatio = weight > 0 ? abs(set.weightKg ?? 0) / weight : 1
                return total + Double(set.reps ?? 0) * weightRatio
            }
            fraction += performed / reps
        }
        return fraction / Double(routine.exerciseIDs.count)
    }
}

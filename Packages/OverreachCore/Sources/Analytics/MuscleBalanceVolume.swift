import Domain
import Foundation

extension MuscleBalance {
    /// Working sets of one session or routine. Warm-ups and running never enter this value.
    public struct SessionVolume: Hashable, Sendable {
        private static let catalog = Dictionary(uniqueKeysWithValues: ExerciseCatalog.builtIn.map { ($0.id, $0) })

        public var directSets: [MuscleGroup: Double] = [:]
        public var fractionalSets: [MuscleGroup: Double] = [:]
        public var patternSets: [MovementPattern: Double] = [:]
        public var pushSets: Double = 0
        public var ambiguousMuscles: Set<MuscleGroup> = []
        public var hasUnclassifiedPulling: Bool = false
        public var hasUnmappedSets: Bool = false

        public init() {}

        mutating func record(_ sets: Int, of exercise: Exercise?) {
            guard sets > 0 else { return }
            guard let exercise, !exercise.needsMuscleMapping else {
                hasUnmappedSets = true
                return
            }
            let count = Double(sets)
            let primary = exercise.primaryMuscles
            let secondary = exercise.secondaryMuscles.subtracting(primary)
            let builtIn = Self.catalog[exercise.id]
            let usesReviewedMapping = builtIn?.primaryMuscles == primary
                && builtIn?.secondaryMuscles == exercise.secondaryMuscles
                && builtIn?.movementPattern == exercise.movementPattern
            // A broad back tag on reviewed stability work or hinges represents spinal erectors.
            let backMeansLumbar = exercise.movementPattern == .hinge || usesReviewedMapping
            for muscle in primary where muscle != .back || !backMeansLumbar {
                directSets[muscle, default: 0] += count
                fractionalSets[muscle, default: 0] += count
            }
            for muscle in secondary where muscle != .back || !backMeansLumbar {
                fractionalSets[muscle, default: 0] += count * 0.5
            }
            if let pattern = exercise.movementPattern {
                patternSets[pattern, default: 0] += count
            }
            let muscles = primary.union(secondary)
            if muscles.contains(.back) && !backMeansLumbar {
                ambiguousMuscles.formUnion([.lats, .upperBack])
            }
            if muscles.contains(.shoulders) {
                ambiguousMuscles.formUnion([.frontDelts, .sideDelts, .rearDelts])
            }
            if exercise.movementPattern == nil && !usesReviewedMapping
                && !primary.isDisjoint(with: [.back, .lats, .upperBack]) {
                hasUnclassifiedPulling = true
            }
            if exercise.movementPattern == .verticalPush || exercise.movementPattern == .horizontalPush
                || (exercise.movementPattern == nil && !primary.isDisjoint(with: [.chest, .triceps])) {
                pushSets += count
            }
        }

        mutating func add(_ volume: SessionVolume, weight: Double) {
            for (muscle, count) in volume.directSets {
                directSets[muscle, default: 0] += count * weight
            }
            for (muscle, count) in volume.fractionalSets {
                fractionalSets[muscle, default: 0] += count * weight
            }
            for (pattern, count) in volume.patternSets {
                patternSets[pattern, default: 0] += count * weight
            }
            pushSets += volume.pushSets * weight
            ambiguousMuscles.formUnion(volume.ambiguousMuscles)
            hasUnclassifiedPulling = hasUnclassifiedPulling || volume.hasUnclassifiedPulling
            hasUnmappedSets = hasUnmappedSets || volume.hasUnmappedSets
        }
    }

    /// Weekly averages paired with individual sessions and the coverage of the absence checks.
    public struct Input: Hashable, Sendable {
        public var weekly: SessionVolume
        public var sessions: [SessionVolume]
        public var pullingWindow: SessionVolume?
        public var hamstringWindow: SessionVolume?
        public var runningKilometres: Double?

        public init(
            weekly: SessionVolume, sessions: [SessionVolume], pullingWindow: SessionVolume? = nil,
            hamstringWindow: SessionVolume? = nil, runningKilometres: Double? = nil
        ) {
            self.weekly = weekly
            self.sessions = sessions
            self.pullingWindow = pullingWindow
            self.hamstringWindow = hamstringWindow
            self.runningKilometres = runningKilometres
        }
    }

    /// Projects the planned rotation, including a partial final turn for blocks with an end date.
    public static func projection(
        block: TrainingBlock, routines: [Routine], exercises: [UUID: Exercise],
        exerciseSettings: [UUID: ProgressionSettings], settings: Settings = Settings()
    ) -> Input? {
        let byID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rotation = block.routineIDs.compactMap { byID[$0] }
        guard !rotation.isEmpty, rotation.count == block.routineIDs.count,
              block.plannedWeeks.map({ $0 > 0 }) != false else { return nil }
        let sessions = rotation.map { routine in
            var volume = SessionVolume()
            for exerciseID in routine.exerciseIDs {
                let exercise = exercises[exerciseID]
                let stored = exerciseSettings[exerciseID]
                let config = ProgressionTargets.settings(
                    for: exercise, stored: stored, focus: stored?.focus ?? routine.focus,
                    prescription: routine.prescription(for: exerciseID)
                )
                volume.record(config.scheme.sets, of: exercise)
            }
            return volume
        }
        let sessionsPerWeek = block.plannedSessionsPerWeek
        let pullingWeeks = max(1, settings.pullingWindowWeeks)
        let hamstringWeeks = max(1, settings.hamstringWindowWeeks)
        let plannedWeeks = block.plannedWeeks
        let weekly = rotationAverage(sessions, perWeek: sessionsPerWeek, weeks: plannedWeeks)
        let projectedCount = plannedWeeks.map { sessionCount(perWeek: sessionsPerWeek, weeks: $0) } ?? sessions.count
        return Input(
            weekly: weekly, sessions: Array(sessions.prefix(projectedCount)),
            pullingWindow: (plannedWeeks ?? Int.max) >= pullingWeeks
                ? rotationAverage(sessions, perWeek: sessionsPerWeek, weeks: pullingWeeks) : nil,
            hamstringWindow: (plannedWeeks ?? Int.max) >= hamstringWeeks
                ? rotationAverage(sessions, perWeek: sessionsPerWeek, weeks: hamstringWeeks) : nil
        )
    }

    private static func rotationAverage(_ sessions: [SessionVolume], perWeek: Int, weeks: Int?) -> SessionVolume {
        guard let weeks else { return combined(sessions, weight: Double(perWeek) / Double(sessions.count)) }
        let count = sessionCount(perWeek: perWeek, weeks: weeks)
        let (turns, remainder) = count.quotientAndRemainder(dividingBy: sessions.count)
        var result = SessionVolume()
        for (index, session) in sessions.enumerated() {
            let occurrences = turns + (index < remainder ? 1 : 0)
            if occurrences > 0 {
                result.add(session, weight: Double(occurrences) / Double(weeks))
            }
        }
        return result
    }

    private static func sessionCount(perWeek: Int, weeks: Int) -> Int {
        let (count, overflowed) = perWeek.multipliedReportingOverflow(by: weeks)
        return overflowed ? .max : count
    }

    public static func history(
        sessions: [StrengthSession], exercises: [UUID: Exercise], now: Date, runningKilometres: Double? = nil,
        settings: Settings = Settings(), calendar: Calendar = .current
    ) -> Input? {
        let today = CalendarDay(now, calendar: calendar)
        let dated = sessions.filter { session in
            session.isCompleted(through: now) && session.entries.contains { $0.sets.contains(where: \.isWorking) }
        }
        guard let first = dated.map(\.startedAt).min() else { return nil }
        let firstDay = CalendarDay(first, calendar: calendar)
        let weeklyStart = windowStart(settings.windowWeeks, before: today, calendar: calendar)
        let pullingStart = windowStart(settings.pullingWindowWeeks, before: today, calendar: calendar)
        let hamstringStart = windowStart(settings.hamstringWindowWeeks, before: today, calendar: calendar)
        let earliest = min(weeklyStart, pullingStart, hamstringStart)
        let volumes = dated.compactMap { session -> (CalendarDay, SessionVolume)? in
            let day = CalendarDay(session.startedAt, calendar: calendar)
            guard day >= earliest else { return nil }
            var volume = SessionVolume()
            for entry in session.entries {
                volume.record(entry.sets.filter(\.isWorking).count, of: exercises[entry.exerciseID])
            }
            return (day, volume)
        }
        let recent = volumes.filter { $0.0 >= weeklyStart }.map(\.1)
        guard !recent.isEmpty else { return nil }
        let days = PlanReviewer.days(from: max(weeklyStart, firstDay), to: today, calendar: calendar) + 1
        let weekCount = max(1, Double(days) / 7)
        return Input(
            weekly: combined(recent, weight: 1 / weekCount), sessions: recent,
            pullingWindow: firstDay <= pullingStart ? combined(volumes.filter { $0.0 >= pullingStart }.map(\.1)) : nil,
            hamstringWindow: firstDay <= hamstringStart
                ? combined(volumes.filter { $0.0 >= hamstringStart }.map(\.1),
                           weight: 1 / Double(max(1, settings.hamstringWindowWeeks))) : nil,
            runningKilometres: runningKilometres
        )
    }

    public static func historyWindowStart(
        now: Date, settings: Settings = Settings(), calendar: Calendar = .current
    ) -> CalendarDay {
        windowStart(settings.windowWeeks, before: CalendarDay(now, calendar: calendar), calendar: calendar)
    }

    private static func windowStart(_ weeks: Int, before day: CalendarDay, calendar: Calendar) -> CalendarDay {
        day.adding(days: 1 - max(1, weeks) * 7, calendar: calendar)
    }

    private static func combined(_ sessions: [SessionVolume], weight: Double = 1) -> SessionVolume {
        sessions.reduce(into: SessionVolume()) { $0.add($1, weight: weight) }
    }
}

import Domain
import Foundation

/// How an exercise went against the target it had when the session started.
public enum TargetOutcome: Hashable, Sendable {
    /// Every planned set done, with more reps, more load or more sets somewhere.
    case exceeded
    case met
    /// Some planned reps or sets were missing.
    case below(repsShort: Int)
    /// Left unfinished and kept out of progression.
    case unfinished
    /// No target to compare with (first time, or no load).
    case noTarget
}

/// A personal best set in this session.
public enum SessionRecord: Hashable, Sendable {
    case estimatedOneRepMax(kg: Double, previousKg: Double)
    case repsAtWeight(weightKg: Double, reps: Int, previousReps: Int)
}

/// One exercise of a finished session, compared with its target and its history.
public struct ExerciseReview: Hashable, Sendable {
    public let exercise: Exercise
    public let outcome: TargetOutcome
    /// Working sets done, and the target the session started with.
    public let done: ExerciseExposure
    public let target: ExerciseTarget?
    /// Mean RPE of the working sets that have one.
    public let averageRPE: Double?
    public let record: SessionRecord?
    /// Target for the next session, now that this one counts.
    public let nextTarget: ExerciseTarget
    public let statusBefore: ExerciseStatus
    public let statusAfter: ExerciseStatus
}

/// A finished session in numbers: totals, plan adherence, records, what comes next.
public struct SessionReview: Hashable, Sendable {
    public let session: StrengthSession
    public let workingSets: Int
    public let tonnageKg: Double
    public let effectiveSets: [MuscleGroup: Double]
    public let exercises: [ExerciseReview]
    /// The last earlier session with the same name, to compare volume.
    public let previous: StrengthSession?
    public let previousTonnageKg: Double?

    /// Exercises that had a target.
    public var exercisesWithTarget: Int {
        exercises.filter { ![.noTarget, .unfinished].contains($0.outcome) }.count
    }

    /// Exercises that met or beat their target.
    public var exercisesOnTarget: Int {
        exercises.filter { $0.outcome == .met || $0.outcome == .exceeded }.count
    }
}

/// Reviews a finished session. Pure: everything comes from the session, its targets and the earlier history.
public enum SessionReviewer {
    /// - Parameters:
    ///   - targets: the target each exercise had when the session started, by exercise id.
    ///   - history: sessions before this one.
    public static func review(
        _ session: StrengthSession,
        targets: [UUID: ExerciseTarget],
        history: [StrengthSession],
        exercises: [Exercise],
        settings: [UUID: ProgressionSettings],
        routine: Routine? = nil
    ) -> SessionReview {
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let earlier = history.filter { $0.id != session.id && $0.startedAt < session.startedAt }
        let previous = earlier
            .filter { $0.name.localizedCaseInsensitiveCompare(session.name) == .orderedSame }
            .max { $0.startedAt < $1.startedAt }
        let allSets = session.entries.flatMap(\.sets)
        return SessionReview(
            session: session,
            workingSets: allSets.filter(\.isWorking).count,
            tonnageKg: StrengthMetrics.tonnage(of: allSets),
            effectiveSets: StrengthMetrics.effectiveSets(in: session, exercises: byID),
            exercises: session.entries.compactMap { entry in
                byID[entry.exerciseID].map { exercise in
                    let config = configuration(
                        for: exercise, in: session, stored: settings[exercise.id], routine: routine
                    )
                    return review(entry, of: exercise, in: session, target: targets[exercise.id], earlier: earlier,
                                  settings: config.settings, startFromBaseline: config.startFromBaseline)
                }
            },
            previous: previous,
            previousTonnageKg: previous.map { StrengthMetrics.tonnage(of: $0.entries.flatMap(\.sets)) }
        )
    }

    /// Reviews a past session against the targets the engine gave it from the history before it (e.g. from
    /// History). Settings are today's: a scheme changed since then is not reflected.
    public static func review(
        _ session: StrengthSession, history: [StrengthSession], exercises: [Exercise],
        settings: [UUID: ProgressionSettings], routine: Routine? = nil
    ) -> SessionReview {
        let earlier = history.filter { $0.id != session.id && $0.startedAt < session.startedAt }
        var targets: [UUID: ExerciseTarget] = [:]
        for exercise in exercises where session.entries.contains(where: { $0.exerciseID == exercise.id }) {
            let before = ExerciseExposure.history(of: exercise.id, in: earlier)
            guard !before.isEmpty else { continue }
            let config = configuration(for: exercise, in: session, stored: settings[exercise.id], routine: routine)
            targets[exercise.id] = ProgressionTargets.next(
                history: before, settings: config.settings, startFromBaseline: config.startFromBaseline
            )
        }
        return review(
            session, targets: targets, history: history, exercises: exercises, settings: settings, routine: routine
        )
    }

    private static func configuration(
        for exercise: Exercise, in session: StrengthSession, stored: ProgressionSettings?, routine: Routine?
    ) -> (settings: ProgressionSettings, startFromBaseline: Bool) {
        let prescribed = routine?.prescription(for: exercise.id)
        let settings = ProgressionTargets.settings(
            for: exercise, stored: stored, focus: session.focus, prescription: prescribed
        )
        return (settings, stored == nil && prescribed == nil)
    }

    private static func review(
        _ entry: ExerciseEntry, of exercise: Exercise, in session: StrengthSession, target: ExerciseTarget?,
        earlier: [StrengthSession], settings: ProgressionSettings, startFromBaseline: Bool
    ) -> ExerciseReview {
        let working = entry.sets.filter(\.isWorking)
        let done = ExerciseExposure(date: session.startedAt, sets: working)
        let before = ExerciseExposure.history(of: exercise.id, in: earlier)
        let after = ExerciseExposure.history(of: exercise.id, in: earlier + [session])
        let rpes = working.compactMap(\.rpe)
        return ExerciseReview(
            exercise: exercise,
            outcome: outcome(of: entry, done: done, target: target),
            done: done,
            target: target,
            averageRPE: rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count),
            record: record(in: done, before: before),
            nextTarget: ProgressionTargets.next(
                history: after, settings: settings, startFromBaseline: startFromBaseline
            ),
            statusBefore: StallDetection.status(history: before, settings: settings),
            statusAfter: StallDetection.status(history: after, settings: settings)
        )
    }

    static func outcome(of entry: ExerciseEntry, done: ExerciseExposure, target: ExerciseTarget?) -> TargetOutcome {
        guard entry.countsForProgression else { return .unfinished }
        guard let target, let met = ProgressionTargets.didMeet(target, in: done) else { return .noTarget }
        guard met else { return .below(repsShort: StallDetection.shortfall(of: target, in: done)) }
        let beat = done.sets.count > target.sets.count || zip(target.sets, done.sets).contains { planned, set in
            (set.reps ?? 0) > planned.reps || (set.weightKg ?? 0) > (planned.weightKg ?? 0) + 0.001
        }
        return beat ? .exceeded : .met
    }

    /// A new best estimated 1RM, or else more reps than ever at one of today's loads.
    static func record(in done: ExerciseExposure, before: [ExerciseExposure]) -> SessionRecord? {
        guard !before.isEmpty else { return nil }
        if let best = done.bestEstimatedOneRepMax,
           let previous = before.compactMap(\.bestEstimatedOneRepMax).max(), best > previous + 0.05 {
            return .estimatedOneRepMax(kg: best, previousKg: previous)
        }
        let earlierSets = before.flatMap(\.sets)
        var found: SessionRecord?
        for set in done.sets {
            guard let weight = set.weightKg, weight > 0, let reps = set.reps else { continue }
            let atWeight = earlierSets.filter { abs(($0.weightKg ?? 0) - weight) < 0.001 }.compactMap(\.reps)
            guard let previous = atWeight.max(), reps > previous else { continue }
            if case let .repsAtWeight(bestWeight, _, _) = found, bestWeight >= weight { continue }
            found = .repsAtWeight(weightKg: weight, reps: reps, previousReps: previous)
        }
        return found
    }
}

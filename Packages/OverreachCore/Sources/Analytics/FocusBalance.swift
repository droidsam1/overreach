import Domain
import Foundation

/// Something worth telling the user about how their training's focus lines up with their goal.
public enum BalanceFinding: Hashable, Sendable {
    /// Several sessions in a row with the same focus while the goal or block calls for something else.
    case focusStreak(focus: TrainingFocus, sessions: Int)
    /// An exercise declared with one focus is being trained with another (e.g. "strength" done at 10–12 reps).
    case exerciseFocusMismatch(exerciseID: UUID, declared: TrainingFocus, observed: TrainingFocus)
    /// A session declared with one focus was trained with another.
    case sessionFocusMismatch(sessionID: UUID, declared: TrainingFocus, observed: TrainingFocus)
    /// A strength goal, but a priority lift had no heavy (strength-focus) exposure in the window.
    case noHeavyWorkOnPriorityLift(exerciseID: UUID, days: Int)
    /// A muscle trained with a single focus only, while the goal needs both strength and size.
    case muscleSingleFocus(muscle: MuscleGroup, focus: TrainingFocus)
    /// Weekly fractional sets for a muscle below the useful range.
    case lowVolume(muscle: MuscleGroup, weeklySets: Double)

    public var evidence: EvidenceReference {
        switch self {
        case .noHeavyWorkOnPriorityLift, .exerciseFocusMismatch, .sessionFocusMismatch, .muscleSingleFocus:
            FocusEvidence.loadingByGoal
        case .focusStreak: FocusEvidence.periodization
        case .lowVolume: ProgressionEvidence.volumeDoseResponse
        }
    }
}

/// Checks the focus of recent training against the goal and the declared block/session/exercise focus.
public enum FocusBalance {
    public struct Settings: Hashable, Sendable {
        public var windowDays = 56
        public var heavyWorkWindowDays = 21
        public var streakLength = 4
        public var minimumWeeklySets = 4.0
        public var singleFocusShare = 0.95
        public var minimumWeeklySetsForSingleFocus = 4.0

        public init() {}
    }

    public static func findings(
        sessions: [StrengthSession],
        exercises: [UUID: Exercise],
        exerciseSettings: [UUID: ProgressionSettings] = [:],
        profile: AthleteProfile,
        now: Date,
        settings: Settings = Settings()
    ) -> [BalanceFinding] {
        let goal = profile.goal?.kind ?? .general
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        let windowStart = now.addingTimeInterval(-Double(settings.windowDays) * 86_400)
        let recent = sorted.filter { $0.startedAt >= windowStart && $0.startedAt <= now }
        guard !recent.isEmpty else { return [] }

        let observed = recent.map { session in (session, FocusClassifier.focus(of: session, history: sorted)) }
        let blockFocus = activeDeclaredBlock(in: profile, now: now)?.focus
        var result: [BalanceFinding] = []

        // Declared session focus vs what was lifted.
        for (session, focus) in observed {
            if let declared = session.focus, let focus, !compatible(declared: declared, observed: focus) {
                result.append(.sessionFocusMismatch(sessionID: session.id, declared: declared, observed: focus))
            }
        }

        // Declared exercise focus vs its last three exposures.
        for (exerciseID, config) in exerciseSettings.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let declared = config.focus else { continue }
            let history = ExerciseExposure.history(of: exerciseID, in: sorted.filter { $0.startedAt <= now })
            let lastThree = history.suffix(3)
            guard lastThree.count == 3 else { continue }
            let foci = lastThree.indices.compactMap { index in
                FocusClassifier.focus(of: history[index], previous: Array(history[..<index]))
            }
            if let dominant = FocusClassifier.dominant(foci), !compatible(declared: declared, observed: dominant) {
                result.append(.exerciseFocusMismatch(exerciseID: exerciseID, declared: declared, observed: dominant))
            }
        }

        // Streaks of one focus that don't fit the goal (a declared block makes a matching streak intentional).
        let trailing = observed.compactMap(\.1)
        if let last = trailing.last {
            let streak = trailing.reversed().prefix { $0 == last }.count
            if streak >= settings.streakLength, last != blockFocus, streakConflicts(last, goal: goal, length: streak) {
                result.append(.focusStreak(focus: last, sessions: streak))
            }
        }

        // Strength goal: priority lifts need heavy exposures.
        if goal == .strength, let priority = profile.goal?.priorityLifts {
            let heavyStart = now.addingTimeInterval(-Double(settings.heavyWorkWindowDays) * 86_400)
            for liftID in priority {
                let history = ExerciseExposure.history(of: liftID, in: sorted.filter { $0.startedAt <= now })
                guard let firstRecent = history.firstIndex(where: { $0.date >= heavyStart }) else { continue }
                let heavy = (firstRecent..<history.count).contains { index in
                    FocusClassifier.focus(of: history[index], previous: Array(history[..<index])) == .strength
                }
                if !heavy {
                    result.append(.noHeavyWorkOnPriorityLift(exerciseID: liftID, days: settings.heavyWorkWindowDays))
                }
            }
        }

        // Per-muscle volume and focus mix.
        let weeks = Double(settings.windowDays) / 7
        let perMuscle = muscleFocusSets(observedSessions: recent, history: sorted, exercises: exercises)
        let tracked: [MuscleGroup] = MuscleGroup.allCases.filter { $0 != .core && $0 != .forearms }
        for muscle in tracked {
            let byFocus = perMuscle[muscle] ?? [:]
            let total = byFocus.values.reduce(0, +)
            let weekly = total / weeks
            if (goal == .hypertrophy || goal == .general), weekly < settings.minimumWeeklySets {
                result.append(.lowVolume(muscle: muscle, weeklySets: weekly))
            }
            guard goal != .hypertrophy, weekly >= settings.minimumWeeklySetsForSingleFocus,
                  let top = byFocus.max(by: { $0.value < $1.value }), top.value / total >= settings.singleFocusShare,
                  top.key != .mixed, blockFocus == nil else { continue }
            result.append(.muscleSingleFocus(muscle: muscle, focus: top.key))
        }
        return result
    }

    /// The declared block covering `now`, if any.
    public static func activeDeclaredBlock(
        in profile: AthleteProfile, now: Date, calendar: Calendar = .current
    ) -> TrainingBlock? {
        let today = CalendarDay(now, calendar: calendar)
        return profile.declaredBlocks.last { block in
            guard block.start <= today else { return false }
            guard let weeks = block.plannedWeeks else { return true }
            return today < block.start.adding(days: weeks * 7, calendar: calendar)
        }
    }

    /// Mixed work satisfies either declared focus; otherwise they must match.
    static func compatible(declared: TrainingFocus, observed: TrainingFocus) -> Bool {
        declared == observed || declared == .mixed || observed == .mixed
    }

    private static func streakConflicts(_ focus: TrainingFocus, goal: TrainingGoal.Kind, length: Int) -> Bool {
        switch goal {
        case .strength: focus == .hypertrophy || focus == .endurance
        case .hypertrophy: focus == .endurance
        case .general, .hybrid: focus != .mixed && length >= 6
        }
    }

    /// Fractional working sets per muscle and focus (primary 1, secondary 0.5).
    private static func muscleFocusSets(
        observedSessions: [StrengthSession], history: [StrengthSession], exercises: [UUID: Exercise]
    ) -> [MuscleGroup: [TrainingFocus: Double]] {
        var result: [MuscleGroup: [TrainingFocus: Double]] = [:]
        for session in observedSessions {
            for entry in session.entries {
                guard let exercise = exercises[entry.exerciseID] else { continue }
                let previous = ExerciseExposure.history(
                    of: entry.exerciseID, in: history.filter { $0.startedAt < session.startedAt }
                )
                let current = ExerciseExposure(date: session.startedAt, sets: entry.sets)
                let reference = (previous.suffix(6) + [current]).compactMap(\.bestEstimatedOneRepMax).max()
                for set in current.sets {
                    guard let focus = FocusClassifier.focus(of: set, oneRepMaxKg: reference) else { continue }
                    for muscle in exercise.primaryMuscles {
                        result[muscle, default: [:]][focus, default: 0] += 1
                    }
                    for muscle in exercise.secondaryMuscles where !exercise.primaryMuscles.contains(muscle) {
                        result[muscle, default: [:]][focus, default: 0] += 0.5
                    }
                }
            }
        }
        return result
    }
}

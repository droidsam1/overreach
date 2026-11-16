import Analytics
import Domain
import Foundation
import Observation

/// A set being logged. Prefilled from the progression target; `isDone` marks it as performed.
public struct DraftSet: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var weightKg: Double?
    public var reps: Int?
    public var rpe: Double?
    public var isDone: Bool

    public init(id: UUID = UUID(), weightKg: Double?, reps: Int?, rpe: Double? = nil, isDone: Bool = false) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isDone = isDone
    }
}

/// An exercise in the session being logged, with the engine's target and status for context.
public struct DraftExercise: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    public var target: ExerciseTarget
    public var status: ExerciseStatus
    public var sets: [DraftSet]
    /// Focus used for this exercise (declared, from the session, or inferred from its recent sets).
    public var focus: TrainingFocus?
    public var isFocusInferred: Bool
    /// Suggested rest between working sets for the focus, in seconds.
    public var restSeconds: ClosedRange<Int>
}

/// The live session logger (phase 1). Targets come from the progression engine; only completed sets are saved.
@MainActor
@Observable
public final class WorkoutModel {
    public private(set) var catalog: [Exercise] = []
    /// Start time of the session in progress; `nil` when no session is open.
    public private(set) var startedAt: Date?
    public var sessionName = "Workout"
    /// Declared focus of the session; `nil` = automatic (per exercise). Call `refreshTargets()` after changing it.
    public var sessionFocus: TrainingFocus?
    /// Exercises of the session in progress. Views bind to it directly (`$model.exercises`).
    public var exercises: [DraftExercise] = []
    public private(set) var errorMessage: String?

    public var isSessionActive: Bool { startedAt != nil }

    private let workouts: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date

    /// How far back history is read to compute targets and stalls.
    static let historyWindow: TimeInterval = 365 * 86_400

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        backup: (any BackupService)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.exerciseRepository = exercises
        self.progression = progression
        self.backup = backup
        self.clock = clock
    }

    public func load() async {
        do {
            catalog = try await exerciseRepository.allExercises()
        } catch {
            errorMessage = "Could not load exercises."
        }
    }

    public func start(name: String = "Workout") {
        guard startedAt == nil else { return }
        sessionName = name
        sessionFocus = nil
        exercises = []
        errorMessage = nil
        startedAt = clock()
    }

    /// Adds `exercise` with sets prefilled from its next progression target.
    public func add(_ exercise: Exercise) async {
        guard isSessionActive else { return }
        exercises.append(await prepare(exercise, id: UUID()))
    }

    /// Recomputes targets for exercises with no completed set (e.g. after changing the session focus).
    public func refreshTargets() async {
        let pending = exercises.filter { !$0.sets.contains(where: \.isDone) }
        for current in pending {
            let refreshed = await prepare(current.exercise, id: current.id)
            if let position = exercises.firstIndex(where: { $0.id == current.id }) {
                exercises[position] = refreshed
            }
        }
    }

    /// Target, status, focus and rest for `exercise`. A declared exercise focus wins over the session focus;
    /// without stored settings, the focus picks the default scheme (`FocusPrescription`).
    private func prepare(_ exercise: Exercise, id: UUID) async -> DraftExercise {
        let history = await history(of: exercise.id)
        let stored = try? await progression.progressionSettings(for: exercise.id)
        let declaredFocus = stored?.focus ?? sessionFocus
        var settings = stored ?? ProgressionSettings(for: exercise)
        if stored == nil, let declaredFocus {
            settings.scheme = FocusPrescription.for(declaredFocus).defaultScheme
        }
        let inferredFocus = FocusClassifier.dominant(history.indices.suffix(3).compactMap { index in
            FocusClassifier.focus(of: history[index], previous: Array(history[..<index]))
        })
        let focus = declaredFocus ?? inferredFocus
        let target = ProgressionTargets.next(history: history, settings: settings)
        let status = StallDetection.status(history: history, settings: settings)
        let sets = target.sets.map { planned in
            DraftSet(weightKg: planned.weightKg ?? history.last?.workingWeightKg, reps: planned.reps)
        }
        return DraftExercise(
            id: id, exercise: exercise, target: target, status: status, sets: sets, focus: focus,
            isFocusInferred: declaredFocus == nil && focus != nil,
            restSeconds: FocusPrescription.for(focus ?? .hypertrophy).restSeconds
        )
    }

    public func removeExercise(_ exerciseID: DraftExercise.ID) {
        exercises.removeAll { $0.id == exerciseID }
    }

    /// Adds a set copying the last set's values.
    public func addSet(to exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = exercises[index].sets.last
        exercises[index].sets.append(DraftSet(weightKg: last?.weightKg, reps: last?.reps, rpe: last?.rpe))
    }

    public func removeSet(_ setID: DraftSet.ID, from exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[index].sets.removeAll { $0.id == setID }
    }

    /// Saves the completed sets and closes the session. Returns `false` if saving failed (the draft is kept).
    @discardableResult
    public func finish() async -> Bool {
        guard let startedAt else { return false }
        let now = clock()
        let entries = exercises.compactMap { exercise -> ExerciseEntry? in
            let done = exercise.sets.filter(\.isDone).map { set in
                WorkoutSet(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, completedAt: now)
            }
            return done.isEmpty ? nil : ExerciseEntry(exerciseID: exercise.exercise.id, sets: done)
        }
        guard !entries.isEmpty else {
            close()
            return true
        }
        let finished = StrengthSession(
            name: sessionName, startedAt: startedAt, endedAt: now, entries: entries, focus: sessionFocus
        )
        do {
            try await workouts.save(finished)
            close()
            await backup?.backUpIfConfigured(now: now)
            return true
        } catch {
            errorMessage = "Could not save the session. It is still open."
            return false
        }
    }

    public func discard() {
        close()
    }

    private func close() {
        startedAt = nil
        exercises = []
        errorMessage = nil
    }

    private func history(of exerciseID: UUID) async -> [ExerciseExposure] {
        let now = clock()
        let sessions = (try? await workouts.sessions(from: now.addingTimeInterval(-Self.historyWindow), to: now)) ?? []
        return ExerciseExposure.history(of: exerciseID, in: sessions)
    }
}

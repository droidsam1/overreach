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
}

/// The live session logger (phase 1). Targets come from the progression engine; only completed sets are saved.
@MainActor
@Observable
public final class WorkoutModel {
    public private(set) var catalog: [Exercise] = []
    /// Start time of the session in progress; `nil` when no session is open.
    public private(set) var startedAt: Date?
    public var sessionName = "Workout"
    /// Exercises of the session in progress. Views bind to it directly (`$model.exercises`).
    public var exercises: [DraftExercise] = []
    public private(set) var errorMessage: String?

    public var isSessionActive: Bool { startedAt != nil }

    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let clock: @Sendable () -> Date

    /// How far back history is read to compute targets and stalls.
    static let historyWindow: TimeInterval = 365 * 86_400

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.progression = progression
        self.clock = clock
    }

    public func load() async {
        do {
            catalog = try await exercises.allExercises()
        } catch {
            errorMessage = "Could not load exercises."
        }
    }

    public func start(name: String = "Workout") {
        guard startedAt == nil else { return }
        sessionName = name
        exercises = []
        errorMessage = nil
        startedAt = clock()
    }

    /// Adds `exercise` with sets prefilled from its next progression target.
    public func add(_ exercise: Exercise) async {
        guard isSessionActive else { return }
        let history = await history(of: exercise.id)
        let stored = try? await progression.progressionSettings(for: exercise.id)
        let settings = stored ?? ProgressionSettings(for: exercise)
        let target = ProgressionTargets.next(history: history, settings: settings)
        let status = StallDetection.status(history: history, settings: settings)
        let sets = target.sets.map { planned in
            DraftSet(weightKg: planned.weightKg ?? history.last?.workingWeightKg, reps: planned.reps)
        }
        exercises.append(DraftExercise(id: UUID(), exercise: exercise, target: target, status: status, sets: sets))
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
        let finished = StrengthSession(name: sessionName, startedAt: startedAt, endedAt: now, entries: entries)
        do {
            try await workouts.save(finished)
            close()
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

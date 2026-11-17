import Domain
import Foundation
import Observation

/// Edits a past session: name, times, focus, notes, exercises and sets. Changes are kept in `draft` and only
/// written when `save()` succeeds; targets and analyses pick them up because they are computed from history.
@MainActor
@Observable
public final class SessionEditorModel: Identifiable {
    /// The session being edited. Views bind to it directly (`$model.draft.name`, `$model.draft.entries`).
    public var draft: StrengthSession
    public let catalog: [Exercise]
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let original: StrengthSession
    private let exerciseNames: [UUID: String]
    private let workouts: any WorkoutRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date

    public init(
        session: StrengthSession,
        catalog: [Exercise],
        workouts: any WorkoutRepository,
        backup: (any BackupService)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.draft = session
        self.original = session
        self.catalog = catalog
        self.exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.workouts = workouts
        self.backup = backup
        self.clock = clock
    }

    public var hasChanges: Bool { draft != original }
    public var issues: [SessionEditIssue] { draft.editIssues }
    public var canSave: Bool { hasChanges && issues.isEmpty && !isSaving }

    public func name(of exerciseID: UUID) -> String {
        exerciseNames[exerciseID] ?? "Unknown exercise"
    }

    // MARK: Times

    /// Moves the session to `date`, keeping its duration and set times.
    public func moveStart(to date: Date) {
        draft = draft.movingStart(to: date)
    }

    /// Sets the end time; `nil` removes it (unknown duration).
    public func setEnd(_ date: Date?) {
        draft.endedAt = date
    }

    // MARK: Exercises

    public func addExercise(_ exercise: Exercise) {
        draft.entries.append(ExerciseEntry(exerciseID: exercise.id, sets: [WorkoutSet()]))
    }

    /// Re-points an entry to another exercise (e.g. logged as the wrong variation), keeping its sets.
    public func replaceExercise(of entryID: ExerciseEntry.ID, with exercise: Exercise) {
        guard let index = draft.entries.firstIndex(where: { $0.id == entryID }) else { return }
        draft.entries[index].exerciseID = exercise.id
    }

    public func removeExercise(_ entryID: ExerciseEntry.ID) {
        draft.entries.removeAll { $0.id == entryID }
    }

    /// Moves an exercise `offset` positions (negative = up), clamped to the list.
    public func moveExercise(_ entryID: ExerciseEntry.ID, by offset: Int) {
        guard let index = draft.entries.firstIndex(where: { $0.id == entryID }) else { return }
        let destination = min(max(index + offset, 0), draft.entries.count - 1)
        guard destination != index else { return }
        draft.entries.insert(draft.entries.remove(at: index), at: destination)
    }

    // MARK: Sets

    /// Adds a set copying the last set's kind, weight, reps and RPE.
    public func addSet(to entryID: ExerciseEntry.ID) {
        guard let index = draft.entries.firstIndex(where: { $0.id == entryID }) else { return }
        let last = draft.entries[index].sets.last
        draft.entries[index].sets.append(WorkoutSet(
            kind: last?.kind ?? .working, weightKg: last?.weightKg, reps: last?.reps, rpe: last?.rpe
        ))
    }

    public func removeSet(_ setID: WorkoutSet.ID, from entryID: ExerciseEntry.ID) {
        guard let index = draft.entries.firstIndex(where: { $0.id == entryID }) else { return }
        draft.entries[index].sets.removeAll { $0.id == setID }
    }

    // MARK: Saving

    /// Saves the cleaned draft (empty sets and exercises removed) over the original session.
    /// Returns the saved session, or `nil` if it could not be saved (the draft is kept).
    public func save() async -> StrengthSession? {
        guard canSave else { return nil }
        isSaving = true
        defer { isSaving = false }
        let cleaned = draft.cleanedForSaving()
        do {
            try await workouts.save(cleaned)
            errorMessage = nil
            await backup?.backUpIfConfigured(now: clock())
            return cleaned
        } catch {
            errorMessage = "Could not save your changes."
            return nil
        }
    }
}

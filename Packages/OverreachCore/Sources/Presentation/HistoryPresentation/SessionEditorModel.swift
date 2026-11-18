import Domain
import Foundation
import Observation
import PresentationKit

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
    private let health: (any HealthWorkoutWriter)?
    private let clock: @Sendable () -> Date

    public init(
        session: StrengthSession,
        catalog: [Exercise],
        workouts: any WorkoutRepository,
        backup: (any BackupService)? = nil,
        health: (any HealthWorkoutWriter)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.draft = session
        self.original = session
        self.catalog = catalog
        self.exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.workouts = workouts
        self.backup = backup
        self.health = health
        self.clock = clock
    }

    public var hasChanges: Bool { draft != original }
    public var issues: [SessionEditIssue] { draft.editIssues }
    public var canSave: Bool { hasChanges && issues.isEmpty && !isSaving }

    /// Why the draft can't be saved yet, in plain language.
    public var issueMessages: [String] { issues.map(\.message) }

    public var exerciseChoices: [ExerciseChoice] { catalog.map(ExerciseChoice.init) }
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses
    public let setKindOptions: [Option<SetKind>] = Option.setKinds

    /// Notes as editable text; an empty text removes them.
    public var notesText: String {
        get { draft.notes ?? "" }
        set { draft.notes = newValue.isEmpty ? nil : newValue }
    }

    public func canMoveUp(_ entryID: ExerciseEntry.ID) -> Bool { draft.entries.first?.id != entryID }
    public func canMoveDown(_ entryID: ExerciseEntry.ID) -> Bool { draft.entries.last?.id != entryID }

    /// 1-based position of a set within its exercise.
    public func number(of setID: WorkoutSet.ID, in entryID: ExerciseEntry.ID) -> Int {
        guard let entry = draft.entries.first(where: { $0.id == entryID }) else { return 1 }
        return (entry.sets.firstIndex { $0.id == setID } ?? 0) + 1
    }

    public func name(of exerciseID: UUID) -> String {
        exerciseNames[exerciseID] ?? L10n.text("Unknown exercise")
    }

    // MARK: Times

    /// Moves the session to `date`, keeping its duration and set times.
    public func moveStart(to date: Date) {
        draft = draft.movingStart(to: date)
    }

    /// Adds an end time one hour after the start, to be adjusted by the user.
    public func addEndTime() {
        draft.endedAt = draft.startedAt.addingTimeInterval(3_600)
    }

    /// Sets the end time; `nil` removes it (unknown duration).
    public func setEnd(_ date: Date?) {
        draft.endedAt = date
    }

    // MARK: Exercises

    public func addExercise(_ exercise: Exercise) {
        draft.entries.append(ExerciseEntry(exerciseID: exercise.id, sets: [WorkoutSet()]))
    }

    public func addExercise(id exerciseID: UUID) {
        guard let exercise = catalog.first(where: { $0.id == exerciseID }) else { return }
        addExercise(exercise)
    }

    public func replaceExercise(of entryID: ExerciseEntry.ID, withID exerciseID: UUID) {
        guard let exercise = catalog.first(where: { $0.id == exerciseID }) else { return }
        replaceExercise(of: entryID, with: exercise)
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
            // A workout in the health app holds only the session's times.
            if cleaned.startedAt != original.startedAt || cleaned.endedAt != original.endedAt {
                await health?.sync(cleaned)
            }
            return cleaned
        } catch {
            errorMessage = L10n.text("Could not save your changes.")
            return nil
        }
    }
}

extension SessionEditIssue {
    public var message: String {
        switch self {
        case .missingName: L10n.text("Give the session a name.")
        case .noSets: L10n.text("Add at least one set, or delete the session from History.")
        case .endsBeforeStart: L10n.text("The end time is before the start time.")
        case .invalidValues: L10n.text("Weights and reps can't be negative, and RPE goes from 1 to 10.")
        }
    }
}

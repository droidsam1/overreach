import Domain
import Foundation
import Observation
import PresentationKit

/// A similar catalog exercise offered while editing.
public struct SuggestionRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let muscles: String
}

/// Text of the merge confirmation.
public struct MergeConfirmation: Hashable, Sendable {
    public let targetID: UUID
    public let confirmLabel: String
    public let message: String
}

/// Create or edit one exercise: names (not for built-in exercises), muscles and equipment, copy from a similar
/// exercise, or merge into another one.
@MainActor
@Observable
public final class ExerciseEditorModel {
    public var draft: MappingDraft
    public var movementPattern: MovementPattern?
    public var name: String
    /// Other names, separated by commas. Used by search and to match imported exercises.
    public var aliasesText: String
    /// Text typed in the merge-target search.
    public var mergeSearchText = ""
    /// Set when the user picked a merge target; cleared by confirming or cancelling.
    public private(set) var pendingMerge: MergeConfirmation?

    public let muscleOptions: [Option<MuscleGroup>] = MuscleGroup.allCases.map { Option(value: $0, name: $0.displayName) }
    public let movementPatternOptions = MovementPattern.allCases.map { Option(value: $0, name: $0.displayName) }
    public let equipmentOptions: [Option<Equipment>] = Equipment.allCases.map { Option(value: $0, name: $0.displayName) }

    private let list: ExercisesModel
    private let exerciseID: UUID
    private let isNew: Bool
    private let initialAliasesText: String

    /// Edits an existing exercise.
    init(list: ExercisesModel, exerciseID: UUID) {
        self.list = list
        self.exerciseID = exerciseID
        isNew = false
        let exercise = list.exercise(id: exerciseID)
        draft = exercise.map(MappingDraft.init) ?? MappingDraft()
        movementPattern = exercise?.movementPattern
        name = exercise?.name ?? ""
        initialAliasesText = exercise?.aliases.sorted().joined(separator: ", ") ?? ""
        aliasesText = initialAliasesText
    }

    /// Creates a new custom exercise.
    init(creatingIn list: ExercisesModel) {
        self.list = list
        exerciseID = UUID()
        isNew = true
        draft = MappingDraft()
        name = ""
        initialAliasesText = ""
        aliasesText = ""
    }

    // MARK: Screen state

    private var exercise: Exercise? { list.exercise(id: exerciseID) }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// False once the exercise was merged away or deleted.
    public var exists: Bool { isNew || exercise != nil }

    public var title: String { exercise?.displayName ?? (isNew ? L10n.text("New exercise") : "") }

    /// Built-in exercises keep their names; new, created and imported ones can change them.
    public var canEditNames: Bool { isNew || exercise?.isCustom == true }

    /// Why the typed names can't be used: another exercise already answers to one of them, which would make
    /// search and imports ambiguous.
    public var nameMessage: String? {
        guard canEditNames else { return nil }
        let currentNames = exercise.map { [$0.name] + $0.aliases } ?? []
        let ownKeys = Set(currentNames.map(SearchText.normalize))
        for candidate in [trimmedName] + editedAliases.sorted() {
            let key = SearchText.normalize(candidate)
            guard !key.isEmpty, !ownKeys.contains(key),
                  let other = list.exercise(answeringTo: key, excluding: exerciseID) else { continue }
            return L10n.format("“{1}” is already used by {2}.", candidate, other.displayName)
        }
        return nil
    }

    public var canSave: Bool {
        draft.canSave && (!canEditNames || (!trimmedName.isEmpty && nameMessage == nil))
    }

    /// Only custom exercises can be merged away; built-in ones stay in the catalog.
    public var canMerge: Bool { exercise?.isCustom ?? false }

    public var suggestions: [SuggestionRow] {
        guard let subject = exercise ?? newExercisePreview else { return [] }
        return list.suggestions(for: subject).map {
            SuggestionRow(
                id: $0.exercise.id, name: $0.exercise.displayName,
                muscles: MuscleGroup.displayList($0.exercise.primaryMuscles)
            )
        }
    }

    /// Exercises this one can be merged into, filtered by the merge search text.
    public var mergeTargets: [ExerciseRow] {
        guard let exercise else { return [] }
        return SearchText.filter(list.mergeTargets(for: exercise), by: mergeSearchText).map(list.row)
    }

    public var errorMessage: String? { list.errorMessage }

    /// A new exercise gets its settings once it exists.
    public var canEditSettings: Bool { exercise != nil }

    public func settingsEditor() -> ExerciseSettingsModel? { list.settingsEditor(for: exerciseID) }

    public func isPrimary(_ muscle: MuscleGroup) -> Bool { draft.primary.contains(muscle) }

    public func isSecondary(_ muscle: MuscleGroup) -> Bool { draft.secondary.contains(muscle) }

    // MARK: Intents

    public func setPrimary(_ muscle: MuscleGroup, _ isOn: Bool) { draft.setPrimary(muscle, isOn) }

    public func setSecondary(_ muscle: MuscleGroup, _ isOn: Bool) { draft.setSecondary(muscle, isOn) }

    public func copyMuscles(from suggestionID: UUID) {
        guard let other = list.exercise(id: suggestionID) else { return }
        draft.copy(from: other)
    }

    /// Saves the draft. Returns true when the screen can close.
    public func save() async -> Bool {
        guard canSave else { return false }
        guard canEditNames else {
            return await list.saveMapping(
                for: exerciseID, primary: draft.primary, secondary: draft.secondary, equipment: draft.equipment
            )
        }
        var edited = exercise ?? Exercise(id: exerciseID, name: trimmedName, primaryMuscles: [], isCustom: true)
        var aliases = editedAliases
        // A renamed exercise keeps answering to its old name, so importing it again does not duplicate it.
        if SearchText.normalize(edited.name) != SearchText.normalize(trimmedName) {
            aliases.insert(edited.name)
        }
        edited.name = trimmedName
        edited.aliases = aliases
        edited.primaryMuscles = draft.primary
        edited.secondaryMuscles = draft.secondary
        edited.equipment = draft.equipment
        edited.movementPattern = movementPattern
        return await list.saveExercise(edited)
    }

    /// Asks for confirmation before merging into `targetID`.
    public func requestMerge(into targetID: UUID) {
        guard canMerge, let exercise, let target = list.exercise(id: targetID) else { return }
        let sessions = list.sessionCount(of: exerciseID)
        pendingMerge = MergeConfirmation(
            targetID: targetID,
            confirmLabel: L10n.format("Merge into {1}", target.displayName),
            message: L10n.format(
                "{1} sessions with {2} will use {3}. {2} is removed and its name is kept as an alias, so importing "
                    + "it again maps to {3}.",
                sessions, exercise.displayName, target.displayName
            )
        )
    }

    public func cancelMerge() { pendingMerge = nil }

    /// Merges into the pending target. Returns true when the screen can close.
    public func confirmMerge() async -> Bool {
        guard let pending = pendingMerge else { return false }
        pendingMerge = nil
        return await list.merge(exerciseID, into: pending.targetID)
    }

    // MARK: Helpers

    /// What is being created so far, to look for similar exercises while typing.
    private var newExercisePreview: Exercise? {
        guard isNew, !trimmedName.isEmpty else { return nil }
        return Exercise(id: exerciseID, name: trimmedName, primaryMuscles: [], equipment: draft.equipment)
    }

    /// The typed aliases without blanks, repeats or the exercise's own name. Untouched text keeps the stored
    /// aliases as they are, since an imported name may itself contain a comma.
    private var editedAliases: Set<String> {
        let entries: [String] = aliasesText == initialAliasesText
            ? exercise?.aliases.sorted() ?? []
            : aliasesText.split(whereSeparator: { $0 == "," || $0.isNewline }).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        var seen: Set<String> = [SearchText.normalize(trimmedName)]
        var aliases: Set<String> = []
        for entry in entries {
            let key = SearchText.normalize(entry)
            if !key.isEmpty, seen.insert(key).inserted {
                aliases.insert(entry)
            }
        }
        return aliases
    }
}

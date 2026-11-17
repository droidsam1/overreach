import Domain
import Foundation
import Observation
import PresentationKit

/// Muscles and equipment being edited. A muscle is either primary or secondary, never both.
public struct MappingDraft: Hashable, Sendable {
    public private(set) var primary: Set<MuscleGroup>
    public private(set) var secondary: Set<MuscleGroup>
    public var equipment: Equipment

    public init(primary: Set<MuscleGroup> = [], secondary: Set<MuscleGroup> = [], equipment: Equipment = .other) {
        self.primary = primary
        self.secondary = secondary.subtracting(primary)
        self.equipment = equipment
    }

    public init(_ exercise: Exercise) {
        self.init(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles, equipment: exercise.equipment)
    }

    /// A muscle needs to be primary for the exercise's volume to count.
    public var canSave: Bool { !primary.isEmpty }

    public mutating func setPrimary(_ muscle: MuscleGroup, _ isOn: Bool) {
        if isOn {
            primary.insert(muscle)
            secondary.remove(muscle)
        } else {
            primary.remove(muscle)
        }
    }

    public mutating func setSecondary(_ muscle: MuscleGroup, _ isOn: Bool) {
        if isOn {
            secondary.insert(muscle)
            primary.remove(muscle)
        } else {
            secondary.remove(muscle)
        }
    }

    /// Takes the other exercise's muscles; its equipment only if none was chosen yet.
    public mutating func copy(from other: Exercise) {
        primary = other.primaryMuscles
        secondary = other.secondaryMuscles.subtracting(other.primaryMuscles)
        if equipment == .other { equipment = other.equipment }
    }
}

/// A selectable muscle or equipment option with its display name.
public struct Option<Value: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public let value: Value
    public let name: String
    public var id: Value { value }
}

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

/// Edit one exercise: muscles, equipment, copy from a similar exercise, or merge into another one.
@MainActor
@Observable
public final class ExerciseEditorModel {
    public var draft: MappingDraft
    /// Text typed in the merge-target search.
    public var mergeSearchText = ""
    /// Set when the user picked a merge target; cleared by confirming or cancelling.
    public private(set) var pendingMerge: MergeConfirmation?

    public let muscleOptions: [Option<MuscleGroup>] = MuscleGroup.allCases.map { Option(value: $0, name: $0.displayName) }
    public let equipmentOptions: [Option<Equipment>] = Equipment.allCases.map { Option(value: $0, name: $0.displayName) }

    private let list: ExercisesModel
    private let exerciseID: UUID

    init(list: ExercisesModel, exerciseID: UUID) {
        self.list = list
        self.exerciseID = exerciseID
        draft = list.exercise(id: exerciseID).map(MappingDraft.init) ?? MappingDraft()
    }

    // MARK: Screen state

    private var exercise: Exercise? { list.exercise(id: exerciseID) }

    /// False once the exercise was merged away or deleted.
    public var exists: Bool { exercise != nil }

    public var title: String { exercise?.name ?? "" }

    public var canSave: Bool { draft.canSave }

    /// Only custom exercises can be merged away; built-in ones stay in the catalog.
    public var canMerge: Bool { exercise?.isCustom ?? false }

    public var suggestions: [SuggestionRow] {
        guard let exercise else { return [] }
        return list.suggestions(for: exercise).map {
            SuggestionRow(id: $0.exercise.id, name: $0.exercise.name, muscles: MuscleGroup.displayList($0.exercise.primaryMuscles))
        }
    }

    /// Exercises this one can be merged into, filtered by the merge search text.
    public var mergeTargets: [ExerciseRow] {
        guard let exercise else { return [] }
        return SearchText.filter(list.mergeTargets(for: exercise), by: mergeSearchText).map(list.row)
    }

    public var errorMessage: String? { list.errorMessage }

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
        await list.saveMapping(
            for: exerciseID, primary: draft.primary, secondary: draft.secondary, equipment: draft.equipment
        )
    }

    /// Asks for confirmation before merging into `targetID`.
    public func requestMerge(into targetID: UUID) {
        guard canMerge, let exercise, let target = list.exercise(id: targetID) else { return }
        let sessions = list.sessionCount(of: exerciseID)
        pendingMerge = MergeConfirmation(
            targetID: targetID,
            confirmLabel: L10n.text("Merge into \(target.name)"),
            message: L10n.text(
                "\(sessions) sessions with \(exercise.name) will use \(target.name). \(exercise.name) is removed and "
                    + "its name is kept as an alias, so importing it again maps to \(target.name)."
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
}

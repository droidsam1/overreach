import Analytics
import Domain
import Foundation
import Observation

/// What a muscle does in an exercise being created.
public enum MuscleRole: String, CaseIterable, Hashable, Sendable {
    case none, primary, secondary

    public var displayName: String {
        switch self {
        case .none: L10n.text("Not worked")
        case .primary: L10n.text("Primary")
        case .secondary: L10n.text("Secondary")
        }
    }
}

/// Creates a custom exercise from an exercise picker, when search does not find it.
///
/// The name typed in the search becomes the exercise's name. Equipment comes from words in the name ("barra",
/// "dumbbell"…) and muscles from the most similar exercise, so the usual case is one tap on Add. Whatever the user
/// changes stays as chosen. A name that an exercise already answers to offers that exercise instead of a duplicate.
@MainActor
@Observable
public final class NewExerciseModel: Identifiable {
    public let id = UUID()
    public var name: String {
        didSet { fillFromName() }
    }

    public private(set) var draft: MappingDraft
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public let muscleOptions = MuscleGroup.allCases.map { Option(value: $0, name: $0.displayName) }
    public let equipmentOptions = Equipment.allCases.map { Option(value: $0, name: $0.displayName) }
    public let roleOptions = MuscleRole.allCases.map { Option(value: $0, name: $0.displayName) }

    private let catalog: [Exercise]
    private let repository: any ExerciseRepository
    private var equipmentChosen = false
    private var musclesChosen = false
    /// The exercise the muscles were copied from, while the user has not changed them.
    private var musclesSource: Exercise?

    public init(name: String, catalog: [Exercise], repository: any ExerciseRepository) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.catalog = catalog
        self.repository = repository
        draft = MappingDraft()
        fillFromName()
    }

    // MARK: Screen state

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var equipment: Equipment {
        get { draft.equipment }
        set {
            draft.equipment = newValue
            equipmentChosen = true
        }
    }

    /// An exercise that already answers to the typed name, offered instead of creating a duplicate.
    public var existing: ExerciseChoice? {
        let key = SearchText.normalize(trimmedName)
        guard !key.isEmpty else { return nil }
        return catalog.first { $0.knownNames.contains { SearchText.normalize($0) == key } }.map(ExerciseChoice.init)
    }

    /// What to say about `existing` and the label of the button that picks it.
    public var existingNotice: (message: String, useLabel: String)? {
        existing.map {
            (L10n.format("{1} is already in your exercises.", $0.name), L10n.format("Use {1}", $0.name))
        }
    }

    /// Where the muscles came from, or what is missing.
    public var musclesNote: String {
        if draft.primary.isEmpty {
            return L10n.text("Choose at least one primary muscle so this exercise counts towards your weekly volume.")
        }
        if let musclesSource {
            return L10n.format("Muscles taken from {1}. Change them if yours differs.", musclesSource.displayName)
        }
        return L10n.text("Primary muscles count one set per working set; secondary ones, half a set.")
    }

    public var canSave: Bool { !trimmedName.isEmpty && existing == nil && draft.canSave && !isSaving }

    public func role(of muscle: MuscleGroup) -> MuscleRole {
        if draft.primary.contains(muscle) { return .primary }
        if draft.secondary.contains(muscle) { return .secondary }
        return .none
    }

    // MARK: Intents

    public func setRole(_ role: MuscleRole, for muscle: MuscleGroup) {
        musclesChosen = true
        musclesSource = nil
        switch role {
        case .primary: draft.setPrimary(muscle, true)
        case .secondary: draft.setSecondary(muscle, true)
        case .none:
            draft.setPrimary(muscle, false)
            draft.setSecondary(muscle, false)
        }
    }

    /// Saves the exercise. Returns it, or `nil` when it can't be saved (see `errorMessage`).
    public func save() async -> Exercise? {
        guard canSave else { return nil }
        isSaving = true
        defer { isSaving = false }
        let exercise = Exercise(
            name: trimmedName,
            primaryMuscles: draft.primary,
            secondaryMuscles: draft.secondary,
            equipment: draft.equipment,
            isCustom: true
        )
        do {
            try await repository.save(exercise)
            errorMessage = nil
            return exercise
        } catch {
            errorMessage = L10n.text("Could not save the exercise.")
            return nil
        }
    }

    // MARK: Helpers

    /// Refreshes what the user has not chosen yet from the typed name.
    private func fillFromName() {
        let guessed = Self.equipment(in: trimmedName)
        let preview = Exercise(name: trimmedName, primaryMuscles: [], equipment: guessed ?? .other)
        let similar = trimmedName.isEmpty ? nil : ExerciseSuggestions.similar(to: preview, in: catalog, limit: 1).first
        if !equipmentChosen {
            draft.equipment = guessed ?? similar?.exercise.equipment ?? .other
        }
        if !musclesChosen {
            let equipment = draft.equipment
            if let source = similar?.exercise {
                draft = MappingDraft(
                    primary: source.primaryMuscles, secondary: source.secondaryMuscles, equipment: equipment
                )
            } else {
                draft = MappingDraft(equipment: equipment)
            }
            musclesSource = similar?.exercise
        }
    }

    /// Equipment named by a word of `name`, in English, Spanish or Galician.
    static func equipment(in name: String) -> Equipment? {
        let words = Set(SearchText.normalize(name).split(whereSeparator: { !$0.isLetter }).map(String.init))
        return equipmentWords.first { !words.isDisjoint(with: $0.words) }?.equipment
    }

    /// Checked in order: "multipower" or "máquina" win over "barra" in "barra en multipower".
    private static let equipmentWords: [(equipment: Equipment, words: Set<String>)] = [
        (.machine, ["machine", "maquina", "multipower", "smith"]),
        (.cable, ["cable", "polea", "poleas"]),
        (.kettlebell, ["kettlebell", "kettlebells", "kb"]),
        (.dumbbell, ["dumbbell", "dumbbells", "db", "mancuerna", "mancuernas", "mancorna", "mancornas"]),
        (.barbell, ["barbell", "barra", "ez"]),
        (.band, ["band", "bands", "banda", "bandas", "goma", "gomas", "elastico", "elastica"]),
        (.bodyweight, ["bodyweight"]),
    ]
}

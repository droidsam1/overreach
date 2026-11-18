import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// One exercise as shown in a list.
public struct ExerciseRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// Primary muscles ("Chest, Triceps"); empty when the exercise has none yet.
    public let muscles: String
    public let needsMuscles: Bool
    public let sessionCount: Int
}

/// The exercise list and muscle mapping (issue #13). Imported exercises that are not in the catalog have no
/// muscles, so their volume does not count until the user maps them or merges them into a catalog exercise.
@MainActor
@Observable
public final class ExercisesModel {
    public private(set) var exercises: [Exercise] = []
    /// Number of sessions that use each exercise.
    public private(set) var sessionCounts: [UUID: Int] = [:]
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Text typed in the search field. While searching, only the full list is shown, filtered.
    public var searchText = ""

    private let workouts: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository
    ) {
        self.workouts = workouts
        self.exerciseRepository = exercises
        self.progression = progression
    }

    // MARK: Screen state

    /// Exercises without muscles, most used first. Hidden while searching.
    public var needsMappingRows: [ExerciseRow] {
        guard searchText.isEmpty else { return [] }
        return needsMapping.map(row)
    }

    /// Every exercise, filtered by the search text.
    public var allRows: [ExerciseRow] {
        SearchText.filter(exercises, by: searchText).map(row)
    }

    public var needsMappingCount: Int { exercises.count(where: \.needsMuscleMapping) }

    public var showsLoadingIndicator: Bool { isLoading && exercises.isEmpty }

    public func sessionCount(of exerciseID: UUID) -> Int { sessionCounts[exerciseID] ?? 0 }

    public func exercise(id: UUID) -> Exercise? { exercises.first { $0.id == id } }

    /// The editor for one exercise, or `nil` if it no longer exists (e.g. merged away).
    public func editor(for exerciseID: UUID) -> ExerciseEditorModel? {
        guard exercise(id: exerciseID) != nil else { return nil }
        return ExerciseEditorModel(list: self, exerciseID: exerciseID)
    }

    /// The form to create a custom exercise.
    public func newExerciseEditor() -> ExerciseEditorModel {
        ExerciseEditorModel(creatingIn: self)
    }

    // MARK: Intents

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            exercises = try await exerciseRepository.allExercises()
            let sessions = try await workouts.sessions(from: .distantPast, to: .distantFuture)
            var counts: [UUID: Int] = [:]
            for session in sessions {
                for exerciseID in Set(session.entries.map(\.exerciseID)) {
                    counts[exerciseID, default: 0] += 1
                }
            }
            sessionCounts = counts
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not load your exercises.")
        }
    }

    /// Saves the muscles and equipment. A muscle in both lists counts as primary. Returns false on failure or
    /// when no primary muscle is given.
    @discardableResult
    public func saveMapping(
        for exerciseID: UUID,
        primary: Set<MuscleGroup>,
        secondary: Set<MuscleGroup>,
        equipment: Equipment
    ) async -> Bool {
        guard var exercise = exercise(id: exerciseID), !primary.isEmpty else { return false }
        exercise.primaryMuscles = primary
        exercise.secondaryMuscles = secondary.subtracting(primary)
        exercise.equipment = equipment
        do {
            try await exerciseRepository.save(exercise)
            if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                exercises[index] = exercise
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.text("Could not save the muscles.")
            return false
        }
    }

    /// Saves a new or edited exercise and refreshes the list. Returns false on failure.
    @discardableResult
    public func saveExercise(_ exercise: Exercise) async -> Bool {
        do {
            try await exerciseRepository.save(exercise)
        } catch {
            errorMessage = L10n.text("Could not save the exercise.")
            return false
        }
        await load()
        return true
    }

    /// Moves the history of `sourceID` to `targetID` and removes the source. The source's names become aliases
    /// of the target (so re-imports resolve to it) and its progression settings move over if the target has
    /// none. Order keeps every session pointing to an existing exercise even if a step fails.
    @discardableResult
    public func merge(_ sourceID: UUID, into targetID: UUID) async -> Bool {
        guard sourceID != targetID, let source = exercise(id: sourceID), let target = exercise(id: targetID) else {
            return false
        }
        do {
            try await exerciseRepository.save(ExerciseMerge.absorbing(source, into: target))

            let sessions = try await workouts.sessions(from: .distantPast, to: .distantFuture)
            try await workouts.save(ExerciseMerge.repoint(sessions, from: sourceID, to: targetID))

            if let settings = try await progression.progressionSettings(for: sourceID),
               try await progression.progressionSettings(for: targetID) == nil {
                try await progression.save(settings, for: targetID)
            }

            try await exerciseRepository.deleteExercise(id: sourceID)
            await load()
            return true
        } catch {
            errorMessage = L10n.text("Could not merge the exercises. Nothing was lost; try again.")
            return false
        }
    }

    // MARK: Helpers for the editor

    func suggestions(for exercise: Exercise) -> [ExerciseSuggestion] {
        ExerciseSuggestions.similar(to: exercise, in: exercises)
    }

    /// Another exercise whose name or alias has the normalized form `key`.
    func exercise(answeringTo key: String, excluding excludedID: UUID) -> Exercise? {
        exercises.first { candidate in
            candidate.id != excludedID
                && ([candidate.name] + candidate.aliases).contains { SearchText.normalize($0) == key }
        }
    }

    func mergeTargets(for exercise: Exercise) -> [Exercise] {
        exercises.filter { $0.id != exercise.id && !$0.needsMuscleMapping }
    }

    func row(_ exercise: Exercise) -> ExerciseRow {
        ExerciseRow(
            id: exercise.id,
            name: exercise.name,
            muscles: MuscleGroup.displayList(exercise.primaryMuscles),
            needsMuscles: exercise.needsMuscleMapping,
            sessionCount: sessionCount(of: exercise.id)
        )
    }

    private var needsMapping: [Exercise] {
        exercises.filter(\.needsMuscleMapping).sorted { sessionCount(of: $0.id) > sessionCount(of: $1.id) }
    }
}

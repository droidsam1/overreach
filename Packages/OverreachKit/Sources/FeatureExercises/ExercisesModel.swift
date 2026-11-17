import Analytics
import Domain
import Foundation
import Observation

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

    /// Exercises without muscles, most used first.
    public var needsMapping: [Exercise] {
        exercises.filter(\.needsMuscleMapping).sorted { sessionCount(of: $0.id) > sessionCount(of: $1.id) }
    }

    public var needsMappingCount: Int { exercises.count(where: \.needsMuscleMapping) }

    public func sessionCount(of exerciseID: UUID) -> Int { sessionCounts[exerciseID] ?? 0 }

    public func exercise(id: UUID) -> Exercise? { exercises.first { $0.id == id } }

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
            errorMessage = "Could not load your exercises."
        }
    }

    /// Catalog exercises with similar names, to copy their muscles or merge into.
    public func suggestions(for exercise: Exercise) -> [ExerciseSuggestion] {
        ExerciseSuggestions.similar(to: exercise, in: exercises)
    }

    /// Mapped exercises the given one can be merged into, sorted by name.
    public func mergeTargets(for exercise: Exercise) -> [Exercise] {
        exercises.filter { $0.id != exercise.id && !$0.needsMuscleMapping }
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
            replace(exercise)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save the muscles."
            return false
        }
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
            let merged = ExerciseMerge.absorbing(source, into: target)
            try await exerciseRepository.save(merged)

            let sessions = try await workouts.sessions(from: .distantPast, to: .distantFuture)
            let repointed = ExerciseMerge.repoint(sessions, from: sourceID, to: targetID)
            try await workouts.save(repointed)

            if let settings = try await progression.progressionSettings(for: sourceID),
               try await progression.progressionSettings(for: targetID) == nil {
                try await progression.save(settings, for: targetID)
            }

            try await exerciseRepository.deleteExercise(id: sourceID)

            await load()
            return true
        } catch {
            errorMessage = "Could not merge the exercises. Nothing was lost; try again."
            return false
        }
    }

    private func replace(_ exercise: Exercise) {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index] = exercise
        }
    }
}

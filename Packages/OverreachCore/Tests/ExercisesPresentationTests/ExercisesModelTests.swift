import Domain
import ExercisesPresentation
import Fixtures
import Foundation
import Testing

@MainActor
@Suite("ExercisesModel")
struct ExercisesModelTests {
    private let bench = Exercise(
        name: "Bench Press (Barbell)", primaryMuscles: [.chest], secondaryMuscles: [.triceps], equipment: .barbell,
        aliases: ["press banca"]
    )
    private let imported = Exercise(name: "Press Banca Pausa", primaryMuscles: [], isCustom: true)
    private let zercher = Exercise(name: "Zercher Squat", primaryMuscles: [], isCustom: true)

    private func session(_ day: Double, _ ids: [UUID]) -> StrengthSession {
        StrengthSession(
            name: "Session",
            startedAt: Date(timeIntervalSince1970: day * 86_400),
            entries: ids.map { ExerciseEntry(exerciseID: $0, sets: [WorkoutSet(weightKg: 80, reps: 5)]) }
        )
    }

    private func makeModel() -> (ExercisesModel, TestStore) {
        let store = TestStore(
            exercises: [bench, imported, zercher],
            sessions: [session(1, [imported.id]), session(2, [imported.id, bench.id]), session(3, [zercher.id])]
        )
        return (ExercisesModel(workouts: store, exercises: store, progression: store, routines: store), store)
    }

    @Test func listsUnmappedExercisesMostUsedFirst() async {
        let (model, _) = makeModel()
        await model.load()

        #expect(model.needsMappingCount == 2)
        #expect(model.needsMappingRows.map(\.id) == [imported.id, zercher.id])
        #expect(model.sessionCount(of: imported.id) == 2)
    }

    @Test func savingMusclesMapsTheExercise() async throws {
        let (model, store) = makeModel()
        await model.load()

        let saved = await model.saveMapping(
            for: zercher.id, primary: [.quadriceps, .glutes], secondary: [.glutes, .core], equipment: .barbell
        )

        #expect(saved)
        #expect(model.needsMappingCount == 1)
        let stored = try #require(try await store.allExercises().first { $0.id == zercher.id })
        #expect(stored.primaryMuscles == [.quadriceps, .glutes])
        #expect(stored.secondaryMuscles == [.core])  // a primary muscle is not also secondary
        #expect(stored.equipment == .barbell)
    }

    @Test func savingWithoutPrimaryMusclesIsRejected() async {
        let (model, _) = makeModel()
        await model.load()

        #expect(await model.saveMapping(for: zercher.id, primary: [], secondary: [.core], equipment: .other) == false)
        #expect(model.needsMappingCount == 2)
    }

    @Test func suggestsSimilarMappedExercises() async {
        let (model, _) = makeModel()
        await model.load()

        #expect(model.editor(for: imported.id)?.suggestions.map(\.id) == [bench.id])
    }

    @Test func mergeMovesHistoryAliasesAndSettingsThenRemovesTheSource() async throws {
        let (model, store) = makeModel()
        let settings = ProgressionSettings(incrementKg: 1.25, isMainLift: true)
        try await store.save(settings, for: imported.id)
        await model.load()

        #expect(await model.merge(imported.id, into: bench.id))

        let exercises = try await store.allExercises()
        #expect(!exercises.contains { $0.id == imported.id })
        #expect(exercises.first { $0.id == bench.id }?.aliases.contains("Press Banca Pausa") == true)
        let sessions = try await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(!sessions.flatMap(\.entries).contains { $0.exerciseID == imported.id })
        #expect(sessions.flatMap(\.entries).count(where: { $0.exerciseID == bench.id }) == 3)
        #expect(try await store.progressionSettings(for: bench.id) == settings)
        #expect(model.needsMappingCount == 1)
        #expect(model.sessionCount(of: bench.id) == 2)
    }

    @Test func mergeMovesRoutinesToTheTarget() async throws {
        let (model, store) = makeModel()
        let routine = Routine(name: "Push", exerciseIDs: [imported.id, zercher.id])
        try await store.save(routine)
        await model.load()

        #expect(await model.merge(imported.id, into: bench.id))

        #expect(try await store.allRoutines().first?.exerciseIDs == [bench.id, zercher.id])
    }

    @Test func mergeKeepsTheTargetsOwnSettings() async throws {
        let (model, store) = makeModel()
        let own = ProgressionSettings(incrementKg: 2.5)
        try await store.save(ProgressionSettings(incrementKg: 1), for: imported.id)
        try await store.save(own, for: bench.id)
        await model.load()

        await model.merge(imported.id, into: bench.id)

        #expect(try await store.progressionSettings(for: bench.id) == own)
    }
}

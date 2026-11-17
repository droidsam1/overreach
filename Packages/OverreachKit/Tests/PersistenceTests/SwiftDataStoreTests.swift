import Domain
import Foundation
import Persistence
import Testing

@Suite("SwiftDataStore")
struct SwiftDataStoreTests {
    private func makeStore() throws -> SwiftDataStore {
        SwiftDataStore.make(container: try PersistenceContainer.make(inMemory: true))
    }

    @Test func savesUpdatesAndDeletesSessions() async throws {
        let store = try makeStore()
        let squat = UUID()
        var session = StrengthSession(
            name: "Legs",
            startedAt: Date(timeIntervalSince1970: 1_000),
            entries: [ExerciseEntry(exerciseID: squat, sets: [WorkoutSet(weightKg: 100, reps: 5, rpe: 8)])]
        )
        let other = StrengthSession(name: "Push", startedAt: Date(timeIntervalSince1970: 9_000))
        try await store.save(session)
        try await store.save(other)

        session.name = "Legs A"
        try await store.save(session)  // update, not a duplicate

        let early = try await store.sessions(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 5_000))
        #expect(early == [session])

        try await store.deleteSession(id: session.id)
        let remaining = try await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(remaining.map(\.name) == ["Push"])
    }

    @Test func deletingExercisesRemovesCustomOnesAndResetsBuiltIns() async throws {
        let store = try makeStore()
        let custom = Exercise(name: "Zercher Squat", primaryMuscles: [], isCustom: true)
        var bench = try #require(ExerciseCatalog.builtIn.first { $0.name == "Bench Press (Barbell)" })
        let original = bench
        bench.aliases.insert("Press banca pausa")
        try await store.save(custom)
        try await store.save(bench)

        try await store.deleteExercise(id: custom.id)
        try await store.deleteExercise(id: bench.id)

        let all = try await store.allExercises()
        #expect(!all.contains { $0.id == custom.id })
        #expect(all.first { $0.id == bench.id } == original)
    }

    @Test func exercisesIncludeTheCatalogAndCustomOnes() async throws {
        let store = try makeStore()
        let custom = Exercise(name: "Zercher Squat", primaryMuscles: [.quadriceps], equipment: .barbell, isCustom: true)
        try await store.save(custom)

        let all = try await store.allExercises()
        #expect(all.count == ExerciseCatalog.builtIn.count + 1)
        #expect(all.contains(custom))
    }

    @Test func checkInsFilterByDayRange() async throws {
        let store = try makeStore()
        let days = (14...17).map { CalendarDay(year: 2026, month: 11, day: $0) }
        for day in days {
            try await store.save(CheckIn(day: day, energy: 3))
        }
        try await store.save(CheckIn(day: days[1], isSick: true))  // replaces

        let found = try await store.checkIns(in: days[1]...days[2])
        #expect(found.map(\.day) == [days[1], days[2]])
        #expect(try await store.checkIn(for: days[1])?.isSick == true)
    }

    @Test func profileAndProgressionSettingsRoundTrip() async throws {
        let store = try makeStore()
        #expect(try await store.profile() == AthleteProfile())

        let profile = AthleteProfile(sex: .male, walkingRoutine: WalkingRoutine(hasDog: true, usualWalksPerDay: 3))
        try await store.save(profile)
        #expect(try await store.profile() == profile)

        let bench = UUID()
        #expect(try await store.progressionSettings(for: bench) == nil)
        let settings = ProgressionSettings(scheme: .linearLoad(sets: 5, reps: 5, targetRPE: 8), incrementKg: 1.25)
        try await store.save(settings, for: bench)
        #expect(try await store.progressionSettings(for: bench) == settings)
    }
}

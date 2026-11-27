import Domain
import StrongImport
import Testing

@Suite("Exercise matcher")
struct ExerciseMatcherTests {
    @Test func resolvesEnglishAndSpanishCatalogNames() {
        var matcher = ExerciseMatcher(catalog: ExerciseCatalog.builtIn)
        let english = matcher.resolve("Bench Press (Barbell)")
        #expect(matcher.resolve("Press de banca (barra)") == english)
        #expect(matcher.resolve("  PRESS DE BANCA  ") == english)
        #expect(matcher.created.isEmpty)
    }

    @Test func matchedPullsAndIsolationExercisesKeepTheirCatalogMetadata() {
        var matcher = ExerciseMatcher(catalog: ExerciseCatalog.builtIn)
        let pulldown = matcher.resolve("Lat Pulldown (Cable)")
        #expect(pulldown.primaryMuscles == [.lats])
        #expect(pulldown.movementPattern == .verticalPull)
        let row = matcher.resolve("Remo sentado (polea)")
        #expect(row.primaryMuscles == [.upperBack])
        #expect(row.movementPattern == .horizontalPull)
        let reverseFly = matcher.resolve("Reverse Fly (Machine)")
        #expect(reverseFly.primaryMuscles == [.rearDelts])
        #expect(reverseFly.movementPattern == nil)
        #expect(matcher.created.isEmpty)
    }

    @Test func unknownNamesBecomeCustomExercises() {
        var matcher = ExerciseMatcher(catalog: ExerciseCatalog.builtIn)
        let created = matcher.resolve("Zercher Squat")
        #expect(created.isCustom)
        #expect(created.needsMuscleMapping)
        #expect(created.movementPattern == nil)
        #expect(matcher.created == [created])
    }
}

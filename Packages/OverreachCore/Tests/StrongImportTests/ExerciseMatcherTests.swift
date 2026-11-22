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

    @Test func unknownNamesBecomeCustomExercises() {
        var matcher = ExerciseMatcher(catalog: ExerciseCatalog.builtIn)
        let created = matcher.resolve("Zercher Squat")
        #expect(created.isCustom)
        #expect(created.needsMuscleMapping)
        #expect(matcher.created == [created])
    }
}

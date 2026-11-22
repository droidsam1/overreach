import Domain
import Foundation
import PresentationKit
import Testing

@Suite("PresentationKit")
struct PresentationKitTests {
    @Test func searchIgnoresCaseAccentsAndSpacing() {
        #expect(SearchText.matches("JALÓN  al", ["Lat Pulldown", "jalon al pecho"]))
        #expect(!SearchText.matches("remo", ["Lat Pulldown", "jalon al pecho"]))
        #expect(SearchText.matches("", ["anything"]))
    }

    @Test func muscleListFollowsCatalogOrder() {
        #expect(MuscleGroup.displayList([.triceps, .chest, .shoulders]) == "Chest, Shoulders, Triceps")
        #expect(MuscleGroup.displayList([]) == "")
    }

    @Test func everyValueHasADisplayName() {
        #expect(MuscleGroup.allCases.allSatisfy { !$0.displayName.isEmpty })
        #expect(Equipment.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    // MARK: Exercise names (ADR-0031)

    private func builtIn(_ name: String) -> Exercise {
        // An unknown name gives an exercise outside the catalog, so the expectations below fail.
        ExerciseCatalog.builtIn.first { $0.name == name } ?? Exercise(name: name, primaryMuscles: [])
    }

    @Test func builtInExercisesShowTheirSpanishNameInSpanishAndGalician() {
        let squat = builtIn("Squat (Barbell)")
        #expect(squat.displayName(language: "es") == "Sentadilla (barra)")
        #expect(squat.displayName(language: "gl") == "Sentadilla (barra)")
        #expect(squat.displayName(language: "en") == "Squat (Barbell)")
    }

    @Test func customAndChangedExercisesKeepTheirOwnName() {
        let custom = Exercise(name: "Press Landmine", primaryMuscles: [.shoulders], isCustom: true)
        #expect(custom.displayName(language: "es") == "Press Landmine")
        var renamed = builtIn("Squat (Barbell)")
        renamed.name = "Mi sentadilla"
        #expect(renamed.displayName(language: "es") == "Mi sentadilla")
    }

    @Test func listsSortByTheDisplayedName() {
        let exercises = [builtIn("Bench Press (Barbell)"), builtIn("Deadlift (Barbell)"), builtIn("Pull Up")]
        #expect(Exercise.byDisplayName(exercises, language: "en").map(\.name)
            == ["Bench Press (Barbell)", "Deadlift (Barbell)", "Pull Up"])
        // Dominadas, Peso muerto, Press de banca
        #expect(Exercise.byDisplayName(exercises, language: "es").map(\.name)
            == ["Pull Up", "Deadlift (Barbell)", "Bench Press (Barbell)"])
    }

    @Test func searchFindsExercisesInEnglishAndSpanish() {
        let catalog = ExerciseCatalog.builtIn
        let names = { (query: String) in SearchText.filter(catalog, by: query).map(\.name) }
        #expect(names("press de banca").contains("Bench Press (Barbell)"))
        #expect(names("bench press").contains("Bench Press (Barbell)"))
        #expect(names("jalón al pecho") == ["Lat Pulldown (Cable)", "Lat Pulldown (Machine)"])
        #expect(names("lat pulldown") == ["Lat Pulldown (Cable)", "Lat Pulldown (Machine)"])
        #expect(names("zancada con barra") == ["Lunge (Barbell)"])
        #expect(names("elevacion de talones").contains("Seated Calf Raise (Plate Loaded)"))
        let choice = ExerciseChoice(builtIn("Leg Press"))
        #expect(SearchText.matches("prensa de piernas", choice.searchTerms))
        #expect(SearchText.matches("leg press", choice.searchTerms))
    }
}

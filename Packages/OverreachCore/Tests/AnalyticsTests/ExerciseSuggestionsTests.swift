import Analytics
import Domain
import Testing

@Suite("Exercise suggestions")
struct ExerciseSuggestionsTests {
    private func imported(_ name: String, _ equipment: Equipment = .other) -> Exercise {
        Exercise(name: name, primaryMuscles: [], equipment: equipment, isCustom: true)
    }

    @Test func sameMovementWithOtherEquipmentIsSuggested() {
        let suggestions = ExerciseSuggestions.similar(
            to: imported("Romanian Deadlift (Kettlebell)", .kettlebell), in: ExerciseCatalog.builtIn
        )
        #expect(suggestions.count >= 2)
        #expect(suggestions.prefix(2).allSatisfy { $0.exercise.name.hasPrefix("Romanian Deadlift") })
    }

    @Test func spanishNamesMatchAliasesIgnoringAccentsAndPlurals() throws {
        let suggestions = ExerciseSuggestions.similar(to: imported("Sentadillas Búlgaras"), in: ExerciseCatalog.builtIn)
        let first = try #require(suggestions.first)
        #expect(first.exercise.name == "Bulgarian Split Squat")
        #expect(first.score == 1)
    }

    @Test func sameEquipmentRanksFirst() throws {
        let catalog = [
            Exercise(name: "Lat Pulldown (Cable)", primaryMuscles: [.back], equipment: .cable),
            Exercise(name: "Lat Pulldown (Machine)", primaryMuscles: [.back], equipment: .machine),
        ]
        let suggestions = ExerciseSuggestions.similar(to: imported("Lat Pulldown (Plate Loaded)", .machine), in: catalog)
        #expect(suggestions.map(\.exercise.name) == ["Lat Pulldown (Machine)", "Lat Pulldown (Cable)"])
    }

    @Test func unrelatedNamesGiveNoSuggestions() {
        #expect(ExerciseSuggestions.similar(to: imported("Tire Flip"), in: ExerciseCatalog.builtIn).isEmpty)
    }

    @Test func skipsItselfAndOtherUnmappedExercises() {
        let source = imported("Zercher Squat")
        let otherUnmapped = imported("Zercher Squat (Barbell)")
        let mapped = Exercise(name: "Zercher Squat (Smith Machine)", primaryMuscles: [.quadriceps], equipment: .machine)
        let suggestions = ExerciseSuggestions.similar(to: source, in: [source, otherUnmapped, mapped])
        #expect(suggestions.map(\.exercise.id) == [mapped.id])
    }

    @Test func respectsTheLimit() {
        let suggestions = ExerciseSuggestions.similar(to: imported("Squat"), in: ExerciseCatalog.builtIn, limit: 2)
        #expect(suggestions.count == 2)
    }
}

import Domain
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
}

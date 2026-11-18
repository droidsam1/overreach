import Domain
import ExercisesPresentation
import Fixtures
import Testing

@MainActor
@Suite("Exercise search empty state")
struct ExerciseSearchEmptyTests {
    @Test func showsNoResultsOnlyWhenNothingMatches() async {
        let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
        let store = TestStore(exercises: [bench])
        let model = ExercisesModel(workouts: store, exercises: store, progression: store, routines: store)
        await model.load()
        #expect(!model.showsNoResults)

        model.searchText = "zzz"

        #expect(model.showsNoResults)
    }
}

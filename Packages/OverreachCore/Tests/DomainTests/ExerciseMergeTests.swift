import Domain
import Foundation
import Testing

@Suite("Exercise merge")
struct ExerciseMergeTests {
    private let source = Exercise(
        name: "Press banca inclinado", primaryMuscles: [], isCustom: true, aliases: ["Incline press"]
    )
    private let target = Exercise(
        name: "Incline Bench Press (Barbell)", primaryMuscles: [.chest], equipment: .barbell,
        aliases: ["press inclinado con barra"]
    )

    @Test func repointsOnlySessionsThatUseTheSource() throws {
        let other = UUID()
        let withSource = StrengthSession(
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 1_000),
            entries: [
                ExerciseEntry(exerciseID: source.id, sets: [WorkoutSet(weightKg: 60, reps: 8)]),
                ExerciseEntry(exerciseID: other, sets: [WorkoutSet(weightKg: 20, reps: 12)]),
                ExerciseEntry(exerciseID: source.id, sets: [WorkoutSet(weightKg: 50, reps: 10)]),
            ]
        )
        let without = StrengthSession(
            name: "Pull",
            startedAt: Date(timeIntervalSince1970: 2_000),
            entries: [ExerciseEntry(exerciseID: other)]
        )

        let changed = ExerciseMerge.repoint([withSource, without], from: source.id, to: target.id)

        let session = try #require(changed.first)
        #expect(changed.count == 1)
        #expect(session.id == withSource.id)
        #expect(session.entries.map(\.exerciseID) == [target.id, other, target.id])
        #expect(session.entries.map(\.sets) == withSource.entries.map(\.sets))
    }

    @Test func targetKeepsItsDataAndGainsTheSourceNamesAsAliases() {
        let merged = ExerciseMerge.absorbing(source, into: target)
        #expect(merged.id == target.id)
        #expect(merged.name == target.name)
        #expect(merged.primaryMuscles == [.chest])
        #expect(merged.aliases == ["press inclinado con barra", "Press banca inclinado", "Incline press"])
    }

    @Test func aliasesAreNotDuplicatedIgnoringCaseAndAccents() {
        let duplicate = Exercise(name: "PRESS INCLINADO CON BARRA", primaryMuscles: [], aliases: ["incline bench press (barbell)"])
        #expect(ExerciseMerge.absorbing(duplicate, into: target).aliases == target.aliases)
    }
}

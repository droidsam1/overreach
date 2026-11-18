import Domain
import Foundation
import Testing

@Suite("Routine")
struct RoutineTests {
    private let squat = UUID()
    private let press = UUID()
    private let row = UUID()

    @Test func keepsOrderAndDropsRepeats() {
        var routine = Routine(name: "Full body", exerciseIDs: [squat, press, squat])
        #expect(routine.exerciseIDs == [squat, press])
        routine.setExercises([row, row, squat])
        #expect(routine.exerciseIDs == [row, squat])
    }

    @Test func comesFromAPastSession() {
        let session = StrengthSession(
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 0),
            entries: [
                ExerciseEntry(exerciseID: press), ExerciseEntry(exerciseID: row), ExerciseEntry(exerciseID: press),
            ],
            focus: .strength
        )
        let routine = Routine(from: session)
        #expect(routine.name == "Push")
        #expect(routine.focus == .strength)
        #expect(routine.exerciseIDs == [press, row])
        #expect(routine.id != session.id)
    }

    @Test func mergingRepointsOnlyTheRoutinesThatUseTheSource() {
        let usesBoth = Routine(name: "A", exerciseIDs: [squat, press, row])
        let usesSource = Routine(name: "B", exerciseIDs: [squat])
        let unrelated = Routine(name: "C", exerciseIDs: [row])

        let changed = ExerciseMerge.repoint([usesBoth, usesSource, unrelated], from: squat, to: press)

        #expect(changed.map(\.id) == [usesBoth.id, usesSource.id])
        #expect(changed[0].exerciseIDs == [press, row])  // the target is not repeated
        #expect(changed[1].exerciseIDs == [press])
    }
}

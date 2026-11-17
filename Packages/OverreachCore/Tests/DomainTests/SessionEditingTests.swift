import Domain
import Foundation
import Testing

@Suite("Session editing")
struct SessionEditingTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = UUID()
    private let row = UUID()

    private func session() -> StrengthSession {
        StrengthSession(
            name: "Lower A",
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            entries: [
                ExerciseEntry(exerciseID: squat, sets: [
                    WorkoutSet(kind: .warmup, weightKg: 60, reps: 5, completedAt: start.addingTimeInterval(300)),
                    WorkoutSet(weightKg: 100, reps: 5, rpe: 8, completedAt: start.addingTimeInterval(900)),
                ]),
                ExerciseEntry(exerciseID: row, sets: [
                    WorkoutSet(weightKg: 70, reps: 10, completedAt: start.addingTimeInterval(2_400)),
                ]),
            ]
        )
    }

    @Test func movingTheStartKeepsDurationAndSetTimes() {
        let dayEarlier = start.addingTimeInterval(-86_400)
        let moved = session().movingStart(to: dayEarlier)

        #expect(moved.startedAt == dayEarlier)
        #expect(moved.durationSeconds == 3_600)
        #expect(moved.entries[0].sets[1].completedAt == dayEarlier.addingTimeInterval(900))
        #expect(moved.entries[1].sets[0].completedAt == dayEarlier.addingTimeInterval(2_400))
    }

    @Test func cleaningDropsEmptySetsAndExercisesAndTrimsTexts() {
        var edited = session()
        edited.name = "  Lower A (corrected) "
        edited.notes = "   "
        edited.entries[0].sets.append(WorkoutSet())
        edited.entries[1].sets = [WorkoutSet(rpe: 8)]  // an RPE alone is not a set
        edited.entries[1].notes = " felt heavy "

        let cleaned = edited.cleanedForSaving()

        #expect(cleaned.name == "Lower A (corrected)")
        #expect(cleaned.notes == nil)
        #expect(cleaned.entries.map(\.exerciseID) == [squat])
        #expect(cleaned.entries[0].sets.count == 2)
        #expect(cleaned.id == edited.id)
    }

    @Test func aValidSessionHasNoIssues() {
        #expect(session().editIssues.isEmpty)
    }

    @Test func reportsWhatPreventsSaving() {
        var edited = session()
        edited.name = " "
        edited.endedAt = start.addingTimeInterval(-60)
        edited.entries = [ExerciseEntry(exerciseID: squat, sets: [WorkoutSet()])]

        #expect(Set(edited.editIssues) == [.missingName, .noSets, .endsBeforeStart])
    }

    @Test func rejectsImplausibleValues() {
        var negative = session()
        negative.entries[0].sets[1].weightKg = -100
        #expect(negative.editIssues == [.invalidValues])

        var rpe = session()
        rpe.entries[1].sets[0].rpe = 11
        #expect(rpe.editIssues == [.invalidValues])
    }
}

import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("Session summary")
struct SessionSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    @Test func finishingShowsHowTheSessionWent() async throws {
        let earlier = StrengthSession(
            name: "Workout", startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [9, 9, 9].map { WorkoutSet(weightKg: 60, reps: $0, rpe: 8) })]
        )
        let store = TestStore(exercises: [bench], sessions: [earlier])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await model.load()
        model.start()
        await model.add(exerciseID: bench.id)
        for index in model.exercises[0].sets.indices where !model.exercises[0].sets[index].isWarmUp {
            model.exercises[0].sets[index].reps = 11
            model.exercises[0].sets[index].rpe = 9.5
            model.exercises[0].sets[index].isDone = true
        }

        #expect(await model.finish())

        let summary = try #require(model.summary)
        #expect(summary.title == "Workout")
        #expect(summary.headline.contains("3 working sets"))
        #expect(summary.adherence == "On target or better in 1 of 1 exercises.")
        #expect(summary.comparison?.hasPrefix("Volume +22 % compared with the last “Workout”") == true)
        #expect(summary.achievement?.hasPrefix("Bench Press: New best estimated 1RM:") == true)
        let row = try #require(summary.rows.first)
        #expect(row.outcome == .above)
        #expect(row.outcomeText == "Above target: 60 kg × 11/11/11 vs 60 kg × 9/9/9")
        #expect(row.details.contains("Harder than planned: RPE 9.5 vs RPE 8."))
        #expect(row.details.contains { $0.hasPrefix("New best estimated 1RM:") })
        #expect(row.details.last?.hasPrefix("Next time: 60 kg × 12/12/12") == true)
        #expect(summary.shareText.contains("• Bench Press: Above target"))

        model.summary = nil
        #expect(model.summary == nil)
    }
}

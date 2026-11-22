import Analytics
import Domain
import Foundation
import Testing
import TrainingServices

@Suite("Training done today")
struct DayTrainingTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = CalendarDay(year: 2026, month: 11, day: 20).startDate(in: Calendar(identifier: .gregorian))
        .addingTimeInterval(15 * 3_600)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func session(_ exercise: Exercise, hoursAgo: Double, sets: Int = 4) -> StrengthSession {
        let start = now.addingTimeInterval(-hoursAgo * 3_600)
        return StrengthSession(
            name: "S", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(
                exerciseID: exercise.id, sets: Array(repeating: WorkoutSet(weightKg: 100, reps: 5, rpe: 7), count: sets)
            )]
        )
    }

    private func run(hoursAgo: Double, minutes: Double = 30) -> RunActivity {
        RunActivity(
            id: "r", source: .appleHealth, startedAt: now.addingTimeInterval(-hoursAgo * 3_600),
            durationSeconds: minutes * 60, distanceMeters: 5_000
        )
    }

    private func assess(
        sessions: [StrengthSession] = [], runs: [RunActivity] = [], planned: [PlannedRun] = []
    ) -> DayTraining {
        DayTraining.assess(
            sessions: sessions, recordings: [], runs: runs, planned: planned, exercises: [squat, bench],
            now: now, calendar: calendar
        )
    }

    @Test func aRestDayHoldsNothingBack() {
        let training = assess()
        #expect(!training.hasTrained)
        #expect(!training.holdsBackUnplannedRun)
    }

    @Test func upperBodyStrengthTodayCountsAndHoldsBackARun() {
        let training = assess(sessions: [session(bench, hoursAgo: 3)])
        #expect(training.hasStrength && !training.hasRun)
        #expect(training.lowerBody == .none)
        #expect(training.holdsBackUnplannedRun)
    }

    @Test func legsTodayAreSharedWithTheRunRule() {
        let training = assess(sessions: [session(squat, hoursAgo: 3)])
        #expect(training.lowerBody == .today)
        #expect(training.holdsBackUnplannedRun)
    }

    @Test func aRunFinishedTodayCountsButAnOldOneDoesNot() {
        #expect(assess(runs: [run(hoursAgo: 4)]).hasRun)
        #expect(!assess(runs: [run(hoursAgo: 20)]).hasRun)
    }

    @Test func aCompletedPlannedRunCounts() {
        let run = run(hoursAgo: 3)
        let planned = PlannedRun(
            day: CalendarDay(now, calendar: calendar), purpose: .easy,
            completion: PlannedRunCompletion(run)
        )
        #expect(assess(planned: [planned]).hasRun)
    }

    @Test func heavyLegsYesterdayHoldBackARunWithoutTrainingToday() {
        let training = assess(sessions: [session(squat, hoursAgo: 24, sets: 8)])
        #expect(!training.hasTrained)
        #expect(training.lowerBody == .yesterdayHeavy)
        #expect(training.holdsBackUnplannedRun)
    }
}

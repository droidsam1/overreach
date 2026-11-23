import Domain
import Foundation
import Testing

@testable import Analytics

@Suite("Rotation projection and run windows")
struct RotationProjectionTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 20)
    private var now: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3_600) }
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let deadlift = Exercise(name: "Deadlift", primaryMuscles: [.hamstrings], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private var exercises: [Exercise] { [squat, deadlift, bench] }

    private struct Workout {
        let routine = UUID()
        let name: String
        let exercise: Exercise
        var sets = 5
        var reps = 5
    }

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }

    private func session(_ workout: Workout, on offset: Int) -> StrengthSession {
        let start = day(offset).startDate(in: calendar).addingTimeInterval(8 * 3_600)
        return StrengthSession(
            name: workout.name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(
                exerciseID: workout.exercise.id,
                sets: Array(repeating: WorkoutSet(weightKg: 100, reps: workout.reps, rpe: 7), count: workout.sets)
            )],
            routineID: workout.routine
        )
    }

    /// `workouts` repeated in order every `gaps` days, the last one on `lastOffset`.
    private func history(_ workouts: [Workout], cycles: Int = 2, gaps: [Int], lastOffset: Int) -> [StrengthSession] {
        let order = Array(repeating: workouts, count: cycles).flatMap { $0 }
        var offset = lastOffset
        var sessions: [StrengthSession] = []
        for (index, workout) in order.enumerated().reversed() {
            sessions.append(session(workout, on: offset))
            offset -= gaps[index % gaps.count]
        }
        return sessions
    }

    private var fourDay: [Workout] {
        [Workout(name: "A", exercise: squat), Workout(name: "B", exercise: bench),
         Workout(name: "C", exercise: deadlift), Workout(name: "D", exercise: bench)]
    }

    private func project(_ sessions: [StrengthSession]) -> RotationProjection? {
        RotationProjection.project(sessions: sessions, exercises: exercises, now: now, calendar: calendar)
    }

    @Test func fourRoutinesOnAlternateDaysScoreEachRestDayAndWrapAround() throws {
        let workouts = fourDay
        let projection = try #require(project(history(workouts, gaps: [2], lastOffset: -1)))
        #expect(projection.cadenceDays == 2)
        #expect(projection.upcoming.map(\.day) == [day(1), day(3), day(5), day(7)])
        #expect(projection.upcoming.map(\.demand) == [.heavy, .none, .heavy, .none])
        let slot = { (index: Int) in projection.upcoming[index].slot }
        #expect(projection.runWindows(from: today, calendar: calendar) == [
            .init(day: day(0), quality: .good, reason: .beforeHeavyLower(slot(0))),
            .init(day: day(2), quality: .avoid, reason: .afterHeavyLower(slot(0))),
            .init(day: day(4), quality: .good, reason: .beforeHeavyLower(slot(2))),
            .init(day: day(6), quality: .avoid, reason: .afterHeavyLower(slot(2))),
            // Day 9 of the cycle is A again.
            .init(day: day(8), quality: .good, reason: .beforeHeavyLower(slot(0))),
        ])
    }

    @Test func aLighterLegDayTurnsTheRestDayBeforeItIntoTheBestWindow() throws {
        var workouts = fourDay
        workouts[0].reps = 10
        workouts[0].sets = 3
        let projection = try #require(project(history(workouts, gaps: [2], lastOffset: -1)))
        let windows = projection.runWindows(from: today, calendar: calendar)
        #expect(windows.first == .init(day: day(0), quality: .best, reason: .awayFromLowerBody))
        let legs = projection.upcoming[0].slot
        #expect(windows[1] == .init(day: day(2), quality: .good, reason: .afterModerateLower(legs)))
    }

    @Test func threeRoutinesEveryThirdDay() throws {
        let workouts = [Workout(name: "Legs", exercise: squat), Workout(name: "Push", exercise: bench),
                        Workout(name: "Pull", exercise: bench)]
        let projection = try #require(project(history(workouts, gaps: [3], lastOffset: 0)))
        #expect(projection.cadenceDays == 3)
        #expect(projection.upcoming.map(\.slot.name) == ["Legs", "Push", "Pull"])
        let windows = projection.runWindows(from: today, calendar: calendar)
        // Between Pull (today) and Legs: the second rest day is the day before the leg session.
        #expect(windows.prefix(2) == [
            .init(day: day(1), quality: .best, reason: .awayFromLowerBody),
            .init(day: day(2), quality: .good, reason: .beforeHeavyLower(projection.upcoming[0].slot)),
        ])
        let legs = projection.upcoming[0].slot
        #expect(windows[2] == .init(day: day(4), quality: .avoid, reason: .afterHeavyLower(legs)))
    }

    @Test func irregularCadenceOrAMissedSessionProjectsNothing() {
        #expect(project(history(fourDay, gaps: [2, 3, 1, 2], lastOffset: -1)) == nil)
        #expect(project(history(fourDay, gaps: [2], lastOffset: -3)) == nil)
        #expect(project(Array(history(fourDay, gaps: [2], lastOffset: -1).prefix(5))) == nil)
    }

    // MARK: Easy run advice

    private func advice(rotation: RotationProjection?, strength: [PlannedStrength] = []) -> EasyRunAdvisor.Decision? {
        var metrics = DailyMetrics(day: today)
        metrics.sleepSeconds = 8 * 3_600
        let run = RunActivity(id: "1", source: .garmin, startedAt: now.addingTimeInterval(-2 * 86_400),
                              durationSeconds: 40 * 60, distanceMeters: 6_000)
        return EasyRunAdvisor.advise(
            goal: RunningGoal(distanceMeters: 5_000, targetSeconds: 1_500), targetDay: nil, schedule: [],
            readiness: Readiness(level: .green, reasons: []), metrics: metrics, runs: [run], now: now,
            calendar: calendar, strength: strength, rotation: rotation
        )
    }

    @Test func theProjectedLegDayTomorrowKeepsTodaysRunShort() throws {
        let projection = try #require(project(history(fourDay, gaps: [2], lastOffset: -1)))
        #expect(advice(rotation: nil) == .example(minutes: 30, plan: nil, isToday: false, recentRuns: 1))
        #expect(advice(rotation: projection) == .example(minutes: 15, plan: nil, isToday: false, recentRuns: 1))
    }

    @Test func aDatedPlanWinsOverTheProjection() throws {
        let projection = try #require(project(history(fourDay, gaps: [2], lastOffset: -1)))
        let dated = PlannedStrength(day: day(3), routineID: UUID())
        #expect(advice(rotation: projection, strength: [dated])
            == .example(minutes: 30, plan: nil, isToday: false, recentRuns: 1))
    }

    @Test func anUpperBodySessionTomorrowDoesNotLimitTheRun() throws {
        let workouts = [fourDay[1], fourDay[0], fourDay[3], fourDay[2]]
        let projection = try #require(project(history(workouts, gaps: [2], lastOffset: -1)))
        #expect(projection.upcoming[0].demand == .none)
        #expect(advice(rotation: projection) == .example(minutes: 30, plan: nil, isToday: false, recentRuns: 1))
    }

    private func offsets(_ workouts: [Workout], _ days: [Int]) -> [StrengthSession] {
        zip(workouts, days).map { session($0, on: $1) }
    }

    @Test func aRecordedSwapKeepsTheProjectionAndTheOriginalOrderResumes() throws {
        let lifts = fourDay
        let order = [0, 1, 2, 3, 0, 2, 1, 3, 0, 1, 2, 3].map { lifts[$0] }
        let sessions = offsets(order, (0..<12).map { -23 + 2 * $0 })
        #expect(project(sessions) == nil)
        let swap = RotationAdjustment(
            day: day(-13), kind: .swap(from: lifts[1].routine.uuidString, to: lifts[2].routine.uuidString),
            reason: .runCarryover
        )
        let projection = try #require(RotationProjection.project(
            sessions: sessions, exercises: exercises, now: now, calendar: calendar, adjustments: [swap]
        ))
        #expect(projection.upcoming.map(\.day) == [day(1), day(3), day(5), day(7)])
        #expect(projection.upcoming.map(\.slot.name) == ["A", "B", "C", "D"])
    }

    @Test func aRecordedPostponementShiftsTheProjectionInsteadOfDroppingIt() throws {
        let lifts = fourDay
        let order = lifts + lifts
        let sessions = offsets(order, [-16, -14, -12, -10, -8, -6, -3, -1])
        #expect(project(sessions) == nil)
        let postponement = RotationAdjustment(day: day(-4), kind: .postpone(days: 1))
        let projection = try #require(RotationProjection.project(
            sessions: sessions, exercises: exercises, now: now, calendar: calendar, adjustments: [postponement]
        ))
        #expect(projection.cadenceDays == 2)
        #expect(projection.upcoming.map(\.day) == [day(1), day(3), day(5), day(7)])
    }

    @Test func aPostponementAcceptedForTheNextSessionShiftsItsDay() throws {
        let sessions = history(fourDay, gaps: [2], lastOffset: -1)
        let postponement = RotationAdjustment(day: day(1), kind: .postpone(days: 1))
        let projection = try #require(RotationProjection.project(
            sessions: sessions, exercises: exercises, now: now, calendar: calendar, adjustments: [postponement]
        ))
        #expect(projection.upcoming.map(\.day) == [day(2), day(4), day(6), day(8)])
    }

    @Test func aHalfDoneSwapProjectsThePlannedSecondWorkoutNext() throws {
        let lifts = fourDay
        let order = [lifts[0], lifts[1], lifts[2], lifts[3], lifts[0], lifts[1], lifts[2], lifts[3], lifts[0], lifts[2]]
        let sessions = offsets(order, (0..<10).map { -19 + 2 * $0 })
        let swap = RotationAdjustment(
            day: day(-1), kind: .swap(from: lifts[1].routine.uuidString, to: lifts[2].routine.uuidString)
        )
        let projection = try #require(RotationProjection.project(
            sessions: sessions, exercises: exercises, now: now, calendar: calendar, adjustments: [swap]
        ))
        #expect(projection.upcoming.map(\.slot.name) == ["B", "D", "A", "B"])
    }
}

import Domain
import Foundation
import Testing

@testable import Analytics

@Suite("Lower-body load")
struct LowerBodyLoadTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = CalendarDay(year: 2026, month: 11, day: 20).startDate(in: Calendar(identifier: .gregorian))
        .addingTimeInterval(15 * 3_600)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func session(_ exercise: Exercise, hoursAgo: Double, sets: Int = 4, rpe: Double = 7) -> StrengthSession {
        let start = now.addingTimeInterval(-hoursAgo * 3_600)
        return StrengthSession(
            name: "S", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(
                exerciseID: exercise.id,
                sets: Array(repeating: WorkoutSet(weightKg: 100, reps: 5, rpe: rpe), count: sets)
            )]
        )
    }

    private func level(_ sessions: [StrengthSession]) -> LowerBodyLoad.Level {
        LowerBodyLoad.assess(sessions: sessions, exercises: [squat, bench], now: now, calendar: calendar)
    }

    @Test func legsToday() {
        #expect(level([session(squat, hoursAgo: 4)]) == .today)
    }

    @Test func heavyLegsYesterdayByVolumeOrEffort() {
        #expect(level([session(squat, hoursAgo: 24, sets: 8)]) == .yesterdayHeavy)
        #expect(level([session(squat, hoursAgo: 24, sets: 3, rpe: 9)]) == .yesterdayHeavy)
    }

    @Test func lightLegsYesterdayIsNoConflict() {
        #expect(level([session(squat, hoursAgo: 24, sets: 3)]) == .none)
    }

    @Test func upperBodyOnlyOrOlderSessionsAreNoConflict() {
        #expect(level([session(bench, hoursAgo: 4, sets: 10, rpe: 10)]) == .none)
        #expect(level([session(squat, hoursAgo: 60, sets: 10, rpe: 10)]) == .none)
    }

    @Test func todayWinsOverYesterday() {
        #expect(level([session(squat, hoursAgo: 24, sets: 8), session(squat, hoursAgo: 4)]) == .today)
    }
}

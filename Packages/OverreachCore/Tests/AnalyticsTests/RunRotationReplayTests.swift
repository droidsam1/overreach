import Domain
import Foundation
import Testing

@testable import Analytics

@Suite("Historical run-to-strength decision replay")
struct RunRotationReplayTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let legs = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let torso = Exercise(name: "Bench", primaryMuscles: [.chest], equipment: .barbell)

    private func history(order: String, gaps: [Int], endingOn day: CalendarDay) -> [StrengthSession] {
        let offsets = gaps.reversed().reduce(into: [0]) { $0.append(($0.last ?? 0) - $1) }.reversed()
        return zip(order, offsets).map { slot, offset in
            let start = day.adding(days: offset, calendar: calendar).startDate(in: calendar)
            let exercise = slot == "D" ? torso : legs
            let sets = (0..<3).map { _ in WorkoutSet(weightKg: 60, reps: 5) }
            return StrengthSession(
                name: String(slot), startedAt: start, endedAt: start.addingTimeInterval(3_600),
                entries: [ExerciseEntry(exerciseID: exercise.id, sets: sets)]
            )
        }
    }

    @Test(arguments: ["CDABCDAB", "DABCDABC", "ABCDABCD"])
    func irregularCadenceKeepsTheOrderButBlocksTheDatedRecommendation(order: String) {
        let day = CalendarDay(year: 2000, month: 4, day: 18)
        let sessions = history(order: order, gaps: [2, 2, 3, 2, 2, 2, 2], endingOn: day)
        let expectedNext: [Character: String] = ["B": "C", "C": "D", "D": "A"]
        let pending = SessionRotation.detect(in: sessions, calendar: calendar)?.next.name
        #expect(pending == order.last.flatMap { expectedNext[$0] })
        #expect(RotationProjection.project(
            sessions: sessions, exercises: [legs, torso], now: day.startDate(in: calendar), calendar: calendar
        ) == nil)
    }

    @Test(arguments: ["ABCDABCC", "DABCCDAB"])
    func aRepeatedSlotLeavesTheOrderUnproven(order: String) {
        let day = CalendarDay(year: 2000, month: 5, day: 18)
        let sessions = history(order: order, gaps: Array(repeating: 2, count: 7), endingOn: day)
        #expect(SessionRotation.detect(in: sessions, calendar: calendar) == nil)
    }

    @Test func stableCadenceKeepsTheLegSessionWhenTimingIsTheOnlySignal() throws {
        let day = CalendarDay(year: 2000, month: 6, day: 20)
        let now = day.startDate(in: calendar).addingTimeInterval(12 * 3_600)
        let run = RunActivity(
            id: "current", source: .garmin, startedAt: now.addingTimeInterval(-20.5 * 3_600),
            durationSeconds: 1_800, distanceMeters: 3_000, aerobicTrainingEffect: 2.5
        )
        let earlier = RunActivity(
            id: "prior", source: .garmin, startedAt: now.addingTimeInterval(-7 * 86_400),
            durationSeconds: 1_800, distanceMeters: 3_000
        )
        let assessment = RunCarryover.assessment(
            run: run, recentRuns: [earlier], checkIn: nil, nextSessionStart: now
        )
        #expect(assessment.reasons == [.close])
        #expect(assessment.level == .light)
        let lastDay = day.adding(days: -2, calendar: calendar)
        let plans = ["CDABCDAB", "DABCDABC"].map {
            let sessions = history(
                order: $0, gaps: Array(repeating: 2, count: 7), endingOn: lastDay
            )
            return RotationProjection.project(
                sessions: sessions, exercises: [legs, torso], now: now, calendar: calendar
            )
        }
        let legPlan = try #require(plans[0])
        let torsoPlan = try #require(plans[1])
        let legSlot = try #require(legPlan.upcoming.first?.slot)
        let torsoSlot = try #require(torsoPlan.upcoming.first?.slot)
        #expect(legSlot.name == "C")
        #expect(torsoSlot.name == "D")
        let suggestion = { (plan: RotationProjection) in
            RotationAdjustment.suggest(
                projection: plan, carryover: assessment.level, readiness: .unknown,
                previousLegSession: nil, runDay: CalendarDay(run.startedAt, calendar: calendar),
                recorded: [], calendar: calendar
            )
        }
        #expect(suggestion(legPlan)?.action == .keep)
        #expect(suggestion(legPlan)?.reasons.isEmpty == true)
        #expect(suggestion(torsoPlan) == nil)
    }
}

import Analytics
import Domain
import Foundation
import Testing

@Suite("Unplanned deloads")
struct DeloadDetectionTests {
    private let origin = CalendarDay(year: 2025, month: 1, day: 1)
    private let lift = UUID()
    private var calendar: Calendar { Calendar(identifier: .iso8601) }

    private func day(_ offset: Int) -> CalendarDay {
        origin.adding(days: offset, calendar: calendar)
    }

    private func session(_ offset: Int, weight: Double = 80, rpe: Double? = 8, routine: UUID? = nil) -> StrengthSession {
        StrengthSession(
            name: "Strength", startedAt: day(offset).startDate(in: calendar),
            entries: [ExerciseEntry(
                exerciseID: lift, sets: (0..<3).map { _ in WorkoutSet(weightKg: weight, reps: 8, rpe: rpe) }
            )],
            routineID: routine
        )
    }

    private func run(_ offset: Int, minutes: Double = 50, effect: Double? = 3.5) -> RunActivity {
        RunActivity(
            id: String(offset), source: .appleHealth, startedAt: day(offset).startDate(in: calendar),
            durationSeconds: minutes * 60, distanceMeters: minutes * 150, aerobicTrainingEffect: effect
        )
    }

    @Test func aBreakSpansWeekBoundariesAndResetsThePlan() throws {
        let sessions = (0...20).map { session($0 * 3) } + [session(77)]
        let profile = AthleteProfile(declaredBlocks: [
            TrainingBlock(focus: .hypertrophy, start: day(0), plannedWeeks: 20, isDeclared: true),
        ])
        let now = day(78).startDate(in: calendar)
        let analysis = PlanAnalysis.run(
            profile: profile, sessions: sessions, exercises: [:], settings: [:], now: now, calendar: calendar
        )
        let period = try #require(analysis.deloads.last)
        #expect(analysis.deloads.count == 1)
        #expect(period.start == day(61))
        #expect(period.end == day(76))
        #expect(period.reason == .noTraining)
        #expect(!period.needsConfirmation)
        #expect(analysis.weeksSinceDeload == 0)
        #expect(analysis.plan.first?.isDeload == false)
        #expect(BlockAdvisor.plan(goal: nil, current: analysis.currentBlock, today: day(78)).first?.isDeload == true)
    }

    @Test func waitsForSevenCompleteDays() {
        let sessions = [session(22), session(25), session(28), session(32)]
        let before = DeloadDetection.periods(sessions: sessions, runs: [], profile: .init(), today: day(39))
        let after = DeloadDetection.periods(sessions: sessions, runs: [], profile: .init(), today: day(40))
        #expect(before.isEmpty)
        #expect(after.first?.start == day(33))
        #expect(after.first?.end == day(39))
    }

    @Test func lightRunsCountButHardRunsOrUsualRunningVolumeDoNot() {
        let history = [21, 23, 25, 28, 30, 32].map { run($0) }
        let easy = DeloadDetection.periods(
            sessions: [], runs: history + [run(35, minutes: 25, effect: 2)], profile: .init(), today: day(40)
        )
        #expect(easy.last?.reason == .easyRuns)
        #expect(easy.last?.needsConfirmation == false)
        let hard = DeloadDetection.periods(
            sessions: [], runs: history + [run(35, minutes: 25)], profile: .init(), today: day(40)
        )
        #expect(hard.isEmpty)
        let usual = DeloadDetection.periods(
            sessions: [], runs: (history + [run(35), run(37), run(39)]).map {
                var run = $0
                run.aerobicTrainingEffect = 2
                return run
            }, profile: .init(), today: day(40)
        )
        #expect(usual.isEmpty)
    }

    @Test func comparesLiftingLoadsAgainstTheRoutineTarget() {
        let routine = Routine(name: "Lower", exerciseIDs: [lift], prescriptions: [
            RoutinePrescription(exerciseID: lift, scheme: .linearLoad(sets: 3, reps: 8, targetRPE: 8)),
        ])
        let history = (0...4).map { session($0 * 7, routine: routine.id) }
        let light = session(35, weight: 30, rpe: nil, routine: routine.id)
        let periods = DeloadDetection.periods(
            sessions: history + [light], runs: [], profile: .init(), routines: [routine], today: day(42)
        )
        #expect(periods.last?.reason == .reducedStrength)
        #expect(periods.last?.needsConfirmation == false)
        let withHardRun = DeloadDetection.periods(
            sessions: history + [light], runs: [run(38)], profile: .init(), routines: [routine], today: day(42)
        )
        #expect(withHardRun.last?.end == day(37))
        let noRecovery = DeloadDetection.periods(
            sessions: history + [light], runs: [run(35)], profile: .init(), routines: [routine], today: day(42)
        )
        #expect(noRecovery.isEmpty)
    }

    @Test func missingRunningDataRequiresAStoredDecision() throws {
        let sessions = [session(22), session(25), session(28), session(32)]
        var profile = AthleteProfile(goal: TrainingGoal(kind: .hybrid))
        let now = day(40).startDate(in: calendar)
        func analyse() -> PlanAnalysis {
            PlanAnalysis.run(profile: profile, sessions: sessions, exercises: [:], settings: [:], now: now, calendar: calendar)
        }
        let period = try #require(analyse().deloads.last)
        #expect(period.needsConfirmation)
        #expect(analyse().weeksSinceDeload == nil)
        profile.deloadDecisions = [
            DeloadDecision(start: period.start, end: period.end, reason: period.reason, accepted: false),
        ]
        #expect(analyse().deloads.isEmpty)
        profile.deloadDecisions = [
            DeloadDecision(start: period.start, end: period.end, reason: period.reason, accepted: true),
        ]
        profile = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(profile))
        #expect(analyse().deloads.last?.needsConfirmation == false)
        #expect(analyse().weeksSinceDeload == 0)
    }
}

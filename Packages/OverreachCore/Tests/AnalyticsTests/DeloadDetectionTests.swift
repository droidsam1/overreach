import Analytics
import Domain
import Foundation
import Testing

@Suite("Unplanned deloads")
struct DeloadDetectionTests {
    private let origin = CalendarDay(year: 2025, month: 1, day: 1)
    private let lift = UUID()
    private let legacy = AthleteProfile(countsBreaksAutomatically: false)
    private var calendar: Calendar { Calendar(identifier: .iso8601) }

    private func day(_ offset: Int) -> CalendarDay {
        origin.adding(days: offset, calendar: calendar)
    }

    private func session(_ offset: Int, weight: Double = 80, rpe: Double? = 8, routine: UUID? = nil) -> StrengthSession {
        let start = day(offset).startDate(in: calendar)
        return StrengthSession(
            name: "Strength", startedAt: start, endedAt: start.addingTimeInterval(3_600),
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
            sessions: [], runs: history + [run(35, minutes: 25, effect: 2)], profile: legacy, today: day(40)
        )
        #expect(easy.last?.reason == .easyRuns)
        #expect(easy.last?.needsConfirmation == false)
        let hard = DeloadDetection.periods(
            sessions: [], runs: history + [run(35, minutes: 25)], profile: legacy, today: day(40)
        )
        #expect(hard.isEmpty)
        let usual = DeloadDetection.periods(
            sessions: [], runs: (history + [run(35), run(37), run(39)]).map {
                var run = $0
                run.aerobicTrainingEffect = 2
                return run
            }, profile: legacy, today: day(40)
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
            sessions: history + [light], runs: [], profile: legacy, routines: [routine], today: day(42)
        )
        #expect(periods.last?.reason == .reducedStrength)
        #expect(periods.last?.needsConfirmation == false)
        let withHardRun = DeloadDetection.periods(
            sessions: history + [light], runs: [run(38)], profile: legacy, routines: [routine], today: day(42)
        )
        #expect(withHardRun.last?.end == day(37))
        let noRecovery = DeloadDetection.periods(
            sessions: history + [light], runs: [run(35)], profile: legacy, routines: [routine], today: day(42)
        )
        #expect(noRecovery.isEmpty)
    }

    @Test func runningDoesNotInterruptAStrengthBreak() throws {
        let sessions = [session(0), session(8), session(16), session(24)]
        let runs = [24, 27, 30, 32].map { run($0) }
        let today = day(33)
        let periods = DeloadDetection.periods(
            sessions: sessions, runs: runs, profile: .init(), today: today, calendar: calendar
        )
        let latest = try #require(periods.last)
        #expect(latest.discipline == .strength)
        #expect(latest.start == day(25))
        #expect(latest.end == day(32))
        #expect(!latest.needsConfirmation)
        #expect(latest.evidence.key == "training-breaks")
        #expect(!periods.contains { $0.discipline == .running })
        #expect(RecoveryHistory.lastRecovery(deloads: [], detected: periods, before: today)?.lastDay == day(32))
    }

    @Test func aWatchWorkoutOccupiesBothDaysWhenItCrossesMidnight() throws {
        let watch = RecordedStrengthActivity(
            id: "watch", source: .garmin, startedAt: day(1).startDate(in: calendar).addingTimeInterval(-1_800),
            durationSeconds: 3_600
        )
        let periods = DeloadDetection.periods(
            sessions: [], runs: [], profile: .init(), recordings: [watch], today: day(500), calendar: calendar
        )
        let period = try #require(periods.first)
        #expect(period.start == day(2))
        #expect(period.end == day(499))
        #expect(period.discipline == .strength)
    }

    @Test func runningBreakNeedsAHistoryOrGoalAndDoesNotCountForStrength() throws {
        let runs = [run(10), run(20)]
        let sessions = [session(20), session(24), session(27), session(31)]
        let today = day(32)
        func periods(_ activities: [RunActivity], profile: AthleteProfile = .init(), failed: Bool = false)
            -> [DetectedDeload] {
            DeloadDetection.periods(
                sessions: sessions, runs: activities, profile: profile, runReadFailed: failed,
                today: today, calendar: calendar
            )
        }
        let detected = periods(runs)
        let period = try #require(detected.last)
        #expect(period.discipline == .running)
        #expect(period.start == day(21))
        #expect(!period.needsConfirmation)
        #expect(RecoveryHistory.lastRecovery(deloads: [], detected: detected, before: today) == nil)
        #expect(periods([run(20)]).isEmpty)
        #expect(periods(runs, failed: true).isEmpty)
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000))
        #expect(periods([run(20)], profile: .init(goal: goal)).last?.discipline == .running)
    }

    @Test func aLegacyDecisionAppliesToBothDisciplines() throws {
        let sessions = [session(20)]
        let runs = [run(10), run(20)]
        let previous = DeloadDecision(start: day(21), end: day(30), reason: .noTraining, accepted: false)
        let profile = AthleteProfile(deloadDecisions: [previous])
        let periods = DeloadDetection.periods(
            sessions: sessions, runs: runs, profile: profile, today: day(32), calendar: calendar
        )
        #expect(periods.isEmpty)
        let json = """
            {"deloadDecisions":[{"start":{"year":2025,"month":1,"day":22},
            "end":{"year":2025,"month":1,"day":31},"reason":"noTraining","accepted":false}]}
            """
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: Data(json.utf8))
        #expect(decoded.countsBreaksAutomatically)
        #expect(decoded.deloadDecisions.first?.discipline == nil)
    }

    @Test func anUnansweredPeriodShowsRecordedActivityAndTypicalWeeklySets() throws {
        var light = session(32, rpe: 6)
        light.entries[0].sets.removeLast(2)
        let sessions = [0, 7, 14, 21, 28, 36].map { session($0) } + [light]
        let recordedRun = run(33, minutes: 20, effect: 2)
        var mirroredRun = recordedRun
        mirroredRun.source = .garmin
        let periods = DeloadDetection.periods(
            sessions: sessions, runs: [recordedRun, mirroredRun], profile: .init(), today: day(37), calendar: calendar
        )
        let period = try #require(periods.first { $0.needsConfirmation })
        let activity = try #require(period.recordedActivity)
        #expect(period.start == day(29))
        #expect(period.end == day(35))
        #expect(activity.strengthSessions == 1)
        #expect(activity.relativeSets == 1.0 / 3)
        #expect(activity.runs == 1)
        #expect(!activity.hasIncompleteRunData)
    }

    @Test func missingRunningDataRequiresAStoredDecision() throws {
        let sessions = [session(22), session(25), session(28), session(32)]
        var profile = AthleteProfile(goal: TrainingGoal(kind: .hybrid), countsBreaksAutomatically: false)
        let now = day(40).startDate(in: calendar)
        func analyse() -> PlanAnalysis {
            PlanAnalysis.run(profile: profile, sessions: sessions, exercises: [:], settings: [:], now: now, calendar: calendar)
        }
        let period = try #require(analyse().deloads.last)
        #expect(period.needsConfirmation)
        #expect(period.recordedActivity?.strengthSessions == 0)
        #expect(period.recordedActivity?.runs == 0)
        #expect(period.recordedActivity?.hasIncompleteRunData == true)
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

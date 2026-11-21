import Analytics
import AIExchange
import AssistantPresentation
import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation
import TrainingServices
import WorkoutPresentation

/// A stalled squat and bench (main lifts) over the last three weeks, and a week of poor recovery.
@MainActor
@Suite("Deload advice on Today")
struct DeloadAdviceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    private var mainLift: ProgressionSettings {
        ProgressionSettings(scheme: .linearLoad(sets: 3, reps: 5, targetRPE: 8), incrementKg: 2.5, isMainLift: true)
    }

    private func session(_ daysAgo: Int, _ weight: Double, _ reps: [Int]) -> StrengthSession {
        let start = now.addingTimeInterval(-Double(daysAgo) * 86_400 - 7_200)
        let sets = reps.map { WorkoutSet(weightKg: weight, reps: $0) }
        return StrengthSession(
            name: "Full body", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: sets), ExerciseEntry(exerciseID: bench.id, sets: sets)]
        )
    }

    private var stalledSessions: [StrengthSession] {
        [
            session(19, 95, [5, 5, 5]), session(16, 97.5, [5, 5, 5]), session(13, 100, [5, 5, 5]),
            session(10, 102.5, [4, 4, 4]), session(7, 102.5, [4, 4, 3]), session(4, 102.5, [4, 3, 3]),
        ]
    }

    /// 60 steady days, then a week of low HRV and short sleep.
    private func metrics(poorWeek: Bool) -> [DailyMetrics] {
        let wobble: [Double] = [0, 4, -3, 6, -5, 2, -1, 5, -4, 3]
        return (0...66).map { offset in
            var day = DailyMetrics(day: today.adding(days: -offset, calendar: calendar), sources: [.appleHealth])
            day.hrvSDNNMs = offset < 7 && poorWeek ? 40 : 55 + wobble[offset % wobble.count]
            day.sleepSeconds = (offset < 7 && poorWeek ? 5.5 : 7.5) * 3_600
            return day
        }
    }

    private func makeAdvice(profile: AthleteProfile = AthleteProfile(), poorWeek: Bool = true) -> DeloadAdvice? {
        let record = TrainingRecord(
            sessions: stalledSessions, exercises: [squat, bench], settings: [squat.id: mainLift, bench.id: mainLift],
            metrics: metrics(poorWeek: poorWeek)
        )
        return advice(for: record, profile: profile)
    }

    private func advice(for record: TrainingRecord, profile: AthleteProfile) -> DeloadAdvice? {
        let assessment = DeloadAssessment.assess(
            today: today, now: now, profile: profile, record: record, calendar: calendar
        )
        return assessment.map { DeloadAdvice.make($0, exercises: record.exercises, calendar: calendar, format: format) }
    }

    @Test func stalledLiftsAndAPoorWeekProposeADeloadWithReasons() throws {
        let advice = try #require(makeAdvice())
        guard case let .proposed(explanation) = advice.state else {
            Issue.record("expected a proposal")
            return
        }
        #expect(explanation.trainingReasons == [
            "2 main lifts have stalled. The stalled exercises are Back Squat, Bench Press.",
        ])
        #expect(explanation.recoveryReasons == [
            "Your 7-day HRV average was below your usual range on 7 of the last 7 days.",
            "Less than 6 h of sleep on 7 of the last 7 nights.",
        ])
        #expect(explanation.evidence.map(\.id) == ["deload-design", "deload-recovery-signals"])
        #expect(explanation.evidence.allSatisfy { !$0.level.isEmpty })
        #expect(explanation.readings.count == 2)
        #expect(explanation.lastRest == "No strength deload or rest period in your logged history.")
        #expect(advice.planText == "Same exercises, half of the working sets, about 10 % less load, RPE 7 at most.")
    }

    /// Eight weeks of training: lighter sessions every 3 days, then the stalled weeks.
    private var longHistory: [StrengthSession] {
        stride(from: 61, through: 22, by: -3).map { session($0, 80, [5, 5, 5]) } + stalledSessions
    }

    private func longAdvice(profile: AthleteProfile) -> [String] {
        let record = TrainingRecord(
            sessions: longHistory, exercises: [squat, bench], settings: [squat.id: mainLift, bench.id: mainLift],
            metrics: metrics(poorWeek: true)
        )
        let advice = advice(for: record, profile: profile)
        guard case let .proposed(explanation) = advice?.state else { return [] }
        return explanation.trainingReasons
    }

    @Test func withoutAnyDeloadTheIntervalSaysHowMuchHistoryThereIs() {
        #expect(longAdvice(profile: AthleteProfile()).contains(
            "No deload or break in the 8 weeks of training logged."
        ))
    }

    @Test func todayAndPlanCountFromTheSameDeload() {
        var profile = AthleteProfile()
        profile.deloads = [DeloadRecord(start: today.adding(days: -15, calendar: calendar), days: 7)]

        let record = TrainingRecord(
            sessions: longHistory, exercises: [squat, bench], settings: [squat.id: mainLift, bench.id: mainLift],
            metrics: metrics(poorWeek: true)
        )
        guard case let .proposed(explanation) = advice(for: record, profile: profile)?.state else {
            Issue.record("expected a proposal")
            return
        }
        let plan = PlanAnalysis.run(
            profile: profile, sessions: longHistory, exercises: [squat.id: squat, bench.id: bench],
            settings: [squat.id: mainLift, bench.id: mainLift], now: now, calendar: calendar
        )

        let lastDay = today.adding(days: -9, calendar: calendar).startDate(in: calendar)
        let date = lastDay.formatted(
            Date.FormatStyle(
                date: .abbreviated, time: .omitted,
                locale: format.locale, calendar: calendar, timeZone: calendar.timeZone
            )
        )
        #expect(explanation.lastRest == "Your last deload week ended on \(date).")
        #expect(!explanation.trainingReasons.contains { $0.contains("weeks since") || $0.contains("No deload") })
        #expect(plan.weeksSinceDeload == 1)
    }

    @Test func aTwentyDayStrengthBreakAllowsFourWeeksToRebuild() throws {
        let runs = stride(from: 43, through: 1, by: -3).map { daysAgo in
            RunActivity(
                id: String(daysAgo), source: .garmin, startedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                durationSeconds: 1_800, distanceMeters: 5_000
            )
        }
        let sessions = [session(43, 100, [5, 5, 5]), session(40, 100, [5, 5, 5])] + stalledSessions
        let profile = AthleteProfile()
        let record = TrainingRecord(
            sessions: sessions, exercises: [squat, bench], settings: [squat.id: mainLift, bench.id: mainLift],
            runs: runs, metrics: metrics(poorWeek: true)
        )
        let plan = PlanAnalysis.run(
            profile: profile, sessions: sessions, exercises: [squat.id: squat, bench.id: bench],
            settings: record.settings, now: now, runs: runs, calendar: calendar
        )
        let period = try #require(plan.deloads.last { $0.discipline == .strength })
        #expect(period.start.adding(days: 19, calendar: calendar) == period.end)
        #expect(RecoveryHistory.isRebuildingStrength(after: period, on: today, calendar: calendar))
        let boundary = period.end.adding(days: 29, calendar: calendar)
        #expect(!RecoveryHistory.isRebuildingStrength(after: period, on: boundary, calendar: calendar))
        #expect(advice(for: record, profile: profile) == nil)
        #expect(advice(for: record, profile: .init(countsBreaksAutomatically: false)) != nil)
    }

    @Test func noProposalInTheWeekAfterAnAcceptedDeload() {
        var profile = AthleteProfile()
        profile.deloads = [DeloadRecord(start: today.adding(days: -10, calendar: calendar), days: 7)]
        #expect(longAdvice(profile: profile).isEmpty)
    }

    @Test(arguments: [false, true])
    func sameRoutineHasTheSameStallStatusAcrossSurfaces(historyIsOld: Bool) async throws {
        let ids = [squat.id, bench.id]
        let exercises = [squat, bench]
        let routine = Routine(
            name: "Full body", exerciseIDs: ids,
            prescriptions: ids.map { RoutinePrescription(exerciseID: $0, scheme: mainLift.scheme) }
        )
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let sessions = stalledSessions.map { original in
            var session = original
            session.routineID = routine.id
            if historyIsOld {
                session.startedAt = session.startedAt.addingTimeInterval(-60 * 86_400)
                session.endedAt = session.endedAt?.addingTimeInterval(-60 * 86_400)
            }
            return session
        }
        let fixedNow = now
        let store = TestStore(exercises: exercises, sessions: sessions, routines: [routine])
        let workout = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await workout.start(routine)
        #expect(workout.exercises.count == 2)
        #expect(workout.exercises.allSatisfy { $0.status.isStalled == !historyIsOld })

        let profile = AthleteProfile()
        let plan = PlanAnalysis.run(
            profile: profile, sessions: sessions, exercises: byID, settings: [:], now: now,
            routines: [routine], calendar: calendar
        )
        #expect(plan.stalledLifts == (historyIsOld ? 0 : 2))

        let pack = ContextPackBuilder.build(
            ContextInput(sessions: sessions, exercises: exercises, routines: [routine]),
            period: today.adding(days: -90, calendar: calendar)...today, now: now, calendar: calendar
        )
        #expect(pack.exerciseTrends.map(\.status) == Array(
            repeating: historyIsOld ? "notEnoughData" : "stalled", count: 2
        ))

        let record = TrainingRecord(
            sessions: sessions, exercises: exercises, settings: [:], routines: [routine],
            metrics: metrics(poorWeek: true)
        )
        let advice = advice(for: record, profile: profile)
        if historyIsOld {
            #expect(advice == nil)
        } else {
            let result = try #require(advice)
            guard case let .proposed(explanation) = result.state else {
                Issue.record("Expected a proposal with two stalled lifts")
                return
            }
            let expected = "2 lifts you train now have stalled. The stalled exercises are Back Squat, Bench Press."
            #expect(explanation.trainingReasons.first == expected)
        }
    }

    @Test func stallsWithGoodRecoveryAreNotEnough() {
        #expect(makeAdvice(poorWeek: false) == nil)
    }

    @Test func extraWalkingCanReinforceAStallBasedDeloadWithAnExplicitReason() throws {
        let sessions = stalledSessions.enumerated().map { index, original in
            var session = original
            session.sessionRPE = 6
            session.endedAt = session.startedAt.addingTimeInterval(index == 5 ? 36 * 60 : 15 * 60)
            return session
        }
        let activity = (-28 ... -1).map { offset in
            let day = today.adding(days: offset, calendar: calendar)
            let duration = offset == -1 ? 150.0 : 30
            let walk = WalkBout(start: day.startDate(in: calendar), durationSeconds: duration * 60, source: .garmin)
            return DailyActivity(day: day, steps: 8_000, walks: [walk])
        }
        func advice(activity: [DailyActivity]) -> DeloadAdvice? {
            let record = TrainingRecord(
                sessions: sessions, exercises: [squat, bench], settings: [squat.id: mainLift, bench.id: mainLift],
                metrics: metrics(poorWeek: false), activity: activity
            )
            return self.advice(for: record, profile: AthleteProfile())
        }

        #expect(advice(activity: []) == nil)
        let result = try #require(advice(activity: activity))
        guard case let .proposed(explanation) = result.state else {
            Issue.record("expected a proposal")
            return
        }
        #expect(explanation.trainingReasons == [
            "2 main lifts have stalled. The stalled exercises are Back Squat, Bench Press.",
            "Strength and extra walking load reached 1.6× your usual week.",
        ])
    }

    @Test func aPostponedProposalStaysHiddenForTheWeek() {
        var profile = AthleteProfile()
        profile.deloadPostponedUntil = today.adding(days: 3, calendar: calendar)
        #expect(makeAdvice(profile: profile) == nil)

        profile.deloadPostponedUntil = today.adding(days: -1, calendar: calendar)
        #expect(makeAdvice(profile: profile) != nil)
    }

    @Test func anAcceptedDeloadShowsTheWeekInProgress() throws {
        var profile = AthleteProfile()
        profile.deloads = [DeloadRecord(start: today.adding(days: -2, calendar: calendar), days: 7)]

        let advice = try #require(makeAdvice(profile: profile))

        #expect(advice.state == .inProgress(
            lastDay: today.adding(days: 4, calendar: calendar).startDate(in: calendar), forLifeStress: false
        ))
    }

    @Test func anAcceptedSteadierWeekKeepsItsPlan() throws {
        var profile = AthleteProfile()
        profile.deloads = [DeloadRecord(start: today, days: 7, forLifeStress: true)]

        let advice = try #require(makeAdvice(profile: profile))

        guard case let .inProgress(_, forLifeStress) = advice.state else {
            Issue.record("Expected a week in progress")
            return
        }
        #expect(forLifeStress)
        #expect(advice.planText.contains("75 %"))
    }

    @Test func aDetectedRestWeekSuppressesTheRepeatProposal() async throws {
        let sessions = stalledSessions.map { original in
            var session = original
            session.startedAt = original.startedAt.addingTimeInterval(-5 * 86_400)
            session.endedAt = original.endedAt?.addingTimeInterval(-5 * 86_400)
            return session
        }
        let store = TestStore(exercises: [squat, bench], sessions: sessions)
        try await store.save(mainLift, for: squat.id)
        try await store.save(mainLift, for: bench.id)
        let model = TodayModel(
            sources: [DayMetrics(days: metrics(poorWeek: true))], profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)
        #expect(model.deloadAdvice == nil)
    }

    @Test(arguments: [false, true])
    func exportedDecisionMatchesTodayAndKeepsPrivateCheckInContextLocal(warningSigns: Bool) async throws {
        let store = TestStore(exercises: [squat, bench], sessions: stalledSessions)
        try await store.save(mainLift, for: squat.id)
        try await store.save(mainLift, for: bench.id)
        let source = DayMetrics(days: metrics(poorWeek: true))
        let checkIns = FixedCheckIn(checkIn: CheckIn(day: today, exerciseWarningSigns: warningSigns))
        let model = TodayModel(
            sources: [source], checkIns: checkIns, profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixedNow = now
        let assistant = AskAIModel(
            workouts: store, exercises: store, progression: store, profiles: store, routines: store,
            checkIns: checkIns, sources: [source], clock: { fixedNow }, calendar: calendar, directory: directory
        )
        await assistant.setPeriod(.fourWeeks)
        let url = try #require(assistant.fileURL)
        let data = try Data(contentsOf: url)
        let pack = try ContextMessage.decode(data)
        #expect(pack.version == 1)
        #expect(pack.dailyMetrics.count == 28)
        #expect(pack.today?.readiness == model.readiness.level.rawValue)
        if warningSigns {
            #expect(model.deloadAdvice == nil)
            #expect(pack.today?.deload.state == "none")
            let json = try #require(String(data: data, encoding: .utf8))
            #expect(!json.contains("exerciseWarningSigns"))
        } else {
            guard case .proposed = model.deloadAdvice?.state else {
                Issue.record("Expected the shared proposal in Today")
                return
            }
            #expect(pack.today?.deload.state == "proposed")
            #expect(pack.today?.deload.signals == ["liftsStalled", "hrvTrendBelowBaseline", "shortSleep"])
        }
    }

    @Test func acceptingRecordsTheDeloadWeekAndPostponingHidesIt() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: stalledSessions)
        try await store.save(mainLift, for: squat.id)
        try await store.save(mainLift, for: bench.id)
        let model = TodayModel(
            sources: [DayMetrics(days: metrics(poorWeek: true))], profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)
        guard case .proposed = model.deloadAdvice?.state else {
            Issue.record("expected a proposal")
            return
        }

        await model.postponeDeload(now: now)
        #expect(model.deloadAdvice == nil)
        #expect(try await store.profile().deloadPostponedUntil == today.adding(days: 6, calendar: calendar))

        await model.acceptDeload(now: now)
        #expect(try await store.profile().deloads == [DeloadRecord(start: today, days: 7)])
        #expect(try await store.profile().deloadPostponedUntil == nil)
        guard case .inProgress = model.deloadAdvice?.state else {
            Issue.record("expected the deload week")
            return
        }
    }

    @Test func theProposalShowsTheNextSessionWithTheDeloadApplied() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: stalledSessions)
        try await store.save(mainLift, for: squat.id)
        try await store.save(mainLift, for: bench.id)
        let model = TodayModel(
            sources: [DayMetrics(days: metrics(poorWeek: true))], profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)
        let session = try #require(model.deloadSession)
        #expect(session.heading == "Next in your rotation: Full body")
        #expect(session.rows.map(\.reference) == ["Last time · 3 × 4 · 102.5 kg", "Last time · 3 × 4 · 102.5 kg"])
        #expect(session.rows.map(\.deload) == ["Deload · 2 × 4 · 92.5 kg", "Deload · 2 × 4 · 92.5 kg"])
        #expect(model.deloadHowTo == "Apply it to every session of the week, starting with the next one:")
    }

    @Test func withoutAKnownNextSessionTheDeloadIsExplainedInGeneral() async throws {
        let names = ["Upper", "Legs", "Gym", "Full body", "Push", "Pull"]
        let sessions = zip(stalledSessions, names).map { original, name in
            var session = original
            session.name = name
            return session
        }
        let store = TestStore(exercises: [squat, bench], sessions: sessions)
        try await store.save(mainLift, for: squat.id)
        try await store.save(mainLift, for: bench.id)
        let model = TodayModel(
            sources: [DayMetrics(days: metrics(poorWeek: true))], profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)

        #expect(model.deloadSession == nil)
        #expect(model.deloadHowTo?.hasPrefix("Every session this week: for example, 4 × 6") == true)
        #expect(model.showsNextSessionInDeload)
        #expect(model.strengthChoices.count == 6)

        let pull = try #require(model.strengthChoices.first { $0.title == "Legs" })
        model.chooseStrengthSession(pull.id)
        #expect(model.deloadSession?.heading == "Your choice: Legs")
    }

    /// A hybrid athlete whose runs could not be read: a week without lifting needs their confirmation (ADR-0029).
    private func breakStore() async throws -> TestStore {
        let sessions = stalledSessions.map { original in
            var session = original
            session.startedAt = original.startedAt.addingTimeInterval(-5 * 86_400)
            session.endedAt = original.endedAt?.addingTimeInterval(-5 * 86_400)
            return session
        }
        let store = TestStore(exercises: [squat, bench], sessions: sessions)
        try await store.save(mainLift, for: squat.id)
        try await store.save(mainLift, for: bench.id)
        try await store.save(AthleteProfile(goal: TrainingGoal(kind: .hybrid), countsBreaksAutomatically: false))
        return store
    }

    @Test func anUnconfirmedBreakIsAskedAboutBeforeProposingADeload() async throws {
        let store = try await breakStore()
        let model = TodayModel(
            sources: [DayMetrics(days: metrics(poorWeek: true))], profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)

        guard case let .confirmBreak(period) = model.deloadAdvice?.state else {
            Issue.record("expected the break question")
            return
        }
        let plan = PlanAnalysis.run(
            profile: try await store.profile(), sessions: try await store.sessions(from: .distantPast, to: now),
            exercises: [:], settings: [:], now: now, calendar: calendar
        )
        #expect(period.start == plan.recentDeloadQuestions.first?.start)
        #expect(period.end == today.adding(days: -1, calendar: calendar))
        #expect(period.details.strength == "Strength sessions: 0.")
        #expect(period.details.running == "Runs recorded: 0. Running data may be incomplete.")
        #expect(model.deloadSession == nil)
        #expect(model.deloadHowTo == nil)

        await model.reviewBreak(accepted: true, now: now)
        #expect(model.deloadAdvice == nil)
        #expect(try await store.profile().deloadDecisions.map(\.accepted) == [true])
    }

    @Test func declaringTheBreakNotARestLetsTheProposalThrough() async throws {
        let store = try await breakStore()
        let model = TodayModel(
            sources: [DayMetrics(days: metrics(poorWeek: true))], profiles: store, workouts: store, exercises: store,
            progression: store, calendar: calendar, format: format
        )
        await model.load(now: now)
        await model.reviewBreak(accepted: false, now: now)

        guard case .proposed = model.deloadAdvice?.state else {
            Issue.record("expected a proposal")
            return
        }
    }
}

private struct DayMetrics: MetricsSource {
    let kind = DataSourceKind.appleHealth
    let days: [DailyMetrics]

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct FixedCheckIn: CheckInRepository {
    let checkIn: CheckIn

    func checkIn(for day: CalendarDay) async throws -> CheckIn? { checkIn.day == day ? checkIn : nil }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] {
        range.contains(checkIn.day) ? [checkIn] : []
    }
    func save(_ checkIn: CheckIn) async throws {}
}

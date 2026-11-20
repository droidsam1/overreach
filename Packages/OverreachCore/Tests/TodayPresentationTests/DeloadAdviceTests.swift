import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

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
        DeloadAdvice.make(
            today: today, now: now, sessions: stalledSessions, exercises: [squat, bench],
            settings: [squat.id: mainLift, bench.id: mainLift], profile: profile,
            history: metrics(poorWeek: poorWeek), checkIns: [], calendar: calendar, format: format
        )
    }

    @Test func stalledLiftsAndAPoorWeekProposeADeloadWithReasons() throws {
        let advice = try #require(makeAdvice())
        guard case let .proposed(reasons) = advice.state else {
            Issue.record("expected a proposal")
            return
        }
        #expect(reasons.map(\.text) == [
            "2 main lifts have stalled.",
            "HRV below your usual range on 7 of the last 7 days.",
            "Less than 6 h of sleep on 7 of the last 7 nights.",
        ])
        #expect(reasons.allSatisfy { !$0.evidence.isEmpty })
        #expect(advice.planText == "Same exercises, half of the working sets, about 10 % less load, RPE 7 at most.")
    }

    @Test func stallsWithGoodRecoveryAreNotEnough() {
        #expect(makeAdvice(poorWeek: false) == nil)
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
            lastDay: today.adding(days: 4, calendar: calendar).startDate(in: calendar)
        ))
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

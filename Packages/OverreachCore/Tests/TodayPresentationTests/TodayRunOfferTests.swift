import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

/// "Good day for an easy run with your dog": a soft offer on a rest day of the strength rotation. It never blocks
/// anything and costs nothing to skip.
@MainActor
@Suite("Today's optional run offer")
struct TodayRunOfferTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    /// A, B, C, D twice on alternate days, the last one `lastDaysAgo` days ago. A and C work the legs.
    private func rotation(lastDaysAgo: Int) -> [StrengthSession] {
        let names = ["A", "B", "C", "D", "A", "B", "C", "D"]
        return names.enumerated().map { index, name in
            let start = now.addingTimeInterval(-Double(lastDaysAgo + (names.count - 1 - index) * 2) * 86_400)
            let exercise = name == "A" || name == "C" ? squat : bench
            return StrengthSession(
                name: name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
                entries: [ExerciseEntry(exerciseID: exercise.id,
                                        sets: Array(repeating: WorkoutSet(weightKg: 100, reps: 6, rpe: 7), count: 4))]
            )
        }
    }

    private func run(daysAgo: Int, minutes: Double = 25) -> RunActivity {
        RunActivity(
            id: "run-\(daysAgo)", source: .garmin, name: "Run",
            startedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            durationSeconds: minutes * 60, distanceMeters: 4_000
        )
    }

    private func model(
        lastDaysAgo: Int = 1, routine: WalkingRoutine = WalkingRoutine(), runs: [RunActivity]? = nil,
        sleepHours: Double = 5, checkIn: CheckInRepository? = nil, answers: DogRunAnswers = DogRunAnswers()
    ) async throws -> TodayModel {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(lastDaysAgo: lastDaysAgo))
        try await store.save(AthleteProfile(walkingRoutine: routine))
        let source = RunOfferSource(day: today, sleepHours: sleepHours, runs: runs ?? [run(daysAgo: 4)])
        let model = TodayModel(
            sources: [source], checkIns: checkIn, profiles: store, workouts: store, exercises: store,
            dogRunAnswers: answers, calendar: calendar, format: format
        )
        await model.load(now: now)
        return model
    }

    @Test func aRestDayWithAGoodWindowOffersAnEasyRunAndAnotherDayIfItDoesNotFit() async throws {
        let model = try await model()
        let offer = try #require(model.runOffer)
        #expect(offer.title == "Good day for an easy run")
        #expect(offer.dismissTitle == "Not today")
        #expect(offer.fallback?.hasPrefix("Not today? ") == true)
        #expect(offer.fallback?.hasSuffix(" also works") == true)
        #expect(!offer.reason.isEmpty)
    }

    @Test func theDogsNameAppearsInTheOffer() async throws {
        let named = try await model(routine: WalkingRoutine(hasDog: true, dogName: " Luna "))
        #expect(named.runOffer?.title == "Good day for an easy run with Luna")
        let unnamed = try await model(routine: WalkingRoutine(hasDog: true))
        #expect(unnamed.runOffer?.title == "Good day for an easy run with your dog")
        let noDog = try await model(routine: WalkingRoutine(hasDog: false, dogName: "Luna"))
        #expect(noDog.runOffer?.title == "Good day for an easy run")
    }

    @Test func confirmedDogRunsPreferALaterUsualWeekday() async throws {
        let runs = [3, 10, 17].map { run(daysAgo: $0) }
        let answers = DogRunAnswers(Dictionary(uniqueKeysWithValues: runs.map { (.init($0), true) }))
        let routine = WalkingRoutine(hasDog: true, dogName: "Luna")
        let baseline = try await model(routine: routine, runs: runs)
        let learned = try await model(routine: routine, runs: runs, answers: answers)
        let weekday = today.adding(days: 4, calendar: calendar).startDate(in: calendar)
        let weekdayStyle = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let fallback = "Not today? \(weekday.formatted(weekdayStyle.weekday(.wide))) also works"
        #expect(baseline.runOffer?.fallback != fallback)
        #expect(learned.runOffer?.fallback == fallback)
        #expect(learned.runOffer?.title == "Good day for an easy run")
    }

    @Test(arguments: [true, false])
    func theOfferUsesTheConfirmedCompanionHistoryForToday(withDog: Bool) async throws {
        let runs = [7, 14, 21].map { run(daysAgo: $0) }
        let answers = DogRunAnswers(Dictionary(uniqueKeysWithValues: runs.map { (.init($0), withDog) }))
        let routine = WalkingRoutine(hasDog: true, dogName: "Luna")
        let learned = try await model(routine: routine, runs: runs, answers: answers)
        let title = withDog ? "Good day for an easy run with Luna" : "Good day for an easy run"
        #expect(learned.runOffer?.title == title)
    }

    @Test func aWindowTomorrowOnlyOffersNothingToday() async throws {
        // The last workout was today: today is a session day, the window comes the day after.
        let model = try await model(lastDaysAgo: 0)
        #expect(model.runOffer == nil)
    }

    @Test func noRotationMeansNoWindowAndNoOffer() async throws {
        let store = TestStore(exercises: [squat, bench])
        let model = TodayModel(
            sources: [RunOfferSource(day: today, sleepHours: 5, runs: [run(daysAgo: 4)])], profiles: store,
            workouts: store, exercises: store, calendar: calendar, format: format
        )
        await model.load(now: now)
        #expect(model.runOffer == nil)
        #expect(model.yourWeek?.days.contains { $0.hasRunWindow } != true)
    }

    @Test func notTodayHidesTheOfferForTheRestOfTheDayAndAReload() async throws {
        let model = try await model()
        #expect(model.runOffer != nil)
        model.dismissRunOffer()
        #expect(model.runOffer == nil)
        await model.load(now: now)
        #expect(model.runOffer == nil)
    }

    @Test func notTodaySurvivesARelaunchTheSameDayButNotTheNextDay() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(lastDaysAgo: 1))
        try await store.save(AthleteProfile())
        var saved: CalendarDay?
        func launch(at date: Date) async -> TodayModel {
            let model = TodayModel(
                sources: [RunOfferSource(day: CalendarDay(date, calendar: calendar), sleepHours: 5,
                                         runs: [run(daysAgo: 4)])],
                profiles: store, workouts: store, exercises: store,
                dismissedRunOfferDay: saved, saveDismissedRunOfferDay: { saved = $0 },
                calendar: calendar, format: format
            )
            await model.load(now: date)
            return model
        }
        let first = await launch(at: now)
        #expect(first.runOffer != nil)
        first.dismissRunOffer()
        #expect(saved == today)
        let relaunched = await launch(at: now.addingTimeInterval(3_600))
        #expect(relaunched.runOffer == nil)
        // Tomorrow the old answer no longer applies; the offer depends only on that day's window.
        let tomorrow = now.addingTimeInterval(86_400)
        let nextDay = await launch(at: tomorrow)
        let fresh = TodayModel(
            sources: [RunOfferSource(day: CalendarDay(tomorrow, calendar: calendar), sleepHours: 5,
                                     runs: [run(daysAgo: 4)])],
            profiles: store, workouts: store, exercises: store, calendar: calendar, format: format
        )
        await fresh.load(now: tomorrow)
        #expect((nextDay.runOffer == nil) == (fresh.runOffer == nil))
    }

    @Test func aDismissalFromAnEarlierDayDoesNotHideTodaysOffer() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(lastDaysAgo: 1))
        try await store.save(AthleteProfile())
        let model = TodayModel(
            sources: [RunOfferSource(day: today, sleepHours: 5, runs: [run(daysAgo: 4)])],
            profiles: store, workouts: store, exercises: store,
            dismissedRunOfferDay: today.adding(days: -1, calendar: calendar), calendar: calendar, format: format
        )
        await model.load(now: now)
        #expect(model.runOffer != nil)
    }

    @Test func aRunLoggedTodayHidesTheOffer() async throws {
        let model = try await model(runs: [run(daysAgo: 0, minutes: 20).movedBack(hours: 3)])
        #expect(model.runOffer == nil)
    }

    @Test func symptomsHideTheOffer() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(lastDaysAgo: 1))
        let model = TodayModel(
            sources: [RunOfferSource(day: today, sleepHours: 5, runs: [run(daysAgo: 4)])],
            checkIns: SickCheckIn(day: today), profiles: store, workouts: store, exercises: store,
            calendar: calendar, format: format
        )
        await model.load(now: now)
        #expect(model.runOffer == nil)
    }

    @Test func theWeekStripMarksTheWindowDaysWithADot() async throws {
        let model = try await model()
        let week = try #require(model.yourWeek)
        let marked = week.days.filter(\.hasRunWindow)
        #expect(!marked.isEmpty)
        #expect(marked.allSatisfy { $0.accessibilityLabel.hasSuffix("Good day for an easy run") })
    }
}

private extension RunActivity {
    func movedBack(hours: Double) -> RunActivity {
        RunActivity(
            id: id, source: source, name: name, startedAt: startedAt.addingTimeInterval(-hours * 3_600),
            durationSeconds: durationSeconds, distanceMeters: distanceMeters
        )
    }
}

private struct RunOfferSource: MetricsSource {
    let kind = DataSourceKind.appleHealth
    let day: CalendarDay
    let sleepHours: Double
    let runs: [RunActivity]

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        var metrics = DailyMetrics(day: day, sources: [.appleHealth])
        metrics.sleepSeconds = sleepHours * 3_600
        return [metrics]
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { runs }
}

private struct SickCheckIn: CheckInRepository {
    let day: CalendarDay
    func checkIn(for day: CalendarDay) async throws -> CheckIn? {
        day == self.day ? CheckIn(day: day, isSick: true) : nil
    }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] { [] }
    func save(_ checkIn: CheckIn) async throws {}
}

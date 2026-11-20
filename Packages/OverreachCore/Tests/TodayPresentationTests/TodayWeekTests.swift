import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

private actor WeekSource: MetricsSource {
    nonisolated let kind = DataSourceKind.appleHealth
    let days: [DailyMetrics]
    let activities: [RunActivity]
    private(set) var accessRequests = 0

    init(days: [DailyMetrics], activities: [RunActivity] = []) {
        self.days = days
        self.activities = activities
    }

    func isAvailable() async -> Bool { true }
    func requestAccess() async { accessRequests += 1 }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        activities.filter { (start...end).contains($0.startedAt) }
    }
}

private struct OneCheckIn: CheckInRepository {
    let stored: CheckIn
    func checkIn(for day: CalendarDay) async throws -> CheckIn? { day == stored.day ? stored : nil }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] { [] }
    func save(_ checkIn: CheckIn) async throws {}
}

private struct OneStrengthRecording: RecordedStrengthSource {
    let activity: RecordedStrengthActivity
    func strengthActivities(from start: Date, to end: Date) async -> [RecordedStrengthActivity] { [activity] }
}

@MainActor
@Suite("Today with a week of data")
struct TodayWeekTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, sleepHours: Double?, hrv: Double?, steps: Int?) -> DailyMetrics {
        var metrics = DailyMetrics(day: CalendarDay(now, calendar: calendar).adding(days: offset, calendar: calendar),
                                   sources: [.appleHealth])
        metrics.sleepSeconds = sleepHours.map { $0 * 3_600 }
        metrics.hrvSDNNMs = hrv
        metrics.steps = steps
        return metrics
    }

    @Test func todayShowsItsValuesAndTheWeekAverages() async throws {
        var today = day(0, sleepHours: 7, hrv: 50, steps: 9_000)
        today.deepSleepSeconds = 1.2 * 3_600
        today.remSleepSeconds = 1.5 * 3_600
        let source = WeekSource(days: [day(-8, sleepHours: 2, hrv: 10, steps: 100), day(-2, sleepHours: 6, hrv: 40, steps: 7_000), today])
        let model = TodayModel(sources: [source], calendar: calendar, format: Format(locale: Locale(identifier: "en_US")))

        await model.load(now: now)

        #expect(model.sleepHours == 7)
        #expect(model.steps == 9_000)
        #expect(model.week.count == 2)  // eight days ago is out of the week
        #expect(model.sleepCaption == "Deep 1.2 h · REM 1.5 h (watch estimate)")
        #expect(model.hrvCaption == "SDNN · 7-day avg 45 ms")
        #expect(model.stepsCaption == "7-day avg 8,000")
        #expect(model.sourcesText == "From Apple Health")
        #expect(!model.showsBodyBattery)
        #expect(!model.showsConnectHealth)
        #expect(model.hrvCoverageNote == "Still building your usual HRV range (SDNN, Apple Health: 2 of 14 comparable readings needed).")
        #expect(model.showsReadinessDetails)
    }

    @Test func withBothWatchesTodayShowsRMSSDAndAveragesOnlyRMSSD() async {
        // Apple's SDNN every night, Garmin's RMSSD tonight and two nights ago (ADR-0025).
        var today = day(0, sleepHours: nil, hrv: 60, steps: nil)
        today.hrvRMSSDMs = 38
        var twoNightsAgo = day(-2, sleepHours: nil, hrv: 58, steps: nil)
        twoNightsAgo.hrvRMSSDMs = 42
        let source = WeekSource(days: [day(-1, sleepHours: nil, hrv: 70, steps: nil), twoNightsAgo, today])
        let model = TodayModel(sources: [source], calendar: calendar, format: Format(locale: Locale(identifier: "en_US")))

        await model.load(now: now)

        #expect(model.hrvMs == 38)
        #expect(model.hrvCaption == "RMSSD · 7-day avg 40 ms")
    }

    @Test func lowHRVShowsTheMeasuredDenominatorAndConfiguredWindow() async {
        let baseline = (6...25).map { day(-$0, sleepHours: nil, hrv: 55, steps: nil) }
        let recent = [0, -1, -3].map { day($0, sleepHours: nil, hrv: 35, steps: nil) }
        let model = TodayModel(
            sources: [WeekSource(days: baseline + recent)],
            readinessSettings: .init(rollingDays: 5), calendar: calendar
        )

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessLines.map(\.text) == [
            "HRV (SDNN, Apple Health) below your usual range (3 of 3 comparable readings low in the last 5 days)."
        ])
        #expect(model.hrvCoverageNote == nil)
    }

    @Test func aMissingRecentReadingShowsWhyHRVWasSkipped() async {
        let baseline = (7...25).map { day(-$0, sleepHours: nil, hrv: 55, steps: nil) }
        let model = TodayModel(
            sources: [WeekSource(days: baseline + [day(-1, sleepHours: nil, hrv: 35, steps: nil)])], calendar: calendar
        )

        await model.load(now: now)

        #expect(model.readinessLevel == .unknown)
        #expect(model.showsReadinessCard)
        #expect(model.hrvCoverageNote == "Too few comparable HRV readings (SDNN, Apple Health) in the last 7 days (1 available, 3 needed).")
    }

    @Test func lowHRVExplainsTheComparisonWithoutInventingMissingNightsOrWorkouts() async {
        let days = (0...30).map { offset in
            let hrv: Double? = switch offset {
            case 0...3: 34
            case 4, 6: nil
            default: 43
            }
            var value = day(-offset, sleepHours: offset == 0 ? 7.6 : nil, hrv: hrv, steps: nil)
            value.restingHeartRate = offset == 0 ? 60 : 59
            return value
        }
        let model = TodayModel(sources: [WeekSource(days: days)], calendar: calendar,
                               format: Format(locale: Locale(identifier: "en_US")))
        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessSummary == "Your HRV is trending below your usual range.")
        #expect(model.readinessAdvice == "Keep it easy today. Run at a pace you can talk at, or lift with light effort.")
        #expect(model.readinessLines.first?.text.contains("4 of 5 comparable readings low") == true)
        #expect(model.readinessLines.first?.source?.absoluteString == "https://doi.org/10.3390/ijerph181910299")
        #expect(model.readinessContext.contains("Sleep last night was 7.6 h."))
        #expect(model.readinessContext.contains(
            "Resting heart rate today is 60 bpm. The average over 7 measured days in the last week is 59 bpm."
        ))
        #expect(model.readinessTrainingContext == nil)
    }

    @Test func showsOnlyWorkoutsFromTheDayBeforeTheLatestComparableReading() async throws {
        let days = (0...25).map { offset in
            day(-offset, sleepHours: nil, hrv: offset == 0 ? nil : (offset < 7 ? 32 : 50), steps: nil)
        }
        let older = RunActivity(id: "prior-workout", source: .appleHealth, name: "Intervals",
                                startedAt: days[2].day.startDate(in: calendar).addingTimeInterval(18 * 3_600),
                                durationSeconds: 1_800, distanceMeters: 4_000)
        let sameDay = RunActivity(id: "same-day", source: .appleHealth, name: "Not before the reading",
                                  startedAt: days[1].day.startDate(in: calendar).addingTimeInterval(18 * 3_600),
                                  durationSeconds: 1_800, distanceMeters: 4_000)
        let model = TodayModel(sources: [WeekSource(days: days, activities: [sameDay, older])], calendar: calendar)
        await model.load(now: now)

        let context = try #require(model.readinessTrainingContext)
        #expect(context.workouts.count == 1)
        #expect(context.workouts.first?.contains("Intervals") == true)
        #expect(model.readinessContext.contains("Resting heart rate is unavailable for today."))
        #expect(model.readinessContext.contains("Sleep data for last night is unavailable."))
    }

    @Test func theDevicesEstimatesSayWhatTheyAre() {
        let model = TodayModel(sources: [], calendar: calendar, format: Format(locale: Locale(identifier: "en_US")))

        #expect(model.vo2MaxCaption == "Watch estimate, follow the trend")
        #expect(model.bodyBatteryCaption == "Garmin's estimate")
        #expect(model.stressCaption == "Garmin's estimate")
    }

    @Test func readinessReasonsOfferFurtherReading() async {
        var days = (1...20).map { day(-$0, sleepHours: 7.5, hrv: 55, steps: nil) }
        days.append(day(0, sleepHours: 4, hrv: 55, steps: nil))
        let model = TodayModel(sources: [WeekSource(days: days)], calendar: calendar)

        await model.load(now: now)

        let sleep = model.readinessLines.first { $0.text.hasPrefix("Short sleep") }
        #expect(sleep?.readings.isEmpty == false)
        #expect(sleep?.readings.allSatisfy { $0.url.host?.contains("fitnessrevolucionario") == true } == true)
    }

    @Test func connectingAsksForAccessAndReloads() async {
        let source = WeekSource(days: [])
        let model = TodayModel(sources: [source], calendar: calendar)
        await model.load(now: now)
        #expect(model.showsConnectHealth)

        await model.connectHealth(now: now)
        #expect(await source.accessRequests == 1)
    }

    @Test func todaysCheckInFeedsTheReadinessLight() async {
        let todayKey = CalendarDay(now, calendar: calendar)
        let checkIns = OneCheckIn(stored: CheckIn(day: todayKey, isSick: true))
        let model = TodayModel(sources: [WeekSource(days: [])], checkIns: checkIns, calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .red)
        #expect(model.readinessAdvice == "Make it a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).")
        #expect(
            model.readinessLines.map(\.text) == ["Marked as sick in today's check-in. Rest until the symptoms ease."]
        )
        #expect(model.readinessLines.first?.evidence == EvidenceLevel.limited.displayName)
    }

    @Test func shortSleepExplainsTheAmberLight() async {
        let model = TodayModel(
            sources: [WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])], calendar: calendar,
            format: Format(locale: Locale(identifier: "en_US"))
        )

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessLines.map(\.text) == ["Short sleep: 5 h."])
        #expect(model.readinessLines.map(\.evidence) == [EvidenceLevel.moderate.displayName])
    }

    @Test func withoutDataTheLightSaysWhatItNeeds() async {
        let model = TodayModel(sources: [WeekSource(days: [])], calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .unknown)
        #expect(model.readinessAdvice == "Not enough data yet to judge today.")
        #expect(model.readinessLines.count == 1)
    }

    @Test func amberShowsALighterExampleFromTheNextUndatedRoutine() async throws {
        let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
        let newExercise = Exercise(name: "New exercise", primaryMuscles: [.glutes])
        let first = Routine(name: "First", exerciseIDs: [squat.id])
        let next = Routine(name: "Lower body", exerciseIDs: [squat.id, newExercise.id], prescriptions: [
            RoutinePrescription(exerciseID: squat.id, scheme: .linearLoad(sets: 4, reps: 6, targetRPE: 8)),
        ])
        let previous = StrengthSession(
            name: first.name, startedAt: now.addingTimeInterval(-3 * 86_400), endedAt: now.addingTimeInterval(-250_000),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 70, reps: 6, rpe: 8)])],
            routineID: first.id
        )
        let store = TestStore(exercises: [squat, newExercise], sessions: [previous], routines: [first, next])
        let block = TrainingBlock(focus: .strength, start: day(-40, sleepHours: nil, hrv: nil, steps: nil).day,
                                  plannedWeeks: 8, isDeclared: true, routineIDs: [first.id, next.id])
        try await store.save(AthleteProfile(declaredBlocks: [block]))
        try await store.save(ProgressionSettings(scheme: .linearLoad(sets: 3, reps: 10, targetRPE: 9), incrementKg: 2.5),
                             for: squat.id)
        let model = TodayModel(sources: [WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])], profiles: store,
                               workouts: store, exercises: store, routines: store, progression: store, calendar: calendar)

        await model.load(now: now)

        let option = try #require(model.strengthOption)
        #expect(option.heading == "Up next in your plan · Lower body")
        #expect(option.exerciseRows.map(\.title) == ["Squat"])
        #expect(option.exerciseRows.first?.reference == "Usual target · 4 × 6")
        #expect(option.exerciseRows.first?.suggestion == "Easy option · 2 × 6, with at least 4 reps left")
        #expect(await store.sessions(from: .distantPast, to: now) == [previous])
    }

    @Test func amberWithoutAPlanUsesTheMostRecentFamiliarSession() async throws {
        let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps])
        let previous = StrengthSession(
            name: "Gym", startedAt: now.addingTimeInterval(-86_400), endedAt: now.addingTimeInterval(-82_800),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: Array(repeating: WorkoutSet(reps: 8, rpe: 5), count: 3))]
        )
        let store = TestStore(exercises: [squat], sessions: [previous])
        let model = TodayModel(sources: [WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])],
                               workouts: store, exercises: store, calendar: calendar)
        await model.load(now: now)

        let option = try #require(model.strengthOption)
        #expect(option.heading == "Based on a recent session · Gym")
        #expect(option.exerciseRows.first?.suggestion == "Easy option · 1 × 8, with at least 5 reps left")
    }

    @Test func alreadyCompletedStrengthAndSicknessHideTheOption() async {
        let today = CalendarDay(now, calendar: calendar)
        let now = today.startDate(in: calendar).addingTimeInterval(12 * 3_600)
        let source = WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])
        let store = TestStore()
        let recording = RecordedStrengthActivity(id: "gym", source: .garmin, startedAt: now.addingTimeInterval(-3_600),
                                                 durationSeconds: 3_000)
        let trained = TodayModel(sources: [source], workouts: store,
                                 recordedStrength: OneStrengthRecording(activity: recording), calendar: calendar)
        await trained.load(now: now)
        #expect(trained.readinessLevel == .amber)
        #expect(trained.strengthOption == nil)

        let sick = TodayModel(sources: [source], checkIns: OneCheckIn(stored: CheckIn(day: today, isSick: true)),
                              workouts: store, calendar: calendar)
        await sick.load(now: now)
        #expect(sick.readinessLevel == .red)
        #expect(sick.strengthOption == nil)

        let overnight = StrengthSession(name: "Late lift", startedAt: now.addingTimeInterval(-45_000),
                                        endedAt: now.addingTimeInterval(-42_000))
        let logged = TodayModel(sources: [source], workouts: TestStore(sessions: [overnight]), calendar: calendar)
        await logged.load(now: now)
        #expect(logged.readinessLevel == .amber)
        #expect(logged.strengthOption == nil)
    }

    @Test func anEmptyHistoryOffersAnEffortCueWithoutInventingAnExercise() async throws {
        let source = WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])
        let model = TodayModel(sources: [source], workouts: TestStore(), calendar: calendar)
        await model.load(now: now)

        let option = try #require(model.strengthOption)
        #expect(option.heading == nil)
        #expect(option.exerciseRows.isEmpty)
        #expect(option.guidance.contains("at least four reps left"))
    }

    @Test func amberDoubleDayUsesTheDatedRoutineAlongsideTheRun() async throws {
        let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps])
        let routine = Routine(name: "Lower", exerciseIDs: [squat.id], prescriptions: [
            RoutinePrescription(exerciseID: squat.id, scheme: .linearLoad(sets: 4, reps: 6, targetRPE: 8)),
        ])
        let rotation = Routine(name: "Undated", exerciseIDs: [squat.id])
        let previous = StrengthSession(
            name: rotation.name, startedAt: now.addingTimeInterval(-86_400), endedAt: now.addingTimeInterval(-82_800),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 70, reps: 6, rpe: 8)])]
        )
        let store = TestStore(exercises: [squat], sessions: [previous], routines: [routine, rotation])
        let today = CalendarDay(now, calendar: calendar)
        let run = PlannedRun(day: today, purpose: .intervals, durationMinutes: 40)
        let assignment = PlannedStrength(day: today, routineID: routine.id)
        var goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000), nextRun: run)
        goal.setStrengthSchedule([assignment])
        let block = TrainingBlock(focus: .strength, start: today, isDeclared: true, routineIDs: [rotation.id])
        let profile = AthleteProfile(goal: goal, declaredBlocks: [block])
        try await store.save(profile)
        let source = WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)], activities: [RunActivity(
            id: "past-run", source: .appleHealth, startedAt: now.addingTimeInterval(-2 * 86_400),
            durationSeconds: 2_400, distanceMeters: 6_000
        )])
        let model = TodayModel(sources: [source], profiles: store, workouts: store, exercises: store, routines: store,
                               progression: store, calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.scheduledStrengthToday?.id == assignment.id)
        #expect(model.scheduledStrengthToday?.title == "Strength · Lower")
        #expect(model.scheduledRunsToday.map(\.id) == [run.id])
        #expect(model.runningOption?.advice == "Try 30 min at a conversational pace in place of the planned session.")
        let comparison = try #require(model.strengthOption)
        #expect(comparison.heading == nil)
        #expect(comparison.exerciseRows.first?.reference == "Usual target · 4 × 6")
        #expect(comparison.exerciseRows.first?.suggestion == "Easy option · 2 × 6, with at least 4 reps left")
        #expect(await store.profile() == profile)
        #expect(await store.sessions(from: .distantPast, to: now) == [previous])
    }

    @Test func aDatedStrengthRestDaySuppressesTheUndatedSuggestion() async throws {
        let today = CalendarDay(now, calendar: calendar)
        let run = PlannedRun(day: today, purpose: .rest)
        var goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000), nextRun: run)
        goal.setStrengthSchedule([PlannedStrength(day: today)])
        let store = TestStore()
        try await store.save(AthleteProfile(goal: goal))
        let model = TodayModel(sources: [WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])],
                               profiles: store, workouts: store, calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.scheduledStrengthToday?.title == "Strength rest day")
        #expect(model.scheduledRunsToday.first?.title == "Running rest day")
        #expect(model.strengthOption == nil)
        #expect(model.runningOption == nil)
    }

    @Test(arguments: [true, false])
    func assignedRoutineShowsCompletedOnlyWhenItsSessionHasFinished(isFinished: Bool) async throws {
        let today = CalendarDay(now, calendar: calendar)
        let midday = today.startDate(in: calendar).addingTimeInterval(12 * 3_600)
        let routine = Routine(name: "Upper")
        let recorded = StrengthSession(name: routine.name, startedAt: midday.addingTimeInterval(-3_600),
                                       endedAt: isFinished ? midday.addingTimeInterval(-300) : nil,
                                       routineID: routine.id)
        var goal = TrainingGoal(kind: .hybrid)
        goal.setStrengthSchedule([PlannedStrength(day: today, routineID: routine.id)])
        let store = TestStore(sessions: [recorded], routines: [routine])
        try await store.save(AthleteProfile(goal: goal))
        let model = TodayModel(sources: [WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])],
                               profiles: store, workouts: store, routines: store, calendar: calendar)

        await model.load(now: midday)

        #expect(model.readinessLevel == .amber)
        #expect(model.scheduledStrengthToday?.title == "Strength · Upper")
        #expect(model.scheduledStrengthToday?.status == (isFinished ? "Completed" : nil))
        #expect(model.strengthOption == nil)
    }

    @Test func comparesTheConcreteEasyRunWithTodaysHybridPlan() async throws {
        let today = CalendarDay(now, calendar: calendar)
        let store = TestStore()
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000, targetSeconds: 900),
                                nextRun: PlannedRun(day: today, purpose: .intervals, durationMinutes: 40))
        try await store.save(AthleteProfile(goal: goal))
        let source = WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)], activities: [RunActivity(
            id: "past-run", source: .appleHealth, startedAt: now.addingTimeInterval(-12 * 86_400),
            durationSeconds: 2_400, distanceMeters: 6_000
        )])
        let model = TodayModel(sources: [source], profiles: store, calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.runningOption?.goal == "Run 5 km in 15:00")
        #expect(model.runningOption?.plan == "Today's running plan · Intervals · 40 min")
        #expect(model.runningOption?.advice == "Try 30 min at a conversational pace in place of the planned session.")
        #expect(try await store.profile().goal == goal)
    }
}

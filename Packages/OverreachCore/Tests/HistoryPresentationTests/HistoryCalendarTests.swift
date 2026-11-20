import Domain
import Fixtures
import Foundation
import HistoryPresentation
import PresentationKit
import Testing

private actor StepsSource: ActivitySource {
    let days: [DailyActivity]
    private(set) var requestedRanges: [ClosedRange<CalendarDay>] = []

    init(_ days: [DailyActivity]) { self.days = days }

    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        requestedRanges.append(range)
        return days.filter { range.contains($0.day) }
    }
}

private actor RunsSource: MetricsSource {
    nonisolated let kind = DataSourceKind.appleHealth
    let all: [RunActivity]

    init(_ runs: [RunActivity]) { all = runs }

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        all.filter { $0.startedAt >= start && $0.startedAt < end }
    }
}

private struct HealthUnavailable: Error {}

private struct FailingSource: MetricsSource, ActivitySource {
    let kind = DataSourceKind.appleHealth
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { throw HealthUnavailable() }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { throw HealthUnavailable() }
    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] { throw HealthUnavailable() }
}

@MainActor
@Suite("History calendar")
struct HistoryCalendarTests {
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1  // Sunday, to check the grid stays Monday first.
        return calendar
    }()

    /// Thursday 19 November 2026, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_795_089_600)

    private func day(_ number: Int, month: Int = 11, year: Int = 2026) -> CalendarDay {
        CalendarDay(year: year, month: month, day: number)
    }

    private func date(_ day: CalendarDay, hour: Int = 18) -> Date {
        day.startDate(in: calendar).addingTimeInterval(Double(hour) * 3_600)
    }

    private func session(on day: CalendarDay, name: String = "Lower") -> StrengthSession {
        let start = date(day)
        return StrengthSession(
            name: name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 100, reps: 5)])]
        )
    }

    private func run(on day: CalendarDay, kilometres: Double, minutes: Double, heartRate: Double? = 150)
        -> RunActivity {
        RunActivity(
            id: UUID().uuidString, source: .appleHealth, name: "Garmin Connect", startedAt: date(day, hour: 8),
            durationSeconds: minutes * 60, distanceMeters: kilometres * 1_000, averageHeartRate: heartRate
        )
    }

    private func model(
        sessions: [StrengthSession] = [],
        activity: (any ActivitySource)? = nil,
        runs: (any MetricsSource)? = nil,
        at now: Date? = nil
    ) async -> HistoryModel {
        let store = TestStore(exercises: [squat], sessions: sessions)
        let fixedNow = now ?? self.now
        let model = HistoryModel(
            workouts: store, exercises: store, routines: store, activity: activity, runs: runs,
            calendar: calendar, format: format, clock: { fixedNow }
        )
        await model.load()
        await model.calendar.load()
        return model
    }

    private func cell(_ day: CalendarDay, in calendar: HistoryCalendarModel) throws -> CalendarDayCell {
        try #require(calendar.cells.first { $0.day == day })
    }

    // MARK: Grid

    @Test func monthStartingOnSundayHasSixLeadingBlanks() async {
        let calendar = await model().calendar

        #expect(calendar.monthTitle == "November 2026")
        #expect(calendar.weekdays.map(\.symbol) == ["M", "T", "W", "T", "F", "S", "S"])
        let cells = calendar.cells
        #expect(cells.count == 42)
        #expect(cells.prefix(6).allSatisfy { $0.isBlank })
        #expect(cells[6].day == day(1))
        #expect(cells[35].day == day(30))
        #expect(cells.suffix(6).allSatisfy { $0.isBlank })
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test func monthStartingOnMondayHasNoLeadingBlanks() async {
        let june = await model(at: date(day(10, month: 6))).calendar
        #expect(june.cells.first?.day == day(1, month: 6))
        #expect(june.cells.count == 35)  // 30 days + 5 trailing blanks

        let february = await model(at: date(day(10, month: 2, year: 2027))).calendar
        #expect(february.cells.count == 28)  // exactly four weeks
        #expect(february.cells.allSatisfy { !$0.isBlank })
    }

    @Test func monthStartingMidweekPadsBothEnds() async {
        let october = await model(at: date(day(10, month: 10))).calendar
        let cells = october.cells
        #expect(cells.count == 35)
        #expect(cells.prefix(3).allSatisfy { $0.isBlank })  // Thursday 1 October
        #expect(cells[3].day == day(1, month: 10))
        #expect(cells.last?.isBlank == true)
    }

    @Test func todayIsHighlightedAndLaterDaysDimmed() async throws {
        let calendar = await model().calendar
        #expect(try cell(day(19), in: calendar).isToday)
        #expect(try !cell(day(18), in: calendar).isFuture)
        #expect(try cell(day(20), in: calendar).isFuture)
        #expect(try !cell(day(20), in: calendar).isToday)
    }

    @Test func agendaShowsRecordedDaysAndRetainsAnEmptySelection() async {
        let model = await model(
            sessions: [session(on: day(2))],
            activity: StepsSource([DailyActivity(day: day(8), steps: 1_100)]),
            runs: RunsSource([run(on: day(5), kilometres: 5, minutes: 28)])
        )
        let calendar = model.calendar

        #expect(calendar.agendaDays.compactMap(\.day) == [day(8), day(5), day(2)])
        calendar.select(day(6))
        #expect(calendar.agendaDays.compactMap(\.day) == [day(8), day(6), day(5), day(2)])
        #expect(calendar.selectedDetail?.isEmpty == true)
        calendar.select(day(6))
        #expect(calendar.agendaDays.compactMap(\.day) == [day(8), day(5), day(2)])
    }

    // MARK: Markers

    @Test func markersShowSessionsRunsBothAndNeither() async throws {
        let model = await model(
            sessions: [session(on: day(2)), session(on: day(4)), session(on: day(4), name: "Upper")],
            runs: RunsSource([
                run(on: day(3), kilometres: 5, minutes: 28), run(on: day(4), kilometres: 10, minutes: 55),
            ])
        )
        let calendar = model.calendar

        let strengthOnly = try cell(day(2), in: calendar)
        #expect(strengthOnly.hasStrength && !strengthOnly.hasRun)
        let runOnly = try cell(day(3), in: calendar)
        #expect(!runOnly.hasStrength && runOnly.hasRun)
        let both = try cell(day(4), in: calendar)
        #expect(both.strengthSessions == 2 && both.runs == 1)
        #expect(both.accessibilityLabel.contains("Strength: 2"))
        let neither = try cell(day(5), in: calendar)
        #expect(!neither.hasStrength && !neither.hasRun && neither.stepsFraction == nil)
    }

    @Test func sessionsOutsideTheMonthAreLeftOut() async {
        let calendar = await model(sessions: [session(on: day(31, month: 10)), session(on: day(1, month: 12))]).calendar
        #expect(calendar.sessions.isEmpty)
        #expect(calendar.cells.allSatisfy { !$0.hasStrength })
    }

    // MARK: Steps ring

    @Test func ringFillsAgainstTheMonthAverageCappedAtOne() async throws {
        let steps = StepsSource([
            DailyActivity(day: day(1), steps: 4_000),
            DailyActivity(day: day(2), steps: 8_000),
            DailyActivity(day: day(3), steps: 12_000),
            DailyActivity(day: day(4), steps: nil),
            DailyActivity(day: day(1, month: 12), steps: 50_000),  // other month: ignored
        ])
        let calendar = await model(activity: steps).calendar

        #expect(calendar.averageSteps == 8_000)
        #expect(try cell(day(1), in: calendar).stepsFraction == 0.5)
        #expect(try cell(day(2), in: calendar).stepsFraction == 1)
        #expect(try cell(day(3), in: calendar).stepsFraction == 1)  // 1.5, capped
        #expect(try cell(day(4), in: calendar).stepsFraction == nil)
        #expect(try cell(day(5), in: calendar).stepsFraction == nil)
        #expect(await steps.requestedRanges == [day(1)...day(30)])
    }

    // MARK: Totals

    @Test func totalsCountSessionsRunsKilometresAndAverageSteps() async {
        let calendar = await model(
            sessions: [session(on: day(2)), session(on: day(9))],
            activity: StepsSource([DailyActivity(day: day(1), steps: 6_000), DailyActivity(day: day(2), steps: 9_002)]),
            runs: RunsSource([
                run(on: day(3), kilometres: 5.3, minutes: 28), run(on: day(10), kilometres: 10, minutes: 55),
            ])
        ).calendar

        #expect(calendar.totals.map(\.value) == ["2", "2", "15.3", "7,501"])
        #expect(calendar.totals.map(\.label) == ["Sessions", "Runs", "Km run", "Steps per day"])
        #expect(calendar.healthHint == nil)
    }

    // MARK: Selection

    @Test func selectingADayShowsItsSessionsRunsAndSteps() async throws {
        let model = await model(
            sessions: [session(on: day(4))],
            activity: StepsSource([DailyActivity(day: day(4), steps: 10_250)]),
            runs: RunsSource([run(on: day(4), kilometres: 5, minutes: 27.5)])
        )
        let calendar = model.calendar
        calendar.select(day(4))

        let detail = try #require(calendar.selectedDetail)
        #expect(detail.title == "Wednesday, November 4")
        #expect(detail.sessions.map(\.title) == ["Lower"])
        #expect(detail.sessions.first?.exerciseList == "Back Squat")
        #expect(detail.steps == "10,250 steps")
        let run = try #require(detail.runs.first)
        #expect(run.title == "Garmin Connect")
        #expect(run.distance == "5 km")
        #expect(run.duration == "27:30")
        #expect(run.pace == "5:30 /km")
        #expect(run.heartRate == "150 bpm")
        #expect(try cell(day(4), in: calendar).isSelected)
        // The linked session detail finds it.
        #expect(model.detail(for: detail.sessions[0].id)?.name == "Lower")

        calendar.select(day(4))
        #expect(calendar.selectedDetail == nil)
    }

    @Test func anEmptyDaySaysSo() async throws {
        let calendar = await model().calendar
        calendar.select(day(6))
        let detail = try #require(calendar.selectedDetail)
        #expect(detail.isEmpty)
        #expect(detail.runs.isEmpty && detail.steps == nil)
    }

    @Test func longRunsShowHours() async throws {
        let halfMarathon = run(on: day(8), kilometres: 21.1, minutes: 65.5, heartRate: nil)
        let calendar = await model(runs: RunsSource([halfMarathon])).calendar
        calendar.select(day(8))
        let run = try #require(calendar.selectedDetail?.runs.first)
        #expect(run.duration == "1:05:30")
        #expect(run.heartRate == nil)
    }

    // MARK: Navigation

    @Test func navigatesMonthsAndReloadsActivityForTheShownMonth() async throws {
        let steps = StepsSource([DailyActivity(day: day(15, month: 10), steps: 7_000)])
        let calendar = await model(
            sessions: [session(on: day(20, month: 10)), session(on: day(5, month: 1, year: 2025))],
            activity: steps,
            runs: RunsSource([run(on: day(21, month: 10), kilometres: 8, minutes: 45)])
        ).calendar
        #expect(calendar.isShowingCurrentMonth)
        #expect(!calendar.canShowNextMonth)

        await calendar.showPreviousMonth()
        #expect(calendar.monthTitle == "October 2026")
        #expect(!calendar.isShowingCurrentMonth && calendar.canShowNextMonth)
        #expect(try cell(day(20, month: 10), in: calendar).hasStrength)
        #expect(try cell(day(21, month: 10), in: calendar).hasRun)
        #expect(try cell(day(15, month: 10), in: calendar).stepsFraction == 1)
        #expect(calendar.cells.allSatisfy { !$0.isToday && !$0.isFuture })
        #expect(await steps.requestedRanges.last == day(1, month: 10)...day(31, month: 10))

        await calendar.showNextMonth()
        #expect(calendar.monthTitle == "November 2026")
        await calendar.showNextMonth()  // no further than this month
        #expect(calendar.monthTitle == "November 2026")

        for _ in 0..<22 { await calendar.showPreviousMonth() }
        #expect(calendar.monthTitle == "January 2025")
        #expect(calendar.sessions.count == 1)  // older than the list's year, still in the calendar

        await calendar.showToday()
        #expect(calendar.isShowingCurrentMonth)
        #expect(calendar.selectedDay == day(19))
    }

    @Test func changingMonthClearsTheSelection() async {
        let calendar = await model().calendar
        calendar.select(day(3))
        await calendar.showPreviousMonth()
        #expect(calendar.selectedDay == nil)
        calendar.select(day(3))  // not in the shown month
        #expect(calendar.selectedDay == nil)
    }

    // MARK: Edits from the list

    @Test func editsAndDeletionsReachTheCalendar() async throws {
        let original = session(on: day(4))
        let model = await model(sessions: [original])
        var moved = original
        moved.startedAt = date(day(6))
        moved.endedAt = moved.startedAt.addingTimeInterval(3_600)

        model.didSave(moved)
        #expect(try !cell(day(4), in: model.calendar).hasStrength)
        #expect(try cell(day(6), in: model.calendar).hasStrength)

        await model.delete(original.id)
        #expect(try !cell(day(6), in: model.calendar).hasStrength)
    }

    // MARK: Missing data

    @Test func withoutHealthShowsSessionsAndAHint() async throws {
        let calendar = await model(sessions: [session(on: day(2))]).calendar
        #expect(try cell(day(2), in: calendar).hasStrength)
        #expect(calendar.totals.map(\.value) == ["1", "–", "–", "–"])
        #expect(calendar.healthHint == "Runs and steps appear here once Apple Health is connected (from Today).")
        #expect(calendar.errorMessage == nil)
    }

    @Test func aFailingSourceNeverBlocksTheSessions() async throws {
        let source = FailingSource()
        let calendar = await model(sessions: [session(on: day(2))], activity: source, runs: source).calendar
        #expect(try cell(day(2), in: calendar).hasStrength)
        #expect(calendar.cells.allSatisfy { $0.stepsFraction == nil && !$0.hasRun })
        #expect(calendar.totals.first?.value == "1")
        #expect(calendar.healthHint == "Could not read Apple Health. Your sessions are still shown.")
    }

    @Test func stepsWithoutRunsStillShowRings() async throws {
        let calendar = await model(activity: StepsSource([DailyActivity(day: day(1), steps: 5_000)])).calendar
        #expect(try cell(day(1), in: calendar).stepsFraction == 1)
        #expect(calendar.totals.map(\.value) == ["0", "–", "–", "5,000"])
        #expect(calendar.healthHint == nil)
    }
}

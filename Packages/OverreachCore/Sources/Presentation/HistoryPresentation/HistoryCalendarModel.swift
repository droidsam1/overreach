import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// One cell of the month grid: a day of the shown month, or a blank before the 1st or after the last day.
public struct CalendarDayCell: Identifiable, Hashable, Sendable {
    public let id: String
    /// `nil` for a blank cell.
    public let day: CalendarDay?
    /// "19"; empty for a blank cell.
    public let number: String
    public let strengthSessions: Int
    public let runs: Int
    /// Steps against the average day of the shown month, from 0 to 1. `nil` without step data: no ring.
    public let stepsFraction: Double?
    public let isToday: Bool
    public let isFuture: Bool
    public let isSelected: Bool
    /// "Thursday 19 November. Strength: 1. Runs: 1. Steps: 8,412".
    public let accessibilityLabel: String

    public var isBlank: Bool { day == nil }
    public var hasStrength: Bool { strengthSessions > 0 }
    public var hasRun: Bool { runs > 0 }
}

/// A weekday heading of the grid ("M", "T", …), Monday first.
public struct CalendarWeekday: Identifiable, Hashable, Sendable {
    public let id: Int
    public let symbol: String
    public let name: String
}

/// One of the month totals under the grid: "12" + "Sessions".
public struct CalendarTotal: Identifiable, Hashable, Sendable {
    public let id: String
    public let value: String
    public let label: String
}

/// What happened on the selected day.
public struct CalendarDayDetail: Hashable, Sendable {
    public let day: CalendarDay
    /// "Thursday, 19 November"
    public let title: String
    public let sessions: [SessionSummary]
    public let recordings: [HistoryStrengthActivity]
    public let runs: [HistoryRunActivity]
    /// "8,412 steps"; `nil` without step data.
    public let steps: String?

    public var isEmpty: Bool { sessions.isEmpty && recordings.isEmpty && runs.isEmpty && steps == nil }
    public var emptyText: String { L10n.text("Nothing recorded on this day.") }
}

/// The month calendar of History: strength days, runs and steps per day (ADR-0014). Sessions come from the
/// workout repository, steps from Apple Health, and runs from available sources. A failing source leaves the
/// successful reads visible.
@MainActor
@Observable
public final class HistoryCalendarModel {
    /// The first day of the shown month.
    public private(set) var month: CalendarDay
    public private(set) var selectedDay: CalendarDay?
    public private(set) var isLoading = false
    public private(set) var sessions: [StrengthSession] = []
    private var strengthMatches = StrengthActivityMatches()
    private var allStrengthReviews: [HistoryStrengthReview] = []

    public var strengthReviews: [HistoryStrengthReview] {
        allStrengthReviews.filter { isInMonth($0.sessionStart) || isInMonth($0.recording.startedAt) }
    }

    private var monthRecordings: [RecordedStrengthActivity] {
        strengthMatches.unmatched.filter { isInMonth($0.startedAt) }
    }

    private var runRecords: [RunDeduplication.CombinedRun] = []
    private var runOriginals: [RunActivity] = []
    private var loadedRunInterval: DateInterval?
    private var runChoices: [RunMatchPair: RunMatchChoice]
    public private(set) var runReviews: [HistoryRunReview] = []
    public var runs: [RunActivity] { runRecords.map(\.activity) }
    public private(set) var steps: [CalendarDay: Int] = [:]
    /// Whether reading Apple Health failed for the shown month.
    public private(set) var activityFailed = false
    public private(set) var sessionsFailed = false
    public private(set) var runWarning: String?
    private var didReadRuns = false
    @ObservationIgnored private var activeLoad: UUID?

    /// Exercise names for the day detail, kept up to date by `HistoryModel`.
    var exerciseNames: [UUID: String] = [:]

    private let workouts: any WorkoutRepository
    private let activity: (any ActivitySource)?
    private let runSources: [any MetricsSource]
    private let calendar: Calendar
    private let format: Format
    private let clock: @Sendable () -> Date

    public init(
        workouts: any WorkoutRepository,
        activity: (any ActivitySource)? = nil,
        runSources: [any MetricsSource] = [],
        calendar: Calendar = .current,
        format: Format = Format(),
        runChoices: [RunMatchPair: RunMatchChoice] = [:],
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.activity = activity
        self.runSources = runSources
        self.calendar = calendar
        self.format = format
        self.clock = clock
        self.runChoices = runChoices
        month = Self.firstDay(of: CalendarDay(clock(), calendar: calendar))
    }

    // MARK: Screen state

    public var today: CalendarDay { CalendarDay(clock(), calendar: calendar) }

    /// "November 2026"
    public var monthTitle: String {
        let style = Date.FormatStyle(
            locale: format.locale, calendar: calendar, timeZone: calendar.timeZone, capitalizationContext: .standalone
        )
        return month.startDate(in: calendar).formatted(style.month(.wide).year())
    }

    public var isShowingCurrentMonth: Bool { month == Self.firstDay(of: today) }
    /// Nothing is recorded ahead of today, so the grid stops at the current month.
    public var canShowNextMonth: Bool { month < Self.firstDay(of: today) }

    /// Monday first.
    public var weekdays: [CalendarWeekday] {
        var localized = calendar
        localized.locale = format.locale
        let symbols = localized.veryShortStandaloneWeekdaySymbols
        let names = localized.standaloneWeekdaySymbols
        // Calendar lists Sunday first.
        return (0..<7).map { index in
            let weekday = (index + 1) % 7
            return CalendarWeekday(id: index, symbol: symbols[weekday], name: names[weekday])
        }
    }

    /// The month grid, a multiple of 7 cells: blanks before the 1st (Monday first) and after the last day.
    public var cells: [CalendarDayCell] {
        let days = daysOfMonth
        let leading = Self.mondayIndex(of: month, calendar: calendar)
        let trailing = (7 - (leading + days.count) % 7) % 7
        let average = averageSteps
        let today = today
        let sessionsByDay = Dictionary(grouping: sessions) { CalendarDay($0.startedAt, calendar: calendar) }
        let recordingsByDay = Dictionary(grouping: monthRecordings) { CalendarDay($0.startedAt, calendar: calendar) }
        let runsByDay = Dictionary(grouping: runs) { CalendarDay($0.startedAt, calendar: calendar) }

        let blanks = { (prefix: String, count: Int) in
            (0..<count).map { index in
                CalendarDayCell(
                    id: "\(prefix)-\(index)", day: nil, number: "", strengthSessions: 0, runs: 0, stepsFraction: nil,
                    isToday: false, isFuture: false, isSelected: false, accessibilityLabel: ""
                )
            }
        }
        let dayCells = days.map { day in
            let strength = (sessionsByDay[day]?.count ?? 0) + (recordingsByDay[day]?.count ?? 0)
            let runCount = runsByDay[day]?.count ?? 0
            let daySteps = steps[day]
            return CalendarDayCell(
                id: day.description,
                day: day,
                number: String(day.day),
                strengthSessions: strength,
                runs: runCount,
                stepsFraction: daySteps.map { Self.fraction(steps: $0, average: average) },
                isToday: day == today,
                isFuture: day > today,
                isSelected: day == selectedDay,
                accessibilityLabel: accessibilityLabel(day: day, strength: strength, runs: runCount, steps: daySteps)
            )
        }
        return blanks("leading", leading) + dayCells + blanks("trailing", trailing)
    }

    /// The most recent recorded days first. Keep the selected day visible even when it has no activity.
    public var agendaDays: [CalendarDayCell] {
        cells.reversed().filter { cell in
            cell.isSelected || cell.hasStrength || cell.hasRun || cell.stepsFraction != nil
        }
    }

    /// Sessions, runs, running km and average steps of the shown month. Runs and steps show "–" when they could
    /// not be read.
    public var totals: [CalendarTotal] {
        let unknown = "–"
        let kilometres = runs.reduce(0) { $0 + $1.distanceMeters } / 1_000
        return [
            CalendarTotal(
                id: "sessions", value: String(sessions.count + monthRecordings.count), label: L10n.text("Sessions")
            ),
            CalendarTotal(id: "runs", value: didReadRuns ? String(runs.count) : unknown, label: L10n.text("Runs")),
            CalendarTotal(
                id: "km",
                value: didReadRuns ? format.number(kilometres, maxFractionDigits: 1) : unknown,
                label: L10n.text("Km run")
            ),
            CalendarTotal(
                id: "steps",
                value: averageSteps.map { format.number($0, maxFractionDigits: 0) } ?? unknown,
                label: L10n.text("Steps per day")
            ),
        ]
    }

    /// Average steps per day of the shown month, over the days with data.
    public var averageSteps: Double? {
        guard !steps.isEmpty else { return nil }
        return Double(steps.values.reduce(0, +)) / Double(steps.count)
    }

    /// Shown under the grid while runs and steps are missing: Health is not connected, or could not be read.
    public var healthHint: String? {
        if activityFailed { return L10n.text("Could not read Apple Health. Your sessions are still shown.") }
        guard steps.isEmpty, runs.isEmpty, runWarning == nil, !isLoading else { return nil }
        return L10n.text("Connect Apple Health or Garmin from Today to see runs. Steps come from Apple Health.")
    }

    public var errorMessage: String? {
        sessionsFailed ? L10n.text("Could not load your sessions for this month.") : nil
    }

    /// The selected day's sessions, runs and steps.
    public var selectedDetail: CalendarDayDetail? {
        guard let day = selectedDay else { return nil }
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        return CalendarDayDetail(
            day: day,
            title: day.startDate(in: calendar).formatted(style.weekday(.wide).day().month(.wide)),
            sessions: sessions
                .filter { CalendarDay($0.startedAt, calendar: calendar) == day }
                .map { session in
                    var summary = SessionSummary(session: session, names: exerciseNames)
                    summary.matchedSource = strengthMatches.activity(for: session.id)?.source
                    return summary
                },
            recordings: monthRecordings
                .filter { CalendarDay($0.startedAt, calendar: calendar) == day }
                .map { HistoryStrengthActivity($0, format: format) },
            runs: runRecords
                .filter { CalendarDay($0.activity.startedAt, calendar: calendar) == day }
                .map { HistoryRunActivity($0, format: format) },
            steps: steps[day].map { L10n.format("{1} steps", format.number(Double($0), maxFractionDigits: 0)) }
        )
    }

    // MARK: Intents

    /// Loads the shown month. The first load selects today.
    public func load() async {
        await load(month: month)
    }

    public func showPreviousMonth() async {
        selectedDay = nil
        await load(month: month.adding(months: -1, calendar: calendar))
    }

    public func showNextMonth() async {
        guard canShowNextMonth else { return }
        selectedDay = nil
        await load(month: month.adding(months: 1, calendar: calendar))
    }

    /// Back to the current month, with today selected.
    public func showToday() async {
        selectedDay = today
        await load(month: Self.firstDay(of: today))
    }

    /// Selects a day of the shown month; selecting it again clears the selection.
    public func select(_ day: CalendarDay?) {
        guard let day, Self.firstDay(of: day) == month else {
            selectedDay = nil
            return
        }
        selectedDay = selectedDay == day ? nil : day
    }

    /// Keeps the grid in line with an edited session.
    func didSave(_ session: StrengthSession) {
        sessions.removeAll { $0.id == session.id }
        guard Self.firstDay(of: CalendarDay(session.startedAt, calendar: calendar)) == month else { return }
        sessions.append(session)
        sessions.sort { $0.startedAt < $1.startedAt }
    }

    func didDelete(_ sessionID: UUID) {
        sessions.removeAll { $0.id == sessionID }
    }

    // MARK: Loading

    private func load(month requested: CalendarDay) async {
        let loadID = UUID()
        activeLoad = loadID
        month = requested
        isLoading = true
        defer {
            if activeLoad == loadID {
                activeLoad = nil
                isLoading = false
            }
        }

        let start = requested.startDate(in: calendar)
        let next = requested.adding(months: 1, calendar: calendar)
        let end = next.startDate(in: calendar)
        let range = requested...next.adding(days: -1, calendar: calendar)
        // Match copies on opposite sides of midnight before filtering by the preferred record's start.
        let runStart = requested.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let runEnd = next.adding(days: 1, calendar: calendar).startDate(in: calendar)
        async let loadedRuns = HistoryRunReadings.load(sources: runSources, from: runStart, to: runEnd)

        let loadedSessions: [StrengthSession]?
        do {
            loadedSessions = try await workouts.sessions(from: start, to: end).filter { $0.startedAt < end }
        } catch {
            loadedSessions = nil
        }

        var failed = false
        var loadedSteps: [CalendarDay: Int] = [:]
        if let activity {
            do {
                for day in try await activity.dailyActivity(in: range) where range.contains(day.day) {
                    if let count = day.steps { loadedSteps[day.day] = count }
                }
            } catch {
                failed = true
            }
        }
        let runResults = await loadedRuns
        guard activeLoad == loadID else { return }
        sessions = loadedSessions ?? []
        sessionsFailed = loadedSessions == nil
        steps = loadedSteps
        runOriginals = runResults.runs
        loadedRunInterval = DateInterval(start: start, end: end)
        resolveRuns()
        didReadRuns = runResults.didRead
        runWarning = runResults.warning(excluding: [.appleHealth])
        activityFailed = failed || runResults.failedSources.contains(.appleHealth)
    }

    // MARK: Helpers

    private var daysOfMonth: [CalendarDay] {
        let count = calendar.range(of: .day, in: .month, for: month.startDate(in: calendar))?.count ?? 30
        return (1...count).map { CalendarDay(year: month.year, month: month.month, day: $0) }
    }

    static func firstDay(of day: CalendarDay) -> CalendarDay {
        CalendarDay(year: day.year, month: day.month, day: 1)
    }

    /// 0 for Monday … 6 for Sunday.
    static func mondayIndex(of day: CalendarDay, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))  // 1 = Sunday
        return (weekday + 5) % 7
    }

    /// Steps against the average day, capped at 1.
    static func fraction(steps: Int, average: Double?) -> Double {
        guard let average, average > 0 else { return 0 }
        return min(1, Double(steps) / average)
    }

    func updateStrength(_ matches: StrengthActivityMatches, reviews: [HistoryStrengthReview]) {
        strengthMatches = matches
        allStrengthReviews = reviews
    }

    private func isInMonth(_ date: Date) -> Bool {
        Self.firstDay(of: CalendarDay(date, calendar: calendar)) == month
    }

    func updateRunChoices(_ choices: [RunMatchPair: RunMatchChoice]) {
        runChoices = choices
        resolveRuns()
    }

    private func resolveRuns() {
        guard let interval = loadedRunInterval else { return }
        let dates = interval.start..<interval.end
        let result = RunDeduplication.resolve(runOriginals, choices: runChoices)
        runRecords = result.runs.filter { dates.contains($0.activity.startedAt) }
        runReviews = result.candidates
            .filter { dates.contains($0.garmin.startedAt) || dates.contains($0.appleHealth.startedAt) }
            .map { HistoryRunReview($0, format: format) }
    }

    private func accessibilityLabel(day: CalendarDay, strength: Int, runs: Int, steps: Int?) -> String {
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        var parts = [day.startDate(in: calendar).formatted(style.weekday(.wide).day().month(.wide))]
        if strength > 0 { parts.append(L10n.format("Strength: {1}", strength)) }
        if runs > 0 { parts.append(L10n.format("Runs: {1}", runs)) }
        if let steps { parts.append(L10n.format("{1} steps", format.number(Double(steps), maxFractionDigits: 0))) }
        return parts.joined(separator: ". ")
    }
}

extension CalendarDay {
    /// The same day `months` months later (or earlier), for first days of a month.
    func adding(months: Int, calendar: Calendar) -> CalendarDay {
        let start = startDate(in: calendar)
        return CalendarDay(calendar.date(byAdding: .month, value: months, to: start) ?? start, calendar: calendar)
    }
}

extension SessionSummary {
    init(session: StrengthSession, names: [UUID: String]) {
        let sets = session.entries.flatMap(\.sets)
        self.init(
            session: session,
            exerciseNames: session.entries.map { names[$0.exerciseID] ?? L10n.text("Unknown exercise") },
            workingSets: sets.filter(\.isWorking).count,
            tonnageKg: StrengthMetrics.tonnage(of: sets)
        )
    }
}

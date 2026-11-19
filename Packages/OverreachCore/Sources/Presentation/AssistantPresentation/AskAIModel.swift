import AIExchange
import Domain
import Foundation
import Observation
import PresentationKit

/// How far back the shared context goes.
public enum ContextPeriod: Int, CaseIterable, Sendable {
    case fourWeeks = 4
    case twelveWeeks = 12
    case sixMonths = 26

    var weeks: Int { rawValue }

    var displayName: String {
        switch self {
        case .fourWeeks: L10n.text("Last 4 weeks")
        case .twelveWeeks: L10n.text("Last 12 weeks")
        case .sixMonths: L10n.text("Last 6 months")
        }
    }
}

/// An optional first request added after the context. The user edits or replaces it in the chat app.
public enum StarterRequest: String, CaseIterable, Sendable {
    case progress, nextBlock, routines, stalls

    var displayName: String {
        switch self {
        case .progress: L10n.text("Analyse my progress")
        case .nextBlock: L10n.text("Plan my next block")
        case .routines: L10n.text("Review my routines")
        case .stalls: L10n.text("Help with stalled lifts")
        }
    }

    var text: String {
        switch self {
        case .progress: L10n.text("Analyse my progress in this period: what is improving, what is not and why.")
        case .nextBlock: L10n.text("Help me plan my next training block.")
        case .routines: L10n.text("Review my routines and tell me what you would change.")
        case .stalls: L10n.text("Which lifts are stalled, and what should I try?")
        }
    }
}

/// "Ask AI" (ADR-0017): packs the training context as raw data for ChatGPT, Claude or another assistant. The user
/// asks the questions there; the app only prepares the data and an optional first request.
@MainActor
@Observable
public final class AskAIModel {
    public private(set) var period = ContextPeriod.twelveWeeks
    public private(set) var request: StarterRequest?
    /// The text to share or copy; `nil` until prepared.
    public private(set) var message: String?
    /// The same context as a `.json` file, for chat apps that take attachments.
    public private(set) var fileURL: URL?
    /// "34 sessions · 12 exercises · 41 KB".
    public private(set) var summary: String?
    public private(set) var isPreparing = false
    public private(set) var errorMessage: String?

    public let periodOptions = ContextPeriod.allCases.map { Option(value: $0, name: $0.displayName) }
    public let requestOptions = StarterRequest.allCases.map { Option(value: $0, name: $0.displayName) }

    private var json: String?
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let profiles: any ProfileRepository
    private let routines: any RoutineRepository
    private let checkIns: (any CheckInRepository)?
    private let sources: [any MetricsSource]
    private let appVersion: String?
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private let directory: URL

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        profiles: any ProfileRepository,
        routines: any RoutineRepository,
        checkIns: (any CheckInRepository)? = nil,
        sources: [any MetricsSource] = [],
        appVersion: String? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        directory: URL = FileManager.default.temporaryDirectory
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.progression = progression
        self.profiles = profiles
        self.routines = routines
        self.checkIns = checkIns
        self.sources = sources
        self.appVersion = appVersion
        self.clock = clock
        self.calendar = calendar
        self.directory = directory
    }

    public func setPeriod(_ period: ContextPeriod) async {
        guard period != self.period else { return }
        self.period = period
        await prepare()
    }

    public func setRequest(_ request: StarterRequest?) {
        self.request = request
        render()
    }

    /// Reads the data of the period and prepares the message and the file.
    public func prepare() async {
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        let now = clock()
        let today = CalendarDay(now, calendar: calendar)
        let first = today.adding(days: 1 - period.weeks * 7, calendar: calendar)
        let start = first.startDate(in: calendar)
        do {
            let all = try await workouts.sessions(from: start.addingTimeInterval(-365 * 86_400), to: now)
            let input = ContextInput(
                sessions: all.filter { $0.startedAt >= start },
                earlierSessions: all.filter { $0.startedAt < start },
                exercises: try await exercises.allExercises(),
                settings: try await progression.allProgressionSettings(),
                routines: try await routines.allRoutines(),
                profile: try? await profiles.profile(),
                checkIns: (try? await checkIns?.checkIns(in: first...today)) ?? [],
                dailyMetrics: await metrics(in: first...today),
                runs: await runs(from: start, to: now),
                appVersion: appVersion
            )
            let pack = ContextPackBuilder.build(input, period: first...today, now: now, calendar: calendar)
            let data = try ContextMessage.json(pack)
            let url = directory.appendingPathComponent("overreach-context-\(today).json")
            try data.write(to: url, options: .atomic)
            json = String(decoding: data, as: UTF8.self)
            fileURL = url
            summary = L10n.format(
                "{1} sessions · {2} exercises · {3} KB", pack.sessions.count, pack.exerciseTrends.count,
                max(1, (data.count + 1023) / 1024)
            )
            render()
        } catch {
            json = nil
            message = nil
            fileURL = nil
            summary = nil
            errorMessage = L10n.text("Could not prepare your data. Try again.")
        }
    }

    private func render() {
        message = json.map { ContextMessage.text(json: $0, request: request?.text) }
    }

    private func metrics(in range: ClosedRange<CalendarDay>) async -> [DailyMetrics] {
        var all: [DailyMetrics] = []
        for source in sources where await source.isAvailable() {
            all += (try? await source.dailyMetrics(in: range)) ?? []
        }
        return all
    }

    private func runs(from start: Date, to end: Date) async -> [RunActivity] {
        var all: [RunActivity] = []
        for source in sources where await source.isAvailable() {
            all += (try? await source.runs(from: start, to: end)) ?? []
        }
        return all
    }
}

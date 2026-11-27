import AIExchange
import Analytics
import Domain
import Foundation
import Observation
import PresentationKit
import TrainingServices

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
    public private(set) var metricGroups: Set<ContextMetricGroup> = []
    public private(set) var includesCycle = false
    public private(set) var availability = ""
    public private(set) var previewMessage: String?
    /// The text to share or copy after the preview is confirmed.
    public private(set) var message: String?
    /// The same context as a `.json` file, for chat apps that take attachments.
    public private(set) var fileURL: URL?
    /// "34 sessions · 12 exercises · 41 KB".
    public private(set) var summary: String?
    public private(set) var isPreparing = false
    public private(set) var errorMessage: String?

    public let periodOptions = ContextPeriod.allCases.map { Option(value: $0, name: $0.displayName) }
    public let requestOptions = StarterRequest.allCases.map { Option(value: $0, name: $0.displayName) }

    public let metricOptions = ContextMetricGroup.allCases.map { Option(value: $0, name: $0.displayName) }

    private var preparationID = UUID()
    private var json: String?
    private var context: ContextPack?
    private let recordLoader: TrainingRecordLoader
    private let activityMatchChoices: @MainActor () -> ActivityMatchChoices
    private let profiles: any ProfileRepository
    private let appVersion: String?
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private let directory: URL
    private let balanceDismissals: MuscleBalanceDismissals

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        profiles: any ProfileRepository,
        routines: any RoutineRepository,
        checkIns: (any CheckInRepository)? = nil,
        sources: [any MetricsSource] = [],
        recordedStrength: (any RecordedStrengthSource)? = nil,
        activity: [any ActivitySource] = [],
        cycle: (any CycleSource)? = nil,
        activityMatchChoices: @escaping @MainActor () -> ActivityMatchChoices = { .init() },
        appVersion: String? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        directory: URL = FileManager.default.temporaryDirectory,
        balanceDismissals: MuscleBalanceDismissals = .init()
    ) {
        self.activityMatchChoices = activityMatchChoices
        recordLoader = TrainingRecordLoader(
            sources: sources, activity: activity, checkIns: checkIns, workouts: workouts, exercises: exercises,
            recordedStrength: recordedStrength, routines: routines, progression: progression, cycle: cycle
        )
        self.profiles = profiles
        self.appVersion = appVersion
        self.clock = clock
        self.calendar = calendar
        self.directory = directory
        self.balanceDismissals = balanceDismissals
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

    public func setMetric(_ group: ContextMetricGroup, included: Bool) {
        if included {
            metricGroups.insert(group)
        } else {
            metricGroups.remove(group)
        }
        exportSelection()
    }

    public func setIncludesCycle(_ includesCycle: Bool) {
        self.includesCycle = includesCycle
        exportSelection()
    }

    public func setAvailability(_ availability: String) {
        self.availability = availability
        render()
    }

    /// Reads the selected period and prepares the report preview.
    public func prepare() async {
        let id = UUID()
        preparationID = id
        isPreparing = true
        discardPreview()
        errorMessage = nil
        let now = clock()
        let today = CalendarDay(now, calendar: calendar)
        let first = today.adding(days: 1 - period.weeks * 7, calendar: calendar)
        let start = first.startDate(in: calendar)
        let profile = try? await profiles.profile()
        let snapshot = await recordLoader.load(now: now, profile: profile, exportFrom: first, calendar: calendar)
        guard preparationID == id else { return }
        isPreparing = false
        guard !Task.isCancelled, !snapshot.localReadFailed else {
            clearPreparedData()
            return
        }
        let assessment = snapshot.assessment(profile: profile, now: now, calendar: calendar)
        let record = snapshot.record
        let choices = activityMatchChoices()
        let runResolution = RunDeduplication.resolve(snapshot.runOriginals, choices: choices.runs)
        let runs = runResolution.runs
        let strength = StrengthActivityMatching.resolve(
            sessions: snapshot.allSessions, activities: snapshot.strengthOriginals, choices: choices.strength
        ).matches
        let input = ContextInput(
            sessions: snapshot.allSessions.filter { $0.startedAt >= start },
            earlierSessions: snapshot.allSessions.filter { $0.startedAt < start },
            exercises: record.exercises,
            settings: record.settings,
            routines: record.routines,
            profile: profile,
            checkIns: snapshot.allCheckIns.filter { $0.day >= first },
            dailyMetrics: snapshot.metricsBySource.filter { $0.day >= first },
            runs: runs.map(\.activity).filter { (start...now).contains($0.startedAt) },
            today: .init(
                assessment, training: snapshot.dayTraining(profile: profile, now: now, calendar: calendar)
            ),
            appVersion: appVersion
        )
        context = ContextPackBuilder.build(
            input, period: first...today, now: now, calendar: calendar, matchedStrength: strength
        )
        setRecordedActivities(snapshot, strength: strength, dates: start...now)
        context?.muscleBalance = muscleBalance(
            record: record, profile: profile, runs: runResolution.unambiguousRuns, now: now
        )
        context?.sleepTrainingTiming = ContextPack.SleepTrainingTimingSummary(
            snapshot.sleepTrainingTiming(resolvedRuns: runResolution.unambiguousRuns, now: now, calendar: calendar)
        )
        exportSelection()
    }

    private func setRecordedActivities(
        _ snapshot: TrainingRecordLoader.Snapshot, strength: StrengthActivityMatches, dates: ClosedRange<Date>
    ) {
        let walks = EverydayMovement.removingDuplicateWalks(snapshot.walkOriginals)
            .filter { dates.contains($0.start) }
            .map(ContextPack.Walk.init)
        context?.walks = walks.isEmpty ? nil : walks
        let recordings = strength.unmatched.filter { dates.contains($0.startedAt) }
            .sorted { $0.startedAt < $1.startedAt }
            .map { ContextPack.StrengthRecording($0, watch: ContextPackBuilder.watch($0)) }
        context?.strengthRecordings = recordings.isEmpty ? nil : recordings
    }

    private func muscleBalance(
        record: TrainingRecord, profile: AthleteProfile?, runs: [RunActivity], now: Date
    ) -> [ContextPack.BalanceSuggestion]? {
        let findings = record.muscleBalance(profile: profile, resolvedRuns: runs, now: now, calendar: calendar)
        let rows = balanceDismissals.visible(
            MuscleBalanceAudit.rows(for: findings), in: MuscleBalanceAudit.historyScope
        )
        guard !rows.isEmpty else { return nil }
        return rows.map {
            .init(text: $0.text, evidenceKey: $0.evidence.key, evidenceLevel: $0.evidence.level.rawValue,
                  runningContext: $0.runningContext)
        }
    }

    private func exportSelection() {
        guard let context else { return }
        let pack = context.selectingMetrics(metricGroups, cycle: includesCycle)
        do {
            let data = try ContextMessage.json(pack)
            errorMessage = nil
            json = String(decoding: data, as: UTF8.self)
            summary = L10n.format(
                "{1} sessions · {2} exercises · {3} KB", pack.sessions.count, pack.exerciseTrends.count,
                max(1, (data.count + 1023) / 1024)
            )
            render()
        } catch {
            clearPreparedData()
        }
    }

    public func confirmPreview() {
        guard let json, let previewMessage else { return }
        let url = directory.appendingPathComponent("overreach-context-\(UUID().uuidString).json")
        do {
            try Data(json.utf8).write(to: url, options: .atomic)
            fileURL = url
            message = previewMessage
        } catch {
            clearPreparedData()
        }
    }

    private func discardPreview() {
        context = nil
        json = nil
        message = nil
        fileURL = nil
        summary = nil
        previewMessage = nil
    }

    private func clearPreparedData() {
        discardPreview()
        errorMessage = L10n.text("Could not prepare your data. Try again.")
    }

    private func render() {
        message = nil
        fileURL = nil
        previewMessage = json.map { json in
            guard request == .nextBlock else { return ContextMessage.text(json: json, request: request?.text) }
            let available = availability.trimmingCharacters(in: .whitespacesAndNewlines)
            var instructions = [PlanMessage.formatGuide]
            if !available.isEmpty {
                instructions.append(L10n.format("My training availability is {1}.", available))
            }
            instructions.append(StarterRequest.nextBlock.text)
            return ContextMessage.text(json: json, request: instructions.joined(separator: "\n\n"))
        }
    }
}

extension ContextMetricGroup {
    fileprivate var displayName: String {
        switch self {
        case .sleep: L10n.text("Sleep")
        case .heart: L10n.text("Heart rate and HRV")
        case .recovery: L10n.text("Recovery metrics")
        case .load: L10n.text("Training load and fitness")
        case .movement: L10n.text("Steps and walks")
        case .personal: L10n.text("Profile biometrics and check-ins")
        }
    }
}

import Analytics
import Domain
import Foundation
import Observation
import PresentationKit
import TrainingServices

/// One reason behind the readiness light, with the strength of its evidence.
public struct ReadinessLine: Hashable, Sendable {
    public let text: String
    public let kind: ReadinessObservation.Kind
    public let evidence: String
    public let source: URL?
    /// "Learn more" for this reason (ADR-0030); often empty.
    public let readings: [Reading]
}

/// State and actions of the Today screen (ADR-0003, ADR-0014): dependencies come in as `Domain` protocols, the
/// view only reads state and calls actions.
@MainActor
@Observable
public final class TodayModel {
    public private(set) var metrics: DailyMetrics?
    /// The last 7 days (today included), merged across sources, oldest first. Days without data are left out.
    public private(set) var week: [DailyMetrics] = []
    /// The week plus the week before it, so readings before an early race in the week can be compared.
    private var recentNights: [DailyMetrics] = []
    public private(set) var readiness = Readiness(level: .unknown, reasons: [.missingData])
    public private(set) var isLoading = false
    /// Sources that failed during the last load. The screen still shows whatever the others returned.
    public private(set) var failedSources: [DataSourceKind] = []
    /// Why each failed source failed (the system's own message), so the screen can say more than "failed".
    private var failureReasons: [DataSourceKind: String] = [:]
    /// Set when asking a source for access failed, e.g. Apple Health without the HealthKit entitlement.
    public private(set) var accessError: String?
    /// Today's check-in, once filled in.
    public private(set) var checkIn: CheckIn?
    private var recentRunPain = false
    public private(set) var recentTrainingDays: [RecentTrainingDay] = []
    public private(set) var scheduledStrengthToday: ScheduledTrainingRow?
    public private(set) var scheduledRunsToday: [ScheduledTrainingRow] = []
    public private(set) var strengthOption: StrengthOption?
    public private(set) var runningOption: RunningOption?
    private var keptPlannedRunDay: CalendarDay?
    private var hasRunningGoal = false
    private var heroTrainingAction: NextAction = .train
    /// A deload proposal (training reinforced by recovery, `deload-recovery-signals`) or the deload week in progress.
    public private(set) var deloadAdvice: DeloadAdvice?
    /// The next session with the deload applied, when the app knows which session comes next.
    public private(set) var deloadSession: DeloadSessionPreview?
    /// Workouts the athlete can say they will do next, when there is no plan (most recent first, or rotation order).
    public private(set) var strengthChoices: [StrengthChoice] = []
    /// What the app knows about the next session: the detected rotation, or that it cannot tell.
    public private(set) var strengthChoiceNote: String?
    private var recentWorkouts: WorkoutContext?
    private var strengthInputs: StrengthInputs?
    private var optionalStrengthDay: CalendarDay?
    private var chosenWorkout: (day: CalendarDay, id: String)?
    private var trainingReadFailed = false
    private var activeLoad: UUID?
    private var loadedDay: CalendarDay?
    /// Today was marked as a deliberate rest (ADR-0041, rule 7).
    public private(set) var restLoggedToday = false
    /// Tomorrow's planned session, for the calm confirmation after logging rest.
    private var tomorrowOutlook: String?
    /// Whether a Garmin account is connected (ADR-0022).
    public private(set) var isGarminConnected = false
    /// The person said they use a Garmin (first-run setup).
    private var wearsGarmin = false
    /// Steps and walks against the usual day (ADR-0010): spikes, very low days and recovery walks.
    public var movementNotes: [MovementNote] {
        guard let now = movementNow,
              let day = calendar.dateInterval(of: .day, for: now) else { return movementAdvice }
        let summary = MovementNote.dogWalkSummary(
            walks: movementWalks, answers: companionAnswers.values, routine: movementRoutine,
            during: day, format: format
        )
        return movementAdvice + (summary.map { [$0] } ?? [])
    }

    private var movementAdvice: [MovementNote] = []
    /// "With Nanoq?" for the latest recent walk nobody has answered yet.
    public var dogWalkQuestion: DogWalkQuestion? {
        guard let now = movementNow else { return nil }
        return DogWalkQuestion.next(
            walks: movementWalks, answers: companionAnswers.values, routine: movementRoutine, now: now,
            in: .init(calendar: calendar, format: format)
        )
    }
    private let companionAnswers: DogWalkAnswers
    private var movementWalks: [WalkBout] = []
    private var movementRoutine = WalkingRoutine()
    private var movementNow: Date?
    private var usualSteps: Double?

    private let recordLoader: TrainingRecordLoader
    private let activityMatchChoices: @MainActor () -> ActivityMatchChoices
    private let sources: [any MetricsSource]
    private let garmin: (any GarminAccount)?
    private let profiles: (any ProfileRepository)?
    /// Menstrual events and tracking mode of the last load, for phase-aware baselines (`cycle-phase-baselines`).
    private var cycleContext: CycleContext?
    private let checkIns: (any CheckInRepository)?
    private let backup: (any BackupService)?
    private let workouts: (any WorkoutRepository)?
    private let readinessSettings: ReadinessRules.Settings
    private let calendar: Calendar
    private let format: Format

    // MARK: Screen state

    public enum WorkoutContinuation: Equatable {
        case resume(String), reviewDraft
    }

    public enum NextAction: Equatable {
        case continueWorkout(WorkoutContinuation)
        case startStrength(Routine)
        case runEasy(minutes: Int?)
        case reviewRun
        case loading, rest, restLogged, trainedToday, checkIn, deload, retry, connectHealth, connectGarmin, train

        public var title: String? {
            switch self {
            case .loading: nil
            case .continueWorkout(.resume): L10n.text("Resume workout")
            case .continueWorkout(.reviewDraft): L10n.text("Review saved workout")
            case let .startStrength(routine): L10n.format("Start {1}", routine.name)
            case let .runEasy(minutes?):
                L10n.format("Run {1} min easy", String(minutes))
            case .runEasy(nil): L10n.text("Run easy")
            case .reviewRun: L10n.text("Review today's run")
            case .rest: L10n.text("Rest today")
            case .restLogged: L10n.text("Undo rest")
            case .trainedToday: L10n.text("Log another workout")
            case .checkIn: L10n.text("Check in")
            case .deload: DeloadProposalText.start(steadier: false)
            case .retry: L10n.text("Try again")
            case .connectHealth: L10n.text("Connect Apple Health")
            case .connectGarmin: L10n.text("Connect your Garmin")
            case .train: L10n.text("Open Train")
            }
        }
    }

    public func nextAction(continuing workout: WorkoutContinuation?) -> NextAction {
        workout.map(NextAction.continueWorkout) ?? nextAction
    }

    public var heroTitle: String {
        switch nextAction {
        case .restLogged: L10n.text("Rest logged. Recovery is training too.")
        case .trainedToday: L10n.text("You've trained today. Recovery is part of the plan.")
        default: readinessAdvice
        }
    }

    public var heroReason: String {
        if nextAction == .restLogged || nextAction == .trainedToday, let tomorrowOutlook { return tomorrowOutlook }
        return readinessSummary ?? readiness.reasons.first.map { text(for: $0) }
            ?? L10n.text("No recovery signals call for reducing training today.")
    }

    public func primaryActionTitle(continuing workout: WorkoutContinuation? = nil) -> String? {
        if workout == nil, nextAction == .deload, case let .proposed(explanation) = deloadAdvice?.state {
            return DeloadProposalText.start(steadier: explanation.lifeStress == .reported)
        }
        return nextAction(continuing: workout).title
    }

    /// Orders existing actions for the first viewport.
    public var nextAction: NextAction {
        let action = baseAction
        return action == .rest && restLoggedToday ? .restLogged : action
    }

    private var baseAction: NextAction {
        guard loadedDay != nil else { return .loading }
        if readiness.reasons.contains(where: \.advisesSkippingTraining) { return .rest }
        if showsCheckIn, suggestedContextQuestion != nil { return .checkIn }
        if readinessLevel == .red { return .rest }
        if case .proposed = deloadAdvice?.state { return .deload }
        if readinessLevel == .amber { return heroTrainingAction }
        if showsSourceWarning, readinessLevel == .unknown { return .retry }
        if showsConnectGarmin, !showsMetrics { return .connectGarmin }
        if showsConnectHealth, !showsMetrics { return .connectHealth }
        if readinessLevel == .unknown, showsCheckIn, checkIn == nil { return .checkIn }
        if readinessLevel == .green { return heroTrainingAction }
        return .train
    }

    /// The single prompt under the hero. Fixed at each load: answering or dismissing one reveals the next on the next
    /// load, not at once.
    public var pendingPrompt: TodayPrompt? {
        guard promptHandledLoad != activeLoadCount else { return nil }
        return TodayPrompt.next(promptFacts)
    }

    private var promptFacts: TodayPrompt.Facts {
        var facts = TodayPrompt.Facts()
        guard showsReadinessCard else { return facts }
        facts.sourceFailure = showsSourceWarning || trainingReadNote != nil
        if case .confirmBreak = deloadAdvice?.state { facts.confirmBreak = true }
        facts.checkIn = showsCheckIn
        facts.connectHealth = showsConnectHealth
        facts.connectGarmin = showsConnectGarmin
        facts.dogWalk = dogWalkQuestion != nil
        facts.shownByPrimary = switch nextAction {
        case .retry: .sourceFailure
        case .checkIn: .checkIn
        case .connectHealth: .connectHealth
        case .connectGarmin: .connectGarmin
        default: nil
        }
        return facts
    }

    /// The blocks Today may stack (ADR-0041, rule 3). Everything else lives on a pushed screen.
    public enum Block: Equatable, Sendable { case hero, scheduledPlan, pendingPrompt, linkRow }

    /// The most blocks Today shows at once.
    public static let blockBudget = 4

    public var visibleBlocks: [Block] {
        var blocks: [Block] = [.hero]
        if scheduledStrengthToday != nil || !scheduledRunsToday.isEmpty { blocks.append(.scheduledPlan) }
        if pendingPrompt != nil { blocks.append(.pendingPrompt) }
        if !links.isEmpty { blocks.append(.linkRow) }
        return blocks
    }

    /// The routes from Today to level 2, in order: Why · Other options · Recovery · History.
    public enum Link: Equatable, Sendable { case why, otherOptions, recovery, history }

    public var links: [Link] {
        guard showsReadinessCard else { return [] }
        var links: [Link] = [.why]
        if showsOtherOptions { links.append(.otherOptions) }
        return links + [.recovery, .history]
    }

    /// Alternatives to the hero: an optional run or an easy strength session.
    public var showsOtherOptions: Bool {
        runningOption?.isOptional == true || canRequestStrengthOption || scheduledStrengthToday != nil
            && strengthOption != nil
    }

    /// Hides the prompt until the next load.
    public func dismissPendingPrompt() { promptHandledLoad = activeLoadCount }
    private var activeLoadCount = 0
    private var promptHandledLoad = -1

    public var readinessLevel: ReadinessLevel { readiness.level }
    public var readinessTitle: String { readiness.level.displayName }

    /// What the light means for today's training.
    public var readinessAdvice: String {
        if readiness.reasons.contains(where: \.advisesSkippingTraining) {
            return safetyAdvice
        }
        return switch readiness.level {
        case .green: L10n.text("Train as planned.")
        case .amber: hasRunningGoal || scheduledStrengthToday != nil ? L10n.text("Keep it easy today.")
            : L10n.text("Keep it easy today. Run at a pace you can talk at, or lift with light effort.")
        case .red: L10n.text("Make it a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).")
        case .unknown: L10n.text("Not enough data yet to judge today.")
        }
    }

    private var safetyAdvice: String {
        if readiness.reasons.contains(.exerciseWarningSigns) {
            return L10n.text("Skip training and seek medical advice before returning to exercise.")
        }
        if readiness.reasons.contains(.runningPainLimitsTraining) {
            return L10n.text("Skip today's session and reassess the pain before running again.")
        }
        if readiness.reasons.contains(.markedSick) {
            return L10n.text("Rest today. Ease back into training once you feel well again.")
        }
        return L10n.text("Skip training today and reassess how you feel.")
    }

    /// Why the light has its colour, each reason with its evidence level.
    public var readinessLines: [ReadinessLine] {
        readiness.reasons.map { reason in
            let evidence = ReadinessRules.evidence(for: reason)
            let source = ReadinessRules.evidenceURL(for: reason)
            return ReadinessLine(
                text: text(for: reason), kind: observationKind(for: reason),
                evidence: evidence.level.displayName, source: source,
                // The research source already has its own link.
                readings: FurtherReading.readings(for: evidence).filter { $0.url != source }
            )
        }
    }

    public var hrvCoverageNote: String? {
        guard let coverage = readiness.hrvCoverage else { return hrvSkippedNote }
        guard !coverage.canCompare else { return nil }
        let series = coverage.metric?.seriesLabel ?? L10n.text("HRV")
        if coverage.baselineReadings < coverage.minimumBaselineReadings {
            return L10n.format(
                "Still building your usual HRV range ({1}: {2} of {3} comparable readings needed).",
                series, String(coverage.baselineReadings), String(coverage.minimumBaselineReadings)
            )
        }
        return L10n.format(
            "Too few comparable HRV readings ({1}) in the last {2} days ({3} available, {4} needed).",
            series, String(coverage.recentDays), String(coverage.recentReadings), String(coverage.minimumRecentReadings)
        )
    }

    /// Why no HRV series was judged when none had a usable reading in the recent window (ADR-0032).
    private var hrvSkippedNote: String? {
        guard let input = readiness.hrvInput, case .hrv(let series?) = input.input else { return nil }
        switch input.status {
        case .stale:
            guard let latest = input.latestDay else { return nil }
            let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
            return L10n.format(
                "HRV not used today: no recent reading ({1}). The latest was on {2}.",
                series.metric.seriesLabel, latest.startDate(in: calendar).formatted(style.day().month(.abbreviated))
            )
        case .outOfRange:
            return L10n.format(
                "HRV not used today: the recent readings ({1}) are outside the plausible range.",
                series.metric.seriesLabel
            )
        default:
            return nil
        }
    }

    public var showsReadinessDetails: Bool { !readiness.reasons.isEmpty || !readiness.inputs.isEmpty }
    public var showsReadinessCard: Bool { loadedDay != nil }

    public var readinessSummary: String? {
        guard let reason = readiness.reasons.first(where: { observationKind(for: $0) == .supporting }) else {
            return nil
        }
        if reason == .markedSick { return L10n.text("You marked yourself as sick in today's check-in.") }
        return text(for: reason)
    }

    public var readinessObservations: [ReadinessObservation] { explanation.observations }
    public var readinessSources: [ReadinessSourceDetail] { explanation.sources }

    private func observationKind(for reason: ReadinessReason) -> ReadinessObservation.Kind {
        if reason == .missingData { return .unavailable }
        if reason.isContext { return .context }
        if case .hrvBelowBaseline = reason, readiness.reasons.contains(.hrvMayReflectCycle) {
            return .context
        }
        return .supporting
    }
    public var readinessTrainingContext: ReadinessTrainingContext? { isLoading ? nil : explanation.trainingContext }

    private var explanation: ReadinessExplanation {
        ReadinessExplanation(
            readiness: readiness, nights: recentNights, plausibleHRV: readinessSettings.plausibleHRVMs,
            training: recentTrainingDays, calendar: calendar, format: format
        )
    }

    /// Recent workouts feed the readiness explanation, the deload and the strength option; History lists them.
    public var trainingReadNote: String? {
        trainingReadFailed ? L10n.text("Some recent workouts could not be loaded.") : nil
    }

    /// The check-in button only shows when check-ins can be stored.
    public var showsCheckIn: Bool { checkIns != nil }
    public var checkInButtonTitle: String {
        if let title = CheckInModel.title(for: suggestedContextQuestion) { return title }
        return checkIn == nil ? L10n.text("How do you feel today?") : L10n.text("Edit today's check-in")
    }

    private var suggestedContextQuestion: CheckIn.Context.Question? {
        guard !isLoading, checkIn?.context == nil, let loadedDay else { return nil }
        let yesterday = loadedDay.adding(days: -1, calendar: calendar)
        let trainedRecently = recentTrainingDays.contains { $0.id >= yesterday && !$0.workouts.isEmpty }
        if let question = ReadinessRules.contextQuestion(
            for: readiness, recentRunPain: recentRunPain, trainedRecently: trainedRecently
        ) { return question }
        // A deload that stress could explain waits for the athlete's answer (`deload-life-stress`).
        if case let .proposed(explanation) = deloadAdvice?.state, explanation.lifeStress == .unanswered {
            return .stress
        }
        return nil
    }

    /// "Energy 4/5 · Soreness 1/3", or "Sick" — what today's check-in said.
    public var checkInSummary: String? {
        guard let checkIn else { return nil }
        if checkIn.exerciseWarningSigns == true { return L10n.text("Symptoms to discuss with a clinician") }
        if checkIn.isSick { return L10n.text("Sick") }
        var parts: [String] = []
        if let energy = checkIn.energy { parts.append(L10n.format("Energy {1}/5", String(energy))) }
        if let soreness = checkIn.soreness { parts.append(L10n.format("Soreness {1}/3", String(soreness))) }
        switch checkIn.context?.answer == .yes ? checkIn.context?.question : nil {
        case .symptoms: parts.append(L10n.text("New symptoms affect training"))
        case .stress: parts.append(L10n.text("More stress than usual"))
        case .fatigue: parts.append(L10n.text("More fatigue than usual"))
        case .runningPain: parts.append(L10n.text("Running pain worsened or affected your stride"))
        case nil: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The check-in sheet for today. After it saves, call `load()` to update the light.
    public func makeCheckInModel(now: Date = .now) -> CheckInModel? {
        guard let checkIns else { return nil }
        let today = CalendarDay(now, calendar: calendar)
        return CheckInModel(
            day: today, existing: checkIn?.day == today ? checkIn : nil, checkIns: checkIns, backup: backup,
            contextQuestion: loadedDay == today ? suggestedContextQuestion : nil
        )
    }

    public var hrvMs: Double? { metrics?.hrvNightlyAverageMs }
    public var restingHeartRate: Double? { metrics?.restingHeartRate }
    /// Sleep in hours (stored in seconds).
    public var sleepHours: Double? { metrics?.sleepSeconds.map { $0 / 3_600 } }
    public var bodyBattery: Double? { metrics?.bodyBatteryHigh }
    public var steps: Double? { metrics?.steps.map(Double.init) }
    public var vo2Max: Double? { metrics?.vo2Max }
    public var stress: Double? { metrics?.averageStress }

    // A tile shows only when some connected source measures that metric: a value today or in the last 7 days. Without
    // an Apple Watch or Garmin there is no HRV tile at all, rather than an empty one.
    public var showsSleep: Bool { has(\.sleepSeconds) }
    public var showsHRV: Bool { has(\.hrvNightlyAverageMs) }
    public var showsRestingHeartRate: Bool { has(\.restingHeartRate) }
    public var showsSteps: Bool { has { $0.steps.map(Double.init) } }
    /// Body Battery and stress are Garmin's.
    public var showsBodyBattery: Bool { has(\.bodyBatteryHigh) }
    public var showsStress: Bool { has(\.averageStress) }
    public var showsVO2Max: Bool { has(\.vo2Max) }
    /// Whether any metric tile shows.
    public var showsMetrics: Bool {
        showsSleep || showsHRV || showsRestingHeartRate || showsSteps || showsBodyBattery || showsStress
            || showsVO2Max
    }

    /// The "Connect Garmin" card: for someone who said they use a Garmin and has not connected it, or when no source
    /// has given anything yet. Settings → Garmin is always there too.
    public var showsConnectGarmin: Bool {
        garmin != nil && !isGarminConnected && !isLoading && (wearsGarmin || !showsMetrics)
    }

    // Every number says what kind it is (evidence review 2026-11, §5): measured by the devices, estimated by them, or
    // computed by Overreach. Sleep stages, Garmin's scores and VO2max are the watch's estimates and never feed a rule.

    /// "Deep 1.2 h · REM 1.6 h (watch estimate)": consumer sleep staging agrees only fairly to moderately with a
    /// sleep lab (`wearable-sleep-stages`).
    public var sleepCaption: String? {
        guard let metrics, metrics.deepSleepSeconds != nil || metrics.remSleepSeconds != nil else { return nil }
        let hours = { (seconds: Double?) in self.format.number((seconds ?? 0) / 3_600, maxFractionDigits: 1) }
        return L10n.format(
            "Deep {1} h · REM {2} h (watch estimate)", hours(metrics.deepSleepSeconds), hours(metrics.remSleepSeconds)
        )
    }

    /// "RMSSD · 7-day avg 42 ms": the statistic shown for the latest night, and its weekly average. RMSSD and SDNN are
    /// separate series and never averaged together (ADR-0025).
    public var hrvCaption: String? {
        let latest = ([metrics].compactMap { $0 } + week.reversed()).lazy.compactMap(\.hrvMetric).first
        guard let latest else { return nil }
        let statistic = latest.rawValue.uppercased()
        guard let weekly = average({ $0.hrv(latest) }) else { return statistic }
        return statistic + " · " + self.weekly(format.number(weekly, maxFractionDigits: 0) + " ms")
    }

    /// Body Battery and stress are Garmin's own scores, not validated independently (`composite-scores`).
    public var bodyBatteryCaption: String { L10n.text("Garmin's estimate") }
    public var stressCaption: String { L10n.text("Garmin's estimate") }
    /// Watch VO2max estimates have a wide individual error: useful as a long-term trend (`wearable-vo2max`).
    public var vo2MaxCaption: String { L10n.text("Watch estimate, follow the trend") }
    public var restingHeartRateCaption: String? {
        average(\.restingHeartRate).map { weekly(format.number($0, maxFractionDigits: 0) + " bpm") }
    }
    public var sleepAverageCaption: String? {
        average(\.sleepSeconds).map { weekly(format.number($0 / 3_600, maxFractionDigits: 1) + " h") }
    }
    /// "Usually 8,400 a day" once there are enough days for the usual day (`walking-load-baseline`), otherwise the
    /// weekly average.
    public var stepsCaption: String? {
        if let usualSteps {
            return L10n.format("Usually {1} a day", format.number(usualSteps, maxFractionDigits: 0))
        }
        return average { $0.steps.map(Double.init) }.map { weekly(format.number($0, maxFractionDigits: 0)) }
    }

    /// "From Apple Health · Garmin" — where today's numbers come from.
    public var sourcesText: String? {
        guard let metrics, !metrics.sources.isEmpty else { return nil }
        let names = DataSourceKind.allCases.filter(metrics.sources.contains).map(\.displayName)
        return L10n.format("From {1}", names.joined(separator: " · "))
    }

    public var showsSourceWarning: Bool { !failedSources.isEmpty }
    /// "Apple Health: <system message>" for each failed source, one per line.
    public var sourceWarningDetail: String? {
        let lines = failedSources.compactMap { kind in failureReasons[kind].map { "\(kind.displayName): \($0)" } }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    public var showsNoDataHint: Bool { !isLoading && metrics == nil && failedSources.isEmpty }
    /// The "Connect Apple Health" button: shown while there is nothing to display.
    public var showsConnectHealth: Bool { !isLoading && metrics == nil }

    /// - Parameter sources: metric sources in priority order. When two sources report the same value,
    ///   the first one wins (e.g. `[garmin, appleHealth]`).
    /// - Parameter checkIns: today's check-in adds how the user feels (and "sick") to the readiness light.
    /// - Parameter cycle: menstrual flow from Apple Health, read only for a natural cycle (ADR-0009).
    /// - Parameter activity: walks from Apple Health or Garmin (ADR-0010). Steps come from `sources`.
    public init(
        sources: [any MetricsSource], activity: [any ActivitySource] = [], checkIns: (any CheckInRepository)? = nil,
        backup: (any BackupService)? = nil,
        garmin: (any GarminAccount)? = nil, profiles: (any ProfileRepository)? = nil,
        workouts: (any WorkoutRepository)? = nil, exercises: (any ExerciseRepository)? = nil,
        recordedStrength: (any RecordedStrengthSource)? = nil, routines: (any RoutineRepository)? = nil,
        progression: (any ProgressionSettingsRepository)? = nil, cycle: (any CycleSource)? = nil,
        activityMatchChoices: @escaping @MainActor () -> ActivityMatchChoices = { .init() },
        dogWalkAnswers: [WalkCompanionAnswer] = [],
        saveDogWalkAnswers: @escaping @MainActor ([WalkCompanionAnswer]) -> Void = { _ in },
        companionAnswers: DogWalkAnswers? = nil,
        readinessSettings: ReadinessRules.Settings = ReadinessRules.Settings(), calendar: Calendar = .current,
        format: Format = Format()
    ) {
        self.activityMatchChoices = activityMatchChoices
        self.companionAnswers = companionAnswers ?? DogWalkAnswers(dogWalkAnswers, save: saveDogWalkAnswers)
        recordLoader = TrainingRecordLoader(
            sources: sources, activity: activity, checkIns: checkIns, workouts: workouts, exercises: exercises,
            recordedStrength: recordedStrength, routines: routines, progression: progression, cycle: cycle
        )
        self.sources = sources
        self.garmin = garmin
        self.profiles = profiles
        self.checkIns = checkIns
        self.backup = backup
        self.workouts = workouts
        self.readinessSettings = readinessSettings
        self.calendar = calendar
        self.format = format
    }

    public func load(now: Date = .now) async {
        let loadID = UUID()
        activeLoad = loadID
        activeLoadCount += 1
        isLoading = true
        scheduledStrengthToday = nil
        scheduledRunsToday = []
        strengthOption = nil
        strengthInputs = nil
        runningOption = nil
        heroTrainingAction = .train
        recentRunPain = false
        defer {
            if activeLoad == loadID {
                isLoading = false
                activeLoad = nil
            }
        }

        let today = CalendarDay(now, calendar: calendar)
        if optionalStrengthDay != today { optionalStrengthDay = nil }
        let profile = try? await profiles?.profile()
        async let garminConnection = garmin?.connection()
        let snapshot = await recordLoader.load(
            now: now, profile: profile, settings: readinessSettings, calendar: calendar
        )
        let calendar = calendar
        let settings = readinessSettings
        let assessment = await Task.detached(priority: .userInitiated) {
            snapshot.assessment(profile: profile, now: now, settings: settings, calendar: calendar)
        }.value
        let garminConnected = await garminConnection != nil
        guard activeLoad == loadID else { return }
        cycleContext = snapshot.record.cycle
        let goal = profile?.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        hasRunningGoal = goal?.running.map { $0.distanceMeters > 0 } ?? false
        loadedDay = today
        restLoggedToday = profile?.restDays.contains(today) ?? false
        let weekStart = today.adding(days: -6, calendar: calendar)
        let history = snapshot.record.metrics
        week = history.filter { $0.day >= weekStart }
        recentNights = history.filter { $0.day >= weekStart.adding(days: -7, calendar: calendar) }
        metrics = history.last { $0.day == today }
        failedSources = snapshot.metrics.failedSources
        failureReasons = Dictionary(
            snapshot.metrics.failures.map { ($0.source, $0.reason) }, uniquingKeysWith: { first, _ in first }
        )
        checkIn = snapshot.checkIn
        isGarminConnected = garminConnected
        wearsGarmin = profile?.wearables.contains(.garmin) ?? false
        readiness = assessment.readiness
        deloadAdvice = workouts == nil ? nil : assessment.deload.map {
            DeloadAdvice.make($0, exercises: snapshot.record.exercises, calendar: calendar, format: format)
        }
        loadRecentTraining(
            in: weekStart...today, now: now, profile: profile, snapshot: snapshot, runningBreak: assessment.runningBreak
        )
    }

    private func loadRecentTraining(
        in range: ClosedRange<CalendarDay>, now: Date, profile: AthleteProfile?,
        snapshot: TrainingRecordLoader.Snapshot, runningBreak: DetectedDeload?
    ) {
        let record = snapshot.record
        trainingReadFailed = record.runReadFailed || snapshot.sessionsFailed
        recentTrainingDays = RecentTraining(calendar: calendar, format: format).days(
            in: range, through: now, metrics: week, checkIns: record.checkIns,
            runs: snapshot.runOriginals, sessions: record.sessions, recordings: snapshot.strengthOriginals,
            exercises: record.exercises, choices: activityMatchChoices(),
            races: (profile?.goal?.scheduledRuns ?? []).compactMap { $0.purpose == .race ? $0.completion : nil }
        )
        let today = range.upperBound
        let goal = profile?.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        loadRunningPlan(
            goal: goal, today: today, now: now, runs: record.runs,
            runningBreak: runningBreak, runReadFailed: record.runReadFailed
        )
        loadWorkoutContext(today: today, profile: profile, record: record)
        updateDeloadSession()

        let assignment = goal?.scheduledStrength.first { $0.day == today }
        let assignedRoutine = assignment?.routineID.flatMap { id in record.routines.first { $0.id == id } }
        scheduledStrengthToday = assignment.map {
            ScheduledTrainingRow.strength($0, routine: assignedRoutine, sessions: record.sessions,
                                          now: now, calendar: calendar)
        }
        let activeRuns = goal?.scheduledRuns.filter { $0.day == today && !$0.isPostponed } ?? []
        tomorrowOutlook = outlook(goal: goal, after: today, routines: record.routines)
        let pendingRuns = activeRuns.filter { $0.completion == nil }
        let nextSlot = recentWorkouts?.planned ?? recentWorkouts?.rotation?.next
        let strength = nextSlot.flatMap { slot in record.routines.first { $0.id.uuidString == slot.id } }
        let strengthDone = hasStrengthToday(sessions: snapshot.allSessions, recordings: record.recordings, now: now)
        let runDone = hasRunToday(record.runs, planned: activeRuns, now: now)
        heroTrainingAction = trainingAction(
            strength: strengthDone ? nil : strength, strengthRest: assignment != nil && assignment?.routineID == nil,
            runs: pendingRuns, priority: goal?.effectivePriority ?? .balanced,
            trainedToday: strengthDone || runDone,
            strengthPlanned: !strengthDone && assignment?.routineID != nil
        )
        updateMovement(
            snapshot, today: today, now: now, profile: profile,
            schedule: .init(strength: assignment,
                            routine: scheduledStrengthToday?.status == nil ? assignedRoutine : nil,
                            exercises: record.exercises, runs: activeRuns)
        )
        guard assignment == nil || assignedRoutine != nil,
              readiness.level == .amber, !readiness.reasons.contains(where: \.advisesSkippingTraining),
              workouts != nil, !snapshot.sessionsFailed,
              !strengthDone else { return }
        if assignment == nil, activeRuns.contains(where: { $0.purpose == .race && $0.completion == nil }) { return }
        loadStrengthOption(
            today: today, now: now, profile: profile, assignedRoutine: assignedRoutine, snapshot: snapshot
        )
    }

    /// "Tomorrow: Strength · Lower" from the plan, when it has something for the next day.
    private func outlook(goal: TrainingGoal?, after today: CalendarDay, routines: [Routine]) -> String? {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        var titles = (goal?.scheduledStrength ?? []).filter { $0.day == tomorrow }.map { assignment in
            assignment.displayName(
                routineName: assignment.routineID.flatMap { id in routines.first { $0.id == id }?.name }
            )
        }
        titles += (goal?.scheduledRuns ?? []).filter { $0.day == tomorrow && !$0.isPostponed && $0.purpose != .rest }
            .map { $0.calendarTitle(format: format) }
        guard !titles.isEmpty else { return nil }
        return L10n.format("Tomorrow: {1}", titles.joined(separator: " · "))
    }

    /// Records today as a deliberate rest. The hero then shows a calm confirmation (ADR-0041, rule 7).
    public func logRest(now: Date = .now) async {
        await setRest(true, now: now)
    }

    public func undoRest(now: Date = .now) async {
        await setRest(false, now: now)
    }

    private func setRest(_ rest: Bool, now: Date) async {
        guard let profiles, var profile = try? await profiles.profile() else { return }
        let today = CalendarDay(now, calendar: calendar)
        if rest { profile.logRest(on: today) } else { profile.undoRest(on: today) }
        guard (try? await profiles.save(profile)) != nil else { return }
        restLoggedToday = rest
    }

    private func trainingAction(
        strength: Routine?, strengthRest: Bool, runs: [PlannedRun], priority: DisciplinePriority,
        trainedToday: Bool, strengthPlanned: Bool
    ) -> NextAction {
        if runs.contains(where: { $0.purpose == .race }) { return .reviewRun }
        let hasScheduledRun = runs.contains { $0.purpose != .rest }
        // Only a dated session still to do justifies a second one; an optional run or the next rotation does not.
        if trainedToday, !hasScheduledRun, !strengthPlanned { return .trainedToday }
        let runAction: NextAction? = if let option = runningOption, option.offersEasyRun,
                                        hasScheduledRun || hasRunningGoal || option.suggestedMinutes != nil {
            .runEasy(minutes: option.suggestedMinutes)
        } else if hasScheduledRun {
            .reviewRun
        } else {
            nil
        }
        if let runAction, priority == .running, hasScheduledRun { return runAction }
        if let strength, !strengthRest { return .startStrength(strength) }
        if let runAction, hasScheduledRun || !strengthRest { return runAction }
        if strengthRest || runs.contains(where: { $0.purpose == .rest }) { return .rest }
        return .train
    }

    private func loadRunningPlan(
        goal: TrainingGoal?, today: CalendarDay, now: Date, runs: [RunActivity],
        runningBreak: DetectedDeload?, runReadFailed: Bool
    ) {
        let running = goal?.running
        let schedule = goal?.scheduledRuns.filter { !$0.isPostponed } ?? []
        let yesterday = today.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let latestRun = schedule.compactMap(\.completion).filter {
            $0.durationSeconds.isFinite && $0.durationSeconds > 0
                && (yesterday...now).contains($0.startedAt.addingTimeInterval($0.durationSeconds))
        }.max { $0.startedAt < $1.startedAt }
        recentRunPain = latestRun?.painDuring == true || latestRun?.painAfter == true
        scheduledRunsToday = schedule.filter { $0.day == today }.map { ScheduledTrainingRow.run($0, format: format) }
        if keptPlannedRunDay == today { return }
        if let decision = EasyRunAdvisor.advise(
            goal: running, targetDay: goal?.targetDate, schedule: schedule, readiness: readiness, metrics: metrics,
            runs: runReadFailed ? [] : runs, now: now, calendar: calendar,
            runningBreak: runReadFailed ? nil : runningBreak, strength: goal?.scheduledStrength ?? [],
            priority: goal?.effectivePriority ?? .balanced, allowEffortOnly: !runReadFailed
        ), decision != .plannedRest {
            runningOption = RunningOption(
                goal: goal, decision: decision, hasRunToday: !scheduledRunsToday.isEmpty,
                calendar: calendar, format: format
            )
        }
    }

    /// Replaces today's planned run with the easy run Today proposed. The entry keeps its identity and dates.
    public func applyRunningAdjustment(now: Date = .now) async {
        guard let adjustment = runningOption?.adjustment, let profiles,
              var profile = try? await profiles.profile(), var goal = profile.goal else { return }
        var schedule = goal.scheduledRuns
        let today = CalendarDay(now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        guard adjustment.original.day == today, let index = schedule.firstIndex(of: adjustment.original),
              goal.targetDate.map({ !(today...tomorrow).contains($0) }) ?? true,
              !schedule.contains(where: { other in
                  other.id != adjustment.runID && !other.isPostponed
                      && (other.day == today || (other.day == tomorrow && other.purpose == .race))
              }) else { return }
        let updated = adjustment.original.easingTo(minutes: adjustment.minutes)
        schedule[index] = updated
        goal.setRunningSchedule(schedule)
        profile.goal = goal
        guard (try? await profiles.save(profile)) != nil else { return }
        await load(now: now)
    }

    /// Keeps the planned run as scheduled and stops proposing a change for the rest of today. Nothing is saved.
    public func keepPlannedRun(now: Date = .now) {
        keptPlannedRunDay = CalendarDay(now, calendar: calendar)
        runningOption = nil
        if case .runEasy = heroTrainingAction { heroTrainingAction = .reviewRun }
    }

    // MARK: Deload

    /// Accepts the proposed deload: a deload week from today. It also resets "weeks since the last deload".
    public func acceptDeload(now: Date = .now) async {
        guard let profiles, var profile = try? await profiles.profile() else { return }
        let today = CalendarDay(now, calendar: calendar)
        let plan = deloadPlan
        profile.deloads.append(DeloadRecord(
            start: today, days: plan.durationDays, forLifeStress: plan == .stressAware ? true : nil
        ))
        profile.deloadPostponedUntil = nil
        try? await profiles.save(profile)
        await load(now: now)
    }

    /// Hides the proposal for a week. It comes back then if training and recovery still suggest it.
    public func postponeDeload(now: Date = .now) async {
        guard let profiles, var profile = try? await profiles.profile() else { return }
        profile.deloadPostponedUntil = CalendarDay(now, calendar: calendar).adding(days: 6, calendar: calendar)
        try? await profiles.save(profile)
        deloadAdvice = nil
    }

    /// Answers whether a detected break counted as a deload, as Plan does (ADR-0029). A yes resets the deload
    /// interval; a no lets the proposal through.
    public func reviewBreak(accepted: Bool, now: Date = .now) async {
        guard let profiles, case let .confirmBreak(period) = deloadAdvice?.state,
              var profile = try? await profiles.profile() else { return }
        profile.recordDeloadDecision(DeloadDecision(
            start: period.start, end: period.end, reason: period.reason, accepted: accepted,
            discipline: period.discipline
        ))
        try? await profiles.save(profile)
        await load(now: now)
    }

    /// A run finished today, from the sources or from a planned run linked to a recording.
    private func hasRunToday(_ runs: [RunActivity], planned: [PlannedRun], now: Date) -> Bool {
        let start = calendar.startOfDay(for: now)
        let finishedToday: (Date, Double) -> Bool = { began, seconds in
            seconds.isFinite && (start...now).contains(began.addingTimeInterval(seconds))
        }
        return runs.contains { finishedToday($0.startedAt, $0.durationSeconds) }
            || planned.contains { $0.completion.map { finishedToday($0.startedAt, $0.durationSeconds) } ?? false }
    }

    private func hasStrengthToday(sessions: [StrengthSession], recordings: [RecordedStrengthActivity], now: Date) -> Bool {
        let start = calendar.startOfDay(for: now)
        return sessions.contains { $0.startedAt <= now && ($0.endedAt ?? $0.startedAt) >= start }
            || recordings.contains { $0.durationSeconds.isFinite && (start...now).contains($0.endedAt) }
    }

    private func loadStrengthOption(
        today: CalendarDay, now: Date, profile: AthleteProfile?, assignedRoutine: Routine?,
        snapshot: TrainingRecordLoader.Snapshot
    ) {
        let record = snapshot.record
        let blocks = assignedRoutine == nil ? profile?.declaredBlocks ?? [] : []
        let historyStart = now.addingTimeInterval(-ProgressionTargets.historyWindow)
        let planned = PlanSchedule.next(
            blocks: blocks, routines: record.routines, sessions: record.sessions, today: today, calendar: calendar
        )
        let familiarityStart = today.adding(days: -EasyStrengthAdjustment.familiarityDays, calendar: calendar)
            .startDate(in: calendar)
        strengthInputs = StrengthInputs(
            assignedRoutine: assignedRoutine, plannedRoutine: snapshot.settingsFailed ? nil : planned?.routine,
            sessions: record.sessions,
            catalog: assignedRoutine != nil && snapshot.settingsFailed ? [] : record.exercises,
            settings: record.settings, historyStart: historyStart, familiarityStart: familiarityStart
        )
        rebuildStrengthOption()
    }

    // MARK: Next strength session

    /// Only a dated strength session gets a comparison without asking.
    public var canRequestStrengthOption: Bool {
        strengthInputs != nil && strengthInputs?.assignedRoutine == nil
    }

    public var showsOptionalStrength: Bool {
        canRequestStrengthOption && optionalStrengthDay != nil && optionalStrengthDay == loadedDay
    }

    public func setShowsOptionalStrength(_ show: Bool) {
        guard canRequestStrengthOption else { return }
        optionalStrengthDay = show ? loadedDay : nil
        rebuildStrengthOption()
    }

    /// Says which workout the athlete will do next, when the app could not tell or guessed wrong. It lasts for today.
    public func chooseStrengthSession(_ id: String) {
        guard let day = loadedDay, strengthChoices.contains(where: { $0.id == id }) else { return }
        chosenWorkout = (day, id)
        updateStrengthChoices()
        rebuildStrengthOption()
        updateDeloadSession()
    }

    /// Completed sessions in this window are enough to see a rotation of up to six workouts done once or twice a week.

    private struct WorkoutContext {
        let sessions: [StrengthSession]
        let catalog: [Exercise]
        let settings: [UUID: ProgressionSettings]
        let rotation: SessionRotation?
        /// The routine a declared plan or today's assignment has next. It wins over a detected rotation.
        let planned: SessionRotation.Slot?
        let recent: [SessionRotation.Slot]
    }

    private struct StrengthInputs {
        let assignedRoutine: Routine?
        let plannedRoutine: Routine?
        let sessions: [StrengthSession]
        let catalog: [Exercise]
        let settings: [UUID: ProgressionSettings]
        let historyStart: Date
        let familiarityStart: Date
    }

    private func loadWorkoutContext(today: CalendarDay, profile: AthleteProfile?, record: TrainingRecord) {
        guard workouts != nil else {
            recentWorkouts = nil
            updateStrengthChoices()
            return
        }
        let blocks = profile?.declaredBlocks ?? []
        let rotationStart = today.adding(days: -LiftStatus.rotationHistoryDays, calendar: calendar)
            .startDate(in: calendar)
        let recent = record.sessions.filter { $0.startedAt >= rotationStart }
        let assignment = profile?.goal.flatMap { $0.kind == .hybrid ? $0 : nil }?.scheduledStrength
            .first { $0.day == today }
        let routine: Routine? = if let id = assignment?.routineID {
            record.routines.first { $0.id == id }
        } else if assignment == nil {
            PlanSchedule.next(blocks: blocks, routines: record.routines, sessions: record.sessions, today: today,
                              calendar: calendar)?.routine
        } else {
            nil
        }
        if chosenWorkout?.day != today { chosenWorkout = nil }
        recentWorkouts = WorkoutContext(
            sessions: recent, catalog: record.exercises, settings: record.settings,
            rotation: SessionRotation.detect(in: recent),
            planned: routine.map { SessionRotation.Slot(id: $0.id.uuidString, name: $0.name) },
            recent: SessionRotation.recentWorkouts(in: recent)
        )
        updateStrengthChoices()
    }

    /// The workout that comes next: the athlete's choice for today, the plan's next routine, or the rotation's next.
    private var nextWorkout: StrengthOption.Basis? {
        guard let context = recentWorkouts, context.planned == nil else { return nil }
        if let chosen = chosenWorkout, let slot = strengthChoices.first(where: { $0.id == chosen.id }) {
            return .chosen(SessionRotation.Slot(id: slot.id, name: slot.title))
        }
        return context.rotation.map { .rotation($0.next) }
    }

    private func updateStrengthChoices() {
        guard !readiness.reasons.contains(where: \.advisesSkippingTraining),
              let context = recentWorkouts, context.planned == nil else {
            strengthChoices = []
            strengthChoiceNote = nil
            return
        }
        let slots = context.rotation?.order ?? context.recent
        strengthChoices = slots.count >= 2 ? slots.map { StrengthChoice(id: $0.id, title: $0.name) } : []
        let selected = chosenWorkout?.id ?? context.rotation?.next.id
        strengthChoices = strengthChoices.map {
            StrengthChoice(id: $0.id, title: $0.title, isSelected: $0.id == selected)
        }
        if let rotation = context.rotation, rotation.order.count >= 2 {
            let cycle = rotation.order.map(\.name).joined(separator: " → ")
            strengthChoiceNote = L10n.format("You rotate through {1}. Next up: {2}.", cycle, rotation.next.name)
        } else if strengthChoices.count >= 2 {
            strengthChoiceNote = L10n.text(
                "Your recent sessions don't follow a fixed order yet. Choose the one you plan to do."
            )
        } else {
            strengthChoiceNote = nil
        }
    }

    private func rebuildStrengthOption() {
        guard let inputs = strengthInputs, inputs.assignedRoutine != nil || showsOptionalStrength else {
            strengthOption = nil
            return
        }
        let routine = inputs.assignedRoutine ?? inputs.plannedRoutine
        strengthOption = StrengthOption.make(
            routine: routine, isDated: inputs.assignedRoutine != nil, sessions: inputs.sessions,
            exercises: inputs.catalog, settings: inputs.settings, historyStart: inputs.historyStart,
            familiarityStart: inputs.familiarityStart, format: format, basis: routine == nil ? nextWorkout : nil
        )
    }

    /// The deload applied to the session that comes next. Without one, Today explains it in general terms.
    /// The plan the advice shows: the steadier week when the athlete reported stress.
    private var deloadPlan: DeloadPlan {
        switch deloadAdvice?.state {
        case let .proposed(explanation): explanation.lifeStress == .reported ? .stressAware : .standard
        case let .inProgress(_, forLifeStress): forLifeStress ? .stressAware : .standard
        default: .standard
        }
    }

    private func updateDeloadSession() {
        deloadSession = nil
        guard let advice = deloadAdvice, let context = recentWorkouts else { return }
        if case .confirmBreak = advice.state { return }
        let target: (slot: SessionRotation.Slot, heading: String)
        if let planned = context.planned {
            target = (planned, L10n.format("Next in your plan: {1}", planned.name))
        } else if let basis = nextWorkout {
            switch basis {
            case let .rotation(slot): target = (slot, L10n.format("Next in your rotation: {1}", slot.name))
            case let .chosen(slot): target = (slot, L10n.format("Your choice: {1}", slot.name))
            }
        } else {
            return
        }
        guard let session = context.sessions.filter({ SessionRotation.slot(for: $0).id == target.slot.id })
            .max(by: { $0.startedAt < $1.startedAt }) else { return }
        deloadSession = DeloadSessionPreview.make(
            heading: target.heading, session: session, exercises: context.catalog, settings: context.settings,
            plan: deloadPlan, format: format
        )
    }

    /// The deload card holds the next-session choice when it shows; the strength option has it otherwise.
    public var showsNextSessionInDeload: Bool { deloadHowTo != nil }

    /// How to apply the deload: to the next session shown below, or to any session when the app cannot tell which.
    public var deloadHowTo: String? {
        guard let advice = deloadAdvice else { return nil }
        if case .confirmBreak = advice.state { return nil }
        if deloadSession != nil {
            return L10n.text("Apply it to every session of the week, starting with the next one:")
        }
        return L10n.text(
            "Every session this week: for example, 4 × 6 at 100 kg becomes 2 × 6 at 90 kg, with at least 3 reps left."
        )
    }

    /// Asks every source for access (the Apple Health permission sheet), then reloads.
    public func connectHealth(now: Date = .now) async {
        accessError = nil
        for source in sources {
            do {
                try await source.requestAccess()
            } catch {
                accessError = L10n.format(
                    "{1} could not ask for permission: {2}", source.kind.displayName, error.localizedDescription
                )
            }
        }
        await load(now: now)
    }

    private func text(for reason: ReadinessReason) -> String {
        switch reason {
        case .markedSick:
            L10n.text("Marked as sick in today's check-in. Rest until the symptoms ease.")
        case .symptomsLimitTraining:
            L10n.text("You reported symptoms that make you feel too unwell to train.")
        case .exerciseWarningSigns:
            L10n.text("Symptoms to discuss with a clinician")
        case .runningPainLimitsTraining:
            L10n.text("Running pain worsened or affected your stride")
        case .unusualFatigue:
            L10n.text("More fatigue than usual")
        case .unusualStress:
            L10n.text("More stress than usual")
        case .hrvBelowBaseline(let nights):
            if let coverage = readiness.hrvCoverage, let metric = coverage.metric {
                L10n.format(
                    "HRV ({1}) below your usual range ({2} of {3} comparable readings low in the last {4} days).",
                    metric.seriesLabel, String(nights), String(coverage.recentReadings), String(coverage.recentDays)
                )
            } else {
                L10n.text("HRV below your usual range.")
            }
        case .hrvMayReflectCycle:
            L10n.text("HRV is normally lower in the second half of the menstrual cycle, so this alone does not make the light red.")
        case .phaseBaseline(.follicular, let cycles):
            L10n.format("Compared with your follicular days in the last {1} cycles.", cycles)
        case .phaseBaseline(.luteal, let cycles):
            L10n.format("Compared with your luteal days in the last {1} cycles.", cycles)
        case .possibleLutealShift:
            L10n.text("Resting HR often rises a few beats before a period; the threshold allows for it.")
        case .restingHeartRateElevated(let bpm):
            L10n.format("Resting HR {1} bpm above your usual.", format.number(bpm, maxFractionDigits: 0))
        case .shortSleep(let hours):
            L10n.format("Short sleep: {1} h.", format.number(hours, maxFractionDigits: 1))
        case .lowEnergy(let score):
            L10n.format("Low energy in today's check-in ({1}/5).", String(score))
        case .highSoreness(let score):
            L10n.format("Sore muscles in today's check-in ({1}/3).", String(score))
        case .missingData:
            L10n.text("It needs about two weeks of HRV or resting HR from Apple Health, last night's sleep or a check-in.")
        }
    }

    /// Use activity-source steps for older walking baselines and prefer merged metric steps where available.
    private func updateMovement(
        _ snapshot: TrainingRecordLoader.Snapshot, today: CalendarDay, now: Date, profile: AthleteProfile?,
        schedule: MovementNote.Schedule
    ) {
        let activity = snapshot.record.activity
        movementWalks = snapshot.walkOriginals
        movementRoutine = profile?.walkingRoutine ?? WalkingRoutine()
        movementNow = now
        let baseline = EverydayMovement.baseline(activity, before: today, calendar: calendar)
        usualSteps = baseline.steps
        let signals = EverydayMovement.signals(activity, today: today, calendar: calendar)
        let canSuggestActivity = !readiness.reasons.contains(where: \.advisesSkippingTraining)
        movementAdvice = MovementNote.notes(
            signals: signals, suggestsRecoveryWalk: canSuggestActivity && (readiness.level == .red || schedule.isRest),
            routine: movementRoutine, today: today, format: format,
            suggestActivity: canSuggestActivity, hasLegSession: schedule.hasLegSession && canSuggestActivity
        )
    }

    /// One tap on Yes or No. The answer is kept for this walk and teaches the usual dog walk times.
    public func answerDogWalk(withDog: Bool) {
        guard let question = dogWalkQuestion else { return }
        companionAnswers.answer(question.walk, among: movementWalks, withDog: withDog)
        if pendingPrompt == .dogWalk { dismissPendingPrompt() }
    }

    private func has(_ value: (DailyMetrics) -> Double?) -> Bool {
        metrics.flatMap(value) != nil || week.contains { value($0) != nil }
    }

    private func average(_ value: (DailyMetrics) -> Double?) -> Double? {
        let values = week.compactMap(value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func weekly(_ value: String) -> String {
        L10n.format("7-day avg {1}", value)
    }
}

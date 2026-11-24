import Analytics
import Domain
import Foundation
import Observation
import PresentationKit
import TrainingServices

/// A rule explanation with the strength of its evidence, as shown on the Plan screen.
public struct ExplainedLine: Hashable, Sendable {
    public let text: String
    public let evidence: String
    /// "Learn more" for this line (ADR-0030); often empty.
    public let readings: [Reading]

    init(text: String, evidence: EvidenceReference) {
        self.text = text
        self.evidence = evidence.level.displayName
        self.readings = FurtherReading.readings(for: evidence)
    }
}

/// What to do next: headline plus reasons.
public struct NextBlockState: Hashable, Sendable {
    /// "Strength block in 2 weeks, for 4–6 weeks."
    public let headline: String
    public let reasons: [ExplainedLine]
}

/// One block of the coming months.
public struct PlanRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let isDeload: Bool
    public let start: Date
    public let weeks: Int
}

public struct DeloadRow: Identifiable, Hashable, Sendable {
    public struct Identifier: Hashable, Sendable {
        public let start: CalendarDay
        public let discipline: TrainingDiscipline?
    }

    public let id: Identifier
    public let start: Date
    public let end: Date
    public let reason: ExplainedLine
}

public struct DeloadQuestionRow: Identifiable, Hashable, Sendable {
    public let id: DeloadRow.Identifier
    public let details: DeloadQuestionDetails
}

/// An exercise in the priority-lift picker.
public struct PriorityLiftRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let isSelected: Bool
}

/// Goal, current block, next-block advice, balance findings and the plan for the coming months (ADR-0013).
@MainActor
@Observable
public final class PlanModel {
    public private(set) var profile = AthleteProfile()
    public private(set) var currentBlock: TrainingBlock?
    public private(set) var suggestion: BlockSuggestion?
    public private(set) var plan: [PlannedBlock] = []
    public private(set) var findings: [BalanceFinding] = []
    public private(set) var exerciseNames: [UUID: String] = [:]
    public private(set) var catalog: [Exercise] = []
    public private(set) var errorMessage: String?
    /// True while the history is being analysed (off the main actor).
    public private(set) var isAnalysing = false
    public private(set) var importedPlanProgress: [ImportedPlanProgressRow] = []
    public private(set) var isReviewingDeload = false
    private var deloads: [DetectedDeload] = []
    private var recentDeloadQuestions: [DetectedDeload] = []
    private var weeksSinceDeload: Int?
    private var lastRecoveryKind: LastRecovery.Kind?
    private var stalledLifts: [StalledLift] = []
    /// Recorded runs read for the analysis, for the single-session ceiling of dated runs.
    private(set) var recentRuns: [RunActivity] = []
    /// Lifts whose next step was applied on this screen; their stall stays until new sessions show progress.
    private var changedLifts: Set<UUID> = []
    public private(set) var isApplyingLiftChange = false
    /// Completed and in-progress strength sessions of the last eight days, for this week's progress.
    private(set) var weekSessions: [StrengthSession] = []
    private var pendingRotationName: String?
    private var strengthRecordedDays: Set<CalendarDay> = []
    /// The current week of the declared block with planned routines, when there is one.

    // Editable state of the screen.
    /// Whether the goal has a target date. Change it with `setHasTargetDate(_:)`.
    public private(set) var hasTargetDate = false
    /// The target date shown in the date picker (kept when the toggle is off). Change it with `setTargetDate(_:)`.
    public private(set) var targetDate: Date
    /// Focus and length of a block the user is about to declare.
    public var newBlockFocus: TrainingFocus = .hypertrophy
    public var newBlockWeeks = 6
    public let newBlockWeeksRange = 1...16
    /// Text typed in the priority-lift search.
    public var priorityLiftSearch = ""
    public var runningDraft: RunningPlanDraft
    public private(set) var isSavingProfile = false
    public var isSavingRunningPain: Bool { isSavingProfile }
    private var availableRoutines: [Routine] = []

    private let profiles: any ProfileRepository
    private var dayTraining = DayTraining()
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let routines: (any RoutineRepository)?
    let clock: @Sendable () -> Date
    let calendar: Calendar
    private let runSources: [any MetricsSource]
    private let recordedStrength: (any RecordedStrengthSource)?

    public init(
        profiles: any ProfileRepository,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        routines: (any RoutineRepository)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current, runSources: [any MetricsSource] = [],
        recordedStrength: (any RecordedStrengthSource)? = nil
    ) {
        self.profiles = profiles
        self.workouts = workouts
        self.exercises = exercises
        self.progression = progression
        self.clock = clock
        self.calendar = calendar
        self.routines = routines
        self.runSources = runSources
        self.recordedStrength = recordedStrength
        targetDate = clock().addingTimeInterval(Self.defaultTargetWeeks * 7 * 86_400)
        runningDraft = RunningPlanDraft(goal: nil)
    }

    var now: Date { clock() }

    /// Default distance of a new target date.
    static let defaultTargetWeeks: Double = 16

    public var goalKind: TrainingGoal.Kind { profile.goal?.kind ?? .general }

    // MARK: Screen state

    public let goalOptions: [Option<TrainingGoal.Kind>] = TrainingGoal.Kind.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses
    public let runningSessionOptions = PlannedRun.Purpose.allCases.map { Option(value: $0, name: $0.displayName) }
    public let runningIntensityOptions = PlannedRun.IntensityBasis.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
    public let racePriorityOptions = PlannedRun.RacePriority.allCases.map { Option(value: $0, name: $0.displayName) }
    public let priorityOptions = DisciplinePriority.allCases.map { Option(value: $0, name: $0.displayName) }
    public var disciplinePriority: DisciplinePriority { profile.goal?.effectivePriority ?? .balanced }
    /// Only a hybrid goal has two disciplines to rank.
    public var showsDisciplinePriority: Bool { goalKind == .hybrid }
    public var showsRunningPlan: Bool { goalKind == .hybrid }
    public var showsHybridCalendar: Bool { showsRunningPlan }
    public var showsRunningCalendar: Bool { showsHybridCalendar && profile.goal?.running != nil }
    public var runningGoalSummary: String? { profile.goal?.running?.displayName() }
    public var runningGoalPace: String? {
        guard let pace = runningDraft.goal?.targetPaceSecondsPerKm else { return nil }
        return L10n.format("Goal pace {1} per km", Format().minutesAndSeconds(Int(pace.rounded())))
    }
    public var canSaveRunningPlan: Bool { runningDraft.isValid && !isSavingProfile && showsRunningPlan }

    /// Priority lifts only matter for a strength goal.
    public var showsPriorityLifts: Bool { goalKind == .strength }
    public var priorityLiftCount: Int { profile.goal?.priorityLifts.count ?? 0 }

    public var priorityLiftRows: [PriorityLiftRow] {
        let selected = Set(profile.goal?.priorityLifts ?? [])
        return Exercise.byDisplayName(SearchText.filter(catalog, by: priorityLiftSearch)).map {
            PriorityLiftRow(id: $0.id, name: $0.displayName, isSelected: selected.contains($0.id))
        }
    }

    /// "Hypertrophy (detected)"; `nil` without training.
    public var currentBlockTitle: String? {
        currentBlock.map { $0.focus.displayName + ($0.isDeclared ? "" : " " + L10n.text("(detected)")) }
    }

    public var currentBlockStart: Date? { currentBlock?.start.startDate(in: calendar) }

    public var next: NextBlockState? {
        guard let suggestion else { return nil }
        let when = suggestion.switchInWeeks == 0
            ? L10n.text("now")
            : L10n.format("in {1} weeks", suggestion.switchInWeeks)
        return NextBlockState(
            headline: L10n.format(
                "{1} block {2}, for {3}–{4} weeks.", suggestion.next.displayName, when,
                suggestion.nextLengthWeeks.lowerBound, suggestion.nextLengthWeeks.upperBound
            ),
            reasons: suggestion.reasons.map { ExplainedLine(text: $0.text, evidence: $0.evidence) }
        )
    }

    public var findingLines: [ExplainedLine] {
        findings.map { ExplainedLine(text: $0.text(names: exerciseNames), evidence: $0.evidence) }
    }

    public var lastDeloadSummary: String? {
        weeksSinceDeload.map {
            if lastRecoveryKind == .detectedBreak, profile.countsBreaksAutomatically {
                switch $0 {
                case 0: return L10n.text("Last strength rest period less than a week ago")
                case 1: return L10n.text("Last strength rest period 1 week ago")
                default: return L10n.format("Last strength rest period {1} weeks ago", $0)
                }
            }
            return switch $0 {
            case 0: L10n.text("Last deload less than a week ago")
            case 1: L10n.text("Last deload 1 week ago")
            default: L10n.format("Last deload {1} weeks ago", $0)
            }
        }
    }

    public var hasRecoveryHistory: Bool { weeksSinceDeload != nil || !deloads.isEmpty }

    public var pendingDeloadRows: [DeloadQuestionRow] {
        recentDeloadQuestions.map(questionRow)
    }

    public var olderDeloadRows: [DeloadQuestionRow] {
        deloads.reversed().filter { $0.needsConfirmation && !recentDeloadQuestions.contains($0) }.map(questionRow)
    }

    private func questionRow(_ period: DetectedDeload) -> DeloadQuestionRow {
        DeloadQuestionRow(
            id: DeloadRow.Identifier(start: period.start, discipline: period.discipline),
            details: DeloadQuestionDetails(period: period, calendar: calendar)
        )
    }

    public var deloadRows: [DeloadRow] {
        deloads.reversed().filter { !$0.needsConfirmation }.map { period in
            let text: String
            switch (period.reason, period.discipline) {
            case (.noTraining, .strength): text = L10n.text("No strength workouts recorded")
            case (.noTraining, .running): text = L10n.text("No runs recorded")
            case (.noTraining, nil): text = L10n.text("No training recorded")
            case (.easyRuns, _): text = L10n.text("Only light running recorded")
            case (.reducedStrength, _): text = L10n.text("Strength training load was well below usual or planned")
            }
            return DeloadRow(
                id: DeloadRow.Identifier(start: period.start, discipline: period.discipline),
                start: period.start.startDate(in: calendar), end: period.end.startDate(in: calendar),
                reason: ExplainedLine(text: text, evidence: period.evidence)
            )
        }
    }

    public var planRows: [PlanRow] {
        plan.enumerated().map { index, block in
            PlanRow(
                id: index,
                title: block.focus?.displayName ?? L10n.text("Deload"),
                isDeload: block.isDeload,
                start: block.start.startDate(in: calendar),
                weeks: block.weeks
            )
        }
    }

    public func load() async {
        do {
            profile = try await profiles.profile()
            resetRunningPlanEditor()
            hasTargetDate = profile.goal?.targetDate != nil
            if let day = profile.goal?.targetDate { targetDate = day.startDate(in: calendar) }
            catalog = try await exercises.allExercises()
            exerciseNames = Exercise.displayNames(catalog)
            let now = clock()
            let day = CalendarDay(now, calendar: calendar)
            let start: Date = profile.countsBreaksAutomatically ? .distantPast
                : day.adding(days: -TrainingRecordLoader.historyDays, calendar: calendar).startDate(in: calendar)
            let firstPlanDay = profile.declaredBlocks.filter {
                $0.isDeclared && !$0.routineIDs.isEmpty && $0.start <= day
            }.map(\.start).min()
            let planStart = firstPlanDay?.startDate(in: calendar) ?? start
            let sessions = try await workouts.sessions(from: min(planStart, start), to: now)
            errorMessage = nil
            if showsHybridCalendar { await loadCalendarRoutines() }
            await analyse(sessions: sessions, from: start, now: now)
        } catch {
            errorMessage = L10n.text("Could not load your plan.")
        }
    }

    // MARK: Actions

    public func reviewDeload(id: DeloadRow.Identifier, accepted: Bool) async {
        guard !isReviewingDeload, let period = deloads.first(where: {
            $0.start == id.start && $0.discipline == id.discipline && $0.needsConfirmation
        }) else { return }
        isReviewingDeload = true
        defer { isReviewingDeload = false }
        do {
            var updated = try await profiles.profile()
            updated.recordDeloadDecision(DeloadDecision(
                start: period.start, end: period.end, reason: period.reason, accepted: accepted,
                discipline: period.discipline
            ))
            try await profiles.save(updated)
            await load()
        } catch {
            errorMessage = L10n.text("Could not save your plan. Try again.")
        }
    }

    public func resetRunningPlanEditor() {
        runningDraft = RunningPlanDraft(goal: profile.goal)
    }

    @discardableResult
    public func saveRunningPlan() async -> Bool {
        guard canSaveRunningPlan, var goal = profile.goal else { return false }
        goal.running = runningDraft.goal
        await save(goal: goal)
        return profile.goal == goal
    }

    public func setGoal(kind: TrainingGoal.Kind) async {
        guard kind != goalKind else { return }
        var goal = profile.goal ?? TrainingGoal(kind: kind)
        goal.kind = kind
        await save(goal: goal)
    }

    public func setPriority(_ priority: DisciplinePriority) async {
        guard !isSavingProfile, priority != disciplinePriority else { return }
        var goal = profile.goal ?? TrainingGoal(kind: goalKind)
        goal.priority = priority == .balanced ? nil : priority
        await save(goal: goal)
    }

    /// Turns the target date on (with the date shown in the picker) or off.
    public func setHasTargetDate(_ isOn: Bool) async {
        guard !isSavingProfile, isOn != hasTargetDate else { return }
        hasTargetDate = isOn
        await saveTargetDate(isOn ? targetDate : nil)
    }

    /// Picks a target date and turns it on.
    public func setTargetDate(_ date: Date) async {
        guard !isSavingProfile else { return }
        targetDate = date
        hasTargetDate = true
        await saveTargetDate(date)
    }

    private func saveTargetDate(_ date: Date?) async {
        var goal = profile.goal ?? TrainingGoal(kind: goalKind)
        goal.targetDate = date.map { CalendarDay($0, calendar: calendar) }
        await save(goal: goal)
    }

    public func togglePriorityLift(_ exerciseID: UUID) async {
        var goal = profile.goal ?? TrainingGoal(kind: goalKind)
        if let index = goal.priorityLifts.firstIndex(of: exerciseID) {
            goal.priorityLifts.remove(at: index)
        } else {
            goal.priorityLifts.append(exerciseID)
        }
        await save(goal: goal)
    }

    /// Declares the block chosen in `newBlockFocus` / `newBlockWeeks`, starting today.
    public func startNewBlock() async {
        let weeks = min(max(newBlockWeeks, newBlockWeeksRange.lowerBound), newBlockWeeksRange.upperBound)
        await startBlock(focus: newBlockFocus, weeks: weeks)
    }

    /// Declares a block starting today.
    public func startBlock(focus: TrainingFocus, weeks: Int) async {
        var updated = profile
        updated.declaredBlocks.append(
            TrainingBlock(focus: focus, start: CalendarDay(clock(), calendar: calendar), plannedWeeks: weeks, isDeclared: true)
        )
        await persist(updated)
    }

    // MARK: Private

    private func save(goal: TrainingGoal) async {
        var updated = profile
        updated.goal = goal
        await persist(updated)
    }

    private func persist(_ updated: AthleteProfile) async {
        guard !isSavingProfile else { return }
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            try await profiles.save(updated)
            profile = updated
            await load()
        } catch {
            errorMessage = L10n.text("Could not save your plan. Try again.")
        }
    }

    /// Runs `PlanAnalysis` off the main actor: with years of history it is the heaviest work in the app.
    private func analyse(sessions: [StrengthSession], from start: Date, now: Date) async {
        isAnalysing = true
        defer { isAnalysing = false }
        let settings: [UUID: ProgressionSettings]
        do {
            settings = try await progression.allProgressionSettings()
        } catch {
            settings = [:]
            errorMessage = L10n.text("Some exercise settings could not be read, so this analysis may be incomplete.")
        }
        let exercises = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let profile = profile
        let calendar = calendar
        let routines = (try? await routines?.allRoutines()) ?? []
        let runReading = await SourceReader(sources: runSources).readRuns(from: start, to: now)
        let runs = runReading.activities
        recentRuns = runs
        let runReadFailed = runReading.failed
        let recordings = (try? await recordedStrength?.strengthActivities(from: start, to: now)) ?? []
        let (analysis, blockProgress) = await Task.detached(priority: .userInitiated) {
            let analysis = PlanAnalysis.run(
                profile: profile, sessions: sessions.filter { $0.startedAt >= start },
                exercises: exercises, settings: settings, now: now,
                runs: runs, routines: routines, runReadFailed: runReadFailed, recordings: recordings, calendar: calendar
            )
            let progress = PlanReviewer.blockProgress(
                blocks: profile.declaredBlocks, sessions: sessions, now: now, calendar: calendar
            )
            return (analysis, progress)
        }.value
        let weekStart = CalendarDay(now, calendar: calendar).adding(days: -7, calendar: calendar)
        weekSessions = sessions.filter { $0.startedAt >= weekStart.startDate(in: calendar) }
        let today = CalendarDay(now, calendar: calendar)
        let completedSessions = sessions.filter { $0.isCompleted(through: now) }
        let strengthDates = completedSessions.map(\.startedAt) + recordings.filter { activity in
            activity.durationSeconds.isFinite && activity.durationSeconds >= 0
                && activity.startedAt.addingTimeInterval(activity.durationSeconds) <= now
        }.map(\.startedAt)
        strengthRecordedDays = Set(strengthDates.map { CalendarDay($0, calendar: calendar) })
        let rotationStart = today.adding(days: -LiftStatus.rotationHistoryDays, calendar: calendar)
            .startDate(in: calendar)
        pendingRotationName = SessionRotation.detect(
            in: completedSessions.filter { $0.startedAt >= rotationStart },
            adjustments: profile.rotationAdjustments, calendar: calendar
        )?.next.name
        dayTraining = DayTraining.assess(
            sessions: sessions, recordings: recordings, runs: runs,
            planned: profile.goal?.scheduledRuns.filter { $0.day == today && !$0.isPostponed } ?? [],
            exercises: catalog, now: now, calendar: calendar
        )
        importedPlanProgress = blockProgress.map {
            ImportedPlanProgressRow(block: $0.block, weeks: $0.weeks, calendar: calendar)
        }
        currentBlock = analysis.currentBlock
        suggestion = analysis.suggestion
        plan = analysis.plan
        findings = analysis.findings
        deloads = analysis.deloads
        recentDeloadQuestions = analysis.recentDeloadQuestions
        weeksSinceDeload = analysis.weeksSinceDeload
        lastRecoveryKind = analysis.lastRecoveryKind
        stalledLifts = analysis.liftsToUnblock
    }
}

extension PlanModel {
    /// Current stalled lifts, the longest-stalled first, each with one next step.
    public var liftsToUnblockRows: [LiftToUnblockRow] {
        stalledLifts.map { lift in
            LiftToUnblockRow(
                lift: lift, name: exerciseNames[lift.exerciseID] ?? L10n.text("An exercise"),
                applied: changedLifts.contains(lift.exerciseID), calendar: calendar,
                format: Format(weightUnit: profile.weightUnit)
            )
        }
    }

    /// Saves the setting change behind the lift's next step (after the user confirmed `LiftChange`).
    public func applyNextStep(for exerciseID: UUID) async {
        guard !isApplyingLiftChange, !changedLifts.contains(exerciseID),
              let lift = stalledLifts.first(where: { $0.exerciseID == exerciseID }),
              let step = lift.nextStep, let settings = lift.applying(step) else { return }
        isApplyingLiftChange = true
        defer { isApplyingLiftChange = false }
        do {
            try await progression.save(settings, for: exerciseID)
            changedLifts.insert(exerciseID)
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not save the exercise settings. Try again.")
        }
    }
}

extension PlanModel {
    public var runningGoalProgress: RunningGoalProgress? {
        guard showsRunningCalendar, let goal = profile.goal, let running = goal.running else { return nil }
        return RunningGoalProgress(goal: running, schedule: goal.scheduledRuns, calendar: calendar)
    }

    public func saveRunningPain(_ row: RunningGoalResultRow, during: Bool?, after: Bool?) async -> Bool {
        await saveRunningPain(row, during: during, after: after, report: nil)
    }

    private func saveRunningPain(
        _ row: RunningGoalResultRow, during: Bool?, after: Bool?, report: RunPainReport?
    ) async -> Bool {
        guard showsRunningCalendar, !isSavingProfile else { return false }
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            var updated = try await profiles.profile()
            guard var goal = updated.goal, goal.kind == .hybrid, goal.running != nil else { return false }
            var schedule = goal.scheduledRuns
            guard let index = schedule.firstIndex(where: { $0.id == row.id }), var result = schedule[index].completion,
                  result.activityID == row.result.activityID, result.source == row.result.source,
                  result.startedAt == row.result.startedAt else {
                errorMessage = L10n.text("The linked run changed. Open progress again and retry.")
                return false
            }
            result.painDuring = during
            result.painAfter = after
            // Yes/no answers have no severity: drop an older one so it never contradicts them.
            result.severityDuring = report?.severityDuring
            result.severityAfter = report?.severityAfter
            result.settledByMorning = report?.settledByMorning
            schedule[index] = schedule[index].updatingCompletion(result)
            goal.setRunningSchedule(schedule)
            updated.goal = goal
            try await profiles.save(updated)
            profile = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.text("Could not save your plan. Try again.")
            return false
        }
    }

    /// Saves 0–10 pain for the run and whether it settled by the next morning (#256).
    public func saveRunningPain(
        _ row: RunningGoalResultRow, severityDuring: Int?, severityAfter: Int?, settledByMorning: Bool?
    ) async -> Bool {
        var report = row.result.painReport
        report.answer(during: severityDuring, after: severityAfter, settledByMorning: settledByMorning)
        return await saveRunningPain(row, during: report.painDuring, after: report.painAfter, report: report)
    }

    public var upcomingRunningEntries: [RunningCalendarRow] {
        let today = CalendarDay(clock(), calendar: calendar)
        let warnings = sessionCeilingWarnings
        return (profile.goal?.scheduledRuns ?? []).filter { $0.day >= today }.sorted { $0.day < $1.day }
            .map { calendarRow(for: $0, isPast: false, exceedsCeiling: warnings[$0.id] != nil) }
    }

    public var pastRunningEntries: [RunningCalendarRow] {
        let today = CalendarDay(clock(), calendar: calendar)
        return (profile.goal?.scheduledRuns ?? []).filter { $0.day < today }.sorted { $0.day > $1.day }
            .map { calendarRow(for: $0, isPast: true) }
    }

    public func editRunningEntry(_ entry: PlannedRun? = nil) -> RunningCalendarDraft {
        errorMessage = nil
        // A new run is not proposed for today once training or tired legs hold back an unplanned one (ADR-0035).
        let now = clock()
        let day = dayTraining.holdsBackUnplannedRun
            ? CalendarDay(now, calendar: calendar).adding(days: 1, calendar: calendar).startDate(in: calendar) : now
        return RunningCalendarDraft(entry: entry, today: day, calendar: calendar)
    }

    public func reviewRunMove(_ original: PlannedRun, to day: CalendarDay) -> RunningCalendarDraft {
        var draft = editRunningEntry(original)
        draft.moveOriginal = original
        draft.date = day.startDate(in: calendar)
        return draft
    }

    public func saveRunningEntry(_ draft: RunningCalendarDraft) async -> Bool {
        guard draft.canSave else { return false }
        return await updateRunningCalendar(
            id: draft.id, entry: draft.entry(calendar: calendar), isNew: draft.isNew,
            moveOriginal: draft.moveOriginal
        )
    }

    public func removeRunningEntry(_ id: UUID) async -> Bool {
        await updateRunningCalendar(id: id, entry: nil, isNew: false)
    }

    public func runningCompletionChoices(for draft: RunningCalendarDraft) async -> [RunningCompletionChoice] {
        let selectedDay = CalendarDay(draft.date, calendar: calendar)
        let now = clock()
        let start = selectedDay.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let end = min(now, selectedDay.adding(days: 2, calendar: calendar).startDate(in: calendar))
        let saved = draft.completion.map {
            RunningCompletionChoice(completion: $0, title: L10n.text("Linked run"))
        }
        guard selectedDay <= CalendarDay(now, calendar: calendar) else { return [] }
        let activities = await SourceReader(sources: runSources).readRuns(from: start, to: end).activities
        let otherLinks = (profile.goal?.scheduledRuns ?? []).filter { $0.id != draft.id }.compactMap(\.completion)
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        let choices = activities.filter { activity in
            CalendarDay(activity.startedAt, calendar: calendar) == selectedDay
                && activity.durationSeconds.isFinite && activity.durationSeconds >= 0
                && activity.startedAt.addingTimeInterval(activity.durationSeconds) <= now
                && !otherLinks.contains { $0.matches(activity) }
                && !(draft.completion?.matches(activity) ?? false)
        }.map { activity in
            let title = (activity.name ?? L10n.text("Run")) + " · " + activity.startedAt.formatted(style)
            return RunningCompletionChoice(completion: PlannedRunCompletion(activity), title: title)
        }
        return (saved.map { [$0] } ?? []) + choices
    }

    private func calendarRow(for entry: PlannedRun, isPast: Bool, exceedsCeiling: Bool = false) -> RunningCalendarRow {
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        let status: String?
        if let completion = entry.completion {
            status = recordedRunStatus(on: CalendarDay(completion.startedAt, calendar: calendar))
        } else if entry.isPostponed {
            status = L10n.text("Postponed")
        } else if isPast, entry.purpose != .rest {
            status = L10n.text("No recorded run linked")
        } else if entry.isAdjusted {
            status = L10n.text("Rescheduled")
        } else {
            status = nil
        }
        let increase = SessionCeiling.Settings().increaseFraction.formatted(.percent)
        let ceiling = exceedsCeiling ? L10n.format("More than {1} over your longest recent run", increase) : nil
        return RunningCalendarRow(entry: entry, date: entry.day.startDate(in: calendar).formatted(style),
                                  title: entry.calendarTitle(), status: status, ceilingWarning: ceiling)
    }

    private func updateRunningCalendar(
        id: UUID, entry: PlannedRun?, isNew: Bool, moveOriginal: PlannedRun? = nil
    ) async -> Bool {
        guard showsRunningCalendar else { return false }
        return await updateCalendar { goal in
            guard goal.running != nil else { return false }
            var schedule = goal.scheduledRuns
            let index = schedule.firstIndex { $0.id == id }
            if let entry {
                if let original = moveOriginal,
                   !canApplyRunMove(original, updated: entry, goal: goal) {
                    errorMessage = L10n.text("Your schedule has changed. Review the current plan and try again.")
                    return false
                }
                // An edit prepared against an entry that was removed cannot recreate it.
                guard isNew == (index == nil), canSchedule(entry, among: schedule) else { return false }
                if let index { schedule[index] = entry } else { schedule.append(entry) }
            } else {
                guard let index else { return true }
                schedule.remove(at: index)
            }
            goal.setRunningSchedule(schedule)
            return true
        }
    }

    private func canApplyRunMove(_ original: PlannedRun, updated: PlannedRun, goal: TrainingGoal) -> Bool {
        let today = CalendarDay(clock(), calendar: calendar)
        guard original.day == today, goal.scheduledRuns.contains(original),
              updated.day > today, updated.completion == nil, !updated.isPostponed else { return false }
        return EasyRunAdvisor.canReschedule(original, to: updated.day, goal: goal, calendar: calendar)
    }

    private func updateCalendar(_ change: (inout TrainingGoal) -> Bool) async -> Bool {
        guard showsHybridCalendar, !isSavingProfile else { return false }
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            var updated = try await profiles.profile()
            guard var goal = updated.goal, goal.kind == .hybrid, change(&goal) else { return false }
            updated.goal = goal
            try await profiles.save(updated)
            profile = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = L10n.text("Could not save your plan. Try again.")
            return false
        }
    }

    private func canSchedule(_ entry: PlannedRun, among entries: [PlannedRun]) -> Bool {
        if entry.isPostponed { return true }
        let others = entries.filter { $0.id != entry.id && !$0.isPostponed }
        if others.contains(where: { $0.day == entry.day && ($0.purpose == .rest || entry.purpose == .rest) }) {
            errorMessage = L10n.text("A running rest day must be the only entry on that date.")
            return false
        }
        if let completion = entry.completion {
            guard CalendarDay(completion.startedAt, calendar: calendar) == entry.day,
                  completion.durationSeconds.isFinite, completion.durationSeconds >= 0,
                  completion.startedAt.addingTimeInterval(completion.durationSeconds) <= clock() else {
                errorMessage = L10n.text("Choose a completed run from this date.")
                return false
            }
            if others.compactMap(\.completion).contains(where: { $0.matches(completion) }) {
                errorMessage = L10n.text("That run is already linked to another entry.")
                return false
            }
        }
        return true
    }
}

extension PlanModel {
    public func strengthRoutineOptions(for draft: StrengthCalendarDraft) -> [Option<UUID>] {
        var options = availableRoutines.map { Option(value: $0.id, name: $0.name) }
        if let id = draft.routineID, !options.contains(where: { $0.value == id }) {
            options.append(Option(value: id, name: L10n.text("Scheduled routine unavailable")))
        }
        return options
    }

    public var pendingRotationSummary: String? {
        pendingRotationName.map { L10n.format("Next in your rotation: {1}", $0) }
    }

    /// Actual runs without an explicit calendar link. Linked runs are already shown on their plan rows.
    public var recordedRunCalendarRows: [RecordedRunCalendarRow] {
        let now = clock()
        let start = CalendarDay(now, calendar: calendar).adding(days: -30, calendar: calendar)
            .startDate(in: calendar)
        let linked = showsRunningCalendar ? profile.goal?.scheduledRuns.compactMap(\.completion) ?? [] : []
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        return recentRuns.reversed().compactMap { run in
            guard run.startedAt >= start,
                  run.durationSeconds.isFinite, run.durationSeconds >= 0,
                  run.startedAt.addingTimeInterval(run.durationSeconds) <= now,
                  !linked.contains(where: { $0.matches(run) }) else { return nil }
            return RecordedRunCalendarRow(
                id: "\(run.source.rawValue):\(run.id)",
                title: run.name ?? L10n.text("Run"), date: run.startedAt.formatted(style),
                status: recordedRunStatus(on: CalendarDay(run.startedAt, calendar: calendar))
            )
        }
    }

    private func recordedRunStatus(on day: CalendarDay) -> String {
        strengthRecordedDays.contains(day) ? L10n.text("Completed") : L10n.text("Run completed · no strength recorded")
    }

    public var upcomingCalendarRows: [HybridCalendarRow] {
        calendarRows(runs: showsRunningCalendar ? upcomingRunningEntries : [], isPast: false)
    }

    public var pastCalendarRows: [HybridCalendarRow] {
        calendarRows(runs: showsRunningCalendar ? pastRunningEntries : [], isPast: true)
    }

    public func loadCalendarRoutines() async {
        do {
            availableRoutines = try await routines?.allRoutines() ?? []
        } catch {
            errorMessage = L10n.text("Could not load your routines.")
        }
    }

    public func editStrengthEntry(_ entry: PlannedStrength? = nil) -> StrengthCalendarDraft {
        errorMessage = nil
        return StrengthCalendarDraft(entry: entry, today: clock(), calendar: calendar)
    }

    public func canSaveStrengthEntry(_ draft: StrengthCalendarDraft) -> Bool {
        !isSavingProfile && (draft.routineID.map { id in availableRoutines.contains { $0.id == id } } ?? true)
    }

    public func saveStrengthEntry(_ draft: StrengthCalendarDraft) async -> Bool {
        guard canSaveStrengthEntry(draft) else { return false }
        let day = CalendarDay(draft.date, calendar: calendar)
        let entry = PlannedStrength(id: draft.id, day: day, routineID: draft.routineID)
        return await updateCalendar { goal in
            var schedule = goal.scheduledStrength
            let index = schedule.firstIndex { $0.id == entry.id }
            guard draft.isNew == (index == nil) else { return false }
            guard !schedule.contains(where: { $0.day == day && $0.id != entry.id }) else {
                errorMessage = L10n.text("There is already a strength entry on this date.")
                return false
            }
            if let index { schedule[index] = entry } else { schedule.append(entry) }
            goal.setStrengthSchedule(schedule)
            return true
        }
    }

    public func removeStrengthEntry(_ id: UUID) async -> Bool {
        await updateCalendar { goal in
            goal.setStrengthSchedule(goal.scheduledStrength.filter { $0.id != id })
            return true
        }
    }

    private func calendarRows(runs: [RunningCalendarRow], isPast: Bool) -> [HybridCalendarRow] {
        let today = CalendarDay(clock(), calendar: calendar)
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        let strength = (profile.goal?.scheduledStrength ?? []).filter { ($0.day < today) == isPast }.map { entry in
            let name = availableRoutines.first { $0.id == entry.routineID }?.name
            let date = entry.day.startDate(in: calendar).formatted(style)
            let row = StrengthCalendarRow(entry: entry, date: date, title: entry.displayName(routineName: name))
            return HybridCalendarRow.strength(row)
        }
        return (strength + runs.map(HybridCalendarRow.run)).sorted { isPast ? $0.day > $1.day : $0.day < $1.day }
    }
}

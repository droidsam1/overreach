import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// A rule explanation with the strength of its evidence, as shown on the Plan screen.
public struct ExplainedLine: Hashable, Sendable {
    public let text: String
    public let evidence: String
    /// "Learn more" for this line (ADR-0027); often empty.
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
    public private(set) var isSavingRunningPlan = false

    private let profiles: any ProfileRepository
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        profiles: any ProfileRepository,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.profiles = profiles
        self.workouts = workouts
        self.exercises = exercises
        self.progression = progression
        self.clock = clock
        self.calendar = calendar
        targetDate = clock().addingTimeInterval(Self.defaultTargetWeeks * 7 * 86_400)
        runningDraft = RunningPlanDraft(goal: nil, now: clock(), calendar: calendar)
    }

    /// Default distance of a new target date.
    static let defaultTargetWeeks: Double = 16

    public var goalKind: TrainingGoal.Kind { profile.goal?.kind ?? .general }

    // MARK: Screen state

    public let goalOptions: [Option<TrainingGoal.Kind>] = TrainingGoal.Kind.allCases.map {
        Option(value: $0, name: $0.displayName)
    }
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses
    public let runningSessionOptions = PlannedRun.Purpose.allCases.map { Option(value: $0, name: $0.displayName) }
    public var showsRunningPlan: Bool { goalKind == .hybrid }
    public var runningGoalSummary: String? { profile.goal?.running?.displayName() }
    public var runningGoalPace: String? {
        guard let pace = runningDraft.goal?.targetPaceSecondsPerKm else { return nil }
        return L10n.format("Goal pace {1} per km", Format().minutesAndSeconds(Int(pace.rounded())))
    }
    public var canSaveRunningPlan: Bool { runningDraft.isValid && !isSavingRunningPlan && showsRunningPlan }

    /// Priority lifts only matter for a strength goal.
    public var showsPriorityLifts: Bool { goalKind == .strength }
    public var priorityLiftCount: Int { profile.goal?.priorityLifts.count ?? 0 }

    public var priorityLiftRows: [PriorityLiftRow] {
        let selected = Set(profile.goal?.priorityLifts ?? [])
        return SearchText.filter(catalog, by: priorityLiftSearch).map {
            PriorityLiftRow(id: $0.id, name: $0.name, isSelected: selected.contains($0.id))
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
            exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let now = clock()
            let sessions = try await workouts.sessions(from: now.addingTimeInterval(-365 * 86_400), to: now)
            errorMessage = nil
            await analyse(sessions: sessions, now: now)
        } catch {
            errorMessage = L10n.text("Could not load your plan.")
        }
    }

    // MARK: Actions

    public func resetRunningPlanEditor() {
        runningDraft = RunningPlanDraft(goal: profile.goal, now: clock(), calendar: calendar)
    }

    @discardableResult
    public func saveRunningPlan() async -> Bool {
        guard canSaveRunningPlan, var goal = profile.goal else { return false }
        isSavingRunningPlan = true
        defer { isSavingRunningPlan = false }
        goal.running = runningDraft.goal
        goal.nextRun = runningDraft.nextRun(calendar: calendar)
        await save(goal: goal)
        return profile.goal == goal
    }

    public func setGoal(kind: TrainingGoal.Kind) async {
        guard kind != goalKind else { return }
        var goal = profile.goal ?? TrainingGoal(kind: kind)
        goal.kind = kind
        await save(goal: goal)
    }

    /// Turns the target date on (with the date shown in the picker) or off.
    public func setHasTargetDate(_ isOn: Bool) async {
        guard isOn != hasTargetDate else { return }
        hasTargetDate = isOn
        await saveTargetDate(isOn ? targetDate : nil)
    }

    /// Picks a target date and turns it on.
    public func setTargetDate(_ date: Date) async {
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
        do {
            try await profiles.save(updated)
            profile = updated
            await load()
        } catch {
            errorMessage = L10n.text("Could not save your plan. Try again.")
        }
    }

    /// Runs `PlanAnalysis` off the main actor: with years of history it is the heaviest work in the app.
    private func analyse(sessions: [StrengthSession], now: Date) async {
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
        let analysis = await Task.detached(priority: .userInitiated) {
            PlanAnalysis.run(
                profile: profile, sessions: sessions, exercises: exercises, settings: settings, now: now,
                calendar: calendar
            )
        }.value
        currentBlock = analysis.currentBlock
        suggestion = analysis.suggestion
        plan = analysis.plan
        findings = analysis.findings
    }
}

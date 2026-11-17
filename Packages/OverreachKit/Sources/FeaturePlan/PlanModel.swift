import Analytics
import Domain
import Foundation
import Observation

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
    }

    public var goalKind: TrainingGoal.Kind { profile.goal?.kind ?? .general }

    public func load() async {
        do {
            profile = try await profiles.profile()
            catalog = try await exercises.allExercises()
            exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let now = clock()
            let sessions = try await workouts.sessions(from: now.addingTimeInterval(-365 * 86_400), to: now)
            await analyse(sessions: sessions, now: now)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your plan."
        }
    }

    // MARK: Actions

    public func setGoal(kind: TrainingGoal.Kind) async {
        var goal = profile.goal ?? TrainingGoal(kind: kind)
        goal.kind = kind
        await save(goal: goal)
    }

    public func setTargetDate(_ date: Date?) async {
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
            errorMessage = "Could not save."
        }
    }

    /// Runs `PlanAnalysis` off the main actor: with years of history it is the heaviest work in the app.
    private func analyse(sessions: [StrengthSession], now: Date) async {
        isAnalysing = true
        defer { isAnalysing = false }
        let settings = (try? await progression.allProgressionSettings()) ?? [:]
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

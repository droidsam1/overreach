import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// One routine as shown in the list.
public struct RoutineRow: Identifiable, Hashable, Sendable {
    public let routine: Routine
    /// "Squat, Leg Press, Calf Raise"
    public let exerciseList: String
    public let focus: String?

    public var id: UUID { routine.id }
    public var name: String { routine.name }
}

/// The session a training plan has next, as shown at the top of Train.
public struct UpNextRow: Hashable, Sendable {
    public let routine: Routine
    /// "Upper A"
    public let title: String
    /// "Strength · week 2 of 6"
    public let detail: String
    /// "Bench Press, Row"
    public let exerciseList: String
    /// "This week: 1 of 3 sessions"
    public let weekProgress: String?
}

/// The saved routines (issue #15), and the next session of the training plan (issue #34). Starting one is done by
/// `WorkoutModel.start(_:)`.
@MainActor
@Observable
public final class RoutinesModel {
    public private(set) var routines: [Routine] = []
    public private(set) var catalog: [Exercise] = []
    public private(set) var errorMessage: String?
    /// The plan's next session; `nil` without a plan running today.
    public private(set) var upNext: UpNextRow?
    /// Proposed changes to the running block (missed sessions, a break, an illness).
    public private(set) var planChecks: [PlanCheckRow] = []

    private let repository: any RoutineRepository
    private let exerciseRepository: any ExerciseRepository
    private let backup: (any BackupService)?
    private let profiles: (any ProfileRepository)?
    private let workouts: (any WorkoutRepository)?
    private let checkIns: (any CheckInRepository)?
    private let calendar: Calendar
    private let clock: @Sendable () -> Date

    /// - Parameters:
    ///   - profiles: where the plan's blocks are (`AthleteProfile.declaredBlocks`).
    ///   - workouts: past sessions, to know which routine of the block comes next.
    ///   - checkIns: recent check-ins, to notice an illness.
    public init(
        routines: any RoutineRepository,
        exercises: any ExerciseRepository,
        backup: (any BackupService)? = nil,
        profiles: (any ProfileRepository)? = nil,
        workouts: (any WorkoutRepository)? = nil,
        checkIns: (any CheckInRepository)? = nil,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        repository = routines
        exerciseRepository = exercises
        self.backup = backup
        self.profiles = profiles
        self.workouts = workouts
        self.checkIns = checkIns
        self.calendar = calendar
        self.clock = clock
    }

    // MARK: Screen state

    public var rows: [RoutineRow] {
        let names = exerciseNames
        return routines.map { routine in
            RoutineRow(
                routine: routine,
                exerciseList: routine.exerciseIDs.compactMap { names[$0] }.joined(separator: ", "),
                focus: routine.focus?.displayName
            )
        }
    }

    public var showsEmptyHint: Bool { routines.isEmpty && errorMessage == nil }

    var exerciseNames: [UUID: String] {
        Exercise.displayNames(catalog)
    }

    public func newEditor() -> RoutineEditorModel {
        RoutineEditorModel(list: self, routine: nil)
    }

    /// The editor for a routine, or `nil` if it no longer exists.
    public func editor(for routineID: UUID) -> RoutineEditorModel? {
        routines.first { $0.id == routineID }.map { RoutineEditorModel(list: self, routine: $0) }
    }

    // MARK: Intents

    public func load() async {
        do {
            catalog = try await exerciseRepository.allExercises()
            routines = try await repository.allRoutines()
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not load your routines.")
        }
        await loadUpNext()
    }

    /// Accepts a proposed change: the plan in the profile is updated and the follow-up recomputed.
    public func accept(_ check: PlanCheckRow) async {
        guard check.adjustment.changesThePlan, let profiles else { return }
        do {
            var profile = try await profiles.profile()
            profile.declaredBlocks = PlanReviewer.applying(
                check.adjustment, to: check.block, in: profile.declaredBlocks, calendar: calendar
            )
            try await profiles.save(profile)
        } catch {
            errorMessage = L10n.text("Could not change the plan. Try again.")
            return
        }
        await backup?.backUpIfConfigured(now: clock())
        await loadUpNext()
    }

    /// How far back sessions are read for the follow-up: enough to notice a break before the block.
    static let lookbackDays = 60

    /// The plan's next session and its follow-up. Best effort: without a profile or sessions there is simply
    /// nothing up next.
    private func loadUpNext() async {
        guard let profile = try? await profiles?.profile() else {
            upNext = nil
            planChecks = []
            return
        }
        let now = clock()
        let today = CalendarDay(now, calendar: calendar)
        let lookback = today.adding(days: -Self.lookbackDays, calendar: calendar)
        let earliest = min(profile.declaredBlocks.map(\.start).min() ?? today, lookback)
        let sessions = (try? await workouts?.sessions(from: earliest.startDate(in: calendar), to: now)) ?? []
        let recentCheckIns = (try? await checkIns?.checkIns(in: today.adding(days: -1, calendar: calendar)...today))
            ?? []
        let planned = PlanSchedule.next(
            blocks: profile.declaredBlocks, routines: routines, sessions: sessions, today: today, calendar: calendar
        )
        let review = PlanReviewer.review(
            blocks: profile.declaredBlocks, sessions: sessions, checkIns: recentCheckIns, today: today,
            calendar: calendar
        )
        planChecks = review.map(PlanFollowUpText.rows) ?? []
        upNext = planned.map { planned in
            let block = planned.block.name ?? planned.block.focus.displayName
            let detail = planned.totalWeeks.map { L10n.format("{1} · week {2} of {3}", block, planned.week, $0) }
                ?? L10n.format("{1} · week {2}", block, planned.week)
            let names = exerciseNames
            return UpNextRow(
                routine: planned.routine,
                title: planned.routine.name,
                detail: detail,
                exerciseList: planned.routine.exerciseIDs.compactMap { names[$0] }.joined(separator: ", "),
                weekProgress: review.flatMap(PlanFollowUpText.weekProgress)
            )
        }
    }

    public func delete(_ routineID: UUID) async {
        do {
            try await repository.deleteRoutine(id: routineID)
            routines.removeAll { $0.id == routineID }
            await backup?.backUpIfConfigured(now: clock())
        } catch {
            errorMessage = L10n.text("Could not delete the routine.")
        }
    }

    /// Saves a routine and refreshes the list. Returns false on failure.
    func save(_ routine: Routine) async -> Bool {
        do {
            try await repository.save(routine)
        } catch {
            errorMessage = L10n.text("Could not save the routine.")
            return false
        }
        await load()
        await backup?.backUpIfConfigured(now: clock())
        return true
    }
}

/// An exercise in the routine being edited.
public struct RoutineExerciseRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
}

/// Create or edit a routine. Nothing is stored until `save()`.
@MainActor
@Observable
public final class RoutineEditorModel: Identifiable {
    public let id: UUID
    public var name: String
    /// `nil` = automatic.
    public var focus: TrainingFocus?
    public private(set) var exerciseIDs: [UUID]
    /// Kept as they are: the editor does not change sets and reps (they come from a plan).
    private let prescriptions: [RoutinePrescription]

    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses
    public let isNew: Bool

    private let list: RoutinesModel

    init(list: RoutinesModel, routine: Routine?) {
        self.list = list
        isNew = routine == nil
        id = routine?.id ?? UUID()
        name = routine?.name ?? ""
        focus = routine?.focus
        prescriptions = routine?.prescriptions ?? []
        // Exercises that no longer exist can't be shown or trained, so they leave the routine on save.
        let known = Set(list.catalog.map(\.id))
        exerciseIDs = routine?.exerciseIDs.filter { known.contains($0) } ?? []
    }

    // MARK: Screen state

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var title: String { isNew ? L10n.text("New routine") : L10n.text("Edit routine") }

    public var canSave: Bool { !trimmedName.isEmpty && !exerciseIDs.isEmpty }

    public var errorMessage: String? { list.errorMessage }

    public var exerciseRows: [RoutineExerciseRow] {
        let names = list.exerciseNames
        return exerciseIDs.map { RoutineExerciseRow(id: $0, name: names[$0] ?? "") }
    }

    /// Exercises not in the routine yet.
    public var exerciseChoices: [ExerciseChoice] {
        let added = Set(exerciseIDs)
        return Exercise.byDisplayName(list.catalog.filter { !added.contains($0.id) }).map(ExerciseChoice.init)
    }

    // MARK: Intents

    /// Refreshes the exercises on offer (some may have been created meanwhile).
    public func reloadCatalog() async { await list.load() }

    public func addExercise(id exerciseID: UUID) {
        guard !exerciseIDs.contains(exerciseID), list.catalog.contains(where: { $0.id == exerciseID }) else { return }
        exerciseIDs.append(exerciseID)
    }

    public func removeExercises(at offsets: IndexSet) {
        exerciseIDs = exerciseIDs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Moves rows as a list's reorder does: `destination` is an offset in the list before the move.
    public func moveExercises(from source: IndexSet, to destination: Int) {
        guard source.allSatisfy({ exerciseIDs.indices.contains($0) }),
              (0...exerciseIDs.count).contains(destination) else { return }
        let moved = source.map { exerciseIDs[$0] }
        var remaining = exerciseIDs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moved, at: destination - source.count(in: 0..<destination))
        exerciseIDs = remaining
    }

    /// Saves the routine. Returns true when the screen can close.
    public func save() async -> Bool {
        guard canSave else { return false }
        return await list.save(Routine(
            id: id, name: trimmedName, focus: focus, exerciseIDs: exerciseIDs, prescriptions: prescriptions
        ))
    }
}

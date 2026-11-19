import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// A set being logged. Prefilled from the progression target; `isDone` marks it as performed.
public struct DraftSet: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var weightKg: Double?
    public var reps: Int?
    public var rpe: Double?
    public var isDone: Bool

    public init(id: UUID = UUID(), weightKg: Double?, reps: Int?, rpe: Double? = nil, isDone: Bool = false) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isDone = isDone
    }
}

/// An exercise in the session being logged, with the engine's target and status for context.
public struct DraftExercise: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let exercise: Exercise
    public var target: ExerciseTarget
    public var status: ExerciseStatus
    public var sets: [DraftSet]
    /// Focus used for this exercise (declared, from the session, or inferred from its recent sets).
    public var focus: TrainingFocus?
    public var isFocusInferred: Bool
    /// Suggested rest between working sets for the focus, in seconds.
    public var restSeconds: ClosedRange<Int>
    /// Stored settings behind the target (`nil` = defaults), to notice when they change.
    var appliedSettings: ProgressionSettings?
    /// Scheme behind the target, for the numbers in its explanation.
    var scheme: ProgressionScheme
    /// The athlete's notes on this exercise (pain, technique, machine settings). Saved trimmed; empty = none.
    public var notes = ""

    /// 1-based position of a set, for its row label.
    public func number(of setID: DraftSet.ID) -> Int {
        (sets.firstIndex { $0.id == setID } ?? 0) + 1
    }
}

/// What the logger shows about an exercise's target: one-line summary plus the reasons behind it.
public struct TargetSummary: Hashable, Sendable {
    /// "Target: 62.5 kg × 8/8/8 @ RPE 8"
    public let targetLine: String
    /// "Hypertrophy (detected) · rest 1:30–2:00"
    public let focusLine: String
    /// "Progressing", "Stalled", …; `nil` without enough history.
    public let status: String?
    public let isStalled: Bool
    /// What to do today and why, with its evidence level, e.g.
    /// "Today: go up to 62.5 kg. Last time you completed every rep. (strong evidence)".
    public let reasons: [String]
    /// Ordered suggestions when stalled, numbered: "1. Use smaller jumps (1.25 kg). (moderate evidence)".
    public let stallSuggestions: [String]
}

extension DraftExercise {
    public var name: String { exercise.name }

    /// Focus declared for this exercise (remembered in its progression settings); `nil` = follow the session.
    public var declaredFocus: TrainingFocus? { appliedSettings?.focus }

    public var summary: TargetSummary { summary(format: Format()) }

    public func summary(format: Format) -> TargetSummary {
        let rest = L10n.format(
            "rest {1}–{2}", format.minutesAndSeconds(restSeconds.lowerBound),
            format.minutesAndSeconds(restSeconds.upperBound)
        )
        let focusLine: String
        if let focus {
            focusLine = focus.displayName + (isFocusInferred ? " " + L10n.text("(detected)") : "") + " · " + rest
        } else {
            focusLine = rest.prefix(1).uppercased() + rest.dropFirst()
        }

        let targetLine: String
        if let first = target.sets.first {
            let weight = first.weightKg.map { format.kilograms($0) + " × " } ?? ""
            let reps = target.sets.map { String($0.reps) }.joined(separator: "/")
            targetLine = L10n.format("Target: {1}{2} @ RPE {3}", weight, reps, format.number(first.targetRPE))
        } else {
            targetLine = L10n.text("Target:") + " –"
        }

        var suggestions: [String] = []
        if case let .stalled(list) = status {
            suggestions = list.enumerated().map { index, suggestion in
                "\(index + 1). \(suggestion.text) (\(suggestion.evidence.level.displayName))"
            }
        }
        return TargetSummary(
            targetLine: targetLine,
            focusLine: focusLine,
            status: status.text,
            isStalled: status.isStalled,
            reasons: target.reasons.map { reason in
                let context = ReasonContext(target: target, scheme: scheme, format: format)
                return "\(reason.instruction(context)) (\(reason.evidence.level.displayName))"
            },
            stallSuggestions: suggestions
        )
    }
}

/// The live session logger (phase 1). Targets come from the progression engine; only completed sets are saved.
@MainActor
@Observable
public final class WorkoutModel {
    public private(set) var catalog: [Exercise] = []
    /// Start time of the session in progress; `nil` when no session is open.
    public private(set) var startedAt: Date?
    public var sessionName = "Workout"
    /// Notes on the whole session (sleep, how it felt). Saved trimmed; empty = none.
    public var sessionNotes = ""
    /// Declared focus of the session; `nil` = automatic (per exercise). Change it with `setSessionFocus(_:)`.
    public private(set) var sessionFocus: TrainingFocus?
    /// Exercises of the session in progress. Views bind to it directly (`$model.exercises`).
    public var exercises: [DraftExercise] = []
    public private(set) var errorMessage: String?
    /// The rest between sets.
    public let rest: RestTimerModel

    public var isSessionActive: Bool { startedAt != nil }

    /// Exercises offered by the "Add exercise" picker.
    public var exerciseChoices: [ExerciseChoice] { catalog.map(ExerciseChoice.init) }

    /// Focus values for the session focus picker ("Auto" = `nil` is added by the view).
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses

    private let workouts: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let backup: (any BackupService)?
    private let health: (any HealthWorkoutWriter)?
    private let clock: @Sendable () -> Date

    /// How far back history is read to compute targets and stalls.
    static let historyWindow: TimeInterval = 365 * 86_400

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        backup: (any BackupService)? = nil,
        health: (any HealthWorkoutWriter)? = nil,
        restAlerts: (any RestAlertScheduler)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.exerciseRepository = exercises
        self.progression = progression
        self.backup = backup
        self.health = health
        self.clock = clock
        rest = RestTimerModel(alerts: restAlerts, clock: clock)
    }

    public func load() async {
        do {
            catalog = try await exerciseRepository.allExercises()
        } catch {
            errorMessage = L10n.text("Could not load exercises.")
        }
    }

    public func start(name: String = L10n.text("Workout")) {
        guard startedAt == nil else { return }
        sessionName = name
        sessionNotes = ""
        sessionFocus = nil
        exercises = []
        errorMessage = nil
        startedAt = clock()
    }

    /// Opens a session from `routine`: its name, focus and exercises, with sets prefilled from each exercise's next
    /// progression target. Exercises that no longer exist are skipped. Does nothing if a session is open.
    public func start(_ routine: Routine) async {
        guard !isSessionActive else { return }
        start(name: routine.name)
        sessionFocus = routine.focus
        let session = startedAt
        await load()
        for exerciseID in routine.exerciseIDs {
            guard let exercise = catalog.first(where: { $0.id == exerciseID }) else { continue }
            let prepared = await prepare(exercise, id: UUID())
            // The session may have been discarded while the target was computed.
            guard startedAt == session else { return }
            exercises.append(prepared)
        }
    }

    /// Adds `exercise` with sets prefilled from its next progression target.
    public func add(_ exercise: Exercise) async {
        guard isSessionActive else { return }
        exercises.append(await prepare(exercise, id: UUID()))
    }

    /// Adds the catalog exercise with `exerciseID` (from `exerciseChoices`).
    public func add(exerciseID: UUID) async {
        guard let exercise = catalog.first(where: { $0.id == exerciseID }) else { return }
        await add(exercise)
    }

    /// Declares the session focus (`nil` = automatic) and recomputes targets that have no completed set.
    public func setSessionFocus(_ focus: TrainingFocus?) async {
        guard focus != sessionFocus else { return }
        sessionFocus = focus
        await refreshTargets()
    }

    /// Recomputes targets for exercises with no completed set (e.g. after changing the session focus).
    public func refreshTargets() async {
        let pending = exercises.filter { !$0.sets.contains(where: \.isDone) }
        for current in pending {
            var refreshed = await prepare(current.exercise, id: current.id)
            if let position = exercises.firstIndex(where: { $0.id == current.id }) {
                refreshed.notes = exercises[position].notes
                exercises[position] = refreshed
            }
        }
    }

    /// Declares the focus of one exercise (`nil` = follow the session) and remembers it for the exercise, like its
    /// progression settings do. Its target is recomputed; sets already done are kept.
    public func setFocus(_ focus: TrainingFocus?, of exerciseID: DraftExercise.ID) async {
        guard let exercise = exercises.first(where: { $0.id == exerciseID })?.exercise else { return }
        let defaults = ProgressionSettings(for: exercise)
        do {
            let stored = try await progression.progressionSettings(for: exercise.id)
            guard stored?.focus != focus else { return }
            let updated = (stored ?? defaults).declaring(focus)
            // Settings equal to the defaults are not stored, so the exercise keeps following the session.
            if updated == defaults {
                try await progression.deleteProgressionSettings(for: exercise.id)
            } else {
                try await progression.save(updated, for: exercise.id)
            }
        } catch {
            errorMessage = L10n.text("Could not save the exercise focus. Try again.")
            return
        }
        await applySettingsChanges()
    }

    /// Brings the session up to date after progression settings changed elsewhere. Only affected exercises are
    /// touched, so typed values survive; exercises with completed sets keep their sets and update the target.
    public func applySettingsChanges() async {
        for current in exercises {
            let stored: ProgressionSettings?
            do {
                stored = try await progression.progressionSettings(for: current.exercise.id)
            } catch {
                continue
            }
            guard stored != current.appliedSettings else { continue }
            var refreshed = await prepare(current.exercise, id: current.id)
            guard let position = exercises.firstIndex(where: { $0.id == current.id }) else { continue }
            refreshed.notes = exercises[position].notes
            if exercises[position].sets.contains(where: \.isDone) {
                refreshed.sets = exercises[position].sets
            }
            exercises[position] = refreshed
        }
    }

    /// Target, status, focus and rest for `exercise`. A declared exercise focus wins over the session focus;
    /// without stored settings, the focus picks the default scheme (`FocusPrescription`).
    private func prepare(_ exercise: Exercise, id: UUID) async -> DraftExercise {
        let history = await history(of: exercise.id)
        let stored: ProgressionSettings?
        do {
            stored = try await progression.progressionSettings(for: exercise.id)
        } catch {
            stored = nil
            warnAboutTargets()
        }
        let declaredFocus = stored?.focus ?? sessionFocus
        var settings = stored ?? ProgressionSettings(for: exercise)
        if stored == nil, let declaredFocus {
            settings.scheme = FocusPrescription.for(declaredFocus).defaultScheme
        }
        let inferredFocus = FocusClassifier.dominant(history.indices.suffix(3).compactMap { index in
            FocusClassifier.focus(of: history[index], previous: Array(history[..<index]))
        })
        let focus = declaredFocus ?? inferredFocus
        let target = ProgressionTargets.next(history: history, settings: settings)
        let status = StallDetection.status(history: history, settings: settings)
        let sets = target.sets.map { planned in
            DraftSet(weightKg: planned.weightKg ?? history.last?.workingWeightKg, reps: planned.reps)
        }
        return DraftExercise(
            id: id, exercise: exercise, target: target, status: status, sets: sets, focus: focus,
            isFocusInferred: declaredFocus == nil && focus != nil,
            restSeconds: FocusPrescription.for(focus ?? .hypertrophy).restSeconds,
            appliedSettings: stored,
            scheme: settings.scheme
        )
    }

    public func removeExercise(_ exerciseID: DraftExercise.ID) {
        exercises.removeAll { $0.id == exerciseID }
        rest.stop(exerciseID: exerciseID)
    }

    /// Adds a set copying the last set's values.
    public func addSet(to exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = exercises[index].sets.last
        exercises[index].sets.append(DraftSet(weightKg: last?.weightKg, reps: last?.reps, rpe: last?.rpe))
    }

    public func removeSet(_ setID: DraftSet.ID, from exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[index].sets.removeAll { $0.id == setID }
        rest.stop(setID: setID)
    }

    /// Marks a set as performed, which starts the rest, or undoes it, which stops the rest it started.
    public func setDone(_ isDone: Bool, set setID: DraftSet.ID, in exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = exercises[index].sets.firstIndex(where: { $0.id == setID }),
              exercises[index].sets[setIndex].isDone != isDone else { return }
        exercises[index].sets[setIndex].isDone = isDone
        if isDone {
            rest.start(after: setID, of: exercises[index])
        } else {
            rest.stop(setID: setID)
        }
    }

    /// Saves the completed sets with the notes and closes the session. Returns `false` if saving failed (the draft
    /// is kept). Notes of exercises without completed sets are dropped with them.
    @discardableResult
    public func finish() async -> Bool {
        guard let startedAt else { return false }
        let now = clock()
        let entries = exercises.compactMap { exercise -> ExerciseEntry? in
            let done = exercise.sets.filter(\.isDone).map { set in
                WorkoutSet(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, completedAt: now)
            }
            return done.isEmpty ? nil : ExerciseEntry(
                exerciseID: exercise.exercise.id, sets: done, notes: Self.trimmedOrNil(exercise.notes)
            )
        }
        guard !entries.isEmpty else {
            close()
            return true
        }
        let finished = StrengthSession(
            name: sessionName, startedAt: startedAt, endedAt: now, entries: entries,
            notes: Self.trimmedOrNil(sessionNotes), focus: sessionFocus
        )
        do {
            try await workouts.save(finished)
            close()
            await backup?.backUpIfConfigured(now: now)
            await health?.sync(finished)
            return true
        } catch {
            errorMessage = L10n.text("Could not save the session. It is still open.")
            return false
        }
    }

    public func discard() {
        close()
    }

    private func close() {
        rest.stop()
        startedAt = nil
        exercises = []
        errorMessage = nil
    }

    private func history(of exerciseID: UUID) async -> [ExerciseExposure] {
        let now = clock()
        do {
            let sessions = try await workouts.sessions(from: now.addingTimeInterval(-Self.historyWindow), to: now)
            return ExerciseExposure.history(of: exerciseID, in: sessions)
        } catch {
            warnAboutTargets()
            return []
        }
    }

    private static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func warnAboutTargets() {
        errorMessage = L10n.text("Could not read your history, so these targets may be off.")
    }
}

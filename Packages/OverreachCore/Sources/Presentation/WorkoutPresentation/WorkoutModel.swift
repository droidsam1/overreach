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
    /// A suggested warm-up set: saved as a warm-up, so it never counts for progress or volume.
    public let isWarmUp: Bool

    public init(
        id: UUID = UUID(), weightKg: Double?, reps: Int?, rpe: Double? = nil, isDone: Bool = false,
        isWarmUp: Bool = false
    ) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isDone = isDone
        self.isWarmUp = isWarmUp
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
    /// Warm-up sets suggested for today's target, whether or not they were added.
    var warmUpPlan: [WarmUpSet] = []
    /// Its muscles were already worked earlier in the session, so the warm-up is shorter.
    var isPrimed = false
    /// The numbers behind the status, to explain it.
    var stallFacts: StallFacts?
    /// How effort is shown in the target and its reasons.
    var effortScale = EffortScale.rpe
    /// Sets and reps come from the routine (a plan's prescription), not from the exercise's own settings.
    public var isPrescribedByRoutine = false

    /// 1-based position of a set among the sets of its kind (warm-ups and working sets are numbered apart).
    public func number(of setID: DraftSet.ID) -> Int {
        guard let set = sets.first(where: { $0.id == setID }) else { return 1 }
        return (sets.filter { $0.isWarmUp == set.isWarmUp }.firstIndex { $0.id == setID } ?? 0) + 1
    }

    /// The sets that count: everything except warm-ups.
    public var workingSets: [DraftSet] { sets.filter { !$0.isWarmUp } }

    /// Whether "Add warm-up sets" has something to add.
    public var canAddWarmUp: Bool { !warmUpPlan.isEmpty && !sets.contains(where: \.isWarmUp) }
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
    /// Why the status is what it is, with the numbers and the evidence level; `nil` without enough history.
    public let statusExplanation: String?
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
        var focusLine: String
        if let focus {
            focusLine = focus.displayName + (isFocusInferred ? " " + L10n.text("(detected)") : "") + " · " + rest
        } else {
            focusLine = rest.prefix(1).uppercased() + rest.dropFirst()
        }
        if isPrescribedByRoutine {
            focusLine += " · " + L10n.text("sets and reps from the routine")
        }

        let targetLine: String
        if let first = target.sets.first {
            let weight = first.weightKg.map { format.kilograms($0) + " × " } ?? ""
            let reps = target.sets.map { String($0.reps) }.joined(separator: "/")
            targetLine = L10n.format(
                "Target: {1}{2} @ {3}", weight, reps, effortScale.text(rpe: first.targetRPE, format: format)
            )
        } else {
            targetLine = L10n.text("Target:") + " –"
        }

        var suggestions: [String] = []
        if case let .stalled(list) = status {
            suggestions = list.enumerated().map { index, suggestion in
                "\(index + 1). \(suggestion.text) (\(suggestion.evidence.level.displayName))"
            }
        }
        var reasons = target.reasons.map { reason in
            let context = ReasonContext(target: target, scheme: scheme, format: format, effortScale: effortScale)
            return "\(reason.instruction(context)) (\(reason.evidence.level.displayName))"
        }
        if let warmUp = warmUpReason {
            reasons.append(warmUp)
        }
        return TargetSummary(
            targetLine: targetLine,
            focusLine: focusLine,
            status: status.text,
            isStalled: status.isStalled,
            statusExplanation: statusExplanation(format: format),
            reasons: reasons,
            stallSuggestions: suggestions
        )
    }

    /// "Stalled: your best estimated 1RM in the last 3 sessions (102 kg) does not beat the 6 before (103 kg)…".
    private func statusExplanation(format: Format) -> String? {
        guard let facts = stallFacts, status != .notEnoughData else { return nil }
        let recent = format.kilograms((facts.recentBestKg * 10).rounded() / 10)
        let previous = format.kilograms((facts.previousBestKg * 10).rounded() / 10)
        var text: String
        switch status {
        case .progressing:
            text = L10n.format(
                "Progressing: your best estimated 1RM in the last {1} sessions ({2}) beats the {3} before ({4}).",
                facts.recentSessions, recent, facts.previousSessions, previous
            )
        case .holding:
            text = L10n.format(
                "Holding: your best estimated 1RM in the last {1} sessions ({2}) does not beat the {3} before ({4}), "
                    + "but you are meeting your targets, so keep going.",
                facts.recentSessions, recent, facts.previousSessions, previous
            )
        case .stalled:
            text = L10n.format(
                "Stalled: your best estimated 1RM in the last {1} sessions ({2}) does not beat the {3} before ({4}), "
                    + "and you missed the target in {5} of them.",
                facts.recentSessions, recent, facts.previousSessions, previous, facts.misses
            )
            if let shortfall = facts.lastShortfall, shortfall > 0 {
                text += " " + (shortfall == 1
                    ? L10n.text("Last time you were 1 rep short.")
                    : L10n.format("Last time you were {1} reps short.", shortfall))
            }
        case .notEnoughData:
            return nil
        }
        return text + " (\(ProgressionEvidence.stallHeuristics.level.displayName))"
    }

    /// Why the warm-up sets are there, when there are any.
    private var warmUpReason: String? {
        let warmUps = sets.filter(\.isWarmUp)
        guard !warmUps.isEmpty else { return nil }
        let count = warmUps.count
        let level = WarmUpEvidence.specific.level.displayName
        if isPrimed {
            return L10n.format(
                "Warm-up: one set close to today's load, because these muscles are already warm from earlier "
                    + "exercises. ({1})",
                level
            )
        }
        return L10n.format(
            "Warm-up: {1} sets with few reps, from light to close to today's load, so the work sets start ready but "
                + "fresh. They do not count for progress. ({2})",
            count, level
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
    /// The routine the session was started from: its prescriptions set sets and reps, and the saved session
    /// remembers it so the plan knows which session comes next.
    public private(set) var sessionRoutine: Routine?
    /// Exercises of the session in progress. Views bind to it directly (`$model.exercises`).
    public var exercises: [DraftExercise] = []
    public private(set) var errorMessage: String?
    /// The summary of the session just finished; set it to `nil` to dismiss it.
    public var summary: SessionReport?
    /// The rest between sets.
    public let rest: RestTimerModel

    public var isSessionActive: Bool { startedAt != nil }

    /// How effort is logged and shown (Settings for the athlete; changed from the logging guide).
    public private(set) var effortScale = EffortScale.rpe
    public var showsRepsInReserve: Bool { effortScale == .repsInReserve }

    /// Asks before finishing when some exercises are unfinished (see `unfinishedExplanation`).
    public var isConfirmingUnfinished = false

    /// Names of exercises with some working sets done and others not, e.g. when the session ends early.
    public var unfinishedExerciseNames: [String] {
        exercises.filter(Self.isUnfinished).map(\.name)
    }

    public var unfinishedExplanation: String {
        L10n.format(
            "Unfinished: {1}. If you stopped early, leave them out of your progression so your next targets stay "
                + "right. The work is saved either way.",
            unfinishedExerciseNames.joined(separator: ", ")
        )
    }

    /// An optional general warm-up, suggested until the first set is done.
    public var generalWarmUpTip: String? {
        guard isSessionActive, !exercises.contains(where: { $0.sets.contains(where: \.isDone) }) else { return nil }
        return L10n.format(
            "Optional: 5–10 minutes of easy cardio before lifting tends to help. ({1})",
            WarmUpEvidence.general.level.displayName
        )
    }

    /// Exercises offered by the "Add exercise" picker.
    public var exerciseChoices: [ExerciseChoice] { catalog.map(ExerciseChoice.init) }

    /// Focus values for the session focus picker ("Auto" = `nil` is added by the view).
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses

    private let workouts: any WorkoutRepository
    private let exerciseRepository: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let backup: (any BackupService)?
    private let health: (any HealthWorkoutWriter)?
    private let profiles: (any ProfileRepository)?
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
        profiles: (any ProfileRepository)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.exerciseRepository = exercises
        self.progression = progression
        self.backup = backup
        self.health = health
        self.profiles = profiles
        self.clock = clock
        rest = RestTimerModel(alerts: restAlerts, clock: clock)
    }

    public func load() async {
        do {
            catalog = try await exerciseRepository.allExercises()
        } catch {
            errorMessage = L10n.text("Could not load exercises.")
        }
        await loadEffortScale()
    }

    private func loadEffortScale() async {
        guard let profile = try? await profiles?.profile() else { return }
        applyEffortScale(profile.effortScale)
    }

    private func applyEffortScale(_ scale: EffortScale) {
        effortScale = scale
        for index in exercises.indices {
            exercises[index].effortScale = scale
        }
    }

    /// Logs effort as RPE or reps in reserve from now on (stored in the profile; sets keep storing RPE).
    public func setEffortScale(_ scale: EffortScale) async {
        guard scale != effortScale else { return }
        applyEffortScale(scale)
        guard let profiles, var profile = try? await profiles.profile() else { return }
        profile.effortScale = scale
        try? await profiles.save(profile)
    }

    public func start(name: String = L10n.text("Workout")) {
        guard startedAt == nil else { return }
        sessionName = name
        sessionNotes = ""
        sessionFocus = nil
        sessionRoutine = nil
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
        sessionRoutine = routine
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
        await loadEffortScale()
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
        // A routine's prescription wins in that routine; the engine still sets the load from history.
        let prescribed = sessionRoutine?.prescription(for: exercise.id)
        if let prescribed {
            settings.scheme = prescribed
        }
        let inferredFocus = FocusClassifier.dominant(history.indices.suffix(3).compactMap { index in
            FocusClassifier.focus(of: history[index], previous: Array(history[..<index]))
        })
        let focus = declaredFocus ?? inferredFocus
        let target = ProgressionTargets.next(history: history, settings: settings)
        let status = StallDetection.status(history: history, settings: settings)
        let working = target.sets.map { planned in
            DraftSet(weightKg: planned.weightKg ?? history.last?.workingWeightKg, reps: planned.reps)
        }
        let primed = isPrimed(exercise, before: id)
        let plan = working.first.map { first in
            WarmUpPrescription.sets(
                workingWeightKg: first.weightKg ?? 0, reps: first.reps ?? 1,
                targetRPE: target.sets.first?.targetRPE ?? settings.scheme.targetRPE, equipment: exercise.equipment,
                incrementKg: settings.incrementKg, primed: primed
            )
        } ?? []
        // Main lifts and the first exercise for its muscles get the warm-up; the rest only on demand.
        let warmUps = settings.isMainLift || !primed ? Self.draftSets(plan) : []
        return DraftExercise(
            id: id, exercise: exercise, target: target, status: status, sets: warmUps + working, focus: focus,
            isFocusInferred: declaredFocus == nil && focus != nil,
            restSeconds: FocusPrescription.for(focus ?? .hypertrophy).restSeconds,
            appliedSettings: stored,
            scheme: settings.scheme,
            warmUpPlan: plan,
            isPrimed: primed,
            stallFacts: StallDetection.facts(history: history, settings: settings),
            effortScale: effortScale,
            isPrescribedByRoutine: prescribed != nil
        )
    }

    private static func draftSets(_ plan: [WarmUpSet]) -> [DraftSet] {
        plan.map { DraftSet(weightKg: $0.weightKg, reps: $0.reps, isWarmUp: true) }
    }

    /// Whether the muscles of `exercise` were worked (primary or secondary) by an exercise before `id` in the session.
    private func isPrimed(_ exercise: Exercise, before id: DraftExercise.ID) -> Bool {
        let earlier = exercises.firstIndex { $0.id == id }.map { Array(exercises[..<$0]) } ?? exercises
        let worked = earlier.reduce(into: Set<MuscleGroup>()) { worked, previous in
            worked.formUnion(previous.exercise.primaryMuscles)
            worked.formUnion(previous.exercise.secondaryMuscles)
        }
        return !exercise.primaryMuscles.isDisjoint(with: worked)
    }

    /// Adds the suggested warm-up sets before the working sets of an exercise ("Add warm-up sets").
    public func addWarmUp(to exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }), exercises[index].canAddWarmUp else {
            return
        }
        exercises[index].sets.insert(contentsOf: Self.draftSets(exercises[index].warmUpPlan), at: 0)
    }

    public func removeExercise(_ exerciseID: DraftExercise.ID) {
        exercises.removeAll { $0.id == exerciseID }
        rest.stop(exerciseID: exerciseID)
    }

    /// Adds a working set copying the last working set's values.
    public func addSet(to exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let last = exercises[index].sets.last { !$0.isWarmUp }
        exercises[index].sets.append(DraftSet(weightKg: last?.weightKg, reps: last?.reps, rpe: last?.rpe))
    }

    public func removeSet(_ setID: DraftSet.ID, from exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[index].sets.removeAll { $0.id == setID }
        rest.stop(setID: setID)
    }

    /// Marks a set as performed, which starts the rest (not after warm-ups), or undoes it, which stops the rest it
    /// started.
    public func setDone(_ isDone: Bool, set setID: DraftSet.ID, in exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = exercises[index].sets.firstIndex(where: { $0.id == setID }),
              exercises[index].sets[setIndex].isDone != isDone else { return }
        exercises[index].sets[setIndex].isDone = isDone
        if isDone {
            if !exercises[index].sets[setIndex].isWarmUp {
                rest.start(after: setID, of: exercises[index])
            }
        } else {
            rest.stop(setID: setID)
        }
    }

    /// Finishes, or asks first when some exercises are unfinished (`isConfirmingUnfinished`).
    public func requestFinish() async {
        if unfinishedExerciseNames.isEmpty {
            await finish()
        } else {
            isConfirmingUnfinished = true
        }
    }

    nonisolated private static func isUnfinished(_ exercise: DraftExercise) -> Bool {
        let working = exercise.workingSets
        return working.contains(where: \.isDone) && working.contains { !$0.isDone }
    }

    /// Saves the completed sets with the notes and closes the session. Returns `false` if saving failed (the draft
    /// is kept). Notes of exercises without completed sets are dropped with them. With `countingUnfinished` false,
    /// unfinished exercises are saved but do not count for progression.
    @discardableResult
    public func finish(countingUnfinished: Bool = true) async -> Bool {
        isConfirmingUnfinished = false
        guard let startedAt else { return false }
        let now = clock()
        let entries = exercises.compactMap { exercise -> ExerciseEntry? in
            let done = exercise.sets.filter(\.isDone).map { set in
                WorkoutSet(
                    kind: set.isWarmUp ? .warmup : .working, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
                    completedAt: now
                )
            }
            return done.isEmpty ? nil : ExerciseEntry(
                exerciseID: exercise.exercise.id, sets: done, notes: Self.trimmedOrNil(exercise.notes),
                countsForProgression: countingUnfinished || !Self.isUnfinished(exercise)
            )
        }
        guard !entries.isEmpty else {
            close()
            return true
        }
        let finished = StrengthSession(
            name: sessionName, startedAt: startedAt, endedAt: now, entries: entries,
            notes: Self.trimmedOrNil(sessionNotes), focus: sessionFocus, routineID: sessionRoutine?.id
        )
        let targets = Dictionary(exercises.map { ($0.exercise.id, $0.target) }, uniquingKeysWith: { first, _ in first })
        do {
            try await workouts.save(finished)
            let summary = await makeSummary(of: finished, targets: targets, now: now)
            close()
            self.summary = summary
            await backup?.backUpIfConfigured(now: now)
            await health?.sync(finished)
            return true
        } catch {
            errorMessage = L10n.text("Could not save the session. It is still open.")
            return false
        }
    }

    private func makeSummary(
        of session: StrengthSession, targets: [UUID: ExerciseTarget], now: Date
    ) async -> SessionReport {
        let history = (try? await workouts.sessions(from: now.addingTimeInterval(-Self.historyWindow), to: now)) ?? []
        let settings = (try? await progression.allProgressionSettings()) ?? [:]
        let review = SessionReviewer.review(
            session, targets: targets, history: history, exercises: catalog, settings: settings
        )
        return SessionReport(review: review, effortScale: effortScale, format: Format())
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

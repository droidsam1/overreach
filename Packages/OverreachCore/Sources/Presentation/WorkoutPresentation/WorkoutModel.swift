import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// A set being logged. Prefilled from the progression target; `isDone` marks it as performed.
public struct DraftSet: Identifiable, Hashable, Codable, Sendable {
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
public struct DraftExercise: Identifiable, Hashable, Codable, Sendable {
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
    /// Progressions offered after the first logged session; optional so drafts saved before them still load.
    var firstProgressionChoices: [FirstProgression.Choice]?
    var setsBeforeProgressionChoice: [DraftSet]?
    /// The working sets of the latest saved session with this exercise; optional so older drafts still load.
    var lastTime: LastTimeSets?

    /// 1-based position of a set among the sets of its kind (warm-ups and working sets are numbered apart).
    public func number(of setID: DraftSet.ID) -> Int {
        guard let set = sets.first(where: { $0.id == setID }) else { return 1 }
        return (sets.filter { $0.isWarmUp == set.isWarmUp }.firstIndex { $0.id == setID } ?? 0) + 1
    }

    /// The sets that count: everything except warm-ups.
    public var workingSets: [DraftSet] { sets.filter { !$0.isWarmUp } }

    /// Whether "Add warm-up sets" has something to add.
    public var canAddWarmUp: Bool { !warmUpPlan.isEmpty && !sets.contains(where: \.isWarmUp) }

    /// Whether "Use last time's values" would change an open working set.
    public var canUseLastTime: Bool { !setsToFillFromLastTime().isEmpty }

    /// Copies weight and reps of last time's sets, by position, into the working sets not yet done. Effort stays
    /// as entered: it describes today's set, not a previous one.
    mutating func useLastTime() {
        guard let lastTime else { return }
        for (index, id) in setsToFillFromLastTime() {
            guard let position = sets.firstIndex(where: { $0.id == id }) else { continue }
            sets[position].weightKg = lastTime.sets[index].weightKg
            sets[position].reps = lastTime.sets[index].reps
        }
    }

    /// Open working sets whose values differ from the set in the same position last time.
    private func setsToFillFromLastTime() -> [(index: Int, id: DraftSet.ID)] {
        guard let lastTime else { return [] }
        return workingSets.enumerated().compactMap { index, set in
            guard !set.isDone, index < lastTime.sets.count else { return nil }
            let last = lastTime.sets[index]
            return set.weightKg != last.weightKg || set.reps != last.reps ? (index, set.id) : nil
        }
    }
}

/// What the logger shows about an exercise's target: one-line summary plus the reasons behind it.
public struct TargetSummary: Hashable, Sendable {
    /// "Target: 62.5 kg × 8/8/8 @ RPE 8"
    public let targetLine: String
    /// "Hypertrophy (detected) · rest 1:30–2:00"
    public let focusLine: String
    /// "Last time (12 Nov): 60 kg × 8/8/7 @ RPE 8", or a clear empty state without saved sets.
    public let lastTimeLine: String
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
    /// "Learn more" about the reasons and suggestions above (ADR-0030); often empty.
    public let readings: [Reading]
}

extension DraftExercise {
    public var name: String { exercise.displayName }

    /// Focus declared for this exercise (remembered in its progression settings); `nil` = follow the session.
    public var declaredFocus: TrainingFocus? { appliedSettings?.focus }

    public var summary: TargetSummary { summary(format: Format()) }

    public var progressionOffer: ProgressionOffer? {
        guard let choices = firstProgressionChoices, !choices.isEmpty, sets == setsBeforeProgressionChoice else {
            return nil
        }
        return ProgressionOffer.make(baseline: target, choices: choices,
                                     effortScale: effortScale, format: Format())
    }

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
        if let first = target.sets.first, target.sets.contains(where: { $0.weightKg != first.weightKg }) {
            targetLine = L10n.format(
                "Target: {1}{2} @ {3}", "", format.groupedSets(target.sets),
                effortScale.text(rpe: first.targetRPE, format: format)
            )
        } else if let first = target.sets.first {
            let weight = first.weightKg.map { format.kilograms($0) + " × " } ?? ""
            let reps = target.sets.map { String($0.reps) }.joined(separator: "/")
            targetLine = L10n.format(
                "Target: {1}{2} @ {3}", weight, reps, effortScale.text(rpe: first.targetRPE, format: format)
            )
        } else {
            targetLine = L10n.text("Target:") + " –"
        }

        var suggestions: [String] = []
        var evidence = target.reasons.map(\.evidence)
        if case let .stalled(list) = status {
            evidence += list.map(\.evidence)
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
        let lastTimeLine = lastTime.map { last in
            L10n.format(
                "Last time ({1}): {2}",
                last.date.formatted(.dateTime.day().month(.abbreviated).locale(format.locale)),
                last.text(effortScale: effortScale, format: format)
            )
        } ?? L10n.text("Last time: no sets logged yet")
        return TargetSummary(
            targetLine: targetLine,
            focusLine: focusLine,
            lastTimeLine: lastTimeLine,
            status: status.text,
            isStalled: status.isStalled,
            statusExplanation: statusExplanation(format: format),
            reasons: reasons,
            stallSuggestions: suggestions,
            readings: FurtherReading.readings(for: evidence)
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
    public var sessionName = "Workout" {
        didSet { saveDraft() }
    }
    /// Notes on the whole session (sleep, how it felt). Saved trimmed; empty = none.
    public var sessionNotes = "" {
        didSet { saveDraft() }
    }
    /// Declared focus of the session; `nil` = automatic (per exercise). Change it with `setSessionFocus(_:)`.
    public private(set) var sessionFocus: TrainingFocus? {
        didSet { saveDraft() }
    }
    /// The routine the session was started from: its prescriptions set sets and reps, and the saved session
    /// remembers it so the plan knows which session comes next.
    public private(set) var sessionRoutine: Routine?
    /// Exercises of the session in progress. Views bind to it directly (`$model.exercises`).
    public var exercises: [DraftExercise] = [] {
        didSet { saveDraft() }
    }
    public private(set) var errorMessage: String?
    public private(set) var isSavingProgression = false
    public private(set) var progressionSaveError: String?
    /// The summary of the session just finished; set it to `nil` to dismiss it.
    public var summary: SessionReport?
    /// The rest between sets.
    public let rest: RestTimerModel

    public var isSessionActive: Bool { startedAt != nil }
    public private(set) var isPreparingSession = false
    public private(set) var isSavingSession = false
    public private(set) var isRecoveringDraft = false
    public private(set) var draftErrorMessage: String?
    public private(set) var draftNotice: String?
    public var needsDraftRecovery: Bool { pendingDraft != nil || isDraftUnreadable }
    public var recoverableWorkoutName: String? { pendingDraft?.name }
    public var recoverableWorkoutStart: Date? { pendingDraft?.startedAt }
    public var canResumeWorkout: Bool { pendingDraft != nil }

    private var sessionID: UUID?
    private var pendingDraft: WorkoutDraft?
    private var isDraftUnreadable = false

    /// How effort is logged and shown (Settings for the athlete; changed from the logging guide).
    public private(set) var effortScale = EffortScale.rpe
    /// The plan of an accepted deload week covering today (ADR-0027): targets are reduced while it lasts.
    public private(set) var deloadPlan: DeloadPlan?
    /// "Deload week: targets have fewer sets and less load until Sunday 23 November."
    public var deloadNotice: String? {
        deloadPlan == nil ? nil : L10n.text("Deload week: today's targets have fewer sets, less load and easier efforts.")
    }
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
    public var exerciseChoices: [ExerciseChoice] { Exercise.byDisplayName(catalog).map(ExerciseChoice.init) }

    /// Focus values for the session focus picker ("Auto" = `nil` is added by the view).
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses

    private let workouts: any WorkoutRepository
    private let draftStore: (any WorkoutDraftStore)?
    private let exerciseRepository: any ExerciseRepository
    private let progression: any ProgressionSettingsRepository
    private let backup: (any BackupService)?
    private let health: (any HealthWorkoutWriter)?
    private let profiles: (any ProfileRepository)?
    private let clock: @Sendable () -> Date

    /// How far back history is read to compute targets and stalls.
    static let historyWindow = ProgressionTargets.historyWindow

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        progression: any ProgressionSettingsRepository,
        backup: (any BackupService)? = nil,
        health: (any HealthWorkoutWriter)? = nil,
        restAlerts: (any RestAlertScheduler)? = nil,
        profiles: (any ProfileRepository)? = nil,
        draftStore: (any WorkoutDraftStore)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.draftStore = draftStore
        self.exerciseRepository = exercises
        self.progression = progression
        self.backup = backup
        self.health = health
        self.profiles = profiles
        self.clock = clock
        rest = RestTimerModel(alerts: restAlerts, clock: clock)
        rest.onChange = { [weak self] in self?.saveDraft() }
        readSavedDraft()
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
        let today = CalendarDay(clock())
        deloadPlan = RecoveryHistory.deloadInProgress(profile, on: today).map {
            $0.forLifeStress == true ? DeloadPlan.stressAware : DeloadPlan.standard
        }
    }

    private func applyEffortScale(_ scale: EffortScale) {
        guard scale != effortScale else { return }
        effortScale = scale
        exercises = exercises.map { exercise in
            var updated = exercise
            updated.effortScale = scale
            return updated
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
        guard !isSessionActive, !needsDraftRecovery, !isSavingSession else { return }
        beginSession(name: name)
        saveDraft()
    }

    private func beginSession(name: String, routine: Routine? = nil) {
        sessionName = name
        sessionNotes = ""
        sessionFocus = routine?.focus
        sessionRoutine = routine
        exercises = []
        errorMessage = nil
        draftNotice = nil
        sessionID = UUID()
        startedAt = clock()
    }

    /// Prefills a routine before exposing the editable draft, so recovery never restores half a routine.
    public func start(_ routine: Routine) async {
        guard !isSessionActive, !needsDraftRecovery, !isSavingSession else { return }
        isPreparingSession = true
        beginSession(name: routine.name, routine: routine)
        await load()
        for exerciseID in routine.exerciseIDs {
            guard let exercise = catalog.first(where: { $0.id == exerciseID }) else { continue }
            exercises.append(await prepare(exercise, id: UUID()))
        }
        isPreparingSession = false
        saveDraft()
    }

    /// Adds an exercise with sets prefilled from its next progression target.
    public func add(_ exercise: Exercise) async {
        guard let sessionID, !isSavingSession, !isPreparingSession else { return }
        let prepared = await prepare(exercise, id: UUID())
        guard self.sessionID == sessionID, !isSavingSession else { return }
        exercises.append(prepared)
    }

    /// Adds the catalog exercise with `exerciseID` (from `exerciseChoices`).
    public func add(exerciseID: UUID) async {
        guard let exercise = catalog.first(where: { $0.id == exerciseID }) else { return }
        await add(exercise)
    }

    /// The form to create an exercise the picker did not find, named as typed in its search.
    public func newExercise(named name: String) -> NewExerciseModel {
        NewExerciseModel(name: name, catalog: catalog, repository: exerciseRepository)
    }

    /// Adds an exercise just created with `newExercise(named:)` to the catalog and the session.
    public func addCreated(_ exercise: Exercise) async {
        if !catalog.contains(where: { $0.id == exercise.id }) { catalog.append(exercise) }
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
        guard let sessionID, !isSavingSession, !isPreparingSession else { return }
        let pending = exercises.filter { !$0.sets.contains(where: \.isDone) }
        for current in pending {
            var refreshed = await prepare(current.exercise, id: current.id)
            guard self.sessionID == sessionID, !isSavingSession else { return }
            if let position = exercises.firstIndex(where: { $0.id == current.id }),
               exercises[position].sets == current.sets {
                refreshed.notes = exercises[position].notes
                exercises[position] = refreshed
            }
        }
    }

    public func progressionOffer(for id: DraftExercise.ID) -> ProgressionOffer? {
        exercises.first { $0.id == id }?.progressionOffer
    }

    public func clearProgressionSaveError() {
        progressionSaveError = nil
    }

    /// Saves the selected scheme for the lift and uses its preview for untouched drafts in this session.
    public func chooseProgression(_ option: ProgressionOffer.Option, for id: DraftExercise.ID) async -> Bool {
        guard !isSavingProgression, let current = exercises.first(where: { $0.id == id }),
              current.progressionOffer?.options.contains(option) == true else { return false }
        isSavingProgression = true
        progressionSaveError = nil
        defer { isSavingProgression = false }
        do {
            guard try await progression.progressionSettings(for: current.exercise.id) == nil,
                  progressionOffer(for: id)?.options.contains(option) == true else {
                progressionSaveError = L10n.text("The exercise changed. Close this screen and review your sets.")
                return false
            }
            try await progression.save(option.choice.settings, for: current.exercise.id)
        } catch {
            progressionSaveError = L10n.text("Could not save the progression. Try again.")
            return false
        }
        let settings = option.choice.settings
        for index in exercises.indices where exercises[index].exercise.id == current.exercise.id {
            var draft = exercises[index]
            if draft.progressionOffer?.options.contains(option) == true {
                draft.target = option.choice.target
                draft.warmUpPlan = Self.warmUpPlan(
                    for: draft.target, exercise: draft.exercise, settings: settings, primed: draft.isPrimed
                )
                draft.sets = Self.prefilledSets(
                    for: draft.target, warmUps: draft.warmUpPlan, settings: settings, primed: draft.isPrimed
                )
            }
            draft.appliedSettings = settings
            draft.scheme = settings.scheme
            draft.firstProgressionChoices = []
            draft.setsBeforeProgressionChoice = []
            exercises[index] = draft
        }
        await backup?.backUpIfConfigured(now: clock())
        return true
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
        guard let sessionID, !isSavingSession, !isPreparingSession else { return }
        for current in exercises {
            let stored: ProgressionSettings?
            do {
                stored = try await progression.progressionSettings(for: current.exercise.id)
            } catch {
                continue
            }
            guard stored != current.appliedSettings else { continue }
            var refreshed = await prepare(current.exercise, id: current.id)
            guard self.sessionID == sessionID, !isSavingSession else { return }
            guard let position = exercises.firstIndex(where: { $0.id == current.id }) else { continue }
            refreshed.notes = exercises[position].notes
            if exercises[position].sets != current.sets || exercises[position].sets.contains(where: \.isDone) {
                refreshed.sets = exercises[position].sets
            }
            exercises[position] = refreshed
        }
    }

    /// Target, status, focus and rest for `exercise`. A declared exercise focus wins over the session focus;
    /// without stored settings, the focus picks the default scheme (`FocusPrescription`).
    private func prepare(_ exercise: Exercise, id: UUID) async -> DraftExercise {
        let now = clock()
        let sessions = await recentSessions(now: now)
        let history = ExerciseExposure.history(of: exercise.id, in: sessions)
        let stored: ProgressionSettings?
        let readSettings: Bool
        do {
            stored = try await progression.progressionSettings(for: exercise.id)
            readSettings = true
        } catch {
            stored = nil
            readSettings = false
            warnAboutTargets()
        }
        let declaredFocus = stored?.focus ?? sessionFocus
        // A routine's prescription wins in that routine; the engine still sets the load from history.
        let prescribed = sessionRoutine?.prescription(for: exercise.id)
        let settings = ProgressionTargets.settings(for: exercise, stored: stored, focus: declaredFocus,
                                                   prescription: prescribed)
        let inferredFocus = FocusClassifier.dominant(history.indices.suffix(3).compactMap { index in
            FocusClassifier.focus(of: history[index], previous: Array(history[..<index]))
        })
        let focus = declaredFocus ?? inferredFocus
        let fromBaseline = stored == nil && prescribed == nil
        let progressed = ProgressionTargets.next(history: history, settings: settings, startFromBaseline: fromBaseline)
        // During an accepted deload week the same exercises are trained lighter (ADR-0027).
        let target = deloadPlan.map { $0.applied(to: progressed, incrementKg: settings.incrementKg) } ?? progressed
        let choices: [FirstProgression.Choice]
        if fromBaseline, deloadPlan == nil, readSettings, history.count == 1, let first = history.first {
            choices = FirstProgression.choices(from: first, settings: settings)
        } else {
            choices = []
        }
        let lift = LiftStatus.assess(exerciseID: exercise.id, history: history, settings: settings, now: now)
        let primed = isPrimed(exercise, before: id)
        let fallbackWeightKg = history.last?.workingWeightKg
        let plan = Self.warmUpPlan(
            for: target, exercise: exercise, settings: settings, primed: primed, fallbackWeightKg: fallbackWeightKg
        )
        let sets = Self.prefilledSets(
            for: target, warmUps: plan, settings: settings, primed: primed, fallbackWeightKg: fallbackWeightKg
        )
        return DraftExercise(
            id: id, exercise: exercise, target: target, status: lift.status, sets: sets, focus: focus,
            isFocusInferred: declaredFocus == nil && focus != nil,
            restSeconds: FocusPrescription.for(focus ?? .hypertrophy).restSeconds,
            appliedSettings: stored,
            scheme: settings.scheme,
            warmUpPlan: plan,
            isPrimed: primed,
            stallFacts: lift.facts,
            effortScale: effortScale,
            isPrescribedByRoutine: prescribed != nil,
            firstProgressionChoices: choices,
            setsBeforeProgressionChoice: choices.isEmpty ? [] : sets,
            lastTime: LastTimeSets.latest(of: exercise.id, in: sessions)
        )
    }

    private static func warmUpPlan(
        for target: ExerciseTarget, exercise: Exercise, settings: ProgressionSettings, primed: Bool,
        fallbackWeightKg: Double? = nil
    ) -> [WarmUpSet] {
        guard let first = target.sets.first else { return [] }
        return WarmUpPrescription.sets(
            workingWeightKg: first.weightKg ?? fallbackWeightKg ?? 0, reps: first.reps, targetRPE: first.targetRPE,
            equipment: exercise.equipment, incrementKg: settings.incrementKg, primed: primed
        )
    }

    private static func prefilledSets(
        for target: ExerciseTarget, warmUps: [WarmUpSet], settings: ProgressionSettings, primed: Bool,
        fallbackWeightKg: Double? = nil
    ) -> [DraftSet] {
        // Main lifts and the first exercise for its muscles get the warm-up; the rest only on demand.
        let warmUpSets = settings.isMainLift || !primed ? draftSets(warmUps) : []
        return warmUpSets + target.sets.map { DraftSet(weightKg: $0.weightKg ?? fallbackWeightKg, reps: $0.reps) }
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

    /// Fills the open working sets with last time's weight and reps, when the athlete asks for it.
    public func useLastTime(for exerciseID: DraftExercise.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }), exercises[index].canUseLastTime else {
            return
        }
        exercises[index].useLastTime()
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
        guard !isSavingSession, !isPreparingSession else { return }
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
        guard let sessionID, let startedAt, !isSavingSession, !isPreparingSession else { return false }
        let now = clock()
        let entries = exercises.compactMap { exercise -> ExerciseEntry? in
            let done = exercise.sets.filter(\.isDone).map { set in
                WorkoutSet(
                    id: set.id, kind: set.isWarmUp ? .warmup : .working, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
                    completedAt: now
                )
            }
            return done.isEmpty ? nil : ExerciseEntry(
                id: exercise.id, exerciseID: exercise.exercise.id, sets: done, notes: Self.trimmedOrNil(exercise.notes),
                countsForProgression: countingUnfinished || !Self.isUnfinished(exercise)
            )
        }
        guard !entries.isEmpty else {
            guard clearStoredDraft() else { return false }
            close()
            return true
        }
        let finished = StrengthSession(
            id: sessionID, name: sessionName, startedAt: startedAt, endedAt: now, entries: entries,
            notes: Self.trimmedOrNil(sessionNotes), focus: sessionFocus, routineID: sessionRoutine?.id
        )
        let targets = Dictionary(exercises.map { ($0.exercise.id, $0.target) }, uniquingKeysWith: { first, _ in first })
        isSavingSession = true
        do {
            try await workouts.save(finished)
        } catch {
            isSavingSession = false
            errorMessage = L10n.text("Could not save the session. It is still open.")
            return false
        }

        // If the app stops after the commit but before cleanup, resume finds the finished session by this same ID.
        if !clearStoredDraft() {
            pendingDraft = draft
        }
        close()
        summary = await makeSummary(of: finished, targets: targets, now: now)
        isSavingSession = false
        await backup?.backUpIfConfigured(now: now)
        await health?.sync(finished)
        return true
    }

    private func makeSummary(
        of session: StrengthSession, targets: [UUID: ExerciseTarget], now: Date
    ) async -> SessionReport {
        let history = (try? await workouts.sessions(from: now.addingTimeInterval(-Self.historyWindow), to: now)) ?? []
        let settings = (try? await progression.allProgressionSettings()) ?? [:]
        let review = SessionReviewer.review(
            session, targets: targets, history: history, exercises: catalog, settings: settings, routine: sessionRoutine
        )
        return SessionReport(review: review, effortScale: effortScale, format: Format())
    }

    public func discard() {
        let mayHavePendingRestAlert = pendingDraft?.rest != nil || isDraftUnreadable
        guard !isPreparingSession, !isSavingSession, !isRecoveringDraft, clearStoredDraft() else { return }
        close(cancelPendingRestAlert: mayHavePendingRestAlert)
    }

    private func close(cancelPendingRestAlert: Bool = false) {
        startedAt = nil
        sessionID = nil
        rest.stop(cancelPendingAlert: cancelPendingRestAlert)
        exercises = []
        errorMessage = nil
    }

    // MARK: Draft recovery

    public func resumeSavedWorkout() async {
        guard let pendingDraft, !isRecoveringDraft, !isSavingSession, !isSessionActive else { return }
        isRecoveringDraft = true
        defer { isRecoveringDraft = false }
        do {
            if try await workouts.containsSession(id: pendingDraft.id) {
                if clearStoredDraft() {
                    if pendingDraft.rest != nil {
                        rest.stop(cancelPendingAlert: true)
                    }
                    draftNotice = L10n.text("This workout is already saved in History.")
                }
                return
            }
        } catch {
            draftErrorMessage = L10n.text("Could not check the saved workout. Try again.")
            return
        }

        sessionID = pendingDraft.id
        startedAt = pendingDraft.startedAt
        sessionName = pendingDraft.name
        sessionNotes = pendingDraft.notes
        sessionFocus = pendingDraft.focus
        sessionRoutine = pendingDraft.routine
        effortScale = pendingDraft.effortScale
        exercises = pendingDraft.exercises
        if let timer = pendingDraft.rest,
           let exercise = exercises.first(where: { $0.id == timer.exerciseID }),
           exercise.sets.contains(where: { $0.id == timer.setID && $0.isDone }) {
            rest.restore(timer, for: exercise)
        }
        self.pendingDraft = nil
        draftErrorMessage = nil
    }

    public func retryDraftAccess() {
        if isSessionActive {
            saveDraft()
        } else if isDraftUnreadable {
            readSavedDraft()
        }
    }

    private var draft: WorkoutDraft? {
        guard let sessionID, let startedAt else { return nil }
        return WorkoutDraft(
            id: sessionID, startedAt: startedAt, name: sessionName, notes: sessionNotes, focus: sessionFocus,
            routine: sessionRoutine, effortScale: effortScale, exercises: exercises, rest: rest.draft
        )
    }

    private func readSavedDraft() {
        do {
            pendingDraft = try draftStore?.readDraft().map { try JSONDecoder().decode(WorkoutDraft.self, from: $0) }
            if let pendingDraft, pendingDraft.version != WorkoutDraft.currentVersion {
                self.pendingDraft = nil
                isDraftUnreadable = true
            } else {
                isDraftUnreadable = false
            }
        } catch {
            pendingDraft = nil
            isDraftUnreadable = true
        }
        draftErrorMessage = isDraftUnreadable ? L10n.text("Could not open the saved workout.") : nil
    }

    private func saveDraft() {
        guard let draftStore, !isPreparingSession, !isRecoveringDraft, !isSavingSession, let draft else { return }
        do {
            try draftStore.writeDraft(JSONEncoder().encode(draft))
            draftErrorMessage = nil
        } catch {
            draftErrorMessage = L10n.text("Could not save the draft. Keep the app open and try again.")
        }
    }

    private func clearStoredDraft() -> Bool {
        do {
            try draftStore?.writeDraft(nil)
            pendingDraft = nil
            isDraftUnreadable = false
            draftErrorMessage = nil
            return true
        } catch {
            draftErrorMessage = L10n.text("Could not remove the saved workout draft. Try again.")
            return false
        }
    }

    private func recentSessions(now: Date) async -> [StrengthSession] {
        do {
            return try await workouts.sessions(from: now.addingTimeInterval(-Self.historyWindow), to: now)
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

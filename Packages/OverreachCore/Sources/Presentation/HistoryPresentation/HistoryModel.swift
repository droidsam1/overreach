import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// One past session as shown in the list.
public struct SessionSummary: Identifiable, Hashable, Sendable {
    public let session: StrengthSession
    public let exerciseNames: [String]
    public let workingSets: Int
    public let tonnageKg: Double
    var matchedSources: [DataSourceKind] = []
    var weightUnit = WeightUnit.kilograms
    var rotationOutcomes: [RotationAdjustment.Outcome] = []

    public var rotationLabels: [String] {
        RotationAdjustment.Action.allCases.filter { action in
            rotationOutcomes.contains { $0.action == action }
        }.map {
            switch $0 {
            case .swapped: L10n.text("Swapped in rotation")
            case .postponed: L10n.text("Postponed in rotation")
            case .capped: L10n.text("Rotation effort capped")
            }
        }
    }

    var sources: [DataSourceKind] {
        [session.source] + matchedSources.filter { $0 != session.source }
    }

    public var sourceText: String { sources.map(\.displayName).joined(separator: " · ") }

    public var id: UUID { session.id }
    public var title: String { session.name }
    public var date: Date { session.startedAt }
    /// "Squat (Barbell), Leg Press"
    public var exerciseList: String { exerciseNames.joined(separator: ", ") }

    /// "12 sets · 3,450 kg"
    public func statsLine(format: Format? = nil) -> String {
        let format = format ?? Format(weightUnit: weightUnit)
        return L10n.format("{1} sets · {2}", workingSets, format.weight(tonnageKg, maxFractionDigits: 0))
    }
}

/// One past session as shown in its detail screen.
public struct SessionDetail: Sendable {
    public struct SetLine: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let number: Int
        /// "80 kg × 5 @ 8 (warm-up)"
        public let text: String
        /// "e1RM 93.3" for working sets with weight and reps.
        public let estimatedOneRepMax: String?
    }

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let sets: [SetLine]
        public let notes: String?
        /// `false` for an exercise left unfinished: shown, but ignored by the progression engine.
        public let countsForProgression: Bool
    }

    public let id: UUID
    public let name: String
    public let startedAt: Date
    public let durationSeconds: TimeInterval?
    public let focus: String?
    public let notes: String?
    public let entries: [Entry]
    public let recording: HistoryStrengthActivity?
    public let sourceText: String
    public let rotationLabels: [String]
}

/// The latest completed set of an exercise the athlete searched for: "What did I lift last time?"
public struct LastExerciseResult: Identifiable, Hashable, Sendable {
    public let sessionID: UUID
    public let exerciseName: String
    public let date: Date
    /// Working sets, as "80 kg × 5 @ 8".
    public let sets: [String]
    public var id: UUID { sessionID }
}

/// A timeline of strength and running, newest first, plus the month calendar.
@MainActor
@Observable
public final class HistoryModel {
    public private(set) var summaries: [SessionSummary] = []
    public private(set) var exerciseNames: [UUID: String] = [:]
    public private(set) var catalog: [Exercise] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var runWarning: String?
    public var activityFilter: HistoryActivityFilter = .all
    public var sourceFilter: DataSourceKind?
    /// Free text matched against activity names, exercises and sources. Empty means no search.
    public var searchText = ""
    public var hasFilters: Bool { activityFilter != .all || sourceFilter != nil }
    public var isSearching: Bool { !SearchText.normalize(searchText).isEmpty }
    var isFiltering: Bool { hasFilters || isSearching }

    public var sourceOptions: [Option<DataSourceKind>] {
        var available = Set(timeline.flatMap { $0.sources })
        if let sourceFilter { available.insert(sourceFilter) }
        return DataSourceKind.allCases.filter { available.contains($0) }.map {
            Option(value: $0, name: $0.displayName)
        }
    }

    public var filterSummary: String {
        [activityFilter == .all ? nil : activityFilter.title, sourceFilter?.displayName]
            .compactMap { $0 }.joined(separator: " · ")
    }
    /// Result of saving a session as a routine, until the user dismisses it.
    public private(set) var routineNotice: String?

    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let routines: any RoutineRepository
    private let backup: (any BackupService)?
    private let health: (any HealthWorkoutWriter)?
    private let profiles: (any ProfileRepository)?
    private var rotationAdjustments: [RotationAdjustment] = []
    private let progression: (any ProgressionSettingsRepository)?
    private let recordedStrength: (any RecordedStrengthSource)?
    private let activitySources: [any ActivitySource]
    private let companionAnswers: DogWalkAnswers
    private let dogRunAnswers: DogRunAnswers
    private var walkingRoutine = WalkingRoutine()
    private var walks: [WalkBout] = []
    private var walkLines: [HistoryWalk] = []
    private let runSources: [any MetricsSource]
    private var format: Format
    private let clock: @Sendable () -> Date
    private var effortScale = EffortScale.rpe
    private var recordings: [RecordedStrengthActivity] = []
    private var runOriginals: [RunActivity] = []
    private var runRange: ClosedRange<Date>?
    public private(set) var runReviews: [HistoryRunReview] = []
    private let saveRunChoices: ([RunMatchPair: RunMatchChoice]) -> Void
    private var runChoices: [RunMatchPair: RunMatchChoice]
    private var runLines: [HistoryRunActivity] = []
    private var timeline: [HistoryRow] = []
    private var strengthMatches = StrengthActivityMatches()
    private var strengthSessions: [StrengthSession] = []
    private var strengthChoices: [StrengthMatchPair: StrengthMatchChoice]
    private let saveStrengthChoices: ([StrengthMatchPair: StrengthMatchChoice]) -> Void
    public private(set) var strengthReviews: [HistoryStrengthReview] = []

    /// How far back the list goes.
    static let window: TimeInterval = 365 * 86_400

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        routines: any RoutineRepository,
        backup: (any BackupService)? = nil,
        health: (any HealthWorkoutWriter)? = nil,
        profiles: (any ProfileRepository)? = nil,
        progression: (any ProgressionSettingsRepository)? = nil,
        runSources: [any MetricsSource] = [],
        recordedStrength: (any RecordedStrengthSource)? = nil,
        activitySources: [any ActivitySource] = [],
        companionAnswers: DogWalkAnswers? = nil,
        dogRunAnswers: DogRunAnswers = DogRunAnswers(),
        calendar: Calendar = .current,
        format: Format = Format(),
        runChoices: [RunMatchPair: RunMatchChoice] = [:],
        saveRunChoices: @escaping ([RunMatchPair: RunMatchChoice]) -> Void = { _ in },
        strengthChoices: [StrengthMatchPair: StrengthMatchChoice] = [:],
        saveStrengthChoices: @escaping ([StrengthMatchPair: StrengthMatchChoice]) -> Void = { _ in },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.routines = routines
        self.backup = backup
        self.health = health
        self.profiles = profiles
        self.progression = progression
        self.recordedStrength = recordedStrength
        self.activitySources = activitySources
        self.companionAnswers = companionAnswers ?? DogWalkAnswers()
        self.dogRunAnswers = dogRunAnswers
        self.runSources = runSources
        self.format = format
        self.clock = clock
        self.runChoices = runChoices
        self.saveRunChoices = saveRunChoices
        self.strengthChoices = strengthChoices
        self.saveStrengthChoices = saveStrengthChoices
        self.calendar = HistoryCalendarModel(
            workouts: workouts, activitySources: activitySources, runSources: runSources,
            calendar: calendar, format: format, runChoices: runChoices, clock: clock
        )
    }

    /// The month calendar: strength days, runs and steps (a sub-screen of History).
    public let calendar: HistoryCalendarModel

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let now = clock()
        let start = now.addingTimeInterval(-Self.window)
        // Read on both sides of the boundary so shifted copies match before we filter by the preferred start.
        async let loadedRuns = HistoryRunReadings.load(
            sources: runSources, from: start.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)
        )
        async let loadedWalks = loadWalks(from: start, to: now)
        async let loadedRecordings = recordedStrength?.strengthActivities(from: .distantPast, to: now)
        var failed = false
        do {
            catalog = try await exercises.allExercises()
            exerciseNames = Exercise.displayNames(catalog)
            calendar.exerciseNames = exerciseNames
        } catch {
            failed = true
        }
        do {
            let sessions = try await workouts.sessions(from: recordedStrength == nil ? start : .distantPast, to: now)
            strengthSessions = sessions
            summaries = sessions.reversed().filter { $0.startedAt >= start }.map(summary)
        } catch {
            failed = true
        }
        if let profile = try? await profiles?.profile() {
            rotationAdjustments = profile.rotationAdjustments
            format.weightUnit = profile.weightUnit
            calendar.weightUnit = profile.weightUnit
            effortScale = profile.effortScale
            walkingRoutine = profile.walkingRoutine
            calendar.restDays = Set(profile.restDays)
        }
        walks = await loadedWalks
        walkLines = EverydayMovement.removingDuplicateWalks(walks).map { walk in
            let sources = Set(CompanionWalkMatching.answerKeys(for: walk, among: walks).map(\.source))
            return HistoryWalk(walk, sources: sources.sorted { $0.rawValue < $1.rawValue },
                               calendar: calendar.calendar, format: format)
        }
        recordings = await loadedRecordings ?? []
        let runReadings = await loadedRuns
        runOriginals = runReadings.runs
        runRange = start...now
        resolveStrength()
        resolveRuns()
        errorMessage = failed ? L10n.text("Could not load your history.") : nil
        runWarning = runReadings.warning()
    }

    private func loadWalks(from start: Date, to now: Date) async -> [WalkBout] {
        let calendar = calendar.calendar
        let range = CalendarDay(start, calendar: calendar)...CalendarDay(now, calendar: calendar)
        var walks: [WalkKey: WalkBout] = [:]
        for source in activitySources {
            let days = (try? await source.dailyActivity(in: range)) ?? []
            for walk in days.flatMap(\.walks) where walk.start >= start && walk.start <= now {
                guard walk.durationSeconds.isFinite, walk.durationSeconds > 0 else { continue }
                walks[WalkKey(walk)] = walk
            }
        }
        return walks.values.sorted { ($0.start, $0.source.rawValue) < ($1.start, $1.source.rawValue) }
    }

    public var walkCompanionDetails: [WalkKey: HistoryWalkCompanion] {
        guard walkingRoutine.hasDog else { return [:] }
        let answers = CompanionWalkMatching.answers(for: walks, answers: companionAnswers.values)
        let suggestions = Set(DogWalkSuggestion.walksToAsk(
            walks: walks, answers: companionAnswers.values, now: clock(), calendar: calendar.calendar
        ).map(WalkKey.init))
        let question = DogWalkAnswers.question(for: walkingRoutine)
        return Dictionary(uniqueKeysWithValues: walkLines.map { row in
            let answer = answers[row.id].map { $0 ? L10n.text("Yes") : L10n.text("No") }
            return (row.id, HistoryWalkCompanion(
                question: question, answer: answer, showsSuggestion: suggestions.contains(row.id)
            ))
        })
    }

    public func answerWalk(_ id: WalkKey, withDog: Bool) {
        guard walkingRoutine.hasDog, let row = walkLines.first(where: { $0.id == id }) else { return }
        companionAnswers.answer(row.walk, among: walks, withDog: withDog)
    }

    public func runCompanion(for run: HistoryRunActivity) -> HistoryRunCompanion? {
        guard walkingRoutine.hasDog else { return nil }
        let answer = dogRunAnswers.answer(for: run.companionKey, linked: run.match)
        return HistoryRunCompanion(question: DogWalkAnswers.question(for: walkingRoutine), answer: answer.map {
            $0 ? L10n.text("Yes") : L10n.text("No")
        })
    }

    public func answerRun(_ run: HistoryRunActivity, withDog: Bool) {
        guard walkingRoutine.hasDog else { return }
        dogRunAnswers.record(withDog, for: run.companionKey, linked: run.match)
    }

    public func runDetail(for run: RunActivity) -> HistoryRunActivity {
        let id = "\(run.source.rawValue):\(run.id)"
        return runLines.first { $0.id == id } ?? HistoryRunActivity(run, sources: [run.source], format: format)
    }

    private func resolveRuns() {
        let result = RunDeduplication.resolve(runOriginals, choices: runChoices)
        runLines = result.runs
            .filter { runRange?.contains($0.activity.startedAt) == true }
            .map { HistoryRunActivity($0, format: format) }
        runReviews = result.candidates
            .filter {
                runRange?.contains($0.garmin.startedAt) == true || runRange?.contains($0.appleHealth.startedAt) == true
            }
            .map { HistoryRunReview($0, format: format) }
        rebuildTimeline()
    }

    public func chooseRunMatch(_ choice: RunMatchChoice?, for pair: RunMatchPair) {
        if choice == .linked {
            guard runReviews.contains(where: { $0.id == pair }) ||
                    calendar.runReviews.contains(where: { $0.id == pair }) else { return }
        }
        runChoices[pair] = choice
        saveRunChoices(runChoices)
        resolveRuns()
        calendar.updateRunChoices(runChoices)
    }

    public func delete(_ sessionID: UUID) async {
        do {
            try await workouts.deleteSession(id: sessionID)
            summaries.removeAll { $0.id == sessionID }
            calendar.didDelete(sessionID)
            strengthSessions.removeAll { $0.id == sessionID }
            strengthChoices = strengthChoices.filter { $0.key.sessionID != sessionID }
            saveStrengthChoices(strengthChoices)
            refreshStrength()
            await backup?.backUpIfConfigured(now: clock())
            await health?.removeWorkout(forSessionID: sessionID)
        } catch {
            errorMessage = L10n.text("Could not delete the session.")
        }
    }

    /// Creates a routine with the session's name, focus and exercises, unless an identical one exists.
    public func saveAsRoutine(sessionID: UUID) async {
        guard let session = session(id: sessionID) else { return }
        let routine = Routine(from: session)
        do {
            let existing = try await routines.allRoutines()
            if existing.contains(where: { $0.name == routine.name && $0.exerciseIDs == routine.exerciseIDs }) {
                routineNotice = L10n.format("“{1}” is already in your routines.", routine.name)
                return
            }
            try await routines.save(routine)
            routineNotice = L10n.format("Saved “{1}” to your routines.", routine.name)
            await backup?.backUpIfConfigured(now: clock())
        } catch {
            routineNotice = L10n.text("Could not save the routine.")
        }
    }

    public func clearRoutineNotice() { routineNotice = nil }

    /// Newest first, with filters and search applied after matching so a multi-source workout stays a single row.
    public var rows: [HistoryRow] {
        guard isFiltering else { return timeline }
        let matched = matchedExerciseIDs
        return timeline.filter { row in
            (activityFilter == .all || row.activityFilter == activityFilter)
                && (sourceFilter.map { row.sources.contains($0) } ?? true)
                && matchesSearch(row, exerciseIDs: matched)
        }
    }

    public var showsEmptyState: Bool { !isLoading && errorMessage == nil && runWarning == nil && timeline.isEmpty }

    public var showsFilteredEmptyState: Bool { !isLoading && isFiltering && !timeline.isEmpty && rows.isEmpty }

    public func clearFilters() {
        activityFilter = .all
        sourceFilter = nil
        searchText = ""
    }

    /// The most recent completed session with an exercise that matches the search, when one exists.
    public var lastTime: LastExerciseResult? {
        guard isSearching, activityFilter == .all || activityFilter == .strength else { return nil }
        let matched = matchedExerciseIDs
        guard !matched.isEmpty else { return nil }
        let now = clock()
        let newestFirst = strengthSessions.sorted { $0.startedAt > $1.startedAt }
        for session in newestFirst where session.isCompleted(through: now) {
            for entry in session.entries where matched.contains(entry.exerciseID) {
                let sets = entry.sets.filter { $0.isWorking && ($0.weightKg != nil || $0.reps != nil) }
                guard !sets.isEmpty else { continue }
                return LastExerciseResult(
                    sessionID: session.id, exerciseName: name(of: entry.exerciseID), date: session.startedAt,
                    sets: sets.map { Self.describe($0, format: format) }
                )
            }
        }
        return nil
    }

    private var matchedExerciseIDs: Set<UUID> {
        isSearching ? Set(SearchText.filter(catalog, by: searchText).map(\.id)) : []
    }

    private func matchesSearch(_ row: HistoryRow, exerciseIDs: Set<UUID>) -> Bool {
        guard isSearching else { return true }
        switch row {
        case let .session(summary):
            return SearchText.matches(searchText, [summary.title] + summary.exerciseNames)
                || summary.session.entries.contains { exerciseIDs.contains($0.exerciseID) }
        case let .recording(recording):
            return SearchText.matches(searchText, [L10n.text("Strength"), recording.source])
        case let .run(run):
            return SearchText.matches(searchText, [run.title, run.sourceText, L10n.text("Run")])
        case let .walk(walk):
            return SearchText.matches(searchText, [walk.title, walk.sourceText])
        }
    }

    /// Deletes the sessions at `offsets` of `summaries` (swipe to delete).
    public func delete(at offsets: IndexSet) async {
        let ids = offsets.map { summaries[$0].id }
        for id in ids { await delete(id) }
    }

    /// Detail of a listed session, with set descriptions and estimated 1RMs.
    public func detail(for sessionID: UUID, format: Format? = nil) -> SessionDetail? {
        let format = format ?? self.format
        guard let session = session(id: sessionID) else { return nil }
        let recording = strengthMatches.activity(for: sessionID)
        var detailsSummary = summary(session)
        detailsSummary.matchedSources = strengthMatches.sources(for: sessionID)
        return SessionDetail(
            id: session.id,
            name: session.name,
            startedAt: session.startedAt,
            durationSeconds: session.durationSeconds,
            focus: session.focus?.displayName,
            notes: session.notes,
            entries: session.entries.map { entry in
                SessionDetail.Entry(
                    id: entry.id,
                    name: name(of: entry.exerciseID),
                    sets: entry.sets.enumerated().map { index, set in
                        SessionDetail.SetLine(
                            id: set.id,
                            number: index + 1,
                            text: Self.describe(set, format: format),
                            estimatedOneRepMax: Self.estimatedOneRepMax(of: set).map {
                                "e1RM " + format.weight($0, maxFractionDigits: 1)
                            }
                        )
                    },
                    notes: entry.notes,
                    countsForProgression: entry.countsForProgression
                )
            },
            recording: recording.map {
                HistoryStrengthActivity($0, sources: strengthMatches.sources(for: $0), format: format)
            },
            sourceText: detailsSummary.sourceText,
            rotationLabels: detailsSummary.rotationLabels
        )
    }

    static func describe(_ set: WorkoutSet, format: Format) -> String {
        var parts: [String] = []
        if let weight = set.weightKg { parts.append(format.weight(weight)) }
        if let reps = set.reps { parts.append("× \(reps)") }
        if let rpe = set.rpe { parts.append("@ \(format.number(rpe))") }
        if set.kind != .working { parts.append("(\(set.kind.displayName.lowercased()))") }
        return parts.joined(separator: " ")
    }

    static func estimatedOneRepMax(of set: WorkoutSet) -> Double? {
        guard set.isWorking, let weight = set.weightKg, let reps = set.reps else { return nil }
        return LoadPrescription.estimatedOneRepMax(weightKg: weight, reps: reps, rpe: set.rpe)
    }

    /// The current version of a listed session.
    /// The report of an open session ("View summary"); set it to `nil` to close it.
    public var report: SessionReport?

    /// Opens the report of a listed session: how it went against the targets the engine gave it then.
    public func showReport(for sessionID: UUID, format: Format? = nil) async {
        let format = format ?? self.format
        guard let session = session(id: sessionID) else { return }
        let settings = (try? await progression?.allProgressionSettings()) ?? [:]
        let routine: Routine?
        if let routineID = session.routineID {
            routine = try? await routines.allRoutines().first { $0.id == routineID }
        } else {
            routine = nil
        }
        let review = SessionReviewer.review(
            session, history: summaries.map(\.session), exercises: catalog, settings: settings, routine: routine,
            weightUnit: format.weightUnit
        )
        report = SessionReport(review: review, effortScale: effortScale, format: format)
    }

    /// A session of the list or of the month shown in the calendar (which can go further back than the list).
    public func session(id: UUID) -> StrengthSession? {
        summaries.first { $0.id == id }?.session ?? calendar.sessions.first { $0.id == id }
    }

    /// An editor for a listed session, or `nil` if it is gone. Call `didSave(_:)` with what it returns.
    public func makeEditor(forSessionID sessionID: UUID) -> SessionEditorModel? {
        session(id: sessionID).map { makeEditor(for: $0) }
    }

    /// An editor for `session`. Call `didSave(_:)` with what it returns to refresh the list.
    public func makeEditor(for session: StrengthSession) -> SessionEditorModel {
        SessionEditorModel(
            session: session, catalog: catalog, workouts: workouts, backup: backup, health: health,
            showsRepsInReserve: effortScale == .repsInReserve, weightUnit: format.weightUnit, clock: clock
        )
    }

    /// A new session for a watch workout that was not logged: its times, no sets yet. Saving it pairs it with the
    /// recording, so it leaves the timeline as a watch-only row, and it is not written to Apple Health a second time
    /// (ADR-0023). Call `didSave(_:)` with what the editor returns.
    public func makeEditor(forRecording id: String) -> SessionEditorModel? {
        guard let recording = recordings.first(where: { $0.id == id }) else { return nil }
        return makeEditor(forRecording: StrengthRecordingID(recording))
    }

    public func makeEditor(forRecording recordingID: StrengthRecordingID) -> SessionEditorModel? {
        guard let recording = recordings.first(where: { StrengthRecordingID($0) == recordingID }) else { return nil }
        let session = StrengthSession(
            name: L10n.text("Strength"), startedAt: recording.startedAt, endedAt: recording.endedAt, source: .app
        )
        return makeEditor(for: session)
    }

    /// Replaces an edited session in the list, keeping it sorted newest first, and in the calendar.
    public func didSave(_ session: StrengthSession, fromRecording recordingID: StrengthRecordingID? = nil) {
        calendar.didSave(session)
        strengthSessions.removeAll { $0.id == session.id }
        strengthSessions.append(session)
        if let recordingID {
            let pair = StrengthMatchPair(sessionID: session.id, recordingID: recordingID)
            if !strengthChoices.contains(where: { $0.key.recordingID == recordingID && $0.value == .linked }) {
                strengthChoices[pair] = .linked
                saveStrengthChoices(strengthChoices)
            }
        }
        summaries.removeAll { $0.id == session.id }
        if session.startedAt >= clock().addingTimeInterval(-Self.window) {
            let position = summaries.firstIndex { $0.session.startedAt < session.startedAt } ?? summaries.endIndex
            summaries.insert(summary(session), at: position)
        }
        refreshStrength()
    }

    public func name(of exerciseID: UUID) -> String {
        exerciseNames[exerciseID] ?? L10n.text("Unknown exercise")
    }

    private func summary(_ session: StrengthSession) -> SessionSummary {
        var summary = SessionSummary(session: session, names: exerciseNames)
        summary.weightUnit = format.weightUnit
        if let outcomes = calendar.rotationOutcomes[session.id] {
            summary.rotationOutcomes = outcomes
        }
        return summary
    }

    private func rebuildTimeline() {
        let now = clock()
        let start = now.addingTimeInterval(-Self.window)
        let logged = summaries.map { summary in
            var row = summary
            row.matchedSources = strengthMatches.sources(for: summary.id)
            return HistoryRow.session(row)
        }
        let watchOnly = strengthMatches.unmatched
            .filter { $0.startedAt >= start && $0.startedAt <= now }
            .map {
                let recording = HistoryStrengthActivity($0, sources: strengthMatches.sources(for: $0), format: format)
                return HistoryRow.recording(recording)
            }
        let movement = runLines.map(HistoryRow.run) + walkLines.map(HistoryRow.walk)
        timeline = (logged + watchOnly + movement).sorted {
            if $0.date == $1.date { return $0.sortID < $1.sortID }
            return $0.date > $1.date
        }
    }

    private func resolveStrength() {
        let outcomes = SessionRotation.outcomes(
            for: strengthSessions, adjustments: rotationAdjustments, calendar: calendar.calendar
        )
        calendar.rotationOutcomes = outcomes
        for index in summaries.indices {
            summaries[index].weightUnit = format.weightUnit
            summaries[index].rotationOutcomes = outcomes[summaries[index].id] ?? []
        }
        let result = StrengthActivityMatching.resolve(
            sessions: strengthSessions, activities: recordings, choices: strengthChoices
        )
        strengthMatches = result.matches
        let reviews = result.candidates.map { HistoryStrengthReview($0, format: format) }
        let start = clock().addingTimeInterval(-Self.window)
        strengthReviews = reviews.filter { $0.sessionStart >= start || $0.recording.startedAt >= start }
        calendar.updateStrength(result.matches, reviews: reviews)
    }

    private func refreshStrength() {
        resolveStrength()
        rebuildTimeline()
    }

    public func chooseStrengthMatch(_ choice: StrengthMatchChoice?, for pair: StrengthMatchPair) {
        guard strengthReviews.contains(where: { $0.id == pair }) ||
                calendar.strengthReviews.contains(where: { $0.id == pair }) else { return }
        setStrengthChoice(choice, for: pair)
    }

    public func separateStrengthMatch(for sessionID: UUID) {
        guard let activity = strengthMatches.activity(for: sessionID) else { return }
        let pair = StrengthMatchPair(sessionID: sessionID, recordingID: StrengthRecordingID(activity))
        setStrengthChoice(.separate, for: pair)
    }

    private func setStrengthChoice(_ choice: StrengthMatchChoice?, for pair: StrengthMatchPair) {
        strengthChoices[pair] = choice
        saveStrengthChoices(strengthChoices)
        refreshStrength()
    }
}

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

    public var id: UUID { session.id }
    public var title: String { session.name }
    public var date: Date { session.startedAt }
    /// "Squat (Barbell), Leg Press"
    public var exerciseList: String { exerciseNames.joined(separator: ", ") }

    /// "12 sets · 3,450 kg"
    public func statsLine(format: Format = Format()) -> String {
        L10n.format("{1} sets · {2}", workingSets, format.kilograms(tonnageKg.rounded()))
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
}

/// Past strength sessions, newest first, plus the month calendar with runs and steps.
@MainActor
@Observable
public final class HistoryModel {
    public private(set) var summaries: [SessionSummary] = []
    public private(set) var exerciseNames: [UUID: String] = [:]
    public private(set) var catalog: [Exercise] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Result of saving a session as a routine, until the user dismisses it.
    public private(set) var routineNotice: String?

    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let routines: any RoutineRepository
    private let backup: (any BackupService)?
    private let health: (any HealthWorkoutWriter)?
    private let profiles: (any ProfileRepository)?
    private let progression: (any ProgressionSettingsRepository)?
    private let recordedStrength: (any RecordedStrengthSource)?
    private let format: Format
    private let clock: @Sendable () -> Date
    private var effortScale = EffortScale.rpe
    private var recordings: [RecordedStrengthActivity] = []

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
        activity: (any ActivitySource)? = nil,
        runSources: [any MetricsSource] = [],
        recordedStrength: (any RecordedStrengthSource)? = nil,
        calendar: Calendar = .current,
        format: Format = Format(),
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
        self.format = format
        self.clock = clock
        self.calendar = HistoryCalendarModel(
            workouts: workouts, activity: activity, runSources: runSources,
            calendar: calendar, format: format, clock: clock
        )
    }

    /// The month calendar: strength days, runs and steps (a sub-screen of History).
    public let calendar: HistoryCalendarModel

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await exercises.allExercises()
            exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            calendar.exerciseNames = exerciseNames
            let now = clock()
            let sessions = try await workouts.sessions(from: now.addingTimeInterval(-Self.window), to: now)
            summaries = sessions.reversed().map(summary)
            errorMessage = nil
            if let profile = try? await profiles?.profile() {
                effortScale = profile.effortScale
            }
            if let recordedStrength {
                recordings = await recordedStrength.strengthActivities(from: .distantPast, to: now)
            }
        } catch {
            errorMessage = L10n.text("Could not load your history.")
        }
    }

    public func delete(_ sessionID: UUID) async {
        do {
            try await workouts.deleteSession(id: sessionID)
            summaries.removeAll { $0.id == sessionID }
            calendar.didDelete(sessionID)
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

    /// Newest first, with watch workouts shown only when they have no matching logged session.
    public var rows: [HistoryRow] {
        let logged = summaries.map(HistoryRow.session)
        guard !recordings.isEmpty else { return logged }
        let start = clock().addingTimeInterval(-Self.window)
        let watchOnly = strengthMatches.unmatched
            .filter { $0.startedAt >= start }
            .map { HistoryRow.recording(HistoryStrengthActivity($0, format: format)) }
        return (logged + watchOnly).sorted { $0.date > $1.date }
    }

    /// "No sessions yet" is shown only when loading finished without rows or errors.
    public var showsEmptyState: Bool { !isLoading && errorMessage == nil && summaries.isEmpty && rows.isEmpty }

    /// Deletes the sessions at `offsets` of `summaries` (swipe to delete).
    public func delete(at offsets: IndexSet) async {
        let ids = offsets.map { summaries[$0].id }
        for id in ids { await delete(id) }
    }

    /// Detail of a listed session, with set descriptions and estimated 1RMs.
    public func detail(for sessionID: UUID, format: Format = Format()) -> SessionDetail? {
        guard let session = session(id: sessionID) else { return nil }
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
                                "e1RM " + format.fixed($0, digits: 1)
                            }
                        )
                    },
                    notes: entry.notes,
                    countsForProgression: entry.countsForProgression
                )
            },
            recording: strengthMatches.activity(for: sessionID).map { HistoryStrengthActivity($0, format: format) }
        )
    }

    static func describe(_ set: WorkoutSet, format: Format) -> String {
        var parts: [String] = []
        if let weight = set.weightKg { parts.append(format.kilograms(weight)) }
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
    public func showReport(for sessionID: UUID, format: Format = Format()) async {
        guard let session = session(id: sessionID) else { return }
        let settings = (try? await progression?.allProgressionSettings()) ?? [:]
        let review = SessionReviewer.review(
            session, history: summaries.map(\.session), exercises: catalog, settings: settings
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
            showsRepsInReserve: effortScale == .repsInReserve, clock: clock
        )
    }

    /// Replaces an edited session in the list, keeping it sorted newest first, and in the calendar.
    public func didSave(_ session: StrengthSession) {
        calendar.didSave(session)
        summaries.removeAll { $0.id == session.id }
        guard session.startedAt >= clock().addingTimeInterval(-Self.window) else { return }
        let position = summaries.firstIndex { $0.session.startedAt < session.startedAt } ?? summaries.endIndex
        summaries.insert(summary(session), at: position)
    }

    public func name(of exerciseID: UUID) -> String {
        exerciseNames[exerciseID] ?? L10n.text("Unknown exercise")
    }

    private func summary(_ session: StrengthSession) -> SessionSummary {
        SessionSummary(session: session, names: exerciseNames)
    }

    private var strengthMatches: StrengthActivityMatches {
        guard !recordings.isEmpty else { return StrengthActivityMatches() }
        // A session may appear in both the list and the selected month, or only in an older month.
        let sessions = Dictionary(
            (summaries.map(\.session) + calendar.sessions).map { ($0.id, $0) },
            uniquingKeysWith: { listed, _ in listed }
        )
        return StrengthActivityMatching.match(sessions: Array(sessions.values), activities: recordings)
    }
}

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
    /// "Watch: 112 bpm avg · Garmin load 48" when a watch recorded the same workout.
    public var watchLine: String?

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
    /// What the watch measured during this session (heart rate, load, training effect), one line each. Empty when no
    /// watch recorded it.
    public var watchLines: [String] = []
}

/// A strength workout a watch recorded with no session logged in the app. The person can log it: the new session
/// starts with the watch's times and no sets.
public struct UnloggedWorkout: Identifiable, Hashable, Sendable {
    public let id: String
    /// "Strength on Garmin"
    public let title: String
    /// "Tue 18 Nov, 18:02 · 54 min · 112 bpm"
    public let detail: String
}

/// Past strength sessions, newest first, plus the month calendar with runs and steps from Apple Health.
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
    /// Watch workouts of the last `unloggedWindow` with no logged session, newest first.
    public private(set) var unlogged: [UnloggedWorkout] = []

    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let routines: any RoutineRepository
    private let backup: (any BackupService)?
    private let health: (any HealthWorkoutWriter)?
    private let profiles: (any ProfileRepository)?
    private let progression: (any ProgressionSettingsRepository)?
    private let recordingSources: [any StrengthRecordingSource]
    private let clock: @Sendable () -> Date
    private let format: Format
    private var effortScale = EffortScale.rpe
    /// Watch recordings in the list's window, one per workout.
    private var recordings: [RecordedStrengthActivity] = []
    /// The watch recording of each logged session that has one.
    private var watchBySession: [UUID: RecordedStrengthActivity] = [:]

    /// How far back watch workouts without a session are offered for logging.
    static let unloggedWindow: TimeInterval = 30 * 86_400

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
        runs: (any MetricsSource)? = nil,
        recordings: [any StrengthRecordingSource] = [],
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
        self.recordingSources = recordings
        self.format = format
        self.clock = clock
        self.calendar = HistoryCalendarModel(
            workouts: workouts, activity: activity, runs: runs, calendar: calendar, format: format, clock: clock
        )
    }

    /// The month calendar: strength days, runs and steps (a sub-screen of History).
    public let calendar: HistoryCalendarModel

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await exercises.allExercises()
            exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            calendar.exerciseNames = exerciseNames
            let now = clock()
            let sessions = try await workouts.sessions(from: now.addingTimeInterval(-Self.window), to: now)
            var found: [RecordedStrengthActivity] = []
            for source in recordingSources {
                found += await source.strengthRecordings(from: now.addingTimeInterval(-Self.window), to: now)
            }
            recordings = StrengthActivityMatching.removingDuplicates(found)
            matchRecordings(to: sessions)
            summaries = sessions.reversed().map(summary)
            errorMessage = nil
            if let profile = try? await profiles?.profile() {
                effortScale = profile.effortScale
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
            matchRecordings(to: summaries.map(\.session))  // its watch workout is unlogged again
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

    /// "No sessions yet" is shown only when loading finished without sessions or errors.
    public var showsEmptyState: Bool { summaries.isEmpty && !isLoading && errorMessage == nil }

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
            watchLines: watchBySession[session.id].map { Self.watchLines($0, format: format) } ?? []
        )
    }

    // MARK: Watch workouts

    /// A new session for a watch workout that was not logged: its times, no sets yet. Saving it pairs it with the
    /// recording (so it leaves the list) and does not write a second workout to Apple Health (ADR-0023).
    public func makeEditor(forUnlogged id: String) -> SessionEditorModel? {
        guard let recording = recordings.first(where: { $0.id == id }) else { return nil }
        let session = StrengthSession(
            name: L10n.text("Strength"), startedAt: recording.startedAt, endedAt: recording.endedAt, source: .app
        )
        return makeEditor(for: session)
    }

    private func matchRecordings(to sessions: [StrengthSession]) {
        let matches = StrengthActivityMatching.match(sessions: sessions, activities: recordings)
        watchBySession = matches.bySession
        let since = clock().addingTimeInterval(-Self.unloggedWindow)
        unlogged = matches.unmatched.filter { $0.startedAt >= since }.reversed().map { unloggedWorkout($0) }
    }

    private func unloggedWorkout(_ recording: RecordedStrengthActivity) -> UnloggedWorkout {
        var parts = [
            recording.startedAt.formatted(date: .abbreviated, time: .shortened),
            L10n.format("{1} min", Int((recording.durationSeconds / 60).rounded())),
        ]
        if let heartRate = recording.averageHeartRate {
            parts.append(L10n.format("{1} bpm", format.number(heartRate, maxFractionDigits: 0)))
        }
        return UnloggedWorkout(
            id: recording.id,
            title: L10n.format("Strength on {1}", recording.source.displayName),
            detail: parts.joined(separator: " · ")
        )
    }

    static func watchLine(_ recording: RecordedStrengthActivity, format: Format) -> String? {
        var parts: [String] = []
        if let heartRate = recording.averageHeartRate {
            parts.append(L10n.format("Watch: {1} bpm avg", format.number(heartRate, maxFractionDigits: 0)))
        }
        if let load = recording.trainingLoad {
            parts.append(L10n.format("Garmin load {1}", format.number(load, maxFractionDigits: 0)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func watchLines(_ recording: RecordedStrengthActivity, format: Format) -> [String] {
        var lines: [String] = []
        if let heartRate = recording.averageHeartRate {
            lines.append(L10n.format("Average heart rate: {1} bpm", format.number(heartRate, maxFractionDigits: 0)))
        }
        if let heartRate = recording.maxHeartRate {
            lines.append(L10n.format("Max heart rate: {1} bpm", format.number(heartRate, maxFractionDigits: 0)))
        }
        if let load = recording.trainingLoad {
            lines.append(L10n.format("Garmin training load: {1}", format.number(load, maxFractionDigits: 0)))
        }
        if let aerobic = recording.aerobicTrainingEffect, let anaerobic = recording.anaerobicTrainingEffect {
            lines.append(L10n.format(
                "Training effect: aerobic {1}, anaerobic {2}",
                format.fixed(aerobic, digits: 1), format.fixed(anaerobic, digits: 1)
            ))
        }
        if !lines.isEmpty {
            lines.append(L10n.format("Recorded by {1}", recording.source.displayName))
        }
        return lines
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
        if session.startedAt >= clock().addingTimeInterval(-Self.window) {
            let position = summaries.firstIndex { $0.session.startedAt < session.startedAt } ?? summaries.endIndex
            summaries.insert(summary(session), at: position)
        }
        // A new or moved session may now pair with a watch workout.
        matchRecordings(to: summaries.map(\.session))
        summaries = summaries.map { summary($0.session) }
    }

    public func name(of exerciseID: UUID) -> String {
        exerciseNames[exerciseID] ?? L10n.text("Unknown exercise")
    }

    private func summary(_ session: StrengthSession) -> SessionSummary {
        var summary = SessionSummary(session: session, names: exerciseNames)
        summary.watchLine = watchBySession[session.id].flatMap { Self.watchLine($0, format: format) }
        return summary
    }
}

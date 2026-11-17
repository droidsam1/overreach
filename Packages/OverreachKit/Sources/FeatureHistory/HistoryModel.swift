import Analytics
import Domain
import Foundation
import Observation

/// One past session as shown in the list.
public struct SessionSummary: Identifiable, Hashable, Sendable {
    public let session: StrengthSession
    public let exerciseNames: [String]
    public let workingSets: Int
    public let tonnageKg: Double

    public var id: UUID { session.id }
}

/// Past strength sessions, newest first (phase 1). Runs join in phase 2.
@MainActor
@Observable
public final class HistoryModel {
    public private(set) var summaries: [SessionSummary] = []
    public private(set) var exerciseNames: [UUID: String] = [:]
    public private(set) var catalog: [Exercise] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date

    /// How far back the list goes.
    static let window: TimeInterval = 365 * 86_400

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        backup: (any BackupService)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.backup = backup
        self.clock = clock
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await exercises.allExercises()
            exerciseNames = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let now = clock()
            let sessions = try await workouts.sessions(from: now.addingTimeInterval(-Self.window), to: now)
            summaries = sessions.reversed().map(summary)
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your history."
        }
    }

    public func delete(_ sessionID: UUID) async {
        do {
            try await workouts.deleteSession(id: sessionID)
            summaries.removeAll { $0.id == sessionID }
            await backup?.backUpIfConfigured(now: clock())
        } catch {
            errorMessage = "Could not delete the session."
        }
    }

    /// The current version of a listed session.
    public func session(id: UUID) -> StrengthSession? {
        summaries.first { $0.id == id }?.session
    }

    /// An editor for `session`. Call `didSave(_:)` with what it returns to refresh the list.
    public func makeEditor(for session: StrengthSession) -> SessionEditorModel {
        SessionEditorModel(session: session, catalog: catalog, workouts: workouts, backup: backup, clock: clock)
    }

    /// Replaces an edited session in the list, keeping it sorted newest first.
    public func didSave(_ session: StrengthSession) {
        summaries.removeAll { $0.id == session.id }
        let position = summaries.firstIndex { $0.session.startedAt < session.startedAt } ?? summaries.endIndex
        summaries.insert(summary(session), at: position)
    }

    public func name(of exerciseID: UUID) -> String {
        exerciseNames[exerciseID] ?? "Unknown exercise"
    }

    private func summary(_ session: StrengthSession) -> SessionSummary {
        let sets = session.entries.flatMap(\.sets)
        return SessionSummary(
            session: session,
            exerciseNames: session.entries.map { name(of: $0.exerciseID) },
            workingSets: sets.filter(\.isWorking).count,
            tonnageKg: StrengthMetrics.tonnage(of: sets)
        )
    }
}

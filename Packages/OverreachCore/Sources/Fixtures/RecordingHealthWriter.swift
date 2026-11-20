import Domain
import Foundation

/// Records what would reach the health app. `failing` makes every call throw; `otherWorkouts` are strength workouts
/// another app (e.g. Garmin Connect) wrote there.
public actor RecordingHealthWriter: HealthWorkoutWriter {
    public private(set) var saved: [StrengthSession] = []
    public private(set) var deleted: [UUID] = []
    private let failing: Bool
    private var otherWorkouts: [RecordedStrengthActivity]

    public struct WriteFailed: Error {}

    public init(failing: Bool = false, otherWorkouts: [RecordedStrengthActivity] = []) {
        self.failing = failing
        self.otherWorkouts = otherWorkouts
    }

    /// Another app writes a workout later (e.g. the watch syncs after the session was saved).
    public func addOtherWorkout(_ workout: RecordedStrengthActivity) {
        otherWorkouts.append(workout)
    }

    public func strengthWorkoutsFromOtherSources(from start: Date, to end: Date) throws -> [RecordedStrengthActivity] {
        if failing { throw WriteFailed() }
        return otherWorkouts.filter { $0.endedAt >= start && $0.startedAt <= end }
    }

    public func saveWorkout(for session: StrengthSession) throws {
        if failing { throw WriteFailed() }
        saved.append(session)
    }

    public func deleteWorkout(forSessionID sessionID: UUID) throws {
        if failing { throw WriteFailed() }
        deleted.append(sessionID)
    }
}

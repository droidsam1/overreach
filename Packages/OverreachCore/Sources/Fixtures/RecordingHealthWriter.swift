import Domain
import Foundation

/// Records what would reach the health app. `failing` makes every call throw.
public actor RecordingHealthWriter: HealthWorkoutWriter {
    public private(set) var saved: [StrengthSession] = []
    public private(set) var deleted: [UUID] = []
    private let failing: Bool

    public struct WriteFailed: Error {}

    public init(failing: Bool = false) {
        self.failing = failing
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

import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("WorkoutModel and Apple Health")
struct WorkoutHealthTests {
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func finishedSession(
        health: RecordingHealthWriter, store: TestStore, completeASet: Bool = true
    ) async -> Bool {
        let times = Clock()
        let model = WorkoutModel(
            workouts: store, exercises: store, progression: store, health: health, clock: { times.next() }
        )
        model.start(name: "Push")
        await model.add(bench)
        model.exercises[0].sets[0].isDone = completeASet
        return await model.finish()
    }

    @Test func aFinishedSessionIsWritten() async throws {
        let health = RecordingHealthWriter()
        let store = TestStore(exercises: [bench])

        #expect(await finishedSession(health: health, store: store))

        let stored = try await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(stored.count == 1)
        #expect(await health.saved == stored)
    }

    @Test func aSessionWithoutCompletedSetsIsNotWritten() async {
        let health = RecordingHealthWriter()

        #expect(await finishedSession(health: health, store: TestStore(exercises: [bench]), completeASet: false))

        #expect(await health.saved.isEmpty)
    }

    @Test func aHealthFailureKeepsTheSession() async throws {
        let store = TestStore(exercises: [bench])

        #expect(await finishedSession(health: RecordingHealthWriter(failing: true), store: store))

        #expect(try await store.sessions(from: .distantPast, to: .distantFuture).count == 1)
    }
}

/// Moves forward a minute per reading, so a session has a duration.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        current.addTimeInterval(60)
        return current
    }
}

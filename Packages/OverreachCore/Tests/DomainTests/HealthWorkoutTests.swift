import Domain
import Fixtures
import Foundation
import Testing

@Suite("Sessions in Apple Health")
struct HealthWorkoutTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func onlyTimedSessionsLoggedInTheAppBelongThere() {
        let end = start.addingTimeInterval(3_600)
        #expect(StrengthSession(name: "A", startedAt: start, endedAt: end).belongsInHealth)
        #expect(!StrengthSession(name: "A", startedAt: start).belongsInHealth)
        #expect(!StrengthSession(name: "A", startedAt: start, endedAt: start).belongsInHealth)
        #expect(!StrengthSession(name: "A", startedAt: start, endedAt: end, source: .strongImport).belongsInHealth)
    }
}

@Suite("Sessions recorded by another app are not written twice")
struct HealthWorkoutDuplicateTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(minutes: Double = 60) -> StrengthSession {
        StrengthSession(name: "Upper", startedAt: start, endedAt: start.addingTimeInterval(minutes * 60))
    }

    private func garmin(offsetMinutes: Double = -3, minutes: Double = 68) -> RecordedStrengthActivity {
        RecordedStrengthActivity(
            id: "garmin-1", source: .appleHealth, startedAt: start.addingTimeInterval(offsetMinutes * 60),
            durationSeconds: minutes * 60
        )
    }

    @Test func aSessionNobodyElseRecordedIsWritten() async {
        let health = RecordingHealthWriter()
        let logged = session()

        await health.sync(logged)

        #expect(await health.saved.map(\.id) == [logged.id])
    }

    @Test func aSessionTheWatchAlreadyWroteIsNotWrittenAgain() async {
        let health = RecordingHealthWriter(otherWorkouts: [garmin()])
        let logged = session()

        await health.sync(logged)

        #expect(await health.saved.isEmpty)
        #expect(await health.deleted == [logged.id])  // and any earlier copy of ours goes
    }

    @Test func aWorkoutAtAnotherTimeDoesNotStopTheWrite() async {
        let health = RecordingHealthWriter(otherWorkouts: [garmin(offsetMinutes: 300)])
        let logged = session()

        await health.sync(logged)

        #expect(await health.saved.map(\.id) == [logged.id])
    }

    @Test func reconcilingRemovesOurCopyOnceTheWatchSyncsLater() async {
        let health = RecordingHealthWriter()
        let matched = session()
        let other = StrengthSession(
            name: "Legs", startedAt: start.addingTimeInterval(86_400), endedAt: start.addingTimeInterval(90_000)
        )
        await health.sync(matched)
        await health.sync(other)
        await health.addOtherWorkout(garmin())

        await health.reconcile([matched, other])

        #expect(await health.deleted == [matched.id])
    }

    @Test func reconcilingIgnoresSessionsThatDoNotBelongInHealth() async {
        let health = RecordingHealthWriter(otherWorkouts: [garmin()])
        var imported = session()
        imported.source = .strongImport

        await health.reconcile([imported])

        #expect(await health.deleted.isEmpty)
    }

    @Test func whenOtherWorkoutsCannotBeReadTheSessionIsStillWritten() async {
        let health = NoReadHealthWriter()
        let logged = session()

        await health.sync(logged)

        #expect(await health.saved == [logged.id])
    }
}

/// A writer that cannot read other apps' workouts (uses the protocol's default).
private actor NoReadHealthWriter: HealthWorkoutWriter {
    private(set) var saved: [UUID] = []

    func saveWorkout(for session: StrengthSession) {
        saved.append(session.id)
    }

    func deleteWorkout(forSessionID sessionID: UUID) {}
}

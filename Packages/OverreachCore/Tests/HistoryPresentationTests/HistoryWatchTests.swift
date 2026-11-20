import Domain
import Fixtures
import Foundation
import HistoryPresentation
import Testing

private struct Recordings: StrengthRecordingSource {
    let items: [RecordedStrengthActivity]
    func strengthRecordings(from start: Date, to end: Date) async -> [RecordedStrengthActivity] {
        items.filter { $0.startedAt >= start && $0.startedAt <= end }
    }
}

@MainActor
@Suite("History with watch workouts")
struct HistoryWatchTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)

    private func session(daysAgo: Double, minutes: Double = 60) -> StrengthSession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return StrengthSession(
            name: "Legs", startedAt: start, endedAt: start.addingTimeInterval(minutes * 60),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 100, reps: 5)])]
        )
    }

    private func garmin(_ id: String, daysAgo: Double, minutes: Double = 62) -> RecordedStrengthActivity {
        RecordedStrengthActivity(
            id: id, source: .garmin, startedAt: now.addingTimeInterval(-daysAgo * 86_400 - 120),
            durationSeconds: minutes * 60, averageHeartRate: 112, maxHeartRate: 148, trainingLoad: 48,
            aerobicTrainingEffect: 2.1, anaerobicTrainingEffect: 1.8, totalSets: 15, totalReps: 70
        )
    }

    private func model(
        sessions: [StrengthSession], recordings: [RecordedStrengthActivity], health: RecordingHealthWriter? = nil
    ) -> (HistoryModel, TestStore) {
        let store = TestStore(exercises: [squat], sessions: sessions)
        let model = HistoryModel(
            workouts: store, exercises: store, routines: store, health: health,
            recordings: [Recordings(items: recordings)], clock: { now }
        )
        return (model, store)
    }

    @Test func aMatchedSessionShowsTheWatchsHeartRateAndLoad() async throws {
        let logged = session(daysAgo: 2)
        let (history, _) = model(sessions: [logged], recordings: [garmin("g1", daysAgo: 2)])
        await history.load()

        #expect(history.summaries.first?.watchLine == "Watch: 112 bpm avg · Garmin load 48")
        let detail = try #require(history.detail(for: logged.id))
        #expect(detail.watchLines == [
            "Average heart rate: 112 bpm", "Max heart rate: 148 bpm", "Garmin training load: 48",
            "Training effect: aerobic 2.1, anaerobic 1.8", "Recorded by Garmin",
        ])
        #expect(history.unlogged.isEmpty)  // the watch workout is this session, not a second one
    }

    @Test func aSessionWithoutAWatchHasNoWatchLines() async throws {
        let logged = session(daysAgo: 2)
        let (history, _) = model(sessions: [logged], recordings: [])
        await history.load()

        #expect(history.summaries.first?.watchLine == nil)
        #expect(try #require(history.detail(for: logged.id)).watchLines.isEmpty)
    }

    @Test func aWatchWorkoutWithoutASessionIsOfferedForLogging() async throws {
        let (history, store) = model(sessions: [], recordings: [garmin("g1", daysAgo: 1), garmin("old", daysAgo: 60)])
        await history.load()

        #expect(history.unlogged.map(\.id) == ["g1"])  // older than 30 days is not offered
        let row = try #require(history.unlogged.first)
        #expect(row.title == "Strength on Garmin")
        #expect(row.detail.hasSuffix("62 min · 112 bpm"))

        let editor = try #require(history.makeEditor(forUnlogged: "g1"))
        editor.addExercise(squat)
        editor.draft.entries[0].sets[0].weightKg = 100
        editor.draft.entries[0].sets[0].reps = 5
        let saved = try #require(await editor.save())
        history.didSave(saved)

        #expect(saved.startedAt == now.addingTimeInterval(-86_400 - 120))  // the watch's times
        #expect(saved.durationSeconds == 62 * 60)
        #expect(await store.sessions(from: .distantPast, to: .distantFuture).count == 1)
        #expect(history.unlogged.isEmpty)
        #expect(history.summaries.first?.watchLine != nil)
    }

    @Test func deletingASessionOffersItsWatchWorkoutAgain() async {
        let logged = session(daysAgo: 3)
        let (history, _) = model(sessions: [logged], recordings: [garmin("g1", daysAgo: 3)])
        await history.load()
        #expect(history.unlogged.isEmpty)

        await history.delete(logged.id)

        #expect(history.unlogged.map(\.id) == ["g1"])
    }

    @Test func garminAndItsHealthCopyAreOfferedOnce() async {
        let copy = RecordedStrengthActivity(
            id: "h1", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 61 * 60
        )
        let (history, _) = model(sessions: [], recordings: [garmin("g1", daysAgo: 1), copy])
        await history.load()

        #expect(history.unlogged.map(\.id) == ["g1"])
    }
}

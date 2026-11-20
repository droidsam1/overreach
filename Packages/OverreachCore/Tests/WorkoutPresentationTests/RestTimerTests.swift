import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

actor RecordingAlerts: RestAlertScheduler {
    enum Event: Equatable {
        case scheduled(Date, String, String)
        case cancelled
    }

    private(set) var events: [Event] = []

    func scheduleRestEnd(at date: Date, title: String, body: String) {
        events.append(.scheduled(date, title, body))
    }

    func cancelRestEnd() { events.append(.cancelled) }
}

@MainActor
@Suite("Rest timer")
struct RestTimerTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func makeModel(focus: TrainingFocus? = .strength) async -> (WorkoutModel, RecordingAlerts) {
        let store = TestStore(exercises: [bench])
        let alerts = RecordingAlerts()
        let fixedNow = now
        let model = WorkoutModel(
            workouts: store, exercises: store, progression: store, restAlerts: alerts, clock: { fixedNow }
        )
        model.start()
        await model.setSessionFocus(focus)
        await model.add(bench)
        return (model, alerts)
    }

    private func completeFirstSet(_ model: WorkoutModel) {
        model.setDone(true, set: model.exercises[0].sets[0].id, in: model.exercises[0].id)
    }

    @Test func aCompletedSetStartsTheSuggestedRest() async throws {
        let (model, alerts) = await makeModel()
        #expect(!model.rest.isActive)

        completeFirstSet(model)

        #expect(model.exercises[0].sets[0].isDone)
        let start = try #require(model.rest.state(at: now))
        #expect(start.remaining == "3:00")
        #expect(start.progress == 0)
        #expect(start.title == "Rest" && start.dismissTitle == "Skip")
        #expect(start.exerciseName == "Bench Press")
        #expect(start.suggestion == "Suggested 3:00–5:00 · moderate evidence (rest-strength)")

        await model.rest.alertsSettled()
        #expect(await alerts.events == [
            .scheduled(now.addingTimeInterval(180), "Rest over", "Next set: Bench Press"),
        ])
    }

    @Test func hypertrophyIsTheFallbackWithoutAFocus() async throws {
        let (model, _) = await makeModel(focus: nil)
        completeFirstSet(model)
        let state = try #require(model.rest.state(at: now))
        #expect(state.remaining == "1:30")
        #expect(state.suggestion.hasSuffix("(rest-hypertrophy)"))
    }

    @Test func countsDownFromTheEndTime() async throws {
        let (model, _) = await makeModel()
        completeFirstSet(model)

        let running = try #require(model.rest.state(at: now.addingTimeInterval(59.5)))
        #expect(running.remaining == "2:01")
        let finished = try #require(model.rest.state(at: now.addingTimeInterval(200)))
        #expect(finished.remaining == "0:00")
        #expect(finished.isFinished && finished.progress == 1)
        #expect(finished.title == "Rest over" && finished.dismissTitle == "Dismiss")
    }

    @Test func adjustingMovesTheEndAndTheAlert() async throws {
        let (model, alerts) = await makeModel()
        completeFirstSet(model)

        model.rest.addTime()
        #expect(model.rest.state(at: now)?.remaining == "3:15")
        #expect(model.rest.state(at: now)?.progress == 0)
        model.rest.removeTime()
        model.rest.removeTime()
        #expect(model.rest.state(at: now)?.remaining == "2:45")

        await model.rest.alertsSettled()
        let last = await alerts.events.last
        #expect(last == .scheduled(now.addingTimeInterval(165), "Rest over", "Next set: Bench Press"))
    }

    @Test func removingAllTheTimeEndsTheRest() async {
        let (model, alerts) = await makeModel(focus: .endurance)
        completeFirstSet(model)  // 30 s
        model.rest.removeTime()
        #expect(model.rest.isActive)
        model.rest.removeTime()
        #expect(!model.rest.isActive)
        await model.rest.alertsSettled()
        #expect(await alerts.events.last == .cancelled)
    }

    @Test func skippingCancelsTheAlert() async {
        let (model, alerts) = await makeModel()
        completeFirstSet(model)
        model.rest.skip()
        #expect(model.rest.state(at: now) == nil)
        await model.rest.alertsSettled()
        #expect(await alerts.events.last == .cancelled)
    }

    @Test func undoingTheSetStopsItsRest() async {
        let (model, _) = await makeModel()
        let exercise = model.exercises[0]
        completeFirstSet(model)
        model.setDone(false, set: exercise.sets[1].id, in: exercise.id)  // already pending: nothing changes
        #expect(model.rest.isActive)
        model.setDone(false, set: exercise.sets[0].id, in: exercise.id)
        #expect(!model.rest.isActive)
        #expect(!model.exercises[0].sets[0].isDone)
    }

    @Test func removingTheExerciseOrClosingTheSessionStopsTheRest() async {
        let (model, _) = await makeModel()
        completeFirstSet(model)
        model.removeExercise(model.exercises[0].id)
        #expect(!model.rest.isActive)

        await model.add(bench)
        completeFirstSet(model)
        model.discard()
        #expect(!model.rest.isActive)
    }
}

import AIExchange
import AssistantPresentation
import Domain
import Fixtures
import Foundation
import Testing

@MainActor
@Suite("Ask AI screen")
struct AskAIModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func session(daysAgo: Double) -> StrengthSession {
        StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [WorkoutSet(weightKg: 60, reps: 10, rpe: 8)])]
        )
    }

    private func makeModel(failing: Bool = false) -> AskAIModel {
        let store = TestStore(exercises: [bench], sessions: [session(daysAgo: 3), session(daysAgo: 100)])
        let fixedNow = now
        let directory = failing
            ? URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
            : FileManager.default.temporaryDirectory
        return AskAIModel(
            workouts: store, exercises: store, progression: store, profiles: store, routines: store,
            clock: { fixedNow }, directory: directory
        )
    }

    @Test func preparesTheContextOfThePeriod() async throws {
        let model = makeModel()
        await model.prepare()

        let message = try #require(model.message)
        #expect(message.hasPrefix("Overreach training context (overreach.context v1)"))
        #expect(model.summary?.hasPrefix("1 sessions · 1 exercises · ") == true)
        #expect(model.errorMessage == nil)

        let url = try #require(model.fileURL)
        let pack = try ContextMessage.decode(Data(contentsOf: url))
        #expect(pack.sessions.count == 1)
        #expect(pack.exerciseTrends.first?.exercise == "Bench Press")
    }

    @Test func aLongerPeriodIncludesOlderSessions() async {
        let model = makeModel()
        await model.prepare()
        await model.setPeriod(.sixMonths)

        #expect(model.period == .sixMonths)
        #expect(model.summary?.hasPrefix("2 sessions") == true)
    }

    @Test func theFirstRequestGoesAfterTheDataAndCanBeRemoved() async throws {
        let model = makeModel()
        await model.prepare()

        model.setRequest(.nextBlock)
        #expect(try #require(model.message).hasSuffix("```\n\nHelp me plan my next training block."))

        model.setRequest(nil)
        #expect(try #require(model.message).hasSuffix("```"))
    }

    @Test func aFailureIsExplainedAndNothingIsOffered() async {
        let model = makeModel(failing: true)
        await model.prepare()

        #expect(model.message == nil)
        #expect(model.fileURL == nil)
        #expect(model.errorMessage == "Could not prepare your data. Try again.")
    }

    @Test func optionsAreNamed() {
        let model = makeModel()
        #expect(model.periodOptions.map(\.value) == ContextPeriod.allCases)
        #expect(model.periodOptions.allSatisfy { !$0.name.isEmpty })
        #expect(model.requestOptions.count == StarterRequest.allCases.count)
    }
}

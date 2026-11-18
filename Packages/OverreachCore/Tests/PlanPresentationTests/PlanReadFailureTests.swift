import Domain
import Fixtures
import Foundation
import PlanPresentation
import Testing

private struct ReadFailed: Error {}

private struct UnreadableSettings: ProgressionSettingsRepository {
    func progressionSettings(for exerciseID: UUID) async throws -> ProgressionSettings? { throw ReadFailed() }
    func save(_ settings: ProgressionSettings, for exerciseID: UUID) async throws {}
    func deleteProgressionSettings(for exerciseID: UUID) async throws {}
    func allProgressionSettings() async throws -> [UUID: ProgressionSettings] { throw ReadFailed() }
}

@MainActor
@Suite("PlanModel read failures")
struct PlanReadFailureTests {
    @Test func warnsWhenTheAnalysisLacksExerciseSettings() async {
        let store = TestStore()
        let model = PlanModel(profiles: store, workouts: store, exercises: store, progression: UnreadableSettings())

        await model.load()

        #expect(model.errorMessage == "Some exercise settings could not be read, so this analysis may be incomplete.")
    }
}

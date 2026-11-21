import Domain
import Fixtures
import Foundation
import SettingsPresentation
import Testing

@MainActor
@Suite("Training preferences")
struct TrainingPreferencesModelTests {
    @Test func breaksCountAutomaticallyUntilTurnedOffAndTheChoiceIsSaved() async throws {
        let store = TestStore()
        try await store.save(AthleteProfile(goal: TrainingGoal(kind: .hybrid)))
        let model = TrainingPreferencesModel(profiles: store)

        await model.load()
        #expect(model.countsBreaksAutomatically)

        await model.setCountsBreaksAutomatically(false)
        #expect(!model.countsBreaksAutomatically)
        #expect(try await store.profile().countsBreaksAutomatically == false)
        #expect(try await store.profile().goal?.kind == .hybrid)
    }

    @Test func aProfileSavedBeforeTheSettingCountsBreaksAutomatically() throws {
        let profile = try JSONDecoder().decode(AthleteProfile.self, from: Data(#"{"effortScale":"rpe"}"#.utf8))
        #expect(profile.countsBreaksAutomatically)
    }
}

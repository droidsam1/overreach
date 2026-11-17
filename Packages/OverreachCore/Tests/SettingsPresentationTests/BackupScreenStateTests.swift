import Domain
import Fixtures
import Foundation
import SettingsPresentation
import Testing

/// A backup service with a fixed latest backup and an empty store.
private actor StubBackupService: BackupService {
    let latest: BackupDocument?

    init(latest: BackupDocument?) { self.latest = latest }

    func isConfigured() async -> Bool { true }
    func folderName() async -> String? { "Overreach" }
    func configure(folder: URL) async throws {}
    func backUp(now: Date) async throws -> BackupSummary { try summary() }
    func backUpIfConfigured(now: Date) async -> Bool { true }
    func exportData(now: Date) async throws -> Data { Data() }
    func latestBackup() async throws -> BackupDocument? { latest }
    func restore(from data: Data) async throws -> BackupSummary { try summary() }

    private func summary() throws -> BackupSummary {
        guard let latest else { throw CancellationError() }
        return latest.summary
    }
    func hasUserData() async throws -> Bool { false }
}

@MainActor
@Suite("Settings screen state")
struct BackupScreenStateTests {
    private func document() -> BackupDocument {
        let session = StrengthSession(
            name: "Legs",
            startedAt: Date(timeIntervalSince1970: 1_790_000_000),
            entries: [ExerciseEntry(exerciseID: UUID(), sets: [WorkoutSet(weightKg: 80, reps: 5)])]
        )
        return BackupDocument(
            createdAt: Date(timeIntervalSince1970: 1_790_010_000),
            appVersion: "0.1.0",
            sessions: [session],
            exercises: [],
            checkIns: [],
            profile: AthleteProfile(),
            progressionSettings: []
        )
    }

    @Test func restoreOfferAndLastBackupAreDescribed() async throws {
        let model = BackupModel(service: StubBackupService(latest: document()))
        await model.load()
        #expect(model.lastBackupText != nil)

        await model.checkRestoreOffer()
        let offer = try #require(model.restoreOfferMessage)
        #expect(offer.hasPrefix("A backup with 1 sessions from "))
        #expect(offer.hasSuffix("was found in your backup folder."))
    }

    @Test func pendingRestoreExplainsTheMerge() throws {
        let model = BackupModel(service: StubBackupService(latest: nil))
        #expect(model.pendingRestoreMessage == nil)
        model.prepareRestore(fileData: try BackupCodec.encode(document()))
        let message = try #require(model.pendingRestoreMessage)
        #expect(message.hasPrefix("1 sessions from "))
        #expect(message.hasSuffix("Items are merged by id: nothing is duplicated."))
        model.cancelRestore()
        #expect(model.pendingRestoreMessage == nil)
    }

    @Test func invalidFileShowsAMessage() {
        let model = BackupModel(service: StubBackupService(latest: nil))
        model.prepareRestore(fileData: Data("not json".utf8))
        #expect(model.message == "That file is not an Overreach backup.")
    }
}

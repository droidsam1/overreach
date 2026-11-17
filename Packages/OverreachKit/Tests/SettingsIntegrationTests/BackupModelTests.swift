import Domain
import Foundation
import Persistence
import SettingsPresentation
import Testing

private actor MemoryDestination: BackupDestination {
    private var latestData: Data?

    func isConfigured() -> Bool { true }
    func folderName() -> String? { "Memory" }
    func configure(folder: URL) {}
    func write(_ data: Data, at date: Date) { latestData = data }
    func latest() -> Data? { latestData }
}

private func service(_ store: InMemoryStore, _ destination: MemoryDestination) -> RepositoryBackupService {
    RepositoryBackupService(
        workouts: store, exercises: store, checkIns: store, profiles: store, progression: store,
        destination: destination
    )
}

@MainActor
@Suite("BackupModel")
struct BackupModelTests {
    @Test func freshInstallIsOfferedTheLatestBackup() async throws {
        let destination = MemoryDestination()
        let original = InMemoryStore()
        await original.save(StrengthSession(name: "Push", startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        _ = try await service(original, destination).backUp(now: Date(timeIntervalSince1970: 1_790_100_000))

        let fresh = InMemoryStore()
        let model = BackupModel(service: service(fresh, destination))
        await model.checkRestoreOffer()
        #expect(model.restoreOffer?.sessions == 1)

        await model.acceptRestoreOffer()
        #expect(model.restoreOffer == nil)
        #expect(try await fresh.sessions(from: .distantPast, to: .distantFuture).count == 1)
    }

    @Test func noOfferWhenTheDeviceAlreadyHasData() async throws {
        let destination = MemoryDestination()
        let store = InMemoryStore()
        await store.save(StrengthSession(name: "Legs", startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        _ = try await service(store, destination).backUp(now: .now)

        let model = BackupModel(service: service(store, destination))
        await model.checkRestoreOffer()
        #expect(model.restoreOffer == nil)
    }

    @Test func rejectsFilesThatAreNotBackups() {
        let model = BackupModel(service: service(InMemoryStore(), MemoryDestination()))
        model.prepareRestore(fileData: Data("Date,Exercise Name\n".utf8))
        #expect(model.pendingRestore == nil)
        #expect(model.message != nil)
    }
}

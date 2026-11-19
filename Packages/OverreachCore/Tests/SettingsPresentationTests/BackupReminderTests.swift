import Domain
import Foundation
import SettingsPresentation
import Testing

/// A backup service without a folder, with or without data on the device.
private actor UnconfiguredBackupService: BackupService {
    let hasData: Bool

    init(hasData: Bool) { self.hasData = hasData }

    func isConfigured() async -> Bool { false }
    func folderName() async -> String? { nil }
    func configure(folder: URL) async throws {}
    func backUp(now: Date) async throws -> BackupSummary { throw BackupError.notConfigured }
    func backUpIfConfigured(now: Date) async -> Bool { false }
    func exportData(now: Date) async throws -> Data { Data() }
    func latestBackup() async throws -> BackupDocument? { nil }
    func restore(from data: Data) async throws -> BackupSummary { throw BackupError.notConfigured }
    func hasUserData() async throws -> Bool { hasData }
}

@MainActor
@Suite("Backup reminders")
struct BackupReminderTests {
    @Test func dataWithoutABackupFolderIsPointedOut() async throws {
        let model = BackupModel(service: UnconfiguredBackupService(hasData: true))
        await model.load()

        let warning = try #require(model.backupWarning)
        #expect(warning.hasPrefix("Your data is only on this iPhone."))
        #expect(model.badgeCount == 1)
    }

    @Test func aFreshInstallWithoutDataIsNotNagged() async {
        let model = BackupModel(service: UnconfiguredBackupService(hasData: false))
        await model.load()

        #expect(model.backupWarning == nil)
        #expect(model.badgeCount == 0)
    }

    @Test func theFirstRunSetupCanAskForTheFolder() {
        let model = BackupModel(service: UnconfiguredBackupService(hasData: false))
        #expect(!model.isRequestingFolderChoice)
        model.requestFolderChoice()
        #expect(model.isRequestingFolderChoice)
    }
}

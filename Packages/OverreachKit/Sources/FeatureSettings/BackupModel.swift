import Domain
import Foundation
import Observation

/// Backup folder, manual backup/export, restore, and the "restore your data?" offer on a fresh install.
@MainActor
@Observable
public final class BackupModel {
    public private(set) var isConfigured = false
    public private(set) var folderName: String?
    public private(set) var lastBackup: BackupSummary?
    public private(set) var message: String?
    public private(set) var isWorking = false
    /// A backup found at launch while the store is empty. The app offers to restore it.
    public private(set) var restoreOffer: BackupSummary?
    /// Data waiting for the user to confirm a restore.
    public private(set) var pendingRestore: BackupSummary?

    private var pendingData: Data?
    private let service: any BackupService
    private let clock: @Sendable () -> Date

    public init(service: any BackupService, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.clock = clock
    }

    /// Drives the restore confirmation; setting it to `false` cancels.
    public var isConfirmingRestore: Bool {
        get { pendingRestore != nil }
        set { if !newValue { cancelRestore() } }
    }

    /// Drives the fresh-install restore offer; setting it to `false` declines.
    public var isOfferingRestore: Bool {
        get { restoreOffer != nil }
        set { if !newValue { declineRestoreOffer() } }
    }

    public func load() async {
        isConfigured = await service.isConfigured()
        folderName = await service.folderName()
        lastBackup = try? await service.latestBackup()?.summary
    }

    public func chooseFolder(_ url: URL) async {
        do {
            try await service.configure(folder: url)
            await load()
            // A folder with an existing backup on a device without data (e.g. after a reinstall): offer to restore
            // instead of backing up an empty store over it.
            await checkRestoreOffer()
            if restoreOffer == nil { await backUpNow() }
        } catch {
            message = "Could not use that folder."
        }
    }

    public func backUpNow() async {
        isWorking = true
        defer { isWorking = false }
        do {
            lastBackup = try await service.backUp(now: clock())
            message = nil
        } catch BackupError.notConfigured {
            message = "Choose a backup folder first."
        } catch BackupError.wouldOverwriteWithEmpty {
            message = "The folder has a backup and this device has no sessions yet. Restore it first."
        } catch {
            message = "Backup failed. Check that the folder is still available."
        }
    }

    /// Writes the export to a temporary file for the share sheet.
    public func exportFile() async -> URL? {
        do {
            let data = try await service.exportData(now: clock())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(BackupCodec.fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            message = "Could not export your data."
            return nil
        }
    }

    /// Reads a backup file and asks for confirmation before restoring.
    public func prepareRestore(fileData: Data) {
        do {
            pendingRestore = try BackupCodec.decode(fileData).summary
            pendingData = fileData
            message = nil
        } catch BackupError.newerFormat {
            message = "This backup was made by a newer version of Overreach. Update the app first."
        } catch {
            message = "That file is not an Overreach backup."
        }
    }

    public func confirmRestore() async {
        guard let data = pendingData else { return }
        await restore(data)
        pendingData = nil
        pendingRestore = nil
    }

    public func cancelRestore() {
        pendingData = nil
        pendingRestore = nil
    }

    // MARK: Fresh install

    /// On launch: if the store is empty and the backup folder has a backup, offer to restore it.
    public func checkRestoreOffer() async {
        guard (try? await service.hasUserData()) == false,
              let backup = try? await service.latestBackup(),
              !backup.sessions.isEmpty else { return }
        restoreOffer = backup.summary
    }

    public func acceptRestoreOffer() async {
        restoreOffer = nil
        do {
            guard let backup = try await service.latestBackup() else { return }
            await restore(try BackupCodec.encode(backup))
        } catch {
            message = "Restore failed."
        }
    }

    public func declineRestoreOffer() {
        restoreOffer = nil
    }

    /// Automatic backup (after a session, when the app goes to the background). Silent when not configured.
    public func backUpIfConfigured() async {
        if await service.backUpIfConfigured(now: clock()) {
            lastBackup = try? await service.latestBackup()?.summary
        }
    }

    private func restore(_ data: Data) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let summary = try await service.restore(from: data)
            message = "Restored \(summary.sessions) sessions."
        } catch {
            message = "Restore failed. Nothing already on this device was removed."
        }
    }
}

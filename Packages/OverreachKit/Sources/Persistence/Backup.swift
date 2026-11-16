import Domain
import Foundation

// MARK: - Service

/// Backs up and restores everything in the repositories (ADR-0004). Restores merge by id, so restoring twice,
/// or restoring over existing data, never duplicates anything.
public actor RepositoryBackupService: BackupService {
    private let workouts: any WorkoutRepository
    private let exercises: any ExerciseRepository
    private let checkIns: any CheckInRepository
    private let profiles: any ProfileRepository
    private let progression: any ProgressionSettingsRepository
    private let destination: any BackupDestination
    private let appVersion: String?

    /// Wide enough to cover every check-in ever stored.
    private static let allDays = CalendarDay(year: 1970, month: 1, day: 1)...CalendarDay(year: 9999, month: 12, day: 31)

    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        checkIns: any CheckInRepository,
        profiles: any ProfileRepository,
        progression: any ProgressionSettingsRepository,
        destination: any BackupDestination,
        appVersion: String? = nil
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.checkIns = checkIns
        self.profiles = profiles
        self.progression = progression
        self.destination = destination
        self.appVersion = appVersion
    }

    public func isConfigured() async -> Bool {
        await destination.isConfigured()
    }

    public func folderName() async -> String? {
        await destination.folderName()
    }

    public func configure(folder: URL) async throws {
        try await destination.configure(folder: folder)
    }

    public func backUp(now: Date) async throws -> BackupSummary {
        guard await destination.isConfigured() else { throw BackupError.notConfigured }
        let document = try await makeDocument(now: now)
        try await destination.write(try BackupCodec.encode(document), at: now)
        return document.summary
    }

    @discardableResult
    public func backUpIfConfigured(now: Date) async -> Bool {
        guard await destination.isConfigured() else { return false }
        return (try? await backUp(now: now)) != nil
    }

    public func exportData(now: Date) async throws -> Data {
        try BackupCodec.encode(try await makeDocument(now: now))
    }

    public func latestBackup() async throws -> BackupDocument? {
        guard let data = try await destination.latest() else { return nil }
        return try BackupCodec.decode(data)
    }

    public func restore(from data: Data) async throws -> BackupSummary {
        let document = try BackupCodec.decode(data)
        // Exercises first, so restored sessions never point to missing exercises.
        for exercise in document.exercises {
            try await exercises.save(exercise)
        }
        for session in document.sessions {
            try await workouts.save(session)
        }
        for checkIn in document.checkIns {
            try await checkIns.save(checkIn)
        }
        for entry in document.progressionSettings {
            try await progression.save(entry.settings, for: entry.exerciseID)
        }
        // Keep a profile the user already set up on this device; otherwise take the backup's.
        if try await profiles.profile() == AthleteProfile() {
            try await profiles.save(document.profile)
        }
        return document.summary
    }

    public func hasUserData() async throws -> Bool {
        let sessions = try await workouts.sessions(from: .distantPast, to: .distantFuture)
        return !sessions.isEmpty
    }

    private func makeDocument(now: Date) async throws -> BackupDocument {
        BackupDocument(
            createdAt: now,
            appVersion: appVersion,
            sessions: try await workouts.sessions(from: .distantPast, to: .distantFuture),
            exercises: BackupCodec.exportableExercises(all: try await exercises.allExercises()),
            checkIns: try await checkIns.checkIns(in: Self.allDays),
            profile: try await profiles.profile(),
            progressionSettings: try await progression.allProgressionSettings()
                .map { ProgressionSettingsEntry(exerciseID: $0.key, settings: $0.value) }
                .sorted { $0.exerciseID.uuidString < $1.exerciseID.uuidString }
        )
    }
}

// MARK: - Folder destination

/// Writes backups into a folder the user picked (an iCloud Drive folder in the prototype), remembered with a
/// bookmark so it survives app restarts. Keeps `Overreach-backup.json` plus dated copies of the last days.
public actor FolderBackupDestination: BackupDestination {
    private let defaultsSuite: String?
    private let bookmarkKey: String
    private let datedCopiesToKeep: Int
    private let calendar: Calendar

    public init(
        defaultsSuite: String? = nil,
        bookmarkKey: String = "backupFolderBookmark",
        datedCopiesToKeep: Int = 14,
        calendar: Calendar = .current
    ) {
        self.defaultsSuite = defaultsSuite
        self.bookmarkKey = bookmarkKey
        self.datedCopiesToKeep = datedCopiesToKeep
        self.calendar = calendar
    }

    /// The bookmark lives in UserDefaults (the standard one, or a named suite for tests).
    private var defaults: UserDefaults {
        defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func isConfigured() -> Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    public func folderName() -> String? {
        try? resolveFolder().lastPathComponent
    }

    public func configure(folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    public func write(_ data: Data, at date: Date) throws {
        let folder = try resolveFolder()
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        try data.write(to: folder.appendingPathComponent(BackupCodec.fileName), options: .atomic)
        try data.write(
            to: folder.appendingPathComponent(BackupCodec.datedFileName(for: date, calendar: calendar)), options: .atomic
        )
        try pruneDatedCopies(in: folder)
    }

    public func latest() throws -> Data? {
        guard isConfigured() else { return nil }
        let folder = try resolveFolder()
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(BackupCodec.fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    private func resolveFolder() throws -> URL {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { throw BackupError.notConfigured }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        else { throw BackupError.folderUnavailable }
        if isStale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    /// Dated copies sort by name (ISO dates), so the oldest go first.
    private func pruneDatedCopies(in folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("Overreach-backup-") && $0.hasSuffix(".json") }
            .sorted()
        for name in names.dropLast(datedCopiesToKeep) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

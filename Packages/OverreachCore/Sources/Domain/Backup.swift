import Foundation

/// Progression settings of one exercise, as stored in a backup.
public struct ProgressionSettingsEntry: Hashable, Codable, Sendable {
    public var exerciseID: UUID
    public var settings: ProgressionSettings

    public init(exerciseID: UUID, settings: ProgressionSettings) {
        self.exerciseID = exerciseID
        self.settings = settings
    }
}

/// Everything the user created, in one versioned JSON document (ADR-0004). Also the export format.
///
/// Built-in catalog exercises are not included unless the user changed them; they are part of the app.
public struct BackupDocument: Hashable, Codable, Sendable {
    /// Bump when the format changes in a way older apps cannot read.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String?
    public var sessions: [StrengthSession]
    public var exercises: [Exercise]
    public var checkIns: [CheckIn]
    public var profile: AthleteProfile
    public var progressionSettings: [ProgressionSettingsEntry]

    public init(
        formatVersion: Int = BackupDocument.currentFormatVersion,
        createdAt: Date,
        appVersion: String? = nil,
        sessions: [StrengthSession] = [],
        exercises: [Exercise] = [],
        checkIns: [CheckIn] = [],
        profile: AthleteProfile = AthleteProfile(),
        progressionSettings: [ProgressionSettingsEntry] = []
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.sessions = sessions
        self.exercises = exercises
        self.checkIns = checkIns
        self.profile = profile
        self.progressionSettings = progressionSettings
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, createdAt, appVersion, sessions, exercises, checkIns, profile, progressionSettings
    }

    /// Tolerant decoding: sections added in later versions fall back to empty, so old backups keep loading.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            formatVersion: try container.decode(Int.self, forKey: .formatVersion),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            appVersion: try container.decodeIfPresent(String.self, forKey: .appVersion),
            sessions: try container.decodeIfPresent([StrengthSession].self, forKey: .sessions) ?? [],
            exercises: try container.decodeIfPresent([Exercise].self, forKey: .exercises) ?? [],
            checkIns: try container.decodeIfPresent([CheckIn].self, forKey: .checkIns) ?? [],
            profile: try container.decodeIfPresent(AthleteProfile.self, forKey: .profile) ?? AthleteProfile(),
            progressionSettings: try container.decodeIfPresent(
                [ProgressionSettingsEntry].self, forKey: .progressionSettings
            ) ?? []
        )
    }

    public var summary: BackupSummary {
        BackupSummary(
            createdAt: createdAt,
            sessions: sessions.count,
            exercises: exercises.count,
            checkIns: checkIns.count,
            progressionSettings: progressionSettings.count
        )
    }
}

public struct BackupSummary: Hashable, Sendable {
    public var createdAt: Date
    public var sessions: Int
    public var exercises: Int
    public var checkIns: Int
    public var progressionSettings: Int

    public init(createdAt: Date, sessions: Int, exercises: Int, checkIns: Int, progressionSettings: Int) {
        self.createdAt = createdAt
        self.sessions = sessions
        self.exercises = exercises
        self.checkIns = checkIns
        self.progressionSettings = progressionSettings
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// The file is not an Overreach backup.
    case notABackup
    /// The backup was written by a newer app version with a format this version cannot read.
    case newerFormat(Int)
    /// No backup folder has been chosen yet.
    case notConfigured
    /// The chosen folder can no longer be accessed (moved, deleted or permission lost).
    case folderUnavailable
}

/// Encoding, decoding and selection rules for backups. Pure, so it is tested on Linux.
public enum BackupCodec {
    public static let fileName = "Overreach-backup.json"

    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable { var formatVersion: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BackupError.notABackup }
        guard header.formatVersion <= BackupDocument.currentFormatVersion else {
            throw BackupError.newerFormat(header.formatVersion)
        }
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
    }

    /// Exercises worth backing up: custom ones and built-in ones the user changed.
    public static func exportableExercises(all: [Exercise], builtIn: [Exercise] = ExerciseCatalog.builtIn) -> [Exercise] {
        let original = Dictionary(builtIn.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return all.filter { original[$0.id] != $0 }
    }

    /// Dated file name for the rolling history, e.g. `Overreach-backup-2026-11-16.json`.
    public static func datedFileName(for date: Date, calendar: Calendar = .current) -> String {
        "Overreach-backup-\(CalendarDay(date, calendar: calendar)).json"
    }
}

/// Where backups are written (an iCloud Drive folder chosen by the user in the prototype).
public protocol BackupDestination: Sendable {
    func isConfigured() async -> Bool
    /// Display name of the chosen folder.
    func folderName() async -> String?
    func configure(folder: URL) async throws
    /// Writes `data` as the latest backup and as a dated copy, keeping a limited history.
    func write(_ data: Data, at date: Date) async throws
    /// The latest backup, if any.
    func latest() async throws -> Data?
}

/// Backs up and restores everything the user created. Implemented in `Persistence`.
public protocol BackupService: Sendable {
    func isConfigured() async -> Bool
    func folderName() async -> String?
    func configure(folder: URL) async throws
    /// Writes a backup to the destination and returns what it contains.
    func backUp(now: Date) async throws -> BackupSummary
    /// Same as `backUp`, but silently does nothing when no folder is configured. Returns `true` on success.
    @discardableResult
    func backUpIfConfigured(now: Date) async -> Bool
    /// The backup document as data, for sharing/exporting.
    func exportData(now: Date) async throws -> Data
    /// The latest backup at the destination, if any.
    func latestBackup() async throws -> BackupDocument?
    /// Merges a backup into the store by id: nothing is duplicated, existing items are replaced by the backup's.
    func restore(from data: Data) async throws -> BackupSummary
    /// Whether the store has any user data (used to offer a restore on a fresh install).
    func hasUserData() async throws -> Bool
}

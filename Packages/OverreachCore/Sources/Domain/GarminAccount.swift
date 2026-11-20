import Foundation

/// The lifetime the person picked when creating their Garmin Personal API key (ADR-0022). Garmin does not report it,
/// so the app asks, to warn before the key expires.
public enum GarminKeyLifetime: Int, Codable, Sendable, CaseIterable {
    case days30 = 30
    case days90 = 90
    case days180 = 180
    case oneYear = 365

    /// The longest, which the setup recommends: one less thing to renew.
    public static let recommended = GarminKeyLifetime.oneYear
}

/// The connected Garmin account, as the person sees it.
public struct GarminConnectionInfo: Hashable, Codable, Sendable {
    public var connectedAt: Date
    /// When the key expires, from the lifetime the person picked (approximate: the key was created a moment before).
    public var keyExpiresAt: Date
    public var lastSync: Date?

    public init(connectedAt: Date, keyExpiresAt: Date, lastSync: Date? = nil) {
        self.connectedAt = connectedAt
        self.keyExpiresAt = keyExpiresAt
        self.lastSync = lastSync
    }
}

/// What a sync brought in.
public struct GarminSyncSummary: Hashable, Sendable {
    /// Days with at least one Garmin value.
    public var days: Int
    public var hrvNights: Int
    public var sleepNights: Int
    public var runs: Int
    public var strengthWorkouts: Int
    /// Records Garmin sent that could not be read. Above zero, Garmin may have changed something.
    public var skippedRecords: Int

    public init(
        days: Int = 0, hrvNights: Int = 0, sleepNights: Int = 0, runs: Int = 0, strengthWorkouts: Int = 0,
        skippedRecords: Int = 0
    ) {
        self.days = days
        self.hrvNights = hrvNights
        self.sleepNights = sleepNights
        self.runs = runs
        self.strengthWorkouts = strengthWorkouts
        self.skippedRecords = skippedRecords
    }
}

/// Progress of a sync: requests done out of the requests planned.
public struct GarminSyncProgress: Hashable, Sendable {
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    public var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
}

public enum GarminAccountError: Error, Equatable, Sendable {
    /// What was pasted is not a key (empty, a link, a sentence).
    case keyLooksWrong
    /// Garmin refused the key: mistyped, deleted, or expired.
    case keyRejected
    /// No connection to Garmin.
    case offline
    /// Too many requests; Garmin asks to wait.
    case rateLimited
    /// Garmin answered with an error or something the app cannot read.
    case garminUnavailable
    /// The key could not be saved securely on this iPhone.
    case storageFailed
    /// No key is saved.
    case notConnected
}

/// The person's Garmin Connect account, reached through their own Personal API key (ADR-0022).
public protocol GarminAccount: Sendable {
    /// The connected account, or nil when no key is saved.
    func connection() async -> GarminConnectionInfo?
    /// Checks the key with Garmin and saves it securely. Nothing is saved when Garmin refuses it.
    func connect(key: String, lifetime: GarminKeyLifetime) async throws(GarminAccountError)
    /// Fetches what is new since the last sync (the last 60 days the first time).
    func sync(
        progress: @escaping @Sendable (GarminSyncProgress) -> Void
    ) async throws(GarminAccountError) -> GarminSyncSummary
    /// Forgets the key and the token. Data already imported stays.
    func disconnect() async
}

import Domain
import Foundation

/// The person's key as kept in secure storage (the Keychain on the iPhone).
public struct GarminStoredKey: Codable, Hashable, Sendable {
    public var value: String
    public var lifetime: GarminKeyLifetime
    public var savedAt: Date

    public init(value: String, lifetime: GarminKeyLifetime, savedAt: Date) {
        self.value = value
        self.lifetime = lifetime
        self.savedAt = savedAt
    }
}

/// Secure storage for the key (synchronised through the person's iCloud Keychain, so it survives updates,
/// reinstalls and a new iPhone) and for the token (this device only).
public protocol GarminSecretStore: Sendable {
    func loadKey() async -> GarminStoredKey?
    func saveKey(_ key: GarminStoredKey) async throws
    func loadToken() async -> GarminToken?
    func saveToken(_ token: GarminToken?) async
    func deleteAll() async
}

/// What was imported, kept on the device between launches so the app does not ask Garmin every time.
public struct GarminCache: Codable, Hashable, Sendable {
    public var lastSync: Date?
    public var lastSyncedDay: CalendarDay?
    public var metrics: [DailyMetrics]
    public var runs: [RunActivity]
    public var strength: [RecordedStrengthActivity]
    /// Walking and hiking activities (ADR-0010). `nil` in a cache written before walks were imported: the next sync
    /// then fetches the activities of the whole first-sync window again, so the walking baseline has its history.
    public var walks: [GarminWalk]?
    /// Absent in caches that still need the elapsed-time metadata from the bounded first-sync activity window.
    public var refreshedRunPerformanceMetadata: Bool?
    /// Nil in caches saved before original activity tracks were downloaded.
    var runningTracks: [String: GarminTrackCache]?

    public init(
        lastSync: Date? = nil, lastSyncedDay: CalendarDay? = nil, metrics: [DailyMetrics] = [],
        runs: [RunActivity] = [], strength: [RecordedStrengthActivity] = [], walks: [GarminWalk]? = [],
        refreshedRunPerformanceMetadata: Bool? = nil
    ) {
        self.lastSync = lastSync
        self.lastSyncedDay = lastSyncedDay
        self.metrics = metrics
        self.runs = runs
        self.strength = strength
        self.walks = walks
        self.refreshedRunPerformanceMetadata = refreshedRunPerformanceMetadata
        runningTracks = nil
    }

    /// Days older than this are dropped: enough for the readiness baselines and a year of trends.
    public static let retentionDays = 400

    private enum CodingKeys: String, CodingKey {
        case lastSync, lastSyncedDay, metrics, runs, strength, walks, refreshedRunPerformanceMetadata, runningTracks
    }

    /// The HRV fields of a cache written before ADR-0025, which kept one value per night in `hrvNightlyAverageMs`,
    /// labelled `hrvMetric` since ADR-0024 and unlabelled before it.
    private struct LegacyHRV: Decodable {
        var hrvNightlyAverageMs: Double?
        var hrvMetric: HRVMetric?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSync = try container.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncedDay = try container.decodeIfPresent(CalendarDay.self, forKey: .lastSyncedDay)
        runs = try container.decodeIfPresent([RunActivity].self, forKey: .runs) ?? []
        strength = try container.decodeIfPresent([RecordedStrengthActivity].self, forKey: .strength) ?? []
        walks = try container.decodeIfPresent([GarminWalk].self, forKey: .walks)
        refreshedRunPerformanceMetadata = try container.decodeIfPresent(
            Bool.self, forKey: .refreshedRunPerformanceMetadata
        )
        runningTracks = try? container.decodeIfPresent([String: GarminTrackCache].self, forKey: .runningTracks)
        var metrics = try container.decodeIfPresent([DailyMetrics].self, forKey: .metrics) ?? []
        let legacy = (try? container.decodeIfPresent([LegacyHRV].self, forKey: .metrics)) ?? []
        // Only Garmin fills this cache, and Garmin only ever reported RMSSD, labelled or not.
        for index in metrics.indices where index < legacy.count && metrics[index].hrv(.rmssd) == nil {
            guard let value = legacy[index].hrvNightlyAverageMs, (legacy[index].hrvMetric ?? .rmssd) == .rmssd
            else { continue }
            metrics[index].setHRV(value, .rmssd)
        }
        self.metrics = metrics
    }

    /// The cache with `range` replaced by a fresh sync. Activities are merged by id, the fresh copy winning.
    func merging(
        _ metrics: [DailyMetrics], runs: [RunActivity], strength: [RecordedStrengthActivity], walks: [GarminWalk] = [],
        range: ClosedRange<CalendarDay>, at date: Date, calendar: Calendar
    ) -> GarminCache {
        let oldest = range.upperBound.adding(days: -Self.retentionDays, calendar: calendar)
        let oldestDate = oldest.startDate(in: calendar)
        var merged = self
        merged.metrics = (self.metrics.filter { !range.contains($0.day) } + metrics)
            .filter { $0.day >= oldest }
            .sorted { $0.day < $1.day }
        // A fresh activity list has no laps: keep the ones fetched before.
        let knownLaps = Dictionary(self.runs.compactMap { run in run.laps.map { (run.id, $0) } }) { first, _ in first }
        let runs = runs.map { run in
            var run = run
            if run.laps == nil { run.laps = knownLaps[run.id] }
            return run
        }
        merged.runs = Self.merge(self.runs, runs, id: \.id).filter { $0.startedAt >= oldestDate }
        merged.strength = Self.merge(self.strength, strength, id: \.id).filter { $0.startedAt >= oldestDate }
        merged.walks = Self.merge(self.walks ?? [], walks, id: \.id).filter { $0.walk.start >= oldestDate }
        merged.refreshedRunPerformanceMetadata = true
        merged.lastSync = date
        merged.lastSyncedDay = max(range.upperBound, lastSyncedDay ?? range.upperBound)
        return merged
    }

    private static func merge<T>(_ old: [T], _ new: [T], id: KeyPath<T, String>) -> [T]
    where T: Identifiable, T.ID == String {
        let fresh = Set(new.map { $0[keyPath: id] })
        return old.filter { !fresh.contains($0[keyPath: id]) } + new
    }

    /// Older caches may already contain repeated activity IDs from overlapping pages.
    mutating func removeDuplicateActivities() {
        runs = Self.unique(runs)
        strength = Self.unique(strength)
        walks = walks.map(Self.unique)
    }

    private static func unique<T: Identifiable>(_ records: [T]) -> [T] {
        var seen: Set<T.ID> = []
        return Array(records.reversed().filter { seen.insert($0.id).inserted }.reversed())
    }
}

public protocol GarminCacheStore: Sendable {
    func load() async -> GarminCache?
    func save(_ cache: GarminCache) async
}

/// The Garmin account and the Garmin metrics source in one place (ADR-0022). Pure Swift: the iPhone supplies the
/// Keychain, URLSession and a file; tests supply fakes.
public actor GarminService: GarminAccount, MetricsSource, ActivitySource, RecordedStrengthSource, RunningTrackSource {
    public nonisolated let kind: DataSourceKind = .garmin
    /// A sync older than this runs again when the app reads metrics (launch, foreground, Today).
    public static let autoSyncInterval: TimeInterval = 30 * 60
    /// Pages of activities per window, as a safety limit.
    static let maximumActivityPages = 10

    private let client: GarminClient
    private let secrets: any GarminSecretStore
    private let cacheStore: any GarminCacheStore
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private var cache: GarminCache?
    private var running: Task<GarminSyncSummary, any Error>?

    public init(
        transport: any GarminTransport,
        secrets: any GarminSecretStore,
        cache: any GarminCacheStore,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.client = GarminClient(transport: transport, clock: clock, sleep: sleep)
        self.secrets = secrets
        self.cacheStore = cache
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: GarminAccount

    public func connection() async -> GarminConnectionInfo? {
        guard let key = await secrets.loadKey() else { return nil }
        let expires = calendar.date(byAdding: .day, value: key.lifetime.rawValue, to: key.savedAt) ?? key.savedAt
        let lastSync = await loadCache().lastSync
        return GarminConnectionInfo(connectedAt: key.savedAt, keyExpiresAt: expires, lastSync: lastSync)
    }

    public func connect(key: String, lifetime: GarminKeyLifetime) async throws(GarminAccountError) {
        guard let value = Self.normalized(key) else { throw .keyLooksWrong }
        let token = try await client.mintToken(key: value)
        do {
            try await secrets.saveKey(GarminStoredKey(value: value, lifetime: lifetime, savedAt: clock()))
        } catch {
            throw .storageFailed
        }
        await secrets.saveToken(token)
    }

    public func sync(
        progress: @escaping @Sendable (GarminSyncProgress) -> Void
    ) async throws(GarminAccountError) -> GarminSyncSummary {
        // One sync at a time: a second caller waits for the first instead of asking Garmin twice.
        if let running { return try await syncResult(running) }
        let task = Task { try await self.performSync(progress: progress) }
        running = task
        defer { running = nil }
        return try await syncResult(task)
    }

    private func syncResult(_ task: Task<GarminSyncSummary, any Error>) async throws(GarminAccountError)
        -> GarminSyncSummary {
        do {
            return try await task.value
        } catch let error as GarminAccountError {
            throw error
        } catch {
            throw .garminUnavailable
        }
    }

    public func disconnect() async {
        await secrets.deleteAll()
    }

    // MARK: MetricsSource

    /// Available while a key is saved or anything was imported before (imported data stays after disconnecting).
    public func isAvailable() async -> Bool {
        if await secrets.loadKey() != nil { return true }
        let cache = await loadCache()
        return !cache.metrics.isEmpty || !cache.runs.isEmpty
    }

    public func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        await syncIfDue()
        return await loadCache().metrics.filter { range.contains($0.day) }
    }

    public func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        let failure = await syncIfDue()
        let runs = await loadCache().runs.filter { $0.startedAt >= start && $0.startedAt <= end }
        if runs.isEmpty, let failure { throw failure }
        return runs
    }

    /// The existing FIT cache is read locally. Sync and activity-list reads own downloads.
    public func runningTrack(for run: RunActivity) async -> RunningTrack? {
        guard run.source == .garmin else { return nil }
        return await loadCache().runningTracks?[run.id]?.track
    }

    /// Strength workouts recorded on the watch, to pair with logged sessions (`StrengthActivityMatching`).
    public func strengthActivities(from start: Date, to end: Date) async -> [RecordedStrengthActivity] {
        await syncIfDue()
        return await loadCache().strength.filter { $0.startedAt >= start && $0.startedAt <= end }
    }

    // MARK: ActivitySource

    /// Daily step totals from the cached summaries, alongside walking and hiking activities.
    public func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        let failure = await syncIfDue()
        let cache = await loadCache()
        var steps: [CalendarDay: Int] = [:]
        for metrics in cache.metrics where range.contains(metrics.day) {
            if let count = metrics.steps { steps[metrics.day] = count }
        }
        let walks = Dictionary(grouping: (cache.walks ?? []).map(\.walk)) { CalendarDay($0.start, calendar: calendar) }
        let days = Set(steps.keys).union(walks.keys.filter { range.contains($0) })
        if days.isEmpty, cache.walks == nil, let failure { throw failure }
        return days.sorted().map { day in
            DailyActivity(day: day, steps: steps[day], walks: (walks[day] ?? []).sorted { $0.start < $1.start })
        }
    }

    // MARK: Sync

    @discardableResult
    private func syncIfDue() async -> GarminAccountError? {
        guard await secrets.loadKey() != nil else { return nil }
        let lastSync = await loadCache().lastSync
        do {
            if let running {
                _ = try await syncResult(running)
            } else if lastSync.map({ clock().timeIntervalSince($0) < Self.autoSyncInterval }) != true {
                _ = try await sync { _ in }
            }
            return nil
        } catch {
            return error
        }
    }

    private func performSync(
        progress: @escaping @Sendable (GarminSyncProgress) -> Void
    ) async throws(GarminAccountError) -> GarminSyncSummary {
        guard let key = await secrets.loadKey() else { throw .notConnected }
        if await client.currentToken == nil, let saved = await secrets.loadToken() {
            await client.restore(saved)
        }
        let cache = await loadCache()
        let today = CalendarDay(clock(), calendar: calendar)
        let range = GarminSyncPlan.range(lastSynced: cache.lastSyncedDay, today: today, calendar: calendar)
        // Fetch the bounded activity history once more when an older cache lacks newly imported fields.
        let needsHistory = cache.walks == nil || cache.refreshedRunPerformanceMetadata != true
        let activityDays = needsHistory ? GarminSyncPlan.firstSyncDays : GarminSyncPlan.activityRefetchDays
        var requests = GarminSyncPlan.requests(for: range, activityDays: activityDays, calendar: calendar)
        var done = 0
        progress(GarminSyncProgress(completed: 0, total: requests.count))

        var hrv: [GarminHRVNight] = []
        var sleep: [GarminSleep] = []
        var summaries: [GarminDailySummary] = []
        var vo2Max: [GarminVO2Max] = []
        var activitiesByID: [String: GarminActivity] = [:]
        var skipped = 0
        var index = 0
        while index < requests.count {
            let endpoint = requests[index]
            index += 1
            let data = try await client.data(for: endpoint, key: key.value)
            do {
                switch endpoint {
                case .hrv:
                    let decoded = try GarminDecoding.hrvNights(from: data)
                    hrv += decoded.records
                    skipped += decoded.skipped
                case .sleep:
                    let decoded = try GarminDecoding.sleeps(from: data)
                    sleep += decoded.records
                    skipped += decoded.skipped
                case .dailySummaries:
                    let decoded = try GarminDecoding.dailySummaries(from: data)
                    summaries += decoded.records
                    skipped += decoded.skipped
                case .vo2Max:
                    let decoded = try GarminDecoding.vo2Max(from: data)
                    vo2Max += decoded.records
                    skipped += decoded.skipped
                case .activitySplits, .activityFIT:
                    break  // optional enrichment after the activity list
                case let .activities(window, start, limit):
                    let decoded = try GarminDecoding.activities(from: data)
                    // Offset pages can overlap when new activities arrive during a sync.
                    decoded.records.forEach { activity in
                        activitiesByID[activity.id] = activity
                    }
                    skipped += decoded.skipped
                    let page = start / max(1, limit) + 1
                    if decoded.records.count + decoded.skipped >= limit, page < Self.maximumActivityPages {
                        requests.append(.activities(window, start: start + limit, limit: limit))
                    }
                }
            } catch {
                throw .garminUnavailable
            }
            done += 1
            progress(GarminSyncProgress(completed: done, total: requests.count))
        }

        let metrics = GarminMapping.dailyMetrics(hrv: hrv, sleep: sleep, summaries: summaries, vo2Max: vo2Max)
        let activities = Array(activitiesByID.values)
        var runs = GarminMapping.runs(activities)
        let strength = GarminMapping.strengthActivities(activities)
        let walks = GarminMapping.walks(activities)
        runs = try await withLaps(runs, cached: cache.runs, key: key.value)
        var updated = cache.merging(
            metrics, runs: runs, strength: strength, walks: walks, range: range, at: clock(), calendar: calendar
        )
        updated.runningTracks = await withRunningTracks(updated, today: today, key: key.value)
        self.cache = updated
        await cacheStore.save(updated)
        await secrets.saveToken(await client.currentToken)
        return GarminSyncSummary(
            days: metrics.count,
            hrvNights: Set(hrv.filter { $0.lastNightAverage != nil }.map(\.day)).count,
            sleepNights: Set(sleep.filter { $0.sleepSeconds != nil }.map(\.day)).count,
            runs: runs.count,
            strengthWorkouts: strength.count,
            skippedRecords: skipped
        )
    }

    /// Fetches the laps of the newest recent runs that have none yet, within the request budget
    /// (`GarminSyncPlan.maximumLapRequests`). Garmin saying it has none is remembered (empty laps) so it is not asked
    /// again; a failure stops the fetching but not the sync, and those runs are tried again on the next one.
    /// Only a rejected key ends the sync, as for any other request.
    private func withLaps(
        _ runs: [RunActivity], cached: [RunActivity], key: String
    ) async throws(GarminAccountError) -> [RunActivity] {
        let known = Set(cached.filter { $0.laps != nil }.map(\.id))
        let oldest = clock().addingTimeInterval(-Double(GarminSyncPlan.lapRefreshDays) * 86_400)
        let wanted = runs.filter { $0.laps == nil && !known.contains($0.id) && $0.startedAt >= oldest }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(GarminSyncPlan.maximumLapRequests)
        var laps: [String: [RunLap]] = [:]
        for run in wanted {
            do {
                let data = try await client.dataIfServed(for: .activitySplits(id: run.id), key: key)
                laps[run.id] = (try? data.map(GarminDecoding.laps(from:))) ?? []
            } catch .keyRejected {
                throw .keyRejected
            } catch {
                break
            }
        }
        return runs.map { run in
            var run = run
            if let found = laps[run.id] { run.laps = found }
            return run
        }
    }

    private func withRunningTracks(
        _ cache: GarminCache, today: CalendarDay, key: String
    ) async -> [String: GarminTrackCache] {
        let now = clock()
        let oldest = today.adding(days: 1 - GarminSyncPlan.trackHistoryDays, calendar: calendar)
            .startDate(in: calendar)
        let recent = cache.runs.filter { run in
            run.startedAt >= oldest && run.startedAt <= now && !run.id.isEmpty
                && run.id.utf8.allSatisfy { (48...57).contains($0) }
        }
        let retainedIDs = Set(recent.map(\.id))
        var stored = (cache.runningTracks ?? [:]).filter { retainedIDs.contains($0.key) }
        let wanted = recent.filter { stored[$0.id]?.needsDownload(at: now) != false }
            .sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
            .prefix(GarminSyncPlan.maximumFITRequests)
        for run in wanted {
            do {
                let data = try await client.dataIfServed(for: .activityFIT(id: run.id), key: key)
                let decoded = data.flatMap { try? GarminFITArchive.track(from: $0) }
                let retryAfter = calendar.date(byAdding: .day, value: 7, to: now) ?? now
                stored[run.id] = decoded.flatMap(GarminTrackCache.init(track:))
                    ?? GarminTrackCache(retryAfter: retryAfter)
            } catch {
                // A request failure ends optional fetches for this sync. Summary data is still saved.
                break
            }
        }
        return stored
    }

    private func loadCache() async -> GarminCache {
        if let cache { return cache }
        var loaded = await cacheStore.load() ?? GarminCache()
        if let cache { return cache }
        loaded.removeDuplicateActivities()
        cache = loaded
        return loaded
    }

    /// The key as pasted, without spaces, line breaks or quotes around it; nil when it cannot be a key (empty, a link,
    /// a sentence). Garmin decides the rest.
    static func normalized(_ pasted: String) -> String? {
        let key = pasted.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`")))
        guard (16...2_048).contains(key.count), !key.contains("://"),
            key.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { return nil }
        return key
    }
}

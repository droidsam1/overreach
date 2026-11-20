import Domain
import Foundation
import Observation
import PresentationKit

/// Connecting Garmin, step by step, with as little for the person to do as Garmin allows (ADR-0022): open the key
/// page, create and copy a key, paste it. The app checks the key, saves it securely and imports the last 60 days on its
/// own. Also the Garmin section of Settings: status, sync now, key expiry, disconnect.
@MainActor
@Observable
public final class GarminSetupModel {
    public enum Step: Int, CaseIterable, Sendable {
        /// What Garmin adds and how the key is kept.
        case intro
        /// Open Garmin Connect, create the key, copy it.
        case createKey
        /// Paste it (and say which lifetime was picked). Checking it starts on its own.
        case pasteKey
        /// The first import, with progress.
        case syncing
        /// What came in.
        case done
    }

    /// The Garmin Connect page where keys are created (sign-in included).
    public static let keyPageURL = URL(string: "https://connect.garmin.com/app/settings/personalApiToken")
    /// Days before expiry when Settings starts to warn.
    static let expiryWarningDays = 14
    /// Days before expiry when a notification reminds the person (it works with the app closed).
    static let reminderDaysBeforeExpiry = 7
    static let reminderID = "garmin-key-expiry"

    public var isPresented = false
    public private(set) var step: Step = .intro
    /// The lifetime picked in Garmin Connect. The setup recommends one year, so it starts there.
    public var lifetime: GarminKeyLifetime = .recommended
    public private(set) var connection: GarminConnectionInfo?
    public private(set) var isChecking = false
    public private(set) var isSyncing = false
    public private(set) var progress: GarminSyncProgress?
    public private(set) var summary: GarminSyncSummary?
    /// The last problem, in words the person can act on.
    public private(set) var errorMessage: String?
    /// The Garmin page was opened during this setup: the next step can say "back from Garmin".
    public private(set) var hasOpenedGarmin = false

    private let account: any GarminAccount
    private let reminders: (any LocalReminderScheduler)?
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        account: any GarminAccount, reminders: (any LocalReminderScheduler)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current
    ) {
        self.account = account
        self.reminders = reminders
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: Screen state

    public var isConnected: Bool { connection != nil }

    /// "Step 2 of 3" for the steps the person acts on.
    public var stepCounterText: String? {
        let acting: [Step] = [.intro, .createKey, .pasteKey]
        guard let index = acting.firstIndex(of: step) else { return nil }
        return L10n.format("Step {1} of {2}", index + 1, acting.count)
    }

    public var canGoBack: Bool { step == .createKey || step == .pasteKey }

    /// Paste is only possible when nothing is being checked or imported.
    public var canPaste: Bool { step == .pasteKey && !isChecking }

    public var progressText: String? {
        guard let progress, progress.total > 0 else { return nil }
        return L10n.format("Importing your last 60 days… {1} of {2}", progress.completed, progress.total)
    }

    /// "Imported 60 days: 58 nights of HRV, 59 nights of sleep, 12 runs and 20 strength workouts."
    public var summaryText: String? {
        guard let summary else { return nil }
        return L10n.format(
            "Imported {1} days: {2} nights of HRV, {3} nights of sleep, {4} runs and {5} strength workouts.",
            summary.days, summary.hrvNights, summary.sleepNights, summary.runs, summary.strengthWorkouts
        )
    }

    /// Shown when Garmin sent records the app could not read.
    public var driftNotice: String? {
        guard let summary, summary.skippedRecords > 0 else { return nil }
        return L10n.format(
            "{1} records from Garmin could not be read. Garmin may have changed something; the rest was imported.",
            summary.skippedRecords
        )
    }

    /// "Last sync: 20 Nov, 10:30" or "Not synced yet".
    public var lastSyncText: String? {
        guard let connection else { return nil }
        guard let lastSync = connection.lastSync else { return L10n.text("Not synced yet") }
        return L10n.format("Last sync: {1}", lastSync.formatted(date: .abbreviated, time: .shortened))
    }

    public var daysUntilExpiry: Int? {
        guard let connection else { return nil }
        let today = calendar.startOfDay(for: clock())
        let expiry = calendar.startOfDay(for: connection.keyExpiresAt)
        return calendar.dateComponents([.day], from: today, to: expiry).day
    }

    /// "Key valid until 20 Nov 2027".
    public var expiryText: String? {
        connection.map {
            L10n.format("Key valid until {1}", $0.keyExpiresAt.formatted(date: .abbreviated, time: .omitted))
        }
    }

    /// A warning when the key expires soon or has expired; the fix is a new key, which the setup walks through.
    public var expiryWarning: String? {
        guard let days = daysUntilExpiry else { return nil }
        if days < 0 {
            return L10n.text("Your Garmin key has expired. Create a new one to keep importing.")
        }
        guard days <= Self.expiryWarningDays else { return nil }
        return days == 0
            ? L10n.text("Your Garmin key expires today. Create a new one to keep importing.")
            : L10n.format("Your Garmin key expires in {1} days. Create a new one to keep importing.", days)
    }

    /// 1 when the Garmin connection needs attention, for the Settings tab badge.
    public var badgeCount: Int { expiryWarning == nil ? 0 : 1 }

    // MARK: Intents

    public func load() async {
        connection = await account.connection()
        await scheduleExpiryReminder()
    }

    /// Opens the setup at the start, or at the key steps when renewing a key.
    public func start() {
        errorMessage = nil
        summary = nil
        progress = nil
        hasOpenedGarmin = false
        step = isConnected ? .createKey : .intro
        isPresented = true
    }

    public func next() {
        errorMessage = nil
        switch step {
        case .intro: step = .createKey
        case .createKey: step = .pasteKey
        case .pasteKey, .syncing, .done: break
        }
    }

    public func back() {
        errorMessage = nil
        switch step {
        case .createKey: step = .intro
        case .pasteKey: step = .createKey
        case .intro, .syncing, .done: break
        }
    }

    /// The person tapped "Open Garmin Connect". Coming back, the paste step is ready.
    public func openedGarmin() {
        hasOpenedGarmin = true
        step = .pasteKey
    }

    /// Checks the pasted key with Garmin, saves it and starts the first import, with no further taps.
    public func paste(_ text: String) async {
        guard canPaste else { return }
        errorMessage = nil
        isChecking = true
        defer { isChecking = false }
        do throws(GarminAccountError) {
            try await account.connect(key: text, lifetime: lifetime)
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        connection = await account.connection()
        await scheduleExpiryReminder()
        step = .syncing
        await sync()
        step = .done
    }

    /// "Sync now" in Settings, and the first import in the setup.
    public func sync() async {
        guard !isSyncing else { return }
        errorMessage = nil
        isSyncing = true
        progress = nil
        defer { isSyncing = false }
        do throws(GarminAccountError) {
            summary = try await account.sync { [weak self] progress in
                Task { @MainActor in self?.progress = progress }
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
        connection = await account.connection()
    }

    public func finish() {
        isPresented = false
    }

    public func disconnect() async {
        await account.disconnect()
        connection = nil
        summary = nil
        await reminders?.cancel(id: Self.reminderID)
    }

    /// A notification at 10:00 a week before the key expires, so the person renews it before imports stop. A key
    /// already that close to expiry is covered by the warning in Settings instead.
    private func scheduleExpiryReminder() async {
        guard let reminders, let connection else { return }
        let day = calendar.date(
            byAdding: .day, value: -Self.reminderDaysBeforeExpiry, to: calendar.startOfDay(for: connection.keyExpiresAt)
        )
        guard let day, let date = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day), date > clock()
        else { return }
        await reminders.schedule(
            id: Self.reminderID, at: date,
            title: L10n.text("Your Garmin key expires in a week"),
            body: L10n.text("Create a new one in Settings → Garmin to keep importing. It takes the same three steps.")
        )
    }

    // MARK: Messages

    static func message(for error: GarminAccountError) -> String {
        switch error {
        case .keyLooksWrong:
            L10n.text("That doesn't look like a key. In Garmin Connect, copy the key itself, then paste it here.")
        case .keyRejected:
            L10n.text(
                "Garmin didn't accept this key. It may be incomplete, deleted or expired: create a new one and paste it."
            )
        case .offline:
            L10n.text("No internet connection. Check it and try again.")
        case .rateLimited:
            L10n.text("Garmin asks to wait a little. Try again in a few minutes.")
        case .garminUnavailable:
            L10n.text("Garmin isn't answering right now. Try again later; nothing was lost.")
        case .storageFailed:
            L10n.text("The key couldn't be saved securely on this iPhone. Try again.")
        case .notConnected:
            L10n.text("Connect your Garmin account first.")
        }
    }
}

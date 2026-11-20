import Domain
import Foundation
import SettingsPresentation
import Testing

/// A Garmin account that accepts one key and imports a fixed summary.
private actor FakeGarminAccount: GarminAccount {
    var info: GarminConnectionInfo?
    var connectError: GarminAccountError?
    var syncError: GarminAccountError?
    var connectedWith: (key: String, lifetime: GarminKeyLifetime)?
    var syncs = 0
    var disconnected = false
    let now: Date

    init(info: GarminConnectionInfo? = nil, connectError: GarminAccountError? = nil, now: Date) {
        self.info = info
        self.connectError = connectError
        self.now = now
    }

    func setSyncError(_ error: GarminAccountError?) { syncError = error }

    func connection() -> GarminConnectionInfo? { info }

    func connect(key: String, lifetime: GarminKeyLifetime) throws(GarminAccountError) {
        if let connectError { throw connectError }
        connectedWith = (key, lifetime)
        info = GarminConnectionInfo(
            connectedAt: now, keyExpiresAt: now.addingTimeInterval(Double(lifetime.rawValue) * 86_400)
        )
    }

    func sync(
        progress: @escaping @Sendable (GarminSyncProgress) -> Void
    ) throws(GarminAccountError) -> GarminSyncSummary {
        syncs += 1
        if let syncError { throw syncError }
        progress(GarminSyncProgress(completed: 6, total: 6))
        info?.lastSync = now
        return GarminSyncSummary(days: 60, hrvNights: 58, sleepNights: 59, runs: 12, strengthWorkouts: 20)
    }

    func disconnect() {
        disconnected = true
        info = nil
    }
}

private actor ReminderSpy: LocalReminderScheduler {
    var scheduled: [String: Date] = [:]
    var titles: [String] = []
    var cancelled: [String] = []

    func schedule(id: String, at date: Date, title: String, body: String) {
        scheduled[id] = date
        titles.append(title)
    }

    func cancel(id: String) {
        cancelled.append(id)
        scheduled[id] = nil
    }
}

private let now = Date(timeIntervalSince1970: 1_795_000_000)

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
    return calendar
}()

@MainActor
@Suite("Garmin setup")
struct GarminSetupModelTests {
    private func model(_ account: FakeGarminAccount) -> GarminSetupModel {
        GarminSetupModel(account: account, clock: { now }, calendar: calendar)
    }

    @Test func aNewConnectionWalksThreeStepsThenImportsOnItsOwn() async throws {
        let account = FakeGarminAccount(now: now)
        let setup = model(account)
        await setup.load()
        setup.start()

        #expect(setup.isPresented)
        #expect(setup.step == .intro)
        #expect(setup.stepCounterText == "Step 1 of 3")
        setup.next()
        #expect(setup.step == .createKey)
        setup.openedGarmin()  // tapping "Open Garmin Connect" moves on, ready for the paste
        #expect(setup.step == .pasteKey)
        #expect(setup.lifetime == .oneYear)  // the recommended lifetime is preselected

        await setup.paste("pasted-key-0123456789")

        #expect(await account.connectedWith?.key == "pasted-key-0123456789")
        #expect(await account.connectedWith?.lifetime == .oneYear)
        #expect(await account.syncs == 1)  // no extra tap to import
        #expect(setup.step == .done)
        #expect(setup.isConnected)
        #expect(
            setup.summaryText
                == "Imported 60 days: 58 nights of HRV, 59 nights of sleep, 12 runs and 20 strength workouts."
        )
        #expect(setup.errorMessage == nil)
        setup.finish()
        #expect(!setup.isPresented)
    }

    @Test func aRejectedKeyStaysOnThePasteStepWithAFix() async {
        let setup = model(FakeGarminAccount(connectError: .keyRejected, now: now))
        setup.start()
        setup.next()
        setup.next()

        await setup.paste("wrong-key-0123456789")

        #expect(setup.step == .pasteKey)
        #expect(setup.errorMessage?.contains("create a new one") == true)
        #expect(!setup.isConnected)
        #expect(setup.canPaste)  // try again at once
    }

    @Test func everyErrorHasAnActionableMessage() async {
        let errors: [GarminAccountError] = [
            .keyLooksWrong, .keyRejected, .offline, .rateLimited, .garminUnavailable, .storageFailed, .notConnected,
        ]
        for error in errors {
            let setup = model(FakeGarminAccount(connectError: error, now: now))
            setup.start()
            setup.next()
            setup.next()
            await setup.paste("key-0123456789abcdef")
            #expect(!(setup.errorMessage ?? "").isEmpty)
        }
    }

    @Test func aFailedFirstImportStillConnectsAndCanBeRetried() async {
        let account = FakeGarminAccount(now: now)
        await account.setSyncError(.rateLimited)
        let setup = model(account)
        setup.start()
        setup.next()
        setup.next()

        await setup.paste("pasted-key-0123456789")

        #expect(setup.isConnected)
        #expect(setup.step == .done)
        #expect(setup.errorMessage?.contains("wait") == true)
        await account.setSyncError(nil)
        await setup.sync()
        #expect(setup.errorMessage == nil)
        #expect(setup.summaryText != nil)
    }

    @Test func settingsShowsLastSyncAndExpiry() async {
        let info = GarminConnectionInfo(
            connectedAt: now, keyExpiresAt: now.addingTimeInterval(200 * 86_400), lastSync: nil
        )
        let setup = model(FakeGarminAccount(info: info, now: now))
        await setup.load()

        #expect(setup.isConnected)
        #expect(setup.lastSyncText == "Not synced yet")
        #expect(setup.expiryText?.hasPrefix("Key valid until") == true)
        #expect(setup.expiryWarning == nil)
        #expect(setup.badgeCount == 0)
    }

    @Test func aKeyAboutToExpireIsPointedOutAndRenewalSkipsTheIntro() async {
        let soon = GarminConnectionInfo(connectedAt: now, keyExpiresAt: now.addingTimeInterval(5 * 86_400))
        let setup = model(FakeGarminAccount(info: soon, now: now))
        await setup.load()

        #expect(setup.expiryWarning == "Your Garmin key expires in 5 days. Create a new one to keep importing.")
        #expect(setup.badgeCount == 1)
        setup.start()
        #expect(setup.step == .createKey)
    }

    @Test func anExpiredKeySaysSo() async {
        let expired = GarminConnectionInfo(connectedAt: now, keyExpiresAt: now.addingTimeInterval(-86_400))
        let setup = model(FakeGarminAccount(info: expired, now: now))
        await setup.load()

        #expect(setup.expiryWarning == "Your Garmin key has expired. Create a new one to keep importing.")
    }

    @Test func disconnecting() async {
        let account = FakeGarminAccount(
            info: GarminConnectionInfo(connectedAt: now, keyExpiresAt: now.addingTimeInterval(86_400 * 30)), now: now
        )
        let setup = model(account)
        await setup.load()

        await setup.disconnect()

        #expect(await account.disconnected)
        #expect(!setup.isConnected)
        #expect(setup.lastSyncText == nil)
    }

    @Test func goingBackAndForth() {
        let setup = model(FakeGarminAccount(now: now))
        setup.start()
        #expect(!setup.canGoBack)
        setup.next()
        #expect(setup.canGoBack)
        setup.back()
        #expect(setup.step == .intro)
    }

    @Test func connectingSchedulesAReminderAWeekBeforeTheKeyExpires() async throws {
        let reminders = ReminderSpy()
        let setup = GarminSetupModel(
            account: FakeGarminAccount(now: now), reminders: reminders, clock: { now }, calendar: calendar
        )
        setup.start()
        setup.next()
        setup.next()
        setup.lifetime = .days90

        await setup.paste("pasted-key-0123456789")

        let date = try #require(await reminders.scheduled["garmin-key-expiry"])
        let expiry = calendar.startOfDay(for: now.addingTimeInterval(90 * 86_400))
        let expected = try #require(calendar.date(
            bySettingHour: 10, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -7, to: expiry) ?? expiry
        ))
        #expect(date == expected)
        #expect(await reminders.titles == ["Your Garmin key expires in a week"])
    }

    @Test func aKeyAlreadyCloseToExpiryReliesOnTheSettingsWarning() async {
        let reminders = ReminderSpy()
        let soon = GarminConnectionInfo(connectedAt: now, keyExpiresAt: now.addingTimeInterval(3 * 86_400))
        let setup = GarminSetupModel(
            account: FakeGarminAccount(info: soon, now: now), reminders: reminders, clock: { now }, calendar: calendar
        )

        await setup.load()

        #expect(await reminders.scheduled.isEmpty)
        #expect(setup.expiryWarning != nil)
    }

    @Test func disconnectingCancelsTheReminder() async {
        let reminders = ReminderSpy()
        let info = GarminConnectionInfo(connectedAt: now, keyExpiresAt: now.addingTimeInterval(200 * 86_400))
        let setup = GarminSetupModel(
            account: FakeGarminAccount(info: info, now: now), reminders: reminders, clock: { now }, calendar: calendar
        )
        await setup.load()
        #expect(await reminders.scheduled["garmin-key-expiry"] != nil)

        await setup.disconnect()

        #expect(await reminders.cancelled == ["garmin-key-expiry"])
        #expect(await reminders.scheduled.isEmpty)
    }
}

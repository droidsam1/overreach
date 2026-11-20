import Domain
import Foundation
import Testing
import TodayPresentation

private actor DaysSource: MetricsSource {
    nonisolated let kind: DataSourceKind
    let days: [DailyMetrics]

    init(kind: DataSourceKind = .appleHealth, days: [DailyMetrics]) {
        self.kind = kind
        self.days = days
    }

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private actor GarminStub: GarminAccount {
    let connected: Bool
    init(connected: Bool) { self.connected = connected }
    func connection() -> GarminConnectionInfo? {
        connected ? GarminConnectionInfo(connectedAt: .distantPast, keyExpiresAt: .distantFuture) : nil
    }
    func connect(key: String, lifetime: GarminKeyLifetime) throws(GarminAccountError) {}
    func sync(
        progress: @escaping @Sendable (GarminSyncProgress) -> Void
    ) throws(GarminAccountError) -> GarminSyncSummary { GarminSyncSummary() }
    func disconnect() {}
}

private actor ProfileStub: ProfileRepository {
    let stored: AthleteProfile
    init(_ stored: AthleteProfile) { self.stored = stored }
    func profile() -> AthleteProfile { stored }
    func save(_ profile: AthleteProfile) {}
}

@MainActor
@Suite("Today shows what the connected sources measure")
struct TodaySourcesTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, _ change: (inout DailyMetrics) -> Void) -> DailyMetrics {
        var metrics = DailyMetrics(
            day: CalendarDay(now, calendar: calendar).adding(days: offset, calendar: calendar), sources: [.appleHealth]
        )
        change(&metrics)
        return metrics
    }

    @Test func anIPhoneAloneShowsStepsOnlyNoEmptyTiles() async {
        let source = DaysSource(days: [day(0) { $0.steps = 8_000 }])
        let model = TodayModel(sources: [source], calendar: calendar)
        await model.load(now: now)

        #expect(model.showsSteps)
        #expect(!model.showsHRV && !model.showsSleep && !model.showsRestingHeartRate)
        #expect(!model.showsBodyBattery && !model.showsStress && !model.showsVO2Max)
        #expect(model.showsMetrics)
    }

    @Test func anAppleWatchShowsHRVSleepAndRestingHRWithoutGarminTiles() async {
        let source = DaysSource(days: [day(0) {
            $0.steps = 9_000
            $0.sleepSeconds = 7 * 3_600
            $0.hrvNightlyAverageMs = 48
            $0.restingHeartRate = 52
        }])
        let model = TodayModel(sources: [source], calendar: calendar)
        await model.load(now: now)

        #expect(model.showsHRV && model.showsSleep && model.showsRestingHeartRate && model.showsSteps)
        #expect(!model.showsBodyBattery && !model.showsStress)
    }

    @Test func aMetricMissingTodayButMeasuredThisWeekKeepsItsTile() async {
        let source = DaysSource(days: [day(-2) { $0.hrvNightlyAverageMs = 45 }, day(0) { $0.steps = 100 }])
        let model = TodayModel(sources: [source], calendar: calendar)
        await model.load(now: now)

        #expect(model.showsHRV)
        #expect(model.hrvMs == nil)  // "–" today, with the 7-day average below
        #expect(model.hrvCaption != nil)
    }

    @Test func garminAddsItsOwnTilesAndHealthFillsTheRest() async {
        let health = DaysSource(days: [day(0) { $0.steps = 7_000 }])
        var garminDay = day(0) {
            $0.hrvNightlyAverageMs = 40
            $0.bodyBatteryHigh = 80
            $0.averageStress = 25
        }
        garminDay.sources = [.garmin]
        let garmin = DaysSource(kind: .garmin, days: [garminDay])
        let model = TodayModel(sources: [garmin, health], calendar: calendar)
        await model.load(now: now)

        #expect(model.showsHRV && model.showsBodyBattery && model.showsStress && model.showsSteps)
        #expect(model.sourcesText?.contains("Garmin") == true)
    }

    @Test func someoneWithAGarminWhoHasNotConnectedItIsOfferedTo() async {
        let source = DaysSource(days: [day(0) { $0.steps = 100 }])
        let model = TodayModel(
            sources: [source], garmin: GarminStub(connected: false),
            profiles: ProfileStub(AthleteProfile(wearables: [.garmin])), calendar: calendar
        )
        await model.load(now: now)
        #expect(model.showsConnectGarmin)

        let connected = TodayModel(
            sources: [source], garmin: GarminStub(connected: true),
            profiles: ProfileStub(AthleteProfile(wearables: [.garmin])), calendar: calendar
        )
        await connected.load(now: now)
        #expect(!connected.showsConnectGarmin)
    }

    @Test func anAppleWatchUserWithDataIsNotNaggedAboutGarmin() async {
        let source = DaysSource(days: [day(0) { $0.hrvNightlyAverageMs = 50 }])
        let model = TodayModel(
            sources: [source], garmin: GarminStub(connected: false),
            profiles: ProfileStub(AthleteProfile(wearables: [.appleWatch])), calendar: calendar
        )
        await model.load(now: now)
        #expect(!model.showsConnectGarmin)
    }

    @Test func withNoDataAtAllGarminIsOfferedAlongsideAppleHealth() async {
        let model = TodayModel(
            sources: [DaysSource(days: [])], garmin: GarminStub(connected: false), calendar: calendar
        )
        await model.load(now: now)
        #expect(!model.showsMetrics)
        #expect(model.showsConnectHealth)
        #expect(model.showsConnectGarmin)
    }
}

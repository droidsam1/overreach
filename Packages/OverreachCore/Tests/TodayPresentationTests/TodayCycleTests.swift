import Domain
import Foundation
import Testing
import TodayPresentation

private actor MetricsStub: MetricsSource {
    nonisolated let kind: DataSourceKind = .garmin
    let days: [DailyMetrics]
    init(_ days: [DailyMetrics]) { self.days = days }
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private actor CycleStub: CycleSource {
    let events: [MenstrualEvent]
    private(set) var reads = 0
    init(_ events: [MenstrualEvent]) { self.events = events }
    func menstrualEvents(in range: ClosedRange<CalendarDay>) async throws -> [MenstrualEvent] {
        reads += 1
        return events.filter { range.contains($0.day) }
    }
}

private actor ProfileStub: ProfileRepository {
    let stored: AthleteProfile
    init(_ stored: AthleteProfile) { self.stored = stored }
    func profile() -> AthleteProfile { stored }
    func save(_ profile: AthleteProfile) {}
}

/// Today reads menstrual flow for a natural cycle and shows the phase-aware comparison (`cycle-phase-baselines`).
@MainActor
@Suite("Today with a natural cycle")
struct TodayCycleTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    /// Cycles of 27, 29, 28, 26 and 30 days; today is cycle day 22 (luteal). Luteal nights: +4 bpm, −10 % RMSSD.
    private let starts = [-161, -134, -105, -77, -51, -21]

    private var events: [MenstrualEvent] {
        starts.flatMap { start in
            (0..<5).map {
                MenstrualEvent(
                    day: today.adding(days: start + $0, calendar: calendar), flow: .medium, source: .appleHealth
                )
            }
        }
    }

    private var metrics: [DailyMetrics] {
        let wobble: [Double] = [0, 2, -1, 1, -2]
        return (0...165).map { age in
            let next = (starts + [7]).first { $0 > -age } ?? 7
            let luteal = next + age <= 14
            var day = DailyMetrics(day: today.adding(days: -age, calendar: calendar), sources: [.garmin])
            day.hrvRMSSDMs = (luteal ? 54 : 60) + wobble[age % wobble.count]
            day.restingHeartRate = luteal ? 54 : 50
            day.sleepSeconds = 7.5 * 3_600
            return day
        }
    }

    private func model(_ mode: CycleTrackingMode, cycle: CycleStub) -> TodayModel {
        TodayModel(
            sources: [MetricsStub(metrics)], profiles: ProfileStub(AthleteProfile(cycleTracking: mode)), cycle: cycle,
            calendar: calendar
        )
    }

    @Test func aNaturalCycleComparesWithTheSameWindowOfPreviousCycles() async {
        let cycle = CycleStub(events)
        let model = model(.naturalCycle, cycle: cycle)
        await model.load(now: now)

        #expect(model.readinessLevel == .green)
        #expect(model.readinessLines.map(\.text) == ["Compared with your luteal days in the last 2 cycles."])
        #expect(model.readinessLines.first?.evidence == "moderate evidence")
        #expect(await cycle.reads == 1)
        #expect(!model.readinessLines.contains { $0.text.localizedCaseInsensitiveContains("ovulat") })
    }

    @Test func otherModesNeverReadCycleData() async {
        let cycle = CycleStub(events)
        let model = model(.hormonalContraception, cycle: cycle)
        await model.load(now: now)

        #expect(await cycle.reads == 0)
        // The whole-cycle baseline reads the normal luteal week as low HRV.
        #expect(model.readinessLevel == .amber)
    }
}

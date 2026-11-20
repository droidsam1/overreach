import Analytics
import Domain
import Foundation
import Testing

@Suite("Easy running advice")
struct EasyRunAdvisorTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 20)
    private var now: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3_600) }

    private func run(daysAgo: Int, minutes: Double, source: DataSourceKind = .garmin, id: String = "1") -> RunActivity {
        RunActivity(id: id, source: source, startedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3_600),
                    durationSeconds: minutes * 60, distanceMeters: 4_000)
    }

    private func decision(
        level: ReadinessLevel = .amber, reasons: [ReadinessReason] = [.shortSleep(hours: 5)],
        plan: PlannedRun? = nil, runs: [RunActivity], withMetrics: Bool = true, painFree: Bool = false
    ) -> EasyRunAdvisor.Decision? {
        var metrics = DailyMetrics(day: today)
        metrics.sleepSeconds = (level == .green ? 8 : 5) * 3_600
        return EasyRunAdvisor.advise(
            goal: RunningGoal(distanceMeters: 5_000, targetSeconds: 900, aimsForPainFree: painFree),
            targetDay: nil, planned: plan, readiness: Readiness(level: level, reasons: reasons),
            metrics: withMetrics ? metrics : nil, runs: runs, now: now, calendar: calendar
        )
    }

    @Test func adjustsIntervalsFromActualRecentRunsAndThePlannedDuration() {
        let plan = PlannedRun(day: today, purpose: .intervals, durationMinutes: 24)
        let runs = [run(daysAgo: 2, minutes: 40), run(daysAgo: 4, minutes: 35, id: "2"),
                    run(daysAgo: 2, minutes: 40, source: .appleHealth, id: "mirror")]
        #expect(decision(plan: plan, runs: runs) == .example(minutes: 18, plan: plan, isToday: true, recentRuns: 2))
        #expect(decision(level: .green, reasons: [], plan: plan, runs: runs) == nil)
    }

    @Test func protectsRestAndCompetition() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        #expect(decision(plan: PlannedRun(day: today, purpose: .rest), runs: []) == .plannedRest)
        #expect(decision(plan: PlannedRun(day: tomorrow, purpose: .race), runs: []) == .nearEvent)
        #expect(decision(level: .red, runs: [run(daysAgo: 1, minutes: 40)]) == nil)
    }

    @Test func anOptionalRunLeavesRoomForTomorrowsQualitySession() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let plan = PlannedRun(day: tomorrow, purpose: .intervals, durationMinutes: 45)
        #expect(decision(level: .green, reasons: [], plan: plan, runs: [run(daysAgo: 2, minutes: 40)])
            == .example(minutes: 15, plan: plan, isToday: false, recentRuns: 1))
    }

    @Test func asksForUsableRecoveryAndRecentRunningBeforeSuggestingMinutes() {
        let recent = [run(daysAgo: 1, minutes: 40)]
        #expect(decision(runs: recent, withMetrics: false) == nil)
        #expect(decision(runs: [run(daysAgo: 15, minutes: 40)]) == nil)
        #expect(decision(runs: recent + [run(daysAgo: 0, minutes: 30, id: "today")]) == nil)
        #expect(decision(runs: recent, painFree: true) == .example(minutes: 20, plan: nil, isToday: false, recentRuns: 1))
        #expect(decision(reasons: [.highSoreness(score: 3)], runs: recent) == nil)
    }
}

import Analytics
import Domain
import Foundation
import Testing
import TrainingServices

@Suite("Sleep and training timing")
struct SleepTrainingTimingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private func day(_ number: Int) -> CalendarDay {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: number)) ?? .distantPast
        return CalendarDay(date, calendar: calendar)
    }

    private func at(_ number: Int, _ hour: Double) -> Date {
        day(number).startDate(in: calendar).addingTimeInterval(hour * 3_600)
    }

    private var now: Date { at(26, 12) }

    private func night(waking number: Int) -> DailyMetrics {
        var metrics = DailyMetrics(day: day(number), sources: [.appleHealth])
        metrics.sleepSeconds = 8 * 3_600
        metrics.sleepStart = at(number, -1)
        metrics.sleepEnd = at(number, 7)
        return metrics
    }

    private func session(_ number: Int, rpe: Double?) -> StrengthSession {
        StrengthSession(
            name: "Gym", startedAt: at(number, 21.5), endedAt: at(number, 22.5), sessionRPE: rpe
        )
    }

    @Test func nightsAndSessionsInsideTheWindowAreCounted() {
        let metrics = (1...26).map(night(waking:))
        let report = SleepTrainingTiming.report(
            metrics: metrics, sessions: (20...25).map { session($0, rpe: 6) }, runs: [], recordings: [], now: now,
            calendar: calendar
        )
        #expect(report.nights == 26)
        #expect(report.sessions == 6)
        #expect(abs((report.usualBedtime ?? 0) - 23 * 60) < 0.01)
    }

    @Test func nightsWithoutTimesAreSkipped() {
        var untimed = night(waking: 25)
        untimed.sleepStart = nil
        let report = SleepTrainingTiming.report(
            metrics: [untimed], sessions: [], runs: [], recordings: [], now: now, calendar: calendar
        )
        #expect(report.nights == 0)
    }

    @Test func hardSessionsAreRPEEightOrRacesOrHardTrainingEffect() {
        let metrics = (10...26).map(night(waking:))
        let race = RunActivity(
            id: "race", source: .garmin, startedAt: at(19, 21.5), durationSeconds: 3_000, distanceMeters: 10_000,
            kind: .race
        )
        var intervals = RunActivity(
            id: "intervals", source: .garmin, startedAt: at(18, 21.5), durationSeconds: 3_000, distanceMeters: 9_000
        )
        intervals.anaerobicTrainingEffect = 3
        let easy = RunActivity(
            id: "easy", source: .garmin, startedAt: at(17, 8), durationSeconds: 3_000, distanceMeters: 8_000
        )
        let report = SleepTrainingTiming.report(
            metrics: metrics, sessions: [session(24, rpe: 8), session(25, rpe: 7)], runs: [race, intervals, easy],
            recordings: [], now: now, calendar: calendar
        )
        #expect(report.sessions == 5)
        #expect(report.hardSessions == 3)
        #expect(report.hardSessionsNearBed == 3)
    }

    @Test func aWatchRecordingOfALoggedSessionCountsOnce() {
        let logged = session(25, rpe: 8)
        let recording = RecordedStrengthActivity(
            id: "watch", source: .garmin, startedAt: at(25, 21.6), durationSeconds: 3_000
        )
        let report = SleepTrainingTiming.report(
            metrics: [], sessions: [logged], runs: [], recordings: [recording], now: now, calendar: calendar
        )
        #expect(report.sessions == 1)
    }

    @Test func dataBeforeTheWindowIsIgnored() {
        let report = SleepTrainingTiming.report(
            metrics: [night(waking: -5)], sessions: [session(-5, rpe: 9)], runs: [], recordings: [], now: now,
            calendar: calendar
        )
        #expect(report.nights == 0 && report.sessions == 0)
    }
}

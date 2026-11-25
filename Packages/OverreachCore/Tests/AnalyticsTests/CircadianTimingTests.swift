@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Circadian timing")
struct CircadianTimingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// November 2026: the 2nd is a Monday, the 7th and 8th a weekend.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    /// A night that ends on `wakeDay` at `wake`, starting at `bed` the evening before (or after midnight if < 12 h).
    private func night(wakeDay: Int, bed: (Int, Int), wake: (Int, Int)) -> CircadianTiming.Span {
        let bedDay = bed.0 < 12 ? wakeDay : wakeDay - 1
        return .init(start: date(bedDay, bed.0, bed.1), end: date(wakeDay, wake.0, wake.1))
    }

    private func session(_ day: Int, _ start: Int, hours: Int = 1, hard: Bool = false) -> CircadianTiming.Span {
        .init(start: date(day, start), end: date(day, start + hours), isHard: hard)
    }

    @Test func steadyScheduleHasNoInsights() {
        let nights = (3...16).map { night(wakeDay: $0, bed: (23, 0), wake: (7, 0)) }
        let report = CircadianTiming.analyze(nights: nights, sessions: [], calendar: calendar)
        #expect(abs((report.usualBedtime ?? 0) - 23 * 60) < 0.01)
        #expect((report.bedtimeSpread ?? 99) < 1)
        #expect(report.insights.isEmpty)
    }

    @Test func bedtimesAcrossMidnightAverageAroundMidnight() {
        let nights = (3...12).map {
            night(wakeDay: $0, bed: $0.isMultiple(of: 2) ? (23, 50) : (0, 10), wake: (7, 30))
        }
        let report = CircadianTiming.analyze(nights: nights, sessions: [], calendar: calendar)
        let bedtime = report.usualBedtime ?? 720
        #expect(bedtime < 5 || bedtime > 1435)
        #expect((report.bedtimeSpread ?? 99) < 20)
        #expect(report.insights.isEmpty)
    }

    @Test func irregularBedtimeIsFlagged() {
        let bedtimes = [(21, 30), (1, 30), (23, 0), (2, 0), (22, 0), (0, 45), (23, 30), (3, 0)]
        let nights = bedtimes.enumerated().map { night(wakeDay: $0.offset + 3, bed: $0.element, wake: (8, 0)) }
        let report = CircadianTiming.analyze(nights: nights, sessions: [], calendar: calendar)
        #expect(report.insights.contains { if case .irregularBedtime = $0 { true } else { false } })
    }

    @Test func tooFewNightsGiveNoStatistics() {
        let nights = (3...6).map { night(wakeDay: $0, bed: (23, 0), wake: (7, 0)) }
        let report = CircadianTiming.analyze(nights: nights, sessions: [], calendar: calendar)
        #expect(report.usualBedtime == nil)
        #expect(report.insights.isEmpty)
    }

    @Test func weekendLieInIsSocialJetlag() {
        let nights = (3...16).map { day -> CircadianTiming.Span in
            [7, 8, 14, 15].contains(day)
                ? night(wakeDay: day, bed: (1, 30), wake: (10, 0))
                : night(wakeDay: day, bed: (23, 0), wake: (7, 0))
        }
        let report = CircadianTiming.analyze(nights: nights, sessions: [], calendar: calendar)
        #expect((report.weekendShift ?? 0) > 60)
        #expect(report.insights.contains { if case .socialJetlag = $0 { true } else { false } })
    }

    @Test func hardSessionsEndingJustBeforeBedAreFlagged() {
        let nights = (3...16).map { night(wakeDay: $0, bed: (23, 0), wake: (7, 0)) }
        let late = (3...6).map { CircadianTiming.Span(start: date($0, 21, 30), end: date($0, 22, 30), isHard: true) }
        let report = CircadianTiming.analyze(
            nights: nights, sessions: late + [session(7, 17, hard: true)], calendar: calendar)
        #expect(report.hardSessionsNearBed == 4)
        #expect(report.insights.contains(.hardSessionsNearBed(count: 4, total: 5)))
    }

    @Test func hardSessionsTwoHoursBeforeBedAreNotFlagged() {
        let nights = (3...16).map { night(wakeDay: $0, bed: (23, 0), wake: (7, 0)) }
        let sessions = (3...8).map {
            CircadianTiming.Span(start: date($0, 19, 30), end: date($0, 20, 45), isHard: true)
        }
        let report = CircadianTiming.analyze(nights: nights, sessions: sessions, calendar: calendar)
        #expect(report.hardSessionsNearBed == 0)
        #expect(report.insights.isEmpty)
    }

    @Test func scatteredTrainingTimeNeedsEnoughSessions() {
        let sessions = [6, 12, 19, 7, 21, 13].enumerated().map { session($0.offset + 2, $0.element) }
        let flagged = CircadianTiming.analyze(nights: [], sessions: sessions, calendar: calendar)
        #expect(flagged.insights.contains { if case .variableTrainingTime = $0 { true } else { false } })
        let few = CircadianTiming.analyze(nights: [], sessions: Array(sessions.prefix(3)), calendar: calendar)
        #expect(few.insights.isEmpty)
    }

    @Test func steadyTrainingTimeIsNotFlagged() {
        let sessions = (2...9).map { session($0, 18) }
        let report = CircadianTiming.analyze(nights: [], sessions: sessions, calendar: calendar)
        #expect(abs((report.usualTrainingStart ?? 0) - 18 * 60) < 0.01)
        #expect(report.insights.isEmpty)
    }
}

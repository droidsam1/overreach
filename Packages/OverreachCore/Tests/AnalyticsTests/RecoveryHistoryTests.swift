import Analytics
import Domain
import Foundation
import Testing

@Suite("Last recovery")
struct RecoveryHistoryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()
    private let today = CalendarDay(year: 2026, month: 11, day: 21)

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }

    private func period(_ start: Int, _ end: Int, confirmed: Bool) -> DetectedDeload {
        DetectedDeload(start: day(start), end: day(end), reason: .noTraining, needsConfirmation: !confirmed)
    }

    @Test func aDeloadWeekCountsFromItsLastDay() {
        let last = RecoveryHistory.lastRecovery(
            deloads: [DeloadRecord(start: day(-20), days: 7)], detected: [], before: today, calendar: calendar
        )
        #expect(last == LastRecovery(lastDay: day(-14), kind: .deloadWeek, firstDay: day(-20)))
    }

    @Test func theLatestOfADeloadWeekAndAConfirmedBreakWins() {
        let deloads = [DeloadRecord(start: day(-60), days: 7), DeloadRecord(start: day(-40), days: 7)]
        let last = RecoveryHistory.lastRecovery(
            deloads: deloads, detected: [period(-20, -12, confirmed: true), period(-9, -3, confirmed: false)],
            before: today, calendar: calendar
        )
        #expect(last == LastRecovery(lastDay: day(-12), kind: .detectedBreak, firstDay: day(-20)))
    }

    @Test func aDeloadWeekInProgressIsNotFinishedYet() {
        var profile = AthleteProfile()
        profile.deloads = [DeloadRecord(start: day(-30), days: 7), DeloadRecord(start: day(-2), days: 7)]

        #expect(RecoveryHistory.deloadInProgress(profile, on: today, calendar: calendar)?.start == day(-2))
        #expect(RecoveryHistory.lastRecovery(
            deloads: profile.deloads, detected: [], before: today, calendar: calendar
        )?.lastDay == day(-24))
    }

    @Test func nothingBeforeTodayMeansNoRecovery() {
        #expect(RecoveryHistory.lastRecovery(deloads: [], detected: [], before: today, calendar: calendar) == nil)
    }
}

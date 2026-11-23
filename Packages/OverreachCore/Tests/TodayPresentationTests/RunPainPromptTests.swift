import Domain
import Foundation
import PresentationKit
import Testing

@testable import TodayPresentation

@Suite("Run pain prompt")
struct RunPainPromptTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(_ id: String, hoursAgo: Double) -> RunActivity {
        RunActivity(id: id, source: .garmin, startedAt: now.addingTimeInterval(-hoursAgo * 3_600),
                    durationSeconds: 1_800, distanceMeters: 5_000)
    }

    private func next(_ runs: [RunActivity], _ reports: [RunPainReport] = []) -> RunPainPrompt? {
        RunPainPrompt.next(runs: runs, reports: reports, now: now, calendar: calendar, format: Format())
    }

    @Test func asksAboutARecentRunWithoutAPlan() {
        let prompt = next([run("a", hoursAgo: 3)])
        #expect(prompt?.question == .severity)
        #expect(prompt?.report.activityID == "a")
    }

    @Test func doesNotAskAgainOnceAnswered() {
        var report = RunPainReport(run("a", hoursAgo: 3))
        report.answer(during: 0, after: 0, settledByMorning: nil)
        #expect(next([run("a", hoursAgo: 3)], [report]) == nil)
    }

    @Test func ignoresRunsOlderThanYesterday() {
        #expect(next([run("old", hoursAgo: 72)]) == nil)
    }

    @Test func asksAboutTheMorningTheDayAfterAPainfulRun() {
        var report = RunPainReport(run("a", hoursAgo: 30))
        report.answer(during: 2, after: 3, settledByMorning: nil)
        #expect(next([run("a", hoursAgo: 30)], [report])?.question == .settled)
        // The same evening it is too early to say whether the pain settled by morning.
        var sameDay = RunPainReport(run("b", hoursAgo: 1))
        sameDay.answer(during: 2, after: 3, settledByMorning: nil)
        #expect(next([run("b", hoursAgo: 1)], [sameDay]) == nil)
    }
}

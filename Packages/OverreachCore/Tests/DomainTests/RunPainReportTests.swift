import Domain
import Foundation
import Testing

@Suite("Run pain report")
struct RunPainReportTests {
    private let run = RunActivity(id: "a", source: .garmin, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                  durationSeconds: 1_800, distanceMeters: 5_000)

    @Test func severityIsClampedAndFollowsTheYesNoAnswers() {
        var report = RunPainReport(run)
        report.answer(during: -2, after: 14, settledByMorning: true)
        #expect(report.severityDuring == 0)
        #expect(report.severityAfter == 10)
        #expect(report.painDuring == false)
        #expect(report.painAfter == true)
    }

    @Test func noPainNeedsNoMorningAnswer() {
        var report = RunPainReport(run)
        report.answer(during: 0, after: 0, settledByMorning: false)
        #expect(report.settledByMorning == nil)
        #expect(report.isTolerated())
    }

    @Test func onlyMildPainThatSettledIsTolerated() {
        var report = RunPainReport(run)
        report.answer(during: 3, after: 1, settledByMorning: true)
        #expect(report.isTolerated())
        report.answer(during: 4, after: 1, settledByMorning: true)
        #expect(!report.isTolerated())
        #expect(report.isTolerated(threshold: 5))
        report.answer(during: 2, after: 1, settledByMorning: nil)
        #expect(!report.isTolerated())
    }

    @Test func aYesNoAnswerKeepsTheCautiousReading() {
        var report = RunPainReport(run)
        report.painAfter = true
        #expect(!report.isTolerated())
        report.painAfter = false
        #expect(report.isTolerated())
    }

    @Test func aGoalStoresOneReportPerRunAndDecodesWithoutThem() throws {
        var goal = TrainingGoal(kind: .hybrid)
        var report = RunPainReport(run)
        report.answer(during: 5, after: 5, settledByMorning: false)
        goal.record(report)
        report.answer(during: 1, after: 0, settledByMorning: true)
        goal.record(report)
        #expect(goal.runPainReports == [report])
        let decoded = try JSONDecoder().decode(TrainingGoal.self, from: JSONEncoder().encode(goal))
        #expect(decoded.runPainReports == [report])
        let json = Data(#"{"kind":"hybrid","priorityLifts":[]}"#.utf8)
        let older = try JSONDecoder().decode(TrainingGoal.self, from: json)
        #expect(older.runPainReports.isEmpty)
    }
}

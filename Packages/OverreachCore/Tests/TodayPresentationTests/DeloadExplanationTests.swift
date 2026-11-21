@testable import Analytics
import Domain
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation
import TrainingServices

struct DeloadExplanationTests {
    private static let stall = DeloadSignal.liftsStalled(count: 2, mainLifts: true)
    private static let drop = DeloadSignal.performanceDrop(lifts: 2)
    private static let effort = DeloadSignal.rpeCreep(lifts: 2)
    private static let load = DeloadSignal.weeklyLoadSpike(ratio: 1.6)
    private static let sleep = DeloadSignal.shortSleep(nights: 5)

    @Test(arguments: [
        ([stall, sleep], "Some lifts have stopped progressing and recent recovery signs support a lighter week."),
        ([stall, load, sleep], "Some lifts have stopped progressing and your training load rose sharply this week."),
        ([effort, load], "The same weights feel harder on several lifts."),
        ([drop, load], "Your estimated maxes have dropped on several lifts."),
        ([stall, drop, sleep], "Your estimated maxes have dropped on several lifts."),
        ([stall, effort], "Some lifts have stopped progressing and the same weights feel harder."),
        ([drop, effort], "Your estimated maxes have dropped and the same weights feel harder."),
        ([stall, drop, effort], "Your estimated maxes have dropped and the same weights feel harder."),
    ])
    func summary(signals: [DeloadSignal], expected: String) {
        #expect(DeloadExplanation.summary(for: signals) == expected)
    }

    @Test func detailShowsEverySignalAndOneEntryPerEvidenceKey() {
        let signals: [DeloadSignal] = [
            .hrvSuppressed(days: 5), Self.stall, Self.drop, Self.effort, .weeksSinceDeload(8), Self.load,
            .restingHeartRateElevated(days: 4), Self.sleep, .poorWellbeing(checkIns: 3),
        ]
        let proposal = DeloadProposal(signals: signals, stalledExerciseIDs: [], score: 6, plan: .standard)
        let calendar = Calendar(identifier: .gregorian)
        let end = CalendarDay(year: 2026, month: 8, day: 22)
        let format = Format(locale: Locale(identifier: "en_US"))
        let assessment = DeloadAssessment.proposed(
            proposal, walkingIncluded: false, lastRecovery: LastRecovery(lastDay: end, kind: .detectedBreak)
        )
        let advice = DeloadAdvice.make(assessment, exercises: [], calendar: calendar, format: format)
        guard case let .proposed(detail) = advice.state else {
            Issue.record("Expected a proposal explanation")
            return
        }

        #expect(detail.trainingReasons == [
            "2 main lifts have stalled.",
            "Estimated maxes dropped on 2 lifts this month.",
            "The same weights feel harder on 2 lifts (RPE up).",
            "8 weeks since your last strength rest period.",
            "Training load rose fast this week (1.6× your usual).",
        ])
        #expect(detail.recoveryReasons == [
            "Your 7-day HRV average was below your usual range on 5 of the last 7 days.",
            "Resting HR above your usual on 4 of the last 7 days.",
            "Less than 6 h of sleep on 5 of the last 7 nights.",
            "Low energy or sore in 3 check-ins this week.",
        ])
        #expect(detail.lastRest == "Your last strength rest period ended on Aug 22, 2026.")
        #expect(detail.evidence.map(\.id) == [
            "deload-design", "deload-recovery-signals", "rpe-creep", "deload-practice", "weekly-load-change",
        ])
        #expect(detail.evidence.allSatisfy { !$0.text.isEmpty && !$0.level.isEmpty })
    }
}

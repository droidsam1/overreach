import Analytics
import Foundation
import PresentationKit
import Testing
@testable import TrendsPresentation

@Suite("Sleep and training times card")
struct SleepTimingCardTests {
    private let spanish = Format(locale: Locale(identifier: "es_ES"))

    private func report(
        nights: Int = 14, bedtime: Double? = 23 * 60, wake: Double? = 7 * 60, sessions: Int = 0,
        training: Double? = nil, insights: [CircadianTiming.Insight] = []
    ) -> CircadianTiming.Report {
        CircadianTiming.Report(
            nights: nights, usualBedtime: bedtime, usualWake: wake, bedtimeSpread: nil, wakeSpread: nil,
            midpointSpread: nil, regularityIndex: nil, weekendShift: nil, sessions: sessions,
            usualTrainingStart: training, trainingSpread: nil, hardSessions: 0, hardSessionsNearBed: 0,
            insights: insights
        )
    }

    @Test func hiddenWithoutEnoughNightsOrSessions() {
        #expect(SleepTimingCard(report(nights: 4, bedtime: nil, wake: nil, sessions: 3)) == nil)
    }

    @Test func regularScheduleShowsOnlyTheNeutralSummary() throws {
        let card = try #require(SleepTimingCard(report(sessions: 6, training: 18 * 60 + 30), format: spanish))
        #expect(card.rows.map(\.label) == ["Usual bedtime", "Usual wake time", "Usual training start"])
        #expect(card.rows.map(\.value) == ["23:00", "7:00", "18:30"])
        #expect(card.summary == "Your sleep and training times look steady.")
        #expect(card.observations.isEmpty)
        #expect(card.footnote == "From the last 28 days: 14 nights, 6 sessions. Observations, not a diagnosis.")
    }

    @Test func sessionsAloneShowTheTrainingTime() throws {
        let card = try #require(
            SleepTimingCard(report(nights: 2, bedtime: nil, wake: nil, sessions: 5, training: 7 * 60), format: spanish)
        )
        #expect(card.rows.map(\.label) == ["Usual training start"])
    }

    @Test func irregularSleepIsWordedAsLongTermHealth() throws {
        let card = try #require(
            SleepTimingCard(report(insights: [.irregularSleep(regularityIndex: 52, midpointSpreadMinutes: 95)]))
        )
        let observation = try #require(card.observations.first)
        #expect(observation.text.contains("regularity 52 of 100"))
        #expect(observation.text.contains("long-term health risk"))
        #expect(observation.evidenceText == "Evidence: limited evidence")
        #expect(card.summary == nil)
    }

    @Test func irregularSleepWithoutIndexNamesTheMidpointShift() throws {
        let card = try #require(
            SleepTimingCard(report(insights: [.irregularSleep(regularityIndex: nil, midpointSpreadMinutes: 92)]))
        )
        #expect(card.observations.first?.text.contains("about 1 h 30 min") == true)
    }

    @Test func socialJetlagMentionsShiftWork() throws {
        let card = try #require(SleepTimingCard(report(insights: [.socialJetlag(minutes: 120)])))
        let text = try #require(card.observations.first?.text)
        #expect(text.contains("about 2 h later"))
        #expect(text.contains("shift work"))
        #expect(card.observations.first?.evidenceText == "Evidence: limited evidence")
    }

    @Test func variableTrainingTimeRanksNoTimeOfDay() throws {
        let card = try #require(SleepTimingCard(report(insights: [.variableTrainingTime(spreadMinutes: 150)])))
        let text = try #require(card.observations.first?.text)
        #expect(text.contains("about 2 h 30 min"))
        #expect(text.contains("no time of day is better"))
    }

    @Test func hardSessionsNearBedSuggestFinishingEarlier() throws {
        let card = try #require(SleepTimingCard(report(insights: [.hardSessionsNearBed(count: 3, total: 5)])))
        let observation = try #require(card.observations.first)
        #expect(observation.text.hasPrefix("3 of 5 hard sessions"))
        #expect(observation.evidenceText == "Evidence: moderate evidence")
    }

    @Test func durationsRoundToFiveMinutes() {
        #expect(SleepTimingCard.duration(43, format: spanish) == "45 min")
        #expect(SleepTimingCard.duration(61, format: spanish) == "1 h")
        #expect(SleepTimingCard.duration(2, format: spanish) == "5 min")
    }
}

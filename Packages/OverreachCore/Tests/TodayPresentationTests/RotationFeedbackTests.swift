import Domain
import Foundation
import Testing

@testable import TodayPresentation

@MainActor
@Suite("Opt-in rotation feedback")
struct RotationFeedbackTests {
    private let day = CalendarDay(year: 2026, month: 11, day: 25)

    @Test func storesNothingBeforeOptInAndClearsTheHistoryWhenDisabled() {
        var saved: [RotationFeedback.State] = []
        let feedback = RotationFeedback { saved.append($0) }

        feedback.shown(.swap, on: day)
        feedback.chose(.accepted, for: .swap, on: day)
        #expect(saved.isEmpty)
        #expect(feedback.recentEntries.isEmpty)

        feedback.setEnabled(true)
        feedback.shown(.swap, on: day)
        feedback.setEnabled(false)

        #expect(feedback.recentEntries.isEmpty)
        #expect(saved.last == .init())
    }

    @Test func deduplicatesOffersAndRestoresChoiceAndOutcome() throws {
        var saved = RotationFeedback.State()
        let feedback = RotationFeedback { saved = $0 }
        feedback.setEnabled(true)
        feedback.shown(.swap, on: day)
        feedback.shown(.swap, on: day)
        feedback.chose(.keptPlan, for: .swap, on: day)
        let entry = try #require(feedback.recentEntries.first)
        feedback.rate(.unnecessary, for: entry.id)
        feedback.report(.completed, for: entry.id)

        let restored = RotationFeedback(try JSONDecoder().decode(
            RotationFeedback.State.self, from: JSONEncoder().encode(saved)
        ))
        #expect(restored.isEnabled)
        #expect(restored.recentEntries.count == 1)
        #expect(restored.recentEntries.first?.choice == .keptPlan)
        #expect(restored.recentEntries.first?.usefulness == .unnecessary)
        #expect(restored.recentEntries.first?.outcome == .completed)
    }
}

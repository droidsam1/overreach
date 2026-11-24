import Foundation
import Testing
@testable import PresentationKit

@MainActor
struct SectionHintsTests {
    @Test func seedsAvailableSectionsAndShowsASectionOnlyOnItsFirstAppearance() {
        let hints = SectionHints()
        #expect(hints.update([.recovery], on: .today).isEmpty)
        #expect(hints.update([], on: .today).isEmpty)
        #expect(hints.update([.recovery, .history], on: .today) == ["New: History"])
        #expect(hints.update([.recovery, .history], on: .today).isEmpty)
        #expect(hints.update([], on: .today).isEmpty)
        #expect(hints.update([.history], on: .today).isEmpty)
    }

    @Test func keepsSeededAndShownSectionsAcrossLaunches() throws {
        var saved: SectionHints.State?
        let hints = SectionHints { saved = $0 }
        #expect(hints.update([], on: .recoveryProgress).isEmpty)
        #expect(hints.update([.recentLoad], on: .recoveryProgress) == ["New: Recent load"])

        let data = try JSONEncoder().encode(try #require(saved))
        let restored = SectionHints(try JSONDecoder().decode(SectionHints.State.self, from: data))
        #expect(restored.update([.recentLoad, .progress], on: .recoveryProgress) == ["New: Progress"])
        #expect(restored.update([.history], on: .today).isEmpty)
    }

    @Test func doesNotRepeatRecoveryOnTheOtherScreen() {
        let hints = SectionHints()
        #expect(hints.update([], on: .today).isEmpty)
        #expect(hints.update([], on: .recoveryProgress).isEmpty)
        #expect(hints.update([.recovery], on: .today) == ["New: Recovery"])
        #expect(hints.update([.recovery], on: .recoveryProgress).isEmpty)
    }
}

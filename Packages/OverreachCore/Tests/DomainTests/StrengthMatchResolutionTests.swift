import Domain
import Foundation
import Testing

struct StrengthMatchResolutionTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func undoKeepsTheRecordingSeparateUntilItIsLinkedOrAllowedAgain() {
        let first = StrengthSession(name: "Upper", startedAt: start, endedAt: start.addingTimeInterval(600))
        let second = StrengthSession(name: "Lower", startedAt: start, endedAt: start.addingTimeInterval(600))
        let recording = RecordedStrengthActivity(id: "1", source: .garmin, startedAt: start, durationSeconds: 600)
        let pair = StrengthMatchPair(sessionID: first.id, recordingID: StrengthRecordingID(recording))

        let ambiguous = StrengthActivityMatching.resolve(
            sessions: [first, second], activities: [recording], choices: [:]
        )
        #expect(ambiguous.candidates.count == 2)
        #expect(ambiguous.matches.unmatched == [recording])

        let linked = StrengthActivityMatching.resolve(
            sessions: [first, second], activities: [recording], choices: [pair: .linked]
        )
        #expect(linked.matches.bySession == [first.id: recording])

        let undone = StrengthActivityMatching.resolve(
            sessions: [first, second], activities: [recording], choices: [pair: .separate]
        )
        #expect(undone.matches.bySession.isEmpty)
        #expect(undone.matches.unmatched == [recording])
        #expect(undone.candidates.first { $0.pair == pair }?.isSeparate == true)
    }

    @Test func savedLinkUsesTheOriginalSourceAndReservesTheSessionWhenUnavailable() throws {
        let session = StrengthSession(name: "Lower", startedAt: start)
        let garmin = RecordedStrengthActivity(
            id: "1", source: .garmin, startedAt: start.addingTimeInterval(-86_400), durationSeconds: 600
        )
        let health = RecordedStrengthActivity(id: "1", source: .appleHealth, startedAt: start, durationSeconds: 600)
        let pair = StrengthMatchPair(sessionID: session.id, recordingID: StrengthRecordingID(garmin))
        let saved = try JSONEncoder().encode([pair: StrengthMatchChoice.linked])
        let choices = try JSONDecoder().decode([StrengthMatchPair: StrengthMatchChoice].self, from: saved)

        let missing = StrengthActivityMatching.resolve(sessions: [session], activities: [health], choices: choices)
        #expect(missing.matches.bySession.isEmpty)
        #expect(missing.matches.unmatched == [health])

        let restored = StrengthActivityMatching.resolve(
            sessions: [session], activities: [health, garmin], choices: choices
        )
        #expect(restored.matches.activity(for: session.id) == garmin)
        #expect(restored.matches.unmatched == [health])
    }
}

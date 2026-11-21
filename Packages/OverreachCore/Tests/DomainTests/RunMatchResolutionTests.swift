import Domain
import Foundation
import Testing

@Suite("Run match review")
struct RunMatchResolutionTests {
    private func run(_ id: String, _ source: DataSourceKind, offset: TimeInterval = 0) -> RunActivity {
        RunActivity(
            id: id, source: source, startedAt: Date(timeIntervalSince1970: 86_400 + offset),
            durationSeconds: 1_800, distanceMeters: 5_000
        )
    }

    @Test func competingOverlapsKeepEveryOriginalUntilReviewed() {
        let watch = run("shared", .garmin, offset: -60)
        let copy = run("shared", .appleHealth, offset: 30)
        let other = run("other", .appleHealth, offset: 120)
        let pair = RunMatchPair(garminID: watch.id, appleHealthID: copy.id)

        let forward = RunDeduplication.resolve([watch, copy, other], choices: [:])
        let reverse = RunDeduplication.resolve([other, copy, watch], choices: [:])
        #expect(forward.runs.count == 3)
        #expect(forward.candidates.count == 2)
        #expect(forward.candidates.map(\.pair) == reverse.candidates.map(\.pair))

        let confirmed = RunDeduplication.resolve([watch, copy, other], choices: [pair: .linked])
        #expect(confirmed.runs.count == 2)
        #expect(confirmed.runs.first?.match == pair)
        #expect(confirmed.runs.first?.sources == [.garmin, .appleHealth])

        let missingCopy = RunDeduplication.resolve([watch, other], choices: [pair: .linked])
        #expect(missingCopy.runs.count == 2)
        #expect(missingCopy.candidates.isEmpty)
    }

    @Test func separationOverridesAutomaticLinkAndCanBeCleared() {
        let watch = run("g", .garmin, offset: -60)
        let copy = run("h", .appleHealth, offset: 30)
        let pair = RunMatchPair(garminID: watch.id, appleHealthID: copy.id)
        let separated = RunDeduplication.resolve([watch, copy], choices: [pair: .separate])
        #expect(separated.runs.count == 2)
        #expect(separated.candidates.first?.isSeparate == true)
        #expect(RunDeduplication.resolve([watch, copy], choices: [:]).runs.first?.match == pair)
    }
}

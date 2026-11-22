import Domain
import Foundation
import Testing

@Suite("Companion walk matching")
struct CompanionWalkMatchingTests {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func walk(
        _ minute: Double, _ minutes: Double, source: DataSourceKind = .garmin
    ) -> WalkBout {
        WalkBout(start: origin.addingTimeInterval(minute * 60), durationSeconds: minutes * 60, source: source)
    }

    private func tagged(_ walks: [WalkBout]) -> [Bool] { walks.map { $0.companion == .dog } }

    @Test func aYesTagsTheWalkAsManualAndANoLeavesItUntagged() {
        let walks = [walk(0, 30), walk(120, 30), walk(240, 30)]
        let answers = [WalkCompanionAnswer(walk: walks[0], withCompanion: true),
                       WalkCompanionAnswer(walk: walks[1], withCompanion: false)]
        let result = CompanionWalkMatching.tagging(walks, answers: answers)
        #expect(tagged(result) == [true, false, false])
        #expect(result[0].companionSource == .manual)
    }

    @Test func aYesCoversTheCopyFromAnotherSource() {
        let garmin = walk(0, 30, source: .garmin)
        let health = walk(1, 30, source: .appleHealth)
        let answers = [WalkCompanionAnswer(walk: health, withCompanion: true)]
        #expect(tagged(CompanionWalkMatching.tagging([garmin, health], answers: answers)) == [true, true])
    }

    @Test func taggingIsIdempotent() {
        let walks = [walk(0, 30), walk(120, 30)]
        let answers = [WalkCompanionAnswer(walk: walks[0], withCompanion: true)]
        let once = CompanionWalkMatching.tagging(walks, answers: answers)
        #expect(CompanionWalkMatching.tagging(once, answers: answers) == once)
    }

    @Test func aNoOnOneCopyCoversTheOtherSource() {
        let garmin = walk(0, 30, source: .garmin)
        let health = walk(1, 30, source: .appleHealth)
        let answers = [WalkCompanionAnswer(walk: health, withCompanion: false)]
        let result = CompanionWalkMatching.tagging([garmin, health], answers: answers)
        #expect(tagged(result) == [false, false])
    }

    @Test func aNoClearsAnEarlierTag() {
        let before = WalkBout(
            start: origin, durationSeconds: 1_800, source: .garmin, companion: .dog, companionSource: .manual)
        let result = CompanionWalkMatching.tagging(
            [before], answers: [WalkCompanionAnswer(walk: before, withCompanion: false)])
        #expect(result[0].companion == nil)
        #expect(result[0].companionSource == nil)
    }

    @Test func inputOrderDoesNotMatter() {
        let walks = [walk(0, 30), walk(1, 30, source: .appleHealth), walk(200, 40)]
        let answers = [WalkCompanionAnswer(walk: walks[2], withCompanion: true)]
        let forward = CompanionWalkMatching.tagging(walks, answers: answers)
        let backward = CompanionWalkMatching.tagging(walks.reversed(), answers: answers)
        #expect(Set(forward) == Set(backward))
    }

    @Test func olderStoredWalksDecodeWithoutACompanion() throws {
        let json = #"{"start":0,"durationSeconds":1800,"source":"garmin"}"#
        let walk = try JSONDecoder().decode(WalkBout.self, from: Data(json.utf8))
        #expect(walk.companion == nil)
        #expect(walk.companionSource == nil)
        let tag = WalkBout(start: .init(timeIntervalSince1970: 0), durationSeconds: 60, source: .garmin,
                           companion: .dog, companionSource: .manual)
        let again = try JSONDecoder().decode(WalkBout.self, from: JSONEncoder().encode(tag))
        #expect(again == tag)
    }
}

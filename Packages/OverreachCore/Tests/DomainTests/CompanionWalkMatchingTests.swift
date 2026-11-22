import Domain
import Foundation
import Testing

@Suite("Companion walk matching")
struct CompanionWalkMatchingTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func walk(
        _ minute: Double, _ minutes: Double, source: DataSourceKind = .garmin
    ) -> WalkBout {
        WalkBout(start: t0.addingTimeInterval(minute * 60), durationSeconds: minutes * 60, source: source)
    }

    private func window(
        _ minute: Double, _ minutes: Double, _ confidence: CompanionWindow.Confidence = .normal
    ) -> CompanionWindow {
        CompanionWindow(
            start: t0.addingTimeInterval(minute * 60), end: t0.addingTimeInterval((minute + minutes) * 60),
            confidence: confidence)
    }

    private func tagged(_ walks: [WalkBout]) -> [Bool] { walks.map { $0.companion == .dog } }

    @Test(arguments: [
        (0.0, 30.0, true),     // exact
        (5.0, 30.0, true),     // starts 5 min later, 25 of 30 overlap
        (0.0, 12.0, true),     // window inside the walk's start: 12 of 12
        (20.0, 30.0, false),   // starts 20 min apart
        (10.0, 12.0, true),    // starts 10 min apart, window fully inside the walk
        (11.0, 12.0, false),   // starts 11 min apart
        (9.0, 30.0, true),     // 21 of 30 = 70 %
    ])
    func overlapTable(offset: Double, length: Double, expected: Bool) {
        let result = CompanionWalkMatching.tagging([walk(0, 30)], windows: [window(offset, length)])
        #expect(tagged(result) == [expected])
        if expected { #expect(result[0].companionSource == .trackerExport) }
    }

    @Test func halfTheShorterIntervalIsEnough() {
        let result = CompanionWalkMatching.tagging([walk(8, 20)], windows: [window(0, 16)])
        #expect(tagged(result) == [true])  // overlap 8 of 16 = 50 %
        let less = CompanionWalkMatching.tagging([walk(9, 20)], windows: [window(0, 16)])
        #expect(tagged(less) == [false])  // 7 of 16
    }

    @Test func lowConfidenceNeedsSeventyPercent() {
        let walks = [walk(0, 30)]
        // Window 10–40 against walk 0–30: 20 of 30 = 67 %.
        #expect(tagged(CompanionWalkMatching.tagging(walks, windows: [window(10, 30, .low)])) == [false])
        #expect(tagged(CompanionWalkMatching.tagging(walks, windows: [window(10, 30)])) == [true])
        // Window 8–38: 22 of 30 = 73 %.
        #expect(tagged(CompanionWalkMatching.tagging(walks, windows: [window(8, 30, .low)])) == [true])
    }

    @Test func aWindowWithNoWalkCreatesNothing() {
        #expect(CompanionWalkMatching.tagging([], windows: [window(0, 30)]).isEmpty)
        let far = CompanionWalkMatching.tagging([walk(600, 30)], windows: [window(0, 30)])
        #expect(tagged(far) == [false])
    }

    @Test func aWindowTagsOnlyTheBestWalk() {
        let walks = [walk(0, 20), walk(2, 30)]
        let result = CompanionWalkMatching.tagging(walks, windows: [window(2, 30)])
        #expect(tagged(result) == [false, true])  // overlap 30 min beats 18 min
    }

    @Test func tiesGoToTheEarlierStartWhateverTheOrder() {
        let early = walk(0, 20, source: .garmin)
        let late = walk(5, 20, source: .appleHealth)
        // Window 2.5–22.5 overlaps both walks by the same 17.5 min.
        let symmetric = window(2.5, 20)
        let forward = CompanionWalkMatching.tagging([early, late], windows: [symmetric])
        let backward = CompanionWalkMatching.tagging([late, early], windows: [symmetric])
        #expect(forward.first { $0.start == early.start }?.companion == .dog)
        #expect(backward.first { $0.start == early.start }?.companion == .dog)
        #expect(forward.first { $0.start == late.start }?.companion == .dog)  // same walk, other source
    }

    @Test func twoWindowsInsideOneLongWalkTagItOnce() {
        let result = CompanionWalkMatching.tagging([walk(0, 60)], windows: [window(0, 20), window(25, 20)])
        // The second window starts 25 min after the walk: too far apart to match.
        #expect(tagged(result) == [true])
        #expect(result.count == 1)
    }

    @Test func duplicateWindowsAreIdempotent() {
        let once = CompanionWalkMatching.tagging([walk(0, 30), walk(120, 30)], windows: [window(0, 30)])
        let twice = CompanionWalkMatching.tagging(once, windows: [window(0, 30), window(0, 30)])
        #expect(once == twice)
        #expect(tagged(twice) == [true, false])
    }

    @Test func manualNoBeatsAWindowAndManualYesIsManual() {
        let walks = [walk(0, 30), walk(120, 30)]
        let answers = [WalkCompanionAnswer(walk: walks[0], withCompanion: false),
                       WalkCompanionAnswer(walk: walks[1], withCompanion: true)]
        let result = CompanionWalkMatching.tagging(walks, answers: answers, windows: [window(0, 30), window(120, 30)])
        #expect(tagged(result) == [false, true])
        #expect(result[1].companionSource == .manual)
    }

    @Test func aNoOnOneCopyCoversTheOtherSource() {
        let garmin = walk(0, 30, source: .garmin)
        let health = walk(1, 30, source: .appleHealth)
        let answers = [WalkCompanionAnswer(walk: health, withCompanion: false)]
        let result = CompanionWalkMatching.tagging([garmin, health], answers: answers, windows: [window(0, 30)])
        #expect(tagged(result) == [false, false])
    }

    @Test func aNoClearsAnEarlierTag() {
        let before = WalkBout(
            start: t0, durationSeconds: 1_800, source: .garmin, companion: .dog, companionSource: .trackerExport)
        let result = CompanionWalkMatching.tagging(
            [before], answers: [WalkCompanionAnswer(walk: before, withCompanion: false)])
        #expect(result[0].companion == nil)
        #expect(result[0].companionSource == nil)
    }

    @Test func midnightAndDaylightSavingAreJustDates() {
        // 2026-03-29 00:30 UTC to 01:30 UTC straddles the European clock change; the walk crosses midnight UTC.
        let start = Date(timeIntervalSince1970: 1_774_744_200)  // 2026-03-29T00:30:00Z
        let walk = WalkBout(start: start.addingTimeInterval(-3_600), durationSeconds: 7_200, source: .garmin)
        let window = CompanionWindow(start: start.addingTimeInterval(-3_000), end: start.addingTimeInterval(3_000))
        #expect(CompanionWalkMatching.tagging([walk], windows: [window])[0].companion == .dog)
    }

    @Test func inputOrderDoesNotMatter() {
        let walks = [walk(0, 30), walk(1, 30, source: .appleHealth), walk(200, 40)]
        let windows = [window(0, 29), window(200, 40, .low)]
        let a = CompanionWalkMatching.tagging(walks, windows: windows)
        let b = CompanionWalkMatching.tagging(walks.reversed(), windows: windows.reversed())
        #expect(Set(a) == Set(b))
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

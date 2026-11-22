import Analytics
import Domain
import Foundation
import Testing

@Suite("Dog walk suggestion")
struct DogWalkSuggestionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
        return calendar
    }()
    /// Sunday 2026-11-22 12:00 in Madrid.
    private var now: Date { moment(day: 0, hour: 12) }

    private func at(day offset: Int, hour: Double) -> Date {
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_795_305_600))  // 2026-11-22 Madrid
        let base = calendar.date(byAdding: .day, value: offset, to: midnight) ?? midnight
        return calendar.date(byAdding: .minute, value: Int(hour * 60), to: base) ?? base
    }

    private func walk(
        day: Int, hour: Double, minutes: Double = 30, source: DataSourceKind = .garmin
    ) -> WalkBout {
        WalkBout(start: moment(day: day, hour: hour), durationSeconds: minutes * 60, source: source)
    }

    private func yes(_ walks: [WalkBout]) -> [WalkCompanionAnswer] {
        walks.map { WalkCompanionAnswer(walk: $0, withCompanion: true) }
    }

    private func ask(_ walks: [WalkBout], _ answers: [WalkCompanionAnswer] = []) -> [WalkBout] {
        DogWalkSuggestion.walksToAsk(walks: walks, answers: answers, now: now, calendar: calendar)
    }

    /// Morning dog walks at 08:00 on the given days, all confirmed.
    private func mornings(_ days: ClosedRange<Int>, hour: Double = 8) -> [WalkBout] {
        days.map { walk(day: $0, hour: hour) }
    }

    @Test func coldStartAsksOnEveryWalkOfTenMinutes() {
        let walks = [walk(day: -1, hour: 8), walk(day: -1, hour: 15, minutes: 9), walk(day: -1, hour: 19, minutes: 10)]
        #expect(ask(walks).map(\.start) == [walks[0].start, walks[2].start])
    }

    @Test func aWalkAnsweredIsNotAskedAgainAndNoIsKept() {
        let walks = [walk(day: -1, hour: 8), walk(day: -1, hour: 19)]
        let answers = [WalkCompanionAnswer(walk: walks[0], withCompanion: false)]
        #expect(ask(walks, answers).map(\.start) == [walks[1].start])
    }

    @Test func aWalkAlreadyTaggedByAnImportIsNotAsked() {
        var tagged = walk(day: -1, hour: 8)
        tagged.companion = .dog
        tagged.companionSource = .trackerExport
        #expect(ask([tagged]).isEmpty)
    }

    @Test func aGarminAndHealthCopyAreAskedOnceAndAnsweredOnce() {
        let garmin = walk(day: -1, hour: 8, source: .garmin)
        let health = walk(day: -1, hour: 8.05, source: .appleHealth)
        #expect(ask([garmin, health]).map(\.source) == [.garmin])
        let answered = ask([garmin, health], [WalkCompanionAnswer(walk: health, withCompanion: false)])
        #expect(answered.isEmpty)
    }

    @Test func onceLearnedItAsksOnlyNearAUsualSlot() {
        let history = mornings(-12 ... -1)  // 12 confirmed 08:00 walks (cold start over)
        let near = walk(day: 0, hour: 8.5)
        let far = walk(day: 0, hour: 11)
        let result = ask(history + [near, far], yes(history))
        #expect(result.map(\.start) == [near.start])
    }

    @Test func aSlotNeedsThreeConfirmationsInTheLastFourWeeks() {
        // Ten answered walks at 08:00 (cold start over) but only two at 18:00, and some are too old to count.
        let mornings = mornings(-10 ... -1)
        let evenings = [walk(day: -2, hour: 18), walk(day: -3, hour: 18), walk(day: -40, hour: 18)]
        let evening = walk(day: 0, hour: 18)
        let walks = mornings + evenings + [evening]
        #expect(ask(walks, yes(mornings + evenings)).isEmpty)
        let third = walk(day: -4, hour: 18.2)
        #expect(ask(walks + [third], yes(mornings + evenings + [third])).map(\.start) == [evening.start])
    }

    @Test func fiveNoAnswersInASlotStopTheQuestion() {
        let history = mornings(-12 ... -1)
        // The five latest mornings are answered "No".
        let latestNo = (-5 ... -1).map { walk(day: $0, hour: 8) }
        let answers = yes(history.filter { !latestNo.contains($0) })
            + latestNo.map { WalkCompanionAnswer(walk: $0, withCompanion: false) }
        let today = walk(day: 0, hour: 8)
        #expect(ask(history + [today], answers).isEmpty)
        // One "Yes" among the last five lets it ask again.
        let mixed = answers.filter { $0.key != WalkKey(latestNo[0]) } + yes([latestNo[0]])
        #expect(ask(history + [today], mixed).map(\.start) == [today.start])
    }

    @Test func slotsAreTheSameAcrossTheClockChange() {
        // Madrid changed to winter time on 2026-10-25: 08:00 local is a different UTC hour on each side.
        let history = (-30 ... -20).map { walk(day: $0, hour: 8) } + (-6 ... -1).map { walk(day: $0, hour: 8) }
        let today = walk(day: 0, hour: 8.25)
        #expect(ask(history + [today], yes(history)).map(\.start) == [today.start])
    }

    @Test func aSlotAroundMidnightIsOneSlot() {
        let history = (-12 ... -1).map { walk(day: $0, hour: $0 % 2 == 0 ? 23.8 : 0.2) }
        let late = walk(day: 0, hour: 23.9)
        let early = walk(day: 0, hour: 0.5)
        let result = ask(history + [late, early], yes(history))
        #expect(result.map(\.start) == [late.start, early.start].sorted())
    }

    @Test func weekendSlotsAreLearnedApartOnceThereAreEnoughAnswers() {
        // 2026-11-22 is a Sunday. Weekday walks at 08:00; weekend walks at 10:00, ten of them in five weekends.
        func isWeekend(_ day: Int) -> Bool { calendar.isDateInWeekend(moment(day: day, hour: 8)) }
        let weekdays = (-27 ... -1).filter { !isWeekend($0) }.map { walk(day: $0, hour: 8) }
        let weekends = (-36 ... -1).filter(isWeekend).map { walk(day: $0, hour: 10) }
        #expect(weekends.count >= 10)
        let history = weekdays + weekends
        let sundayEight = walk(day: 0, hour: 8)
        let sundayTen = walk(day: 0, hour: 10)
        let result = ask(history + [sundayEight, sundayTen], yes(history))
        #expect(result.map(\.start) == [sundayTen.start])
        // A Monday still follows the weekday slot.
        let mondayStart = moment(day: 1, hour: 8)
        let monday = WalkBout(start: mondayStart, durationSeconds: 1_800, source: .garmin)
        let later = DogWalkSuggestion.walksToAsk(
            walks: history + [monday], answers: yes(history), now: moment(day: 1, hour: 12), calendar: calendar)
        #expect(later.map(\.start) == [monday.start])
    }

    @Test func inputOrderDoesNotMatter() {
        let history = mornings(-12 ... -1)
        let today = [walk(day: 0, hour: 8), walk(day: 0, hour: 11)]
        let forward = ask(history + today, yes(history))
        let backward = ask((history + today).reversed(), yes(history).reversed())
        #expect(forward == backward)
    }
}

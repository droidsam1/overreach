import Domain
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation

private struct StepsSource: MetricsSource {
    let kind = DataSourceKind.garmin
    let days: [DailyMetrics]
    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct WalksSource: ActivitySource {
    let walks: [WalkBout]
    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        [DailyActivity(day: range.upperBound, walks: walks)]
    }
}

private struct DogProfile: ProfileRepository {
    var routine: WalkingRoutine
    func profile() async throws -> AthleteProfile {
        var profile = AthleteProfile()
        profile.walkingRoutine = routine
        return profile
    }
    func save(_ profile: AthleteProfile) async throws {}
}

@MainActor
@Suite("Today: With the dog?")
struct TodayDogWalkTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    private var steps: StepsSource {
        StepsSource(days: (-28...0).map { offset in
            var metrics = DailyMetrics(day: today.adding(days: offset, calendar: calendar), sources: [.garmin])
            metrics.steps = 9_000
            return metrics
        })
    }

    private var recentWalk: WalkBout {
        WalkBout(start: now.addingTimeInterval(-3 * 3_600), durationSeconds: 1_800, source: .garmin)
    }

    private func model(
        routine: WalkingRoutine, walks: [WalkBout], answers: [WalkCompanionAnswer] = [],
        saved: @escaping @MainActor ([WalkCompanionAnswer]) -> Void = { _ in }
    ) -> TodayModel {
        TodayModel(
            sources: [steps], activity: [WalksSource(walks: walks)], profiles: DogProfile(routine: routine),
            dogWalkAnswers: answers, saveDogWalkAnswers: saved, calendar: calendar, format: format
        )
    }

    @Test func asksAboutARecentWalkByTheDogsName() async {
        let model = model(routine: WalkingRoutine(hasDog: true, dogName: " Nanoq "), walks: [recentWalk])
        await model.load(now: now)
        #expect(model.dogWalkQuestion?.text == "With Nanoq?")
        #expect(model.dogWalkQuestion?.walk.start == recentWalk.start)
    }

    @Test func withoutANameItAsksAboutYourDog() async {
        let model = model(routine: WalkingRoutine(hasDog: true), walks: [recentWalk])
        await model.load(now: now)
        #expect(model.dogWalkQuestion?.text == "With your dog?")
    }

    @Test func doesNotAskWithoutADog() async {
        let model = model(routine: WalkingRoutine(), walks: [recentWalk])
        await model.load(now: now)
        #expect(model.dogWalkQuestion == nil)
    }

    @Test func doesNotAskAboutWalksOlderThanTwoDays() async {
        let old = WalkBout(start: now.addingTimeInterval(-72 * 3_600), durationSeconds: 1_800, source: .garmin)
        let model = model(routine: WalkingRoutine(hasDog: true), walks: [old])
        await model.load(now: now)
        #expect(model.dogWalkQuestion == nil)
    }

    @Test func doesNotAskAboutAnAnsweredWalk() async {
        let answered = WalkCompanionAnswer(walk: recentWalk, withCompanion: false)
        let model = model(routine: WalkingRoutine(hasDog: true), walks: [recentWalk], answers: [answered])
        await model.load(now: now)
        #expect(model.dogWalkQuestion == nil)
    }

    @Test func oneTapStoresTheAnswerAndClearsTheQuestion() async {
        var stored: [WalkCompanionAnswer] = []
        let model = model(routine: WalkingRoutine(hasDog: true), walks: [recentWalk]) { stored = $0 }
        await model.load(now: now)
        model.answerDogWalk(withDog: true)
        #expect(stored == [WalkCompanionAnswer(walk: recentWalk, withCompanion: true)])
        #expect(model.dogWalkQuestion == nil)
    }
}

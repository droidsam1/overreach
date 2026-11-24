import Domain
import Fixtures
import Foundation
import HistoryPresentation
import PresentationKit
import Testing

private struct HistoryWalkSource: ActivitySource {
    let walks: [WalkBout]

    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        [DailyActivity(day: range.upperBound, walks: walks)]
    }
}

@MainActor
struct HistoryWalkTests {
    @Test func changingAnAnswerUpdatesBothCopiesAndSurvivesReload() async throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let start = now.addingTimeInterval(-3_600)
        let garmin = WalkBout(start: start, durationSeconds: 900, source: .garmin)
        let health = WalkBout(start: start.addingTimeInterval(60), durationSeconds: 900, source: .appleHealth)
        var profile = AthleteProfile()
        profile.walkingRoutine = WalkingRoutine(hasDog: true, dogName: "Nanoq")
        let store = TestStore()
        try await store.save(profile)
        var saved = [WalkCompanionAnswer(walk: health, withCompanion: true)]
        func load(_ walks: [WalkBout]) async -> HistoryModel {
            let model = HistoryModel(
                workouts: store, exercises: store, routines: store, profiles: store,
                activitySources: [HistoryWalkSource(walks: walks)],
                companionAnswers: DogWalkAnswers(saved) { saved = $0 }, clock: { now }
            )
            await model.load()
            model.activityFilter = .walking
            return model
        }

        let history = await load([garmin, health])
        #expect(history.rows.map(\.id) == [.walk(WalkKey(garmin))])
        #expect(history.walkCompanionDetails[WalkKey(garmin)]?.answer == "Yes")
        history.answerWalk(WalkKey(garmin), withDog: false)
        #expect(history.walkCompanionDetails[WalkKey(garmin)]?.answer == "No")
        let reloaded = await load([health])
        #expect(reloaded.walkCompanionDetails[WalkKey(health)]?.answer == "No")
        #expect(reloaded.walkCompanionDetails[WalkKey(health)]?.showsSuggestion == false)
    }
}

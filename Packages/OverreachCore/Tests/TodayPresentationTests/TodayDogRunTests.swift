import Domain
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation

private struct RecordedRunSource: MetricsSource {
    let kind: DataSourceKind
    let recordedRuns: [RunActivity]

    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        recordedRuns.filter { (start...end).contains($0.startedAt) }
    }
}

private struct RunCompanionProfile: ProfileRepository {
    let routine: WalkingRoutine

    func profile() async throws -> AthleteProfile { AthleteProfile(walkingRoutine: routine) }
    func save(_ profile: AthleteProfile) async throws {}
}

@MainActor
@Suite("Today: Did you run with the dog?")
struct TodayDogRunTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func run(
        source: DataSourceKind = .garmin, id: String = "run", startedHoursAgo: Double = 1
    ) -> RunActivity {
        RunActivity(id: id, source: source, startedAt: now.addingTimeInterval(-startedHoursAgo * 3_600),
                    durationSeconds: 1_800, distanceMeters: 5_000)
    }

    private func model(
        runs: [RunActivity], routine: WalkingRoutine = .init(hasDog: true, dogName: " Nanoq "),
        answers: DogRunAnswers = DogRunAnswers(), choices: [RunMatchPair: RunMatchChoice] = [:]
    ) -> TodayModel {
        let sources = Dictionary(grouping: runs, by: \.source).map { source, runs in
            RecordedRunSource(kind: source, recordedRuns: runs)
        }
        return TodayModel(sources: sources, profiles: RunCompanionProfile(routine: routine),
                          activityMatchChoices: { .init(runs: choices) }, dogRunAnswers: answers)
    }

    @Test func recentUnplannedRunWithoutWalkReadingsAsksByName() async {
        let model = model(runs: [run()])
        await model.load(now: now)
        #expect(model.pendingPrompt == .dogRun)
        #expect(model.dogRunQuestion?.text == "With Nanoq?")
    }

    @Test func noQuestionForOldOrUnfinishedRunsOrWithoutADog() async {
        let model = model(runs: [run(id: "old", startedHoursAgo: 60), run(id: "unfinished", startedHoursAgo: 0.1)])
        await model.load(now: now)
        #expect(model.dogRunQuestion == nil)

        let withoutDog = self.model(runs: [run()], routine: .init())
        await withoutDog.load(now: now)
        #expect(withoutDog.dogRunQuestion == nil)
    }

    @Test(arguments: [false, true])
    func bothAnswersPersistAndDoNotRepeatWhenGarminAddsACopy(_ withDog: Bool) async throws {
        var stored: [DogRunAnswers.Key: Bool] = [:]
        let health = run(source: .appleHealth, id: "health")
        let answers = DogRunAnswers { stored = $0 }
        let first = model(runs: [health], answers: answers)
        await first.load(now: now)
        let question = try #require(first.dogRunQuestion)
        first.answerDogRun(question, withDog: withDog)
        #expect(first.pendingPrompt == nil)
        #expect(stored == [DogRunAnswers.Key(health): withDog])

        let refreshed = model(runs: [health, run()], answers: DogRunAnswers(stored))
        await refreshed.load(now: now)
        #expect(refreshed.dogRunQuestion == nil)
    }

    @Test func aSeparateRunDoesNotInheritTheAnswerFromAnOverlappingRun() async {
        let health = run(source: .appleHealth, id: "health")
        let garmin = run()
        let pair = RunMatchPair(garminID: garmin.id, appleHealthID: health.id)
        let model = model(runs: [health, garmin], answers: DogRunAnswers([.init(health): false]),
                          choices: [pair: .separate])
        await model.load(now: now)
        #expect(model.dogRunQuestion?.run.activity.id == garmin.id)
    }
}

import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation

private struct RecoverySource: MetricsSource {
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

/// Profile questions that moved out of onboarding (ADR-0041, rule 5): when each one is due, and that each is asked
/// once unless it was put off with "Later".
@MainActor
@Suite("Today: profile questions in context")
struct TodayProfileQuestionTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .iso8601)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    private func recovery(hrv: Bool) -> RecoverySource {
        RecoverySource(days: (-6...0).map { offset in
            var metrics = DailyMetrics(day: today.adding(days: offset, calendar: calendar), sources: [.garmin])
            metrics.steps = 9_000
            if hrv { metrics.hrvRMSSDMs = 55 }
            return metrics
        })
    }

    private func walks(_ count: Int) -> [WalkBout] {
        (0..<count).map {
            WalkBout(start: now.addingTimeInterval(-Double($0 + 1) * 86_400), durationSeconds: 1_800, source: .garmin)
        }
    }

    private func model(
        profile: AthleteProfile = AthleteProfile(), hrv: Bool = true, walks count: Int = 0,
        log: ProfileQuestionLog = ProfileQuestionLog()
    ) async -> (TodayModel, TestStore) {
        let store = TestStore()
        try? await store.save(profile)
        let model = TodayModel(
            sources: [recovery(hrv: hrv)], activity: [WalksSource(walks: walks(count))], profiles: store,
            profileQuestions: log, calendar: calendar, format: format
        )
        await model.load(now: now)
        return (model, store)
    }

    // MARK: When each question is due

    @Test func theCycleQuestionIsDueWithRecoveryReadingsAndNoAnswerYet() async {
        let (model, _) = await model()
        #expect(model.profileQuestion?.question == .cycleTracking)
        #expect(model.pendingPrompt == .profileQuestion)
        let ids = model.profileQuestion?.answers.map(\.id)
        #expect(ids == ["naturalCycle", "hormonalContraception", "menopause", "no"])
    }

    @Test func theCycleQuestionWaitsForReadingsThatItWouldChange() async {
        let (model, _) = await model(hrv: false)
        #expect(model.profileQuestion == nil)
    }

    @Test func theCycleQuestionIsNotAskedWhenTheFieldIsAnswered() async {
        for profile in [
            AthleteProfile(sex: .male), AthleteProfile(sex: .female), AthleteProfile(sex: .unspecified),
            AthleteProfile(cycleTracking: .menopause)
        ] {
            let (model, _) = await model(profile: profile)
            #expect(model.profileQuestion == nil)
        }
    }

    @Test func theWalkingQuestionNeedsDetectedWalksAndAnEmptyRoutine() async {
        let known = AthleteProfile(sex: .male)
        let (few, _) = await model(profile: known, hrv: false, walks: 2)
        #expect(few.profileQuestion == nil)

        let (enough, _) = await model(profile: known, hrv: false, walks: 3)
        #expect(enough.profileQuestion?.question == .walkingRoutine)

        for routine in [WalkingRoutine(hasDog: true), WalkingRoutine(usualWalksPerDay: 2)] {
            let (answered, _) = await model(
                profile: AthleteProfile(sex: .male, walkingRoutine: routine), hrv: false, walks: 5
            )
            #expect(answered.profileQuestion == nil)
        }
    }

    @Test func oneQuestionAtATimeTheCycleFirst() async {
        let (model, _) = await model(walks: 5)
        #expect(model.profileQuestion?.question == .cycleTracking)
    }

    // MARK: Asked once

    @Test func anAnswerIsSavedAndNeverAskedAgain() async throws {
        var saved: [ProfileQuestionLog.State] = []
        let log = ProfileQuestionLog { saved.append($0) }
        let (model, store) = await model(log: log)

        #expect(await model.answerProfileQuestion("naturalCycle"))
        #expect(try await store.profile().cycleTracking == .naturalCycle)
        #expect(saved.last?.answered == [.cycleTracking])
        // The prompt stays fixed until the next load, then nothing is left to ask.
        #expect(model.pendingPrompt == nil)
        await model.load(now: now)
        #expect(model.profileQuestion == nil)
    }

    @Test func sayingNoStoresNothingInTheProfileButIsNotAskedAgain() async throws {
        let (model, store) = await model()
        #expect(await model.answerProfileQuestion("no"))
        #expect(try await store.profile() == AthleteProfile())
        await model.load(now: now)
        #expect(model.profileQuestion == nil)
    }

    @Test func aDogAnswerSetsTheRoutineAndUnlocksTheWalkQuestion() async throws {
        let (model, store) = await model(profile: AthleteProfile(sex: .male), hrv: false, walks: 4)
        #expect(model.profileQuestion?.question == .walkingRoutine)
        #expect(await model.answerProfileQuestion("yes"))
        #expect(try await store.profile().walkingRoutine.hasDog)
        await model.load(now: now)
        #expect(model.profileQuestion == nil)
        #expect(model.dogWalkQuestion?.text == "With your dog?")
    }

    @Test func aFailedSaveKeepsTheQuestion() async {
        let (model, store) = await model()
        await store.setFailing(true)
        #expect(await model.answerProfileQuestion("naturalCycle") == false)
        #expect(model.profileQuestion?.question == .cycleTracking)
    }

    @Test func laterHidesItTodayAndAsksAgainTomorrow() async {
        let log = ProfileQuestionLog()
        let (model, _) = await model(log: log)
        model.postponeProfileQuestion()
        #expect(model.pendingPrompt == nil)
        await model.load(now: now)
        #expect(model.profileQuestion == nil)

        let tomorrow = now.addingTimeInterval(86_400)
        await model.load(now: tomorrow)
        #expect(model.profileQuestion?.question == .cycleTracking)
    }

    @Test func theLogRestoresFromWhatWasSaved() async {
        let log = ProfileQuestionLog(.init())
        log.answer(.cycleTracking)
        let restored = ProfileQuestionLog(log.state)
        let (model, _) = await model(log: restored)
        #expect(model.profileQuestion == nil)
    }
}

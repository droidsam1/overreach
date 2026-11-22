import Analytics
import Domain
import Foundation
import Testing
import TrainingServices

@testable import AIExchange

@Suite("Context pack: training done today")
struct ContextTodayTrainingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func today(_ training: DayTraining?) -> ContextPack.Today {
        let record = TrainingRecord(sessions: [], exercises: [], settings: [:])
        return .init(DailyAssessment(record: record, profile: nil, checkIn: nil, now: now), training: training)
    }

    @Test func statesWhatWasTrainedAndTheLegs() {
        let training = today(DayTraining(hasStrength: true, lowerBody: .yesterdayHeavy)).training
        #expect(training == ContextPack.TodayTraining(DayTraining(hasStrength: true, lowerBody: .yesterdayHeavy)))
        #expect(training?.strength == true && training?.run == false)
        #expect(training?.lowerBody == "yesterdayHeavy")
    }

    @Test func omitsTheBlockWhenNothingWasRead() {
        #expect(today(nil).training == nil)
    }
}

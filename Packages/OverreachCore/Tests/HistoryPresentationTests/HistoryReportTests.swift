import Domain
import Fixtures
import Foundation
import HistoryPresentation
import Testing

@MainActor
@Suite("Session report from History")
struct HistoryReportTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func session(daysAgo: Double, reps: [Int]) -> StrengthSession {
        StrengthSession(
            name: "Push", startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            endedAt: now.addingTimeInterval(-daysAgo * 86_400 + 3_600),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: reps.map { WorkoutSet(weightKg: 60, reps: $0, rpe: 8) })]
        )
    }

    @Test func aPastSessionIsComparedWithTheTargetItHadThen() async throws {
        let first = session(daysAgo: 6, reps: [9, 9, 9])
        let second = session(daysAgo: 3, reps: [10, 10, 9])
        let store = TestStore(exercises: [bench], sessions: [first, second])
        let fixedNow = now
        let model = HistoryModel(workouts: store, exercises: store, routines: store, progression: store,
                                 clock: { fixedNow })
        await model.load()

        await model.showReport(for: second.id)

        let report = try #require(model.report)
        #expect(report.title == "Push")
        #expect(report.headline.hasPrefix("60 min · 3 working sets"))
        let row = try #require(report.rows.first)
        #expect(row.outcome == .below)  // the target after 9/9/9 was 10/10/10
        #expect(row.outcomeText == "Below target: 60 kg × 10/10/9 vs 60 kg × 10/10/10")
        #expect(report.comparison?.hasPrefix("Volume +7 % compared with the last “Push”") == true)

        model.report = nil
        #expect(model.report == nil)
    }

    @Test func theFirstSessionHasNoTarget() async throws {
        let only = session(daysAgo: 3, reps: [9, 9, 9])
        let store = TestStore(exercises: [bench], sessions: [only])
        let fixedNow = now
        let model = HistoryModel(workouts: store, exercises: store, routines: store, clock: { fixedNow })
        await model.load()

        await model.showReport(for: only.id)

        #expect(model.report?.rows.first?.outcome == .noTarget)
        #expect(model.report?.adherence == nil)
    }
}

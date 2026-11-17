import Domain
import Fixtures
import Foundation
import PlanPresentation
import Testing

@MainActor
@Suite("PlanModel")
struct PlanModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell, aliases: ["sentadilla"])
    private let bench = Exercise(name: "Bench Press (Barbell)", primaryMuscles: [.chest], equipment: .barbell)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func sessions() -> [StrengthSession] {
        (1...8).map { index in
            StrengthSession(
                name: "Lower",
                startedAt: now.addingTimeInterval(-Double(index) * 3 * 86_400),
                entries: [ExerciseEntry(exerciseID: squat.id, sets: (1...3).map { _ in WorkoutSet(weightKg: 80, reps: 10, rpe: 8) })]
            )
        }
    }

    private func model(history: [StrengthSession] = []) async -> (PlanModel, TestStore) {
        let store = TestStore(exercises: [squat, bench], sessions: history)
        let fixedNow = now
        let model = PlanModel(
            profiles: store, workouts: store, exercises: store, progression: store, clock: { fixedNow }, calendar: calendar
        )
        await model.load()
        return (model, store)
    }

    @Test func goalKindAndPriorityLifts() async throws {
        let (model, store) = await model()
        #expect(model.goalKind == .general)
        #expect(!model.showsPriorityLifts)
        #expect(model.goalOptions.map(\.value) == TrainingGoal.Kind.allCases)

        await model.setGoal(kind: .strength)
        #expect(model.showsPriorityLifts)
        #expect(try await store.profile().goal?.kind == .strength)

        model.priorityLiftSearch = "SENTADILLA"
        #expect(model.priorityLiftRows.map(\.name) == ["Squat (Barbell)"])
        await model.togglePriorityLift(squat.id)
        #expect(model.priorityLiftCount == 1)
        #expect(model.priorityLiftRows.first?.isSelected == true)
    }

    @Test func targetDateToggleKeepsTheChosenDate() async throws {
        let (model, store) = await model()
        #expect(!model.hasTargetDate)
        let chosen = now.addingTimeInterval(70 * 86_400)

        await model.setTargetDate(chosen)
        #expect(model.hasTargetDate)
        #expect(try await store.profile().goal?.targetDate == CalendarDay(chosen, calendar: calendar))

        await model.setHasTargetDate(false)
        #expect(!model.hasTargetDate)
        #expect(try await store.profile().goal?.targetDate == nil)

        await model.setHasTargetDate(true)
        #expect(try await store.profile().goal?.targetDate == CalendarDay(chosen, calendar: calendar))
    }

    @Test func newBlockIsDeclaredAndClampedToTheAllowedLength() async throws {
        let (model, store) = await model(history: sessions())
        model.newBlockFocus = .strength
        model.newBlockWeeks = 40

        await model.startNewBlock()

        let block = try #require(try await store.profile().declaredBlocks.last)
        #expect(block.focus == .strength)
        #expect(block.plannedWeeks == model.newBlockWeeksRange.upperBound)
        #expect(model.currentBlockTitle == "Strength")
        #expect(model.currentBlockStart != nil)
    }

    @Test func detectedBlockAndPlanRowsAreDescribed() async {
        let (model, _) = await model(history: sessions())
        #expect(model.currentBlockTitle?.hasSuffix("(detected)") == true)
        #expect(model.planRows.map(\.id) == Array(0..<model.planRows.count))
        #expect(model.planRows.allSatisfy { !$0.title.isEmpty && $0.weeks > 0 })
        #expect(model.findingLines.allSatisfy { !$0.text.isEmpty && !$0.evidence.isEmpty })
        if let next = model.next {
            #expect(next.headline.contains(" block "))
            #expect(next.reasons.allSatisfy { !$0.evidence.isEmpty })
        }
    }

    @Test func withoutTrainingThereIsNoCurrentBlock() async {
        let (model, _) = await model()
        #expect(model.currentBlockTitle == nil)
    }
}

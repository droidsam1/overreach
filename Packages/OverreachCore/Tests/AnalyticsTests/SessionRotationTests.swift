import Analytics
import Domain
import Foundation
import Testing

@Suite("Session rotation")
struct SessionRotationTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func sessions(_ names: [String], routines: [String: UUID] = [:]) -> [StrengthSession] {
        names.enumerated().map { index, name in
            let started = start.addingTimeInterval(Double(index) * 2 * 86_400)
            return StrengthSession(
                name: name, startedAt: started, endedAt: started.addingTimeInterval(3_600),
                entries: [ExerciseEntry(exerciseID: UUID(), sets: [WorkoutSet(weightKg: 60, reps: 8)])],
                routineID: routines[name]
            )
        }
    }

    @Test func twoFullCyclesGiveTheNextWorkout() throws {
        let rotation = try #require(SessionRotation.detect(in: sessions(["A", "B", "C", "D", "A", "B", "C", "D"])))
        #expect(rotation.next.name == "A")
        #expect(rotation.order.map(\.name) == ["A", "B", "C", "D"])
    }

    @Test func continuesMidCycle() throws {
        let rotation = try #require(
            SessionRotation.detect(in: sessions(["A", "B", "C", "D", "A", "B", "C", "D", "A", "B"]))
        )
        #expect(rotation.next.name == "C")
    }

    @Test func oneCycleIsNotEnoughToGuess() {
        let history = sessions(["A", "B", "C", "D", "A", "B"])
        #expect(SessionRotation.detect(in: history) == nil)
        #expect(SessionRotation.recentWorkouts(in: history).map(\.name) == ["B", "A", "D", "C"])
    }

    @Test func aChangeOfProgramUsesOnlyTheLatestPattern() throws {
        let rotation = try #require(
            SessionRotation.detect(in: sessions(["Push", "Pull", "Legs", "A", "B", "A", "B"]))
        )
        #expect(rotation.order.map(\.name) == ["A", "B"])
    }

    @Test func oneRepeatedWorkoutNeedsThreeSessions() throws {
        #expect(SessionRotation.detect(in: sessions(["Full body", "Full body"])) == nil)
        let history = sessions(["Gym", "Full body", "full body", "Full Body"])
        let rotation = try #require(SessionRotation.detect(in: history))
        #expect(rotation.order.count == 1)
    }

    @Test func routinesMatchByIDAndNamesIgnoreCaseAndAccents() throws {
        let upper = UUID()
        var history = sessions(["Día A", "dia b", "DIA A", "Día B"])
        history[0].routineID = upper
        history[2].routineID = upper
        history[2].name = "Upper (renamed)"
        let rotation = try #require(SessionRotation.detect(in: history))
        #expect(rotation.next.id == upper.uuidString)
    }

    @Test func sessionsWithoutExercisesAreIgnored() throws {
        var history = sessions(["A", "B", "A", "B"])
        history.insert(StrengthSession(name: "Empty", startedAt: start.addingTimeInterval(86_400)), at: 1)
        #expect(SessionRotation.detect(in: history)?.next.name == "A")
    }

    private func swap(_ history: [StrengthSession], at index: Int, from: String, target: String) -> RotationAdjustment {
        RotationAdjustment(
            day: CalendarDay(history[index].startedAt, calendar: .current),
            kind: .swap(from: SessionRotation.slot(for: sessions([from])[0]).id,
                        to: SessionRotation.slot(for: sessions([target])[0]).id)
        )
    }

    @Test func aRecordedSwapKeepsTheRotationDetected() throws {
        let history = sessions(["A", "B", "C", "D", "A", "C", "B", "D", "A", "B", "C", "D"])
        #expect(SessionRotation.detect(in: history) == nil)
        let adjustment = swap(history, at: 5, from: "B", target: "C")
        let rotation = try #require(SessionRotation.detect(in: history, adjustments: [adjustment]))
        #expect(rotation.order.map(\.name) == ["A", "B", "C", "D"])
        #expect(rotation.next.name == "A")
    }

    @Test func aSwapThatIsNotRecordedStillBreaksTheCycle() {
        let history = sessions(["A", "B", "C", "D", "A", "B", "C", "D", "A", "C", "B", "D"])
        let unrelated = RotationAdjustment(day: CalendarDay(year: 2000, month: 1, day: 1), kind: .postpone(days: 1))
        #expect(SessionRotation.detect(in: history, adjustments: [unrelated]) == nil)
    }

    @Test func aSwapHalfDoneNamesTheWorkoutThatReallyComesNext() throws {
        let history = sessions(["A", "B", "C", "D", "A", "B", "C", "D", "A", "C"])
        let adjustment = swap(history, at: 9, from: "B", target: "C")
        let rotation = try #require(SessionRotation.detect(in: history, adjustments: [adjustment]))
        #expect(rotation.next.name == "B")
    }
}

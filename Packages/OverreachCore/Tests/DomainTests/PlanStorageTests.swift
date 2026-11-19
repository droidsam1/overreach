import Domain
import Foundation
import Testing

/// New plan fields are optional in stored data (ADR-0018): data saved before them keeps loading.
@Suite("Stored plans")
struct PlanStorageTests {
    private let squat = UUID()
    private let bench = UUID()

    @Test func routinesSavedBeforePrescriptionsStillLoad() throws {
        let id = UUID()
        let old = #"{"id":"\#(id)","name":"Legs","exerciseIDs":["\#(squat)"]}"#
        let routine = try JSONDecoder().decode(Routine.self, from: Data(old.utf8))
        #expect(routine.id == id)
        #expect(routine.prescriptions.isEmpty)
    }

    @Test func prescriptionsRoundTripAndFollowTheExercises() throws {
        var routine = Routine(name: "Upper", exerciseIDs: [bench, squat], prescriptions: [
            RoutinePrescription(exerciseID: squat, scheme: .linearLoad(sets: 5, reps: 5, targetRPE: 8)),
            RoutinePrescription(exerciseID: UUID(), scheme: .linearLoad(sets: 1, reps: 1, targetRPE: 8)),  // not in it
            RoutinePrescription(exerciseID: squat, scheme: .linearLoad(sets: 3, reps: 3, targetRPE: 8)),  // last wins
        ])
        #expect(routine.prescriptions == [
            RoutinePrescription(exerciseID: squat, scheme: .linearLoad(sets: 3, reps: 3, targetRPE: 8)),
        ])
        let decoded = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(routine))
        #expect(decoded == routine)

        routine.setExercises([bench])
        #expect(routine.prescription(for: squat) == nil)
    }

    @Test func blocksSavedBeforePlansStillLoad() throws {
        let old = #"{"focus":"strength","start":{"year":2026,"month":9,"day":1},"plannedWeeks":6,"isDeclared":true}"#
        let block = try JSONDecoder().decode(TrainingBlock.self, from: Data(old.utf8))
        #expect(block.name == nil)
        #expect(block.routineIDs.isEmpty)
        #expect(block.end(calendar: Calendar(identifier: .gregorian)) == CalendarDay(year: 2026, month: 10, day: 13))
    }

    @Test func sessionsRememberTheirRoutine() throws {
        let routineID = UUID()
        let session = StrengthSession(name: "Upper", startedAt: Date(timeIntervalSince1970: 0), routineID: routineID)
        let decoded = try JSONDecoder().decode(StrengthSession.self, from: JSONEncoder().encode(session))
        #expect(decoded.routineID == routineID)
    }
}

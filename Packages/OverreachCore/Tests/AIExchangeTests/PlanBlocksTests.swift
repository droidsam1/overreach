import AIExchange
import Domain
import Foundation
import Testing

@Suite("AI plans with blocks and per-routine prescriptions")
struct PlanBlocksTests {
    private let bench = Exercise(name: "Bench Press (Barbell)", primaryMuscles: [.chest], equipment: .barbell)
    private let row = Exercise(name: "Bent Over Row (Barbell)", primaryMuscles: [.back], equipment: .barbell)
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let today = CalendarDay(year: 2026, month: 11, day: 19)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// A year in three blocks, as the issue's example asks: strength first, hypertrophy second, then hybrid.
    private let yearPlan = """
        {"format": "overreach.plan", "version": 1, "startDate": "2027-01-04",
         "routines": [
           {"id": "upper-s", "name": "Upper (strength)",
            "exercises": ["Bench Press (Barbell)", "Bent Over Row (Barbell)"],
            "prescriptions": [{"exercise": "Bench Press (Barbell)",
                               "scheme": {"type": "rpeBased", "sets": 5, "reps": 3, "targetRPE": 8}}]},
           {"id": "lower-s", "name": "Lower (strength)", "exercises": ["Squat (Barbell)"],
            "prescriptions": [{"exercise": "Squat (Barbell)",
                               "scheme": {"type": "linearLoad", "sets": 5, "reps": 5}}]},
           {"id": "full-h", "name": "Full body (hypertrophy)",
            "exercises": ["Squat (Barbell)", "Bench Press (Barbell)", "Bent Over Row (Barbell)"],
            "prescriptions": [{"exercise": "Bench Press (Barbell)",
                               "scheme": {"type": "doubleProgression", "sets": 3, "minReps": 8, "maxReps": 12}}]}
         ],
         "blocks": [
           {"name": "Strength", "focus": "strength", "weeks": 16, "routines": ["upper-s", "lower-s"]},
           {"name": "Hypertrophy", "focus": "hypertrophy", "weeks": 20, "routines": ["Full body (hypertrophy)"]},
           {"focus": "mixed", "weeks": 16, "routines": ["upper-s", "full-h"]}
         ]}
        """

    private func importing(_ text: String, routines: [Routine] = []) throws -> PlanImport {
        let message = try PlanMessageReader.read(text).get()
        return PlanImporter.plan(
            message, exercises: [bench, row, squat], routines: routines, settings: [:], today: today, calendar: calendar
        )
    }

    @Test func importsBlocksBackToBackWithTheirRoutines() throws {
        let planned = try importing(yearPlan)
        #expect(planned.issues.isEmpty)
        #expect(planned.canImport)
        let ids = Dictionary(uniqueKeysWithValues: planned.routines.map { ($0.routine.name, $0.routine.id) })

        #expect(planned.blocks.map(\.focus) == [.strength, .hypertrophy, .mixed])
        #expect(planned.blocks.map(\.start) == [
            CalendarDay(year: 2027, month: 1, day: 4),
            CalendarDay(year: 2027, month: 4, day: 26),  // + 16 weeks
            CalendarDay(year: 2027, month: 9, day: 13),  // + 20 weeks
        ])
        #expect(planned.blocks.map(\.plannedWeeks) == [16, 20, 16])
        #expect(planned.blocks.map(\.name) == ["Strength", "Hypertrophy", nil])
        #expect(planned.blocks.allSatisfy { $0.isDeclared })
        #expect(planned.blocks[0].routineIDs == [ids["Upper (strength)"], ids["Lower (strength)"]])
        #expect(planned.blocks[1].routineIDs == [ids["Full body (hypertrophy)"]])  // by name
    }

    @Test func routinesCarryTheirOwnSetsAndReps() throws {
        let planned = try importing(yearPlan)
        let upper = try #require(planned.routines.first { $0.routine.name == "Upper (strength)" }).routine
        let full = try #require(planned.routines.first { $0.routine.name == "Full body (hypertrophy)" }).routine

        #expect(upper.prescription(for: bench.id) == .rpeBased(sets: 5, reps: 3, targetRPE: 8))
        #expect(upper.prescription(for: row.id) == nil)  // follows the exercise's own settings
        #expect(full.prescription(for: bench.id) == .doubleProgression(sets: 3, minReps: 8, maxReps: 12, targetRPE: 8))
    }

    @Test func withoutAStartDateThePlanStartsToday() throws {
        let plan = """
            {"format": "overreach.plan", "version": 1,
             "routines": [{"id": "a", "name": "A", "exercises": ["Squat (Barbell)"]}],
             "blocks": [{"focus": "strength", "weeks": 4, "routines": ["a"]}]}
            """
        #expect(try importing(plan).blocks.first?.start == today)
    }

    @Test func blocksCanUseRoutinesAlreadyInTheApp() throws {
        let existing = Routine(name: "Legs", exerciseIDs: [squat.id])
        let plan = """
            {"format": "overreach.plan", "version": 1,
             "blocks": [{"focus": "hypertrophy", "weeks": 8, "routines": ["legs"]}]}
            """
        let planned = try importing(plan, routines: [existing])
        #expect(planned.canImport)
        #expect(planned.blocks.first?.routineIDs == [existing.id])
    }

    @Test func flagsSessionTimeAndPeakWeeklyVolumeWithoutBlocking() throws {
        let plan = """
            {"format": "overreach.plan", "version": 1,
             "routines": [{"id": "a", "name": "Legs", "focus": "strength", "maxDurationMinutes": 20,
                           "exercises": ["Squat (Barbell)"],
                           "prescriptions": [{"exercise": "Squat (Barbell)",
                                              "scheme": {"type": "linearLoad", "sets": 10, "reps": 5}}]},
                          {"id": "b", "name": "Upper", "exercises": ["Bench Press (Barbell)"]}],
             "blocks": [{"name": "Build", "focus": "strength", "weeks": 2,
                         "routines": ["b", "a", "a"], "sessionsPerWeek": 4}]}
            """
        let planned = try importing(plan)
        #expect(planned.canImport)
        #expect(planned.warnings.contains(.sessionDuration(routine: "Legs", minutes: 32, limit: 20)))
        #expect(planned.warnings.contains(.weeklyVolume(block: "Build", muscle: .quadriceps, sets: 30, guide: 20)))
        #expect(PlanImporter.correctionPrompt(for: [], warnings: planned.warnings).contains("20-minute limit"))
    }

    @Test func rejectsAnInvalidSessionTimeLimit() throws {
        let plan = """
            {"format": "overreach.plan", "version": 1,
             "routines": [{"name": "Legs", "maxDurationMinutes": 0, "exercises": ["Squat (Barbell)"]}]}
            """
        let planned = try importing(plan)
        #expect(!planned.canImport)
        #expect(planned.issues.contains(.invalidValue(
            field: "routines[0].maxDurationMinutes", value: "0", expected: "1 to 1440"
        )))
    }

    @Test func explainsWhatIsWrongWithBlocksAndPrescriptions() throws {
        let plan = """
            {"format": "overreach.plan", "version": 1, "startDate": "next monday",
             "routines": [{"name": "A", "exercises": ["Squat (Barbell)"],
                           "prescriptions": [{"exercise": "Bench Press (Barbell)",
                                              "scheme": {"type": "linearLoad", "sets": 5, "reps": 5}}]},
                          {"name": "B", "exercises": ["Squat (Barbell)"],
                           "prescriptions": [{"exercise": "Squat (Barbell)",
                                              "scheme": {"type": "linearLoad", "sets": 5, "reps": 5, "minReps": 3}}]}],
             "blocks": [{"focus": "power", "weeks": 60, "routines": ["Z"]}, {"weeks": 4}]}
            """
        let planned = try importing(plan)
        #expect(!planned.canImport)
        #expect(planned.issues.contains(.prescriptionOutsideRoutine(routine: "A", exercise: "Bench Press (Barbell)")))
        #expect(planned.issues.contains(.invalidValue(
            field: "startDate", value: "next monday", expected: "a date like 2027-01-04"
        )))
        #expect(planned.issues.contains(.invalidValue(
            field: "blocks[0].focus", value: "power", expected: "strength, hypertrophy, mixed or endurance"
        )))
        #expect(planned.issues.contains(.invalidValue(field: "blocks[0].weeks", value: "60", expected: "1 to 52")))
        #expect(planned.issues.contains(.unknownRoutine(name: "Z")))
        #expect(planned.issues.contains(.invalidValue(
            field: "blocks[1].focus", value: "missing", expected: "strength, hypertrophy, mixed or endurance"
        )))
        #expect(planned.warnings == [.ignoredField("routines[1].prescriptions[0].scheme.minReps")])

        let correction = PlanImporter.correctionPrompt(for: planned.issues, warnings: planned.warnings)
        #expect(correction.contains("Block routine \"Z\""))
        #expect(correction.contains("not one of its exercises"))
    }

    @Test func unknownFieldsInBlocksAreReported() throws {
        let plan = """
            {"format": "overreach.plan", "version": 1,
             "routines": [{"id": "a", "name": "A", "exercises": ["Squat (Barbell)"],
                           "prescriptions": [{"exercise": "Squat (Barbell)", "load": 100,
                                              "scheme": {"type": "linearLoad", "sets": 5, "reps": 5}}]}],
             "blocks": [{"focus": "strength", "weeks": 4, "routines": ["a"], "deload": true}]}
            """
        let planned = try importing(plan)
        #expect(planned.canImport)
        #expect(Set(planned.warnings) == [.ignoredField("blocks[0].deload"),
                                          .ignoredField("routines[0].prescriptions[0].load")])
    }

    @Test func applyingKeepsEarlierBlocksAndReplacesLaterOnes() throws {
        let planned = try importing(yearPlan)
        let september = CalendarDay(year: 2026, month: 9, day: 1)
        let february = CalendarDay(year: 2027, month: 2, day: 1)
        let past = TrainingBlock(focus: .hypertrophy, start: september, isDeclared: true)
        let replaced = TrainingBlock(focus: .endurance, start: february, isDeclared: true)
        let inferred = TrainingBlock(focus: .mixed, start: CalendarDay(year: 2027, month: 3, day: 1), isDeclared: false)

        let result = planned.applying(to: [past, replaced, inferred])
        #expect(result == [past, inferred] + planned.blocks)
    }

    @Test func sessionsPerWeekIsCheckedAndKept() throws {
        let plan = """
            {"format": "overreach.plan", "version": 1,
             "routines": [{"id": "a", "name": "A", "exercises": ["Squat (Barbell)"]}],
             "blocks": [{"focus": "strength", "weeks": 4, "routines": ["a"], "sessionsPerWeek": 3},
                        {"focus": "strength", "weeks": 4, "routines": ["a"], "sessionsPerWeek": 20}]}
            """
        let planned = try importing(plan)
        #expect(planned.issues == [.invalidValue(field: "blocks[1].sessionsPerWeek", value: "20", expected: "1 to 14")])
        #expect(planned.blocks.first?.sessionsPerWeek == 3)
    }

    @Test func aPlanWithOnlyBlocksCanBeImported() throws {
        let existing = Routine(name: "Legs", exerciseIDs: [squat.id])
        let plan = #"{"format": "overreach.plan", "version": 1, "blocks": [{"focus": "strength", "weeks": 2}]}"#
        let planned = try importing(plan, routines: [existing])
        #expect(planned.canImport)
        #expect(planned.blocks.first?.routineIDs == [])
    }

    @Test func theContextPackShowsThePlanSoTheAICanReviseIt() throws {
        let upper = Routine(name: "Upper", exerciseIDs: [bench.id], prescriptions: [
            RoutinePrescription(exerciseID: bench.id, scheme: .rpeBased(sets: 5, reps: 3, targetRPE: 8)),
        ])
        var profile = AthleteProfile()
        profile.declaredBlocks = [TrainingBlock(
            focus: .strength, start: today, plannedWeeks: 6, isDeclared: true, name: "Strength", routineIDs: [upper.id]
        )]
        let pack = ContextPackBuilder.build(
            ContextInput(exercises: [bench, row, squat], routines: [upper], profile: profile),
            period: today.adding(days: -27, calendar: calendar)...today, now: Date(), calendar: calendar
        )
        let routine = try #require(pack.routines.first)
        #expect(routine.prescriptions?.first?.exercise == "Bench Press (Barbell)")
        #expect(routine.prescriptions?.first?.scheme.reps == 3)
        let block = try #require(pack.athlete.declaredBlocks.first)
        #expect(block.name == "Strength")
        #expect(block.routines == ["Upper"])

        // A reply that reuses the pack's routine id updates that routine, and blocks can name it by id.
        let reply = """
            {"format": "overreach.plan", "version": 1,
             "routines": [{"id": "\(routine.id.lowercased())", "name": "Upper heavy",
                           "exercises": ["Bench Press (Barbell)"]}],
             "blocks": [{"focus": "strength", "weeks": 4, "routines": ["\(routine.id)"]}]}
            """
        let planned = try importing(reply, routines: [upper])
        #expect(planned.routines.first?.routine.id == upper.id)
        #expect(planned.routines.first?.isUpdate == true)
        #expect(planned.blocks.first?.routineIDs == [upper.id])
    }
}

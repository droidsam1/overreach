import AIExchange
import Analytics
import Domain
import Foundation
import Testing

@Suite("Reading AI plans")
struct PlanMessageTests {
    private let bench = Exercise(name: "Bench Press (Barbell)", primaryMuscles: [.chest], equipment: .barbell,
                                 aliases: ["Press banca"])
    private let row = Exercise(name: "Bent Over Row (Barbell)", primaryMuscles: [.back], equipment: .barbell)
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell)

    private let plan = """
        {"format": "overreach.plan", "version": 1,
         "routines": [{"id": "upper-a", "name": "Upper A", "focus": "strength",
                       "exercises": ["bench press (barbell)", "Press Banca", "Bent Over Row (Barbell)"]}],
         "exerciseSettings": [{"exercise": "Bench Press (Barbell)", "focus": "strength", "isMainLift": true}]}
        """

    private func read(_ text: String) throws -> PlanMessage {
        try PlanMessageReader.read(text).get()
    }

    private func importing(
        _ text: String, routines: [Routine] = [], settings: [UUID: ProgressionSettings] = [:]
    ) throws -> PlanImport {
        PlanImporter.plan(try read(text), exercises: [bench, row, squat], routines: routines, settings: settings)
    }

    // MARK: Reading

    @Test func findsThePlanInsideAChatAnswer() throws {
        let answer = "Here is your plan:\n\n```json\n\(plan)\n```\n\nLet me know if you want changes."
        #expect(try read(answer).routines?.first?.name == "Upper A")
        #expect(try read(plan).routines?.count == 1)
        #expect(try read("Sure! \(plan) Enjoy.").exerciseSettings?.count == 1)
    }

    @Test func explainsWhatIsWrongWithTheText() {
        #expect(PlanMessageReader.read("No JSON here") == .failure(.noJSON))
        #expect(PlanMessageReader.read(#"{"format":"overreach.context","version":1}"#)
            == .failure(.notAPlan(format: "overreach.context")))
        #expect(PlanMessageReader.read(#"{"format":"overreach.plan","version":2}"#) == .failure(.newerVersion(2)))
        #expect(PlanMessageReader.read(#"{"format":"overreach.plan"}"#) == .failure(.unsupportedVersion(0)))
        let wrongType = #"{"format":"overreach.plan","version":1,"routines":[{"name":"A","exercises":"Squat"}]}"#
        guard case let .failure(.invalid(detail)) = PlanMessageReader.read(wrongType) else {
            Issue.record("expected an invalid plan")
            return
        }
        #expect(detail.contains("routines[0].exercises"))
    }

    @Test func aPlanBlockWinsOverOtherJSONInTheAnswer() throws {
        let answer = "```json\n{\"a\": 1}\n```\nand\n```json\n\(plan)\n```"
        #expect(try read(answer).routines?.first?.id == "upper-a")
    }

    // MARK: Planning

    @Test func resolvesNamesIgnoringCaseAccentsAndByAlias() throws {
        let planned = try importing(plan)
        #expect(planned.issues.isEmpty)
        #expect(planned.canImport)
        let routine = try #require(planned.routines.first)
        #expect(routine.routine.exerciseIDs == [bench.id, row.id])  // a routine lists each exercise once
        #expect(routine.exerciseNames == ["Bench Press (Barbell)", "Bent Over Row (Barbell)"])
        #expect(routine.routine.focus == .strength)
        #expect(!routine.isUpdate)
    }

    @Test func importingTheSameRoutineAgainUpdatesIt() throws {
        let first = try #require(try importing(plan).routines.first?.routine)
        let again = try #require(try importing(plan, routines: [first]).routines.first)
        #expect(again.routine.id == first.id)
        #expect(again.isUpdate)
    }

    @Test func aRoutineWithTheSameNameIsUpdatedEvenWithoutAnID() throws {
        let mine = Routine(name: "upper a", exerciseIDs: [squat.id])
        let planned = try importing(plan, routines: [mine])
        #expect(planned.routines.first?.routine.id == mine.id)
        #expect(planned.routines.first?.isUpdate == true)
    }

    @Test func settingsFollowTheFocusAndKeepWhatIsNotMentioned() throws {
        let stored = ProgressionSettings(incrementKg: 1.25)
        let planned = try importing(plan, settings: [bench.id: stored])
        let change = try #require(planned.settings.first)
        #expect(change.settings.focus == .strength)
        #expect(change.settings.scheme == FocusPrescription.for(.strength).defaultScheme)
        #expect(change.settings.incrementKg == 1.25)
        #expect(change.settings.isMainLift)
        #expect(change.isUpdate)
    }

    @Test func anExplicitSchemeIsValidated() throws {
        let good = """
            {"format":"overreach.plan","version":1,"exerciseSettings":[{"exercise":"Squat (Barbell)",
             "scheme":{"type":"doubleProgression","sets":3,"minReps":6,"maxReps":10,"targetRPE":8.5}}]}
            """
        let scheme = try #require(try importing(good).settings.first?.settings.scheme)
        #expect(scheme == .doubleProgression(sets: 3, minReps: 6, maxReps: 10, targetRPE: 8.5))

        let bad = """
            {"format":"overreach.plan","version":1,"exerciseSettings":[{"exercise":"Squat (Barbell)",
             "scheme":{"type":"doubleProgression","sets":30,"minReps":10,"maxReps":6}}]}
            """
        let planned = try importing(bad)
        #expect(!planned.canImport)
        #expect(planned.settings.isEmpty)
        #expect(planned.issues.contains(.invalidValue(field: "exerciseSettings[0].scheme.sets", value: "30",
                                                      expected: "1 to 10")))
        #expect(planned.issues.count == 2)
    }

    @Test func unknownExercisesBlockTheImportAndSuggestTheClosest() throws {
        let text = """
            {"format":"overreach.plan","version":1,"routines":[{"name":"Legs","exercises":["Barbell Squats"]}]}
            """
        let planned = try importing(text)
        #expect(!planned.canImport)
        #expect(planned.routines.isEmpty)
        #expect(planned.issues == [.unknownExercise(name: "Barbell Squats", closest: "Squat (Barbell)")])

        let prompt = PlanImporter.correctionPrompt(for: planned.issues)
        #expect(prompt.contains("\"Barbell Squats\" is not in the catalog; the closest is \"Squat (Barbell)\"."))
        #expect(prompt.hasPrefix("Overreach could not import your plan"))
    }

    @Test func otherProblemsAreFlagged() throws {
        let text = """
            {"format":"overreach.plan","version":1,"routines":[
              {"id":"a","name":"A","exercises":["Squat (Barbell)"]},
              {"id":"a","name":"A again","exercises":["Squat (Barbell)"]},
              {"name":"Empty","exercises":[]},
              {"exercises":["Squat (Barbell)"]},
              {"name":"B","focus":"power","exercises":["Squat (Barbell)"]}],
             "exerciseSettings":[{"focus":"strength"}]}
            """
        let issues = try importing(text).issues
        #expect(issues.contains(.duplicateRoutine(id: "a")))
        #expect(issues.contains(.emptyRoutine(name: "Empty")))
        #expect(issues.contains(.unnamedRoutine(index: 3)))
        #expect(issues.contains(.missingExercise(index: 0)))
        #expect(issues.contains { if case .invalidValue("routines[4].focus", "power", _) = $0 { true } else { false } })
        #expect(try importing(#"{"format":"overreach.plan","version":1}"#).issues == [.empty])
    }

    @Test func theFormatGuideIsAValidPlanForTheBuiltInNames() throws {
        let message = try read(PlanMessage.formatGuide)
        #expect(message.format == "overreach.plan")
        #expect(message.routines?.first?.id == "upper-a")
        #expect(message.exerciseSettings?.first?.scheme?.type == "rpeBased")
    }
}

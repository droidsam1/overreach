@testable import AIExchange
import Domain
import Foundation
import Testing

/// The schema given to the AI, the published file and the app's validation must say the same thing.
@Suite("overreach.plan schema")
struct PlanSchemaTests {
    private var schema: [String: Any] {
        get throws {
            let object = try JSONSerialization.jsonObject(with: Data(PlanMessage.jsonSchema.utf8))
            return try #require(object as? [String: Any])
        }
    }

    private func definition(_ name: String) throws -> [String: Any] {
        let defs = try #require(try schema["$defs"] as? [String: Any])
        return try #require(defs[name] as? [String: Any])
    }

    /// JSON numbers come back as Int, Double or NSNumber depending on the platform.
    private func number(_ value: Any?) -> Double? {
        if let value = value as? Int { return Double(value) }
        if let value = value as? Double { return value }
        return (value as? NSNumber)?.doubleValue
    }

    private func properties(_ object: [String: Any]) throws -> Set<String> {
        Set(try #require(object["properties"] as? [String: Any]).keys)
    }

    @Test func thePublishedFileIsTheSameSchema() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/schemas/overreach.plan.v1.schema.json")
        let published = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        #expect(published.trimmingCharacters(in: .whitespacesAndNewlines) == PlanMessage.jsonSchema)
    }

    @Test func fieldsMatchWhatTheAppReads() throws {
        #expect(try properties(schema) == PlanMessage.fields["plan"])
        #expect(try properties(definition("routine")) == PlanMessage.fields["routine"])
        #expect(try properties(definition("exerciseSettings")) == PlanMessage.fields["exerciseSettings"])
        #expect(try properties(definition("scheme")) == PlanMessage.fields["scheme"])
    }

    @Test func valuesAndRangesMatchTheValidation() throws {
        let focus = try #require(try definition("focus")["enum"] as? [String])
        #expect(Set(focus) == Set(TrainingFocus.allCases.map(\.rawValue)))

        let reps = try definition("reps")
        #expect(number(reps["minimum"]) == Double(PlanImporter.repRange.lowerBound))
        #expect(number(reps["maximum"]) == Double(PlanImporter.repRange.upperBound))

        let scheme = try #require(try definition("scheme")["properties"] as? [String: Any])
        let types = try #require((scheme["type"] as? [String: Any])?["enum"] as? [String])
        #expect(types == ["doubleProgression", "linearLoad", "repCycle", "rpeBased"])
        let sets = try #require(scheme["sets"] as? [String: Any])
        #expect(number(sets["minimum"]) == Double(PlanImporter.setRange.lowerBound))
        #expect(number(sets["maximum"]) == Double(PlanImporter.setRange.upperBound))
        let rpe = try #require(scheme["targetRPE"] as? [String: Any])
        #expect(number(rpe["minimum"]) == PlanImporter.rpeRange.lowerBound)
        #expect(number(rpe["maximum"]) == PlanImporter.rpeRange.upperBound)

        let settings = try #require(try definition("exerciseSettings")["properties"] as? [String: Any])
        let increment = try #require(settings["incrementKg"] as? [String: Any])
        #expect(number(increment["maximum"]) == PlanImporter.incrementRange.upperBound)
    }

    @Test func theGuideCarriesTheSchemaAndAValidExample() throws {
        #expect(PlanMessage.formatGuide.contains(PlanMessage.jsonSchema))
        let example = try PlanMessageReader.read(PlanMessage.formatGuide.components(separatedBy: "Example:")[1]).get()
        #expect(example.routines?.first?.id == "upper-a")
        #expect(example.ignoredFields.isEmpty)
    }
}

@Suite("Explaining broken JSON")
struct JSONSyntaxTests {
    @Test func validJSONHasNoProblem() {
        #expect(JSONSyntax.describeProblem(in: #"{"a": [1, -2.5e3, true, null, "x\"y"]}"#) == nil)
    }

    @Test func aMissingCommaIsLocated() throws {
        let text = "{\n  \"format\": \"overreach.plan\",\n  \"name\": \"Upper A\" \"focus\": \"strength\"\n}"
        let problem = try #require(JSONSyntax.describeProblem(in: text))
        #expect(problem.hasPrefix("line 3, column 21: expected \",\" or \"}\""))
        #expect(problem.hasSuffix("`\"name\": \"Upper A\" \"focus\": \"strength\"`"))
    }

    @Test func trailingCommasAndCurlyQuotesAreNamed() throws {
        let trailing = try #require(JSONSyntax.describeProblem(in: "{\"a\": [1, 2,]}"))
        #expect(trailing.contains("remove the comma before \"]\""))
        let objectComma = try #require(JSONSyntax.describeProblem(in: "{\"a\": 1,}"))
        #expect(objectComma.contains("remove the comma before \"}\""))
        let curly = try #require(JSONSyntax.describeProblem(in: "{\"a\": “b”}"))
        #expect(curly.contains("straight double quotes"))
    }

    @Test func truncatedJSONSaysItEnds() throws {
        let problem = try #require(JSONSyntax.describeProblem(in: "{\"routines\": [{\"name\": \"A\""))
        #expect(problem.contains("(the text ends there)"))
    }

    @Test func theReaderReportsTheLocation() {
        let answer = "```json\n{\"format\": \"overreach.plan\", \"version\": 1,\n \"routines\": [}\n```"
        guard case let .failure(.invalid(detail)) = PlanMessageReader.read(answer) else {
            Issue.record("expected an invalid plan")
            return
        }
        #expect(detail.hasPrefix("line 2, column 15: expected a value"))
    }
}

@Suite("Ignored fields")
struct IgnoredFieldsTests {
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell)

    @Test func fieldsOutsideTheFormatAreReportedButDoNotBlock() throws {
        let text = """
            {"format":"overreach.plan","version":1,"note":"hi",
             "routines":[{"name":"Legs","exercises":["Squat (Barbell)"],"sets":3}],
             "exerciseSettings":[{"exercise":"Squat (Barbell)","rest":120,
               "scheme":{"type":"doubleProgression","sets":3,"minReps":6,"maxReps":10,"reps":8,"tempo":"3-1-1"}}]}
            """
        let message = try PlanMessageReader.read(text).get()
        #expect(message.ignoredFields == [
            "exerciseSettings[0].rest", "exerciseSettings[0].scheme.tempo", "note", "routines[0].sets",
        ])

        let planned = PlanImporter.plan(message, exercises: [squat], routines: [], settings: [:])
        #expect(planned.canImport)
        #expect(planned.warnings.contains(.ignoredField("exerciseSettings[0].scheme.reps")))
        #expect(planned.warnings.count == 5)

        let prompt = PlanImporter.correctionPrompt(for: planned.issues, warnings: planned.warnings)
        #expect(prompt.hasPrefix("Overreach can import your plan"))
        #expect(prompt.contains("- routines[0].sets is not part of the format and was ignored."))
        #expect(prompt.contains("overreach.plan.v1.schema.json"))
    }

    @Test func aCleanPlanHasNoWarnings() throws {
        let text = #"{"format":"overreach.plan","version":1,"routines":[{"name":"L","exercises":["Squat (Barbell)"]}]}"#
        let message = try PlanMessageReader.read(text).get()
        #expect(message.ignoredFields.isEmpty)
        #expect(PlanImporter.plan(message, exercises: [squat], routines: [], settings: [:]).warnings.isEmpty)
    }
}

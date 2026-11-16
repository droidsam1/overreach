import Domain
import Foundation
@testable import StrongImport
import Testing

/// Anonymised sample in the exact layout of a real Strong export (2026).
private let sampleCSV = """
Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
2026-10-20 18:30:00,"Torso A",1h 6m,"Bench Press (Barbell)",W,40.0,10.0,0,0.0,
2026-10-20 18:30:00,"Torso A",1h 6m,"Bench Press (Barbell)",1,80.0,6.0,0,0.0,
2026-10-20 18:30:00,"Torso A",1h 6m,"Bench Press (Barbell)",2,80.0,6.0,0,0.0,8
2026-10-20 18:30:00,"Torso A",1h 6m,"Pull Up",1,0.0,8.0,0,0.0,
2026-10-20 18:30:00,"Torso A",1h 6m,"Pull Up",F,0.0,5.0,0,0.0,
2026-10-20 18:30:00,"Torso A",1h 6m,"Plank",1,0.0,0.0,0,45.0,
2026-10-22 07:05:10,"Pierna, día 2",37m,"Front Squat (Barbell)",1,70.0,5.0,0,0.0,
2026-10-22 07:05:10,"Pierna, día 2",37m,"Sentadilla Búlgara",1,12.5,10.0,0,0.0,
2026-10-22 07:05:10,"Pierna, día 2",37m,"Nordic Curl",1,0,6,0,0,

"""

private func utcCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    return calendar
}

private func catalogExercise(_ name: String) throws -> Exercise {
    try #require(ExerciseCatalog.builtIn.first { $0.name == name })
}

@Suite("Strong CSV import")
struct StrongCSVImporterTests {
    private func importSample(_ csv: String = sampleCSV) throws -> StrongCSVImporter.Result {
        try StrongCSVImporter.parse(
            csv,
            catalog: ExerciseCatalog.builtIn,
            options: .init(calendar: try utcCalendar())
        )
    }

    @Test func groupsRowsIntoSessionsInOrder() throws {
        let result = try importSample()

        #expect(result.sessions.map(\.name) == ["Torso A", "Pierna, día 2"])
        #expect(result.setCount == 9)
        #expect(result.skippedLines.isEmpty)

        let torso = result.sessions[0]
        let calendar = try utcCalendar()
        let components = DateComponents(year: 2026, month: 10, day: 20, hour: 18, minute: 30)
        let start = try #require(calendar.date(from: components))
        #expect(torso.startedAt == start)
        #expect(torso.durationSeconds == 66 * 60)
        #expect(torso.source == .strongImport)
        let expectedExercises = [
            try catalogExercise("Bench Press (Barbell)").id,
            try catalogExercise("Pull Up").id,
            try catalogExercise("Plank").id,
        ]
        #expect(torso.entries.map(\.exerciseID) == expectedExercises)
        #expect(result.sessions[1].durationSeconds == 37 * 60)
    }

    @Test func readsSetKindsWeightsRepsRPEAndTime() throws {
        let torso = try importSample().sessions[0]
        let bench = torso.entries[0].sets
        #expect(bench.map(\.kind) == [.warmup, .working, .working])
        #expect(bench.map(\.weightKg) == [40, 80, 80])
        #expect(bench.map(\.reps) == [10, 6, 6])
        #expect(bench.map(\.rpe) == [nil, nil, 8])

        let pullUps = torso.entries[1].sets
        #expect(pullUps.map(\.kind) == [.working, .failure])
        #expect(pullUps.allSatisfy { $0.weightKg == nil })  // weight 0 = bodyweight

        let plank = try #require(torso.entries[2].sets.first)
        #expect(plank.durationSeconds == 45)
        #expect(plank.reps == nil)
    }

    @Test func matchesCatalogAliasesIgnoringAccentsAndCreatesUnknownExercises() throws {
        let result = try importSample()
        let leg = result.sessions[1]

        let bulgarian = try catalogExercise("Bulgarian Split Squat")
        #expect(leg.entries[1].exerciseID == bulgarian.id)
        #expect(result.newExercises.map(\.name) == ["Nordic Curl"])
        #expect(result.newExercises.allSatisfy { $0.isCustom && $0.needsMuscleMapping })
        #expect(leg.entries[2].exerciseID == result.newExercises[0].id)
    }

    @Test func importingTwiceGivesTheSameIDs() throws {
        let first = try importSample()
        let second = try importSample()
        #expect(first.sessions.map(\.id) == second.sessions.map(\.id))
        #expect(first.sessions[0].entries[0].sets.map(\.id) == second.sessions[0].entries[0].sets.map(\.id))
        #expect(first.newExercises.map(\.id) == second.newExercises.map(\.id))
    }

    @Test func supportsSemicolonsDecimalCommasAndEscapedQuotes() throws {
        // Raw string: the CSV contains `"""`, which would close a normal multi-line literal.
        let csv = #"""
        Date;Workout Name;Exercise Name;Set Order;Weight;Reps
        2026-01-05 10:00:00;"Día ""pesado""";Squat (Barbell);1;"102,5";3
        """#
        let result = try importSample(csv)
        let session = try #require(result.sessions.first)
        #expect(session.name == "Día \"pesado\"")
        #expect(session.entries.first?.sets.first?.weightKg == 102.5)
        #expect(session.endedAt == nil)  // no Duration column
    }

    @Test func convertsPoundsToKilograms() throws {
        let csv = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps
        2026-01-05 10:00:00,A,Deadlift (Barbell),1,225,5
        """
        let result = try StrongCSVImporter.parse(
            csv,
            catalog: ExerciseCatalog.builtIn,
            options: .init(weightUnit: .pounds, calendar: try utcCalendar())
        )
        let weight = try #require(result.sessions.first?.entries.first?.sets.first?.weightKg)
        #expect(abs(weight - 102.058) < 0.001)
    }

    @Test func skipsUnreadableRowsAndReportsTheirLines() throws {
        let csv = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps
        not a date,A,Squat (Barbell),1,100,5
        2026-01-05 10:00:00,A,Squat (Barbell),Rest Timer,0,0
        2026-01-05 10:00:00,A,Squat (Barbell),1,100,5
        """
        let result = try importSample(csv)
        #expect(result.skippedLines == [2, 3])
        #expect(result.setCount == 1)
    }

    @Test func rejectsFilesWithoutTheRequiredColumns() {
        #expect(throws: StrongCSVImporter.ImportError.emptyFile) {
            try StrongCSVImporter.parse("", catalog: [])
        }
        #expect(throws: StrongCSVImporter.ImportError.missingColumns(["set order", "weight", "reps"])) {
            try StrongCSVImporter.parse("Date,Exercise Name\n2026-01-01,Squat", catalog: [])
        }
    }

    @Test func parsesStrongDurations() {
        #expect(StrongCSVImporter.parseDuration("1h 6m") == 3960)
        #expect(StrongCSVImporter.parseDuration("37m") == 2220)
        #expect(StrongCSVImporter.parseDuration("2h") == 7200)
        #expect(StrongCSVImporter.parseDuration("45s") == 45)
        #expect(StrongCSVImporter.parseDuration("n/a") == nil)
    }

    /// Runs only when OVERREACH_STRONG_EXPORT points to a real export on your machine. Never commit real exports.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OVERREACH_STRONG_EXPORT"] != nil))
    func importsARealExportWithoutLosingRows() throws {
        let path = try #require(ProcessInfo.processInfo.environment["OVERREACH_STRONG_EXPORT"])
        let csv = try String(contentsOfFile: path, encoding: .utf8)
        let dataRows = CSVReader.rows(from: csv).count - 1

        let result = try StrongCSVImporter.parse(csv, catalog: ExerciseCatalog.builtIn)

        #expect(result.skippedLines.isEmpty)
        #expect(result.setCount == dataRows)
        print("Imported \(result.sessions.count) sessions, \(result.setCount) sets; "
            + "unmapped exercises: \(result.newExercises.map(\.name))")
    }
}

@Suite("CSV reader")
struct CSVReaderTests {
    @Test func handlesQuotesLineBreaksAndBOM() {
        let text = "\u{FEFF}a,b\r\n\"x, y\",\"line\nbreak\"\r\n\r\n"
        #expect(CSVReader.rows(from: text) == [["a", "b"], ["x, y", "line\nbreak"]])
    }
}

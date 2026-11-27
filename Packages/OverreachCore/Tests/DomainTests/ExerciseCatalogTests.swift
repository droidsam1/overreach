import Domain
import Foundation
import Testing

@Suite("Exercise catalog")
struct ExerciseCatalogTests {
    private func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    @Test func idsAreUniqueAndStable() {
        let ids = ExerciseCatalog.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ExerciseCatalog.builtIn.map(\.id) == ids)
        let bench = ExerciseCatalog.builtIn.first { $0.name == "Bench Press (Barbell)" }
        #expect(bench?.id == UUID.stable("builtin-exercise|Bench Press (Barbell)"))
    }

    @Test func everyExerciseHasPrimaryMusclesAndIsNotCustom() {
        for exercise in ExerciseCatalog.builtIn {
            #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.name) has no primary muscle")
            #expect(!exercise.isCustom)
        }
    }

    @Test func namesAndAliasesNeverCollide() {
        var owner: [String: String] = [:]
        for exercise in ExerciseCatalog.builtIn {
            for name in exercise.knownNames {
                let key = normalize(name)
                if let other = owner[key], other != exercise.name {
                    Issue.record("\"\(name)\" is used by both \(other) and \(exercise.name)")
                }
                owner[key] = exercise.name
            }
        }
    }

    @Test func everyBuiltInExerciseHasASpanishName() {
        for exercise in ExerciseCatalog.builtIn {
            #expect(ExerciseCatalog.englishName(of: exercise.id) == exercise.name)
            let spanish = ExerciseCatalog.spanishName(of: exercise.id)
            #expect(spanish?.isEmpty == false, "\(exercise.name) has no Spanish name")
            #expect(exercise.knownNames.contains { $0 == spanish })
        }
        let bench = ExerciseCatalog.builtIn.first { $0.name == "Bench Press (Barbell)" }
        #expect(bench.flatMap { ExerciseCatalog.spanishName(of: $0.id) } == "Press de banca (barra)")
    }

    @Test func customExercisesHaveNoCatalogNames() {
        let custom = Exercise(name: "Landmine Press", primaryMuscles: [.shoulders], isCustom: true, aliases: ["mina"])
        #expect(ExerciseCatalog.spanishName(of: custom.id) == nil)
        #expect(custom.knownNames == ["Landmine Press", "mina"])
    }

    @Test func legacyBroadMappingsDecodeAndBuiltInsGainTheirReviewedDetail() throws {
        let bench = try #require(ExerciseCatalog.builtIn.first { $0.name == "Bench Press (Barbell)" })
        var oldBench = bench
        oldBench.secondaryMuscles = [.shoulders, .triceps]
        oldBench.movementPattern = nil
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode(Exercise.self, from: encoder.encode(oldBench)) == bench)

        oldBench.secondaryMuscles.insert(.forearms)
        let override = try decoder.decode(Exercise.self, from: encoder.encode(oldBench))
        #expect(override.secondaryMuscles == [.shoulders, .triceps, .forearms])
        #expect(override.movementPattern == .horizontalPush)

        let custom = Exercise(name: "My row", primaryMuscles: [.back], secondaryMuscles: [.shoulders], isCustom: true)
        #expect(try decoder.decode(Exercise.self, from: encoder.encode(custom)) == custom)
    }

    @Test func newMuscleLabelsAndMovementPatternRoundTripInABackup() throws {
        let exercise = Exercise(
            name: "My cable row", primaryMuscles: [.upperBack, .lats], secondaryMuscles: [.rearDelts],
            equipment: .cable, isCustom: true, movementPattern: .horizontalPull
        )
        let backup = BackupDocument(createdAt: Date(timeIntervalSince1970: 0), exercises: [exercise])
        #expect(try BackupCodec.decode(BackupCodec.encode(backup)) == backup)
    }

    @Test func stableIDsAreDeterministicAndDistinct() {
        #expect(UUID.stable("a") == UUID.stable("a"))
        #expect(UUID.stable("a") != UUID.stable("b"))
        #expect(UUID.stable("ab") != UUID.stable("ba"))
    }
}

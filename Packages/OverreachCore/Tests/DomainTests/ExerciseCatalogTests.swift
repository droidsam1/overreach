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
            for name in [exercise.name] + exercise.aliases.sorted() {
                let key = normalize(name)
                if let other = owner[key], other != exercise.name {
                    Issue.record("\"\(name)\" is used by both \(other) and \(exercise.name)")
                }
                owner[key] = exercise.name
            }
        }
    }

    @Test func stableIDsAreDeterministicAndDistinct() {
        #expect(UUID.stable("a") == UUID.stable("a"))
        #expect(UUID.stable("a") != UUID.stable("b"))
        #expect(UUID.stable("ab") != UUID.stable("ba"))
    }
}

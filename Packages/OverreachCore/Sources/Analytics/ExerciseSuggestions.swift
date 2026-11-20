import Domain
import Foundation

/// A catalog exercise that looks like the one being mapped, with a 0–1 similarity score.
public struct ExerciseSuggestion: Hashable, Sendable {
    public let exercise: Exercise
    public let score: Double

    public init(exercise: Exercise, score: Double) {
        self.exercise = exercise
        self.score = score
    }
}

/// Finds catalog exercises with similar names, to copy their muscles or merge into them (issue #13).
///
/// This is name matching, not a training rule: no evidence applies. Score = best Jaccard overlap of word sets
/// between the exercise's name and the candidate's name or aliases (accents, case, punctuation, plurals and
/// filler words ignored), plus a small bonus for the same equipment.
public enum ExerciseSuggestions {
    /// Minimum word overlap for a candidate to be suggested.
    static let threshold = 0.3
    static let equipmentBonus = 0.15

    private static let fillerWords: Set<String> = [
        "a", "al", "and", "con", "de", "del", "el", "en", "la", "las", "los", "of", "on", "the", "with", "y",
    ]

    /// Up to `limit` mapped exercises from `catalog` that look like `exercise`, best first.
    public static func similar(to exercise: Exercise, in catalog: [Exercise], limit: Int = 3) -> [ExerciseSuggestion] {
        let names = exercise.knownNames
        let ownWords = names.map(words).filter { !$0.isEmpty }
        guard !ownWords.isEmpty else { return [] }

        let suggestions = catalog.compactMap { candidate -> ExerciseSuggestion? in
            guard candidate.id != exercise.id, !candidate.needsMuscleMapping else { return nil }
            let candidateWords = candidate.knownNames.map(words).filter { !$0.isEmpty }
            var overlap = 0.0
            for own in ownWords {
                for other in candidateWords {
                    overlap = max(overlap, jaccard(own, other))
                }
            }
            guard overlap >= threshold else { return nil }
            let sameEquipment = exercise.equipment != .other && exercise.equipment == candidate.equipment
            return ExerciseSuggestion(exercise: candidate, score: min(1, overlap + (sameEquipment ? equipmentBonus : 0)))
        }
        return Array(
            suggestions.sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    /// Lowercased, accent-free words without punctuation, filler words or a plural "s".
    static func words(_ name: String) -> Set<String> {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let tokens = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return Set(tokens.filter { !fillerWords.contains($0) }.map(singular))
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs).count
        return union == 0 ? 0 : Double(lhs.intersection(rhs).count) / Double(union)
    }
}

import Domain
import Foundation

/// Resolves exercise names from imported data to exercises in the catalog, by name or alias, ignoring case,
/// accents and extra spaces. Unknown names become new custom exercises that still need a muscle mapping.
public struct ExerciseMatcher: Sendable {
    private var byKey: [String: Exercise] = [:]
    /// Exercises created during matching, in order of first appearance.
    public private(set) var created: [Exercise] = []

    public init(catalog: [Exercise]) {
        for exercise in catalog {
            register(exercise)
        }
    }

    /// The catalog exercise for `name`, or a new custom exercise if none matches.
    public mutating func resolve(_ name: String) -> Exercise {
        let key = Self.normalize(name)
        if let existing = byKey[key] {
            return existing
        }
        let exercise = Exercise(
            id: .stable("custom-exercise|\(key)"),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryMuscles: [],
            equipment: Self.inferEquipment(from: name),
            isCustom: true
        )
        byKey[key] = exercise
        created.append(exercise)
        return exercise
    }

    /// Lowercased, accent-free, single-spaced form used for matching.
    public static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private mutating func register(_ exercise: Exercise) {
        for candidate in exercise.knownNames {
            let key = Self.normalize(candidate)
            if byKey[key] == nil {
                byKey[key] = exercise
            }
        }
    }

    /// Strong-style names end with the equipment in parentheses, e.g. "Lunge (Dumbbell)".
    static func inferEquipment(from name: String) -> Equipment {
        let lowered = normalize(name)
        let rules: [(String, Equipment)] = [
            ("(barbell", .barbell), ("(dumbbell", .dumbbell), ("(machine", .machine), ("(smith", .machine),
            ("(plate loaded", .machine), ("(cable", .cable), ("(kettlebell", .kettlebell), ("(band", .band),
            ("(bodyweight", .bodyweight), ("(assisted", .machine),
        ]
        return rules.first { lowered.contains($0.0) }?.1 ?? .other
    }
}

import Domain
import Foundation

/// A selectable value with its display name (pickers, toggles).
public struct Option<Value: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public let value: Value
    public let name: String
    public var id: Value { value }

    public init(value: Value, name: String) {
        self.value = value
        self.name = name
    }
}

extension Option where Value == TrainingFocus {
    public static var trainingFocuses: [Option] { TrainingFocus.allCases.map { Option(value: $0, name: $0.displayName) } }
}

extension Option where Value == SetKind {
    public static var setKinds: [Option] { SetKind.allCases.map { Option(value: $0, name: $0.displayName) } }
}

/// An exercise offered in an exercise picker: name plus the other names search should match.
public struct ExerciseChoice: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let searchTerms: [String]

    public init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        searchTerms = [exercise.name] + exercise.aliases.sorted()
    }
}

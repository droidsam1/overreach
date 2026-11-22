import Domain

/// Muscles and equipment being edited. A muscle is either primary or secondary, never both.
public struct MappingDraft: Hashable, Sendable {
    public private(set) var primary: Set<MuscleGroup>
    public private(set) var secondary: Set<MuscleGroup>
    public var equipment: Equipment

    public init(primary: Set<MuscleGroup> = [], secondary: Set<MuscleGroup> = [], equipment: Equipment = .other) {
        self.primary = primary
        self.secondary = secondary.subtracting(primary)
        self.equipment = equipment
    }

    public init(_ exercise: Exercise) {
        self.init(primary: exercise.primaryMuscles, secondary: exercise.secondaryMuscles, equipment: exercise.equipment)
    }

    /// A muscle needs to be primary for the exercise's volume to count.
    public var canSave: Bool { !primary.isEmpty }

    public mutating func setPrimary(_ muscle: MuscleGroup, _ isOn: Bool) {
        if isOn {
            primary.insert(muscle)
            secondary.remove(muscle)
        } else {
            primary.remove(muscle)
        }
    }

    public mutating func setSecondary(_ muscle: MuscleGroup, _ isOn: Bool) {
        if isOn {
            secondary.insert(muscle)
            primary.remove(muscle)
        } else {
            secondary.remove(muscle)
        }
    }

    /// Takes the other exercise's muscles; its equipment only if none was chosen yet.
    public mutating func copy(from other: Exercise) {
        primary = other.primaryMuscles
        secondary = other.secondaryMuscles.subtracting(other.primaryMuscles)
        if equipment == .other { equipment = other.equipment }
    }
}

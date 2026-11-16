import Foundation

/// Muscle groups used to attribute training volume and fatigue.
public enum MuscleGroup: String, CaseIterable, Codable, Sendable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quadriceps, hamstrings, glutes, calves
    case core

    public var region: BodyRegion {
        switch self {
        case .chest, .back, .shoulders, .biceps, .triceps, .forearms: .upper
        case .quadriceps, .hamstrings, .glutes, .calves: .lower
        case .core: .core
        }
    }
}

public enum BodyRegion: String, Codable, Sendable {
    case upper, lower, core
}

public enum Equipment: String, CaseIterable, Codable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other
}

/// An exercise definition from the catalog (built-in or user-created).
public struct Exercise: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// Muscles that count 1 effective set per working set.
    public var primaryMuscles: Set<MuscleGroup>
    /// Muscles that count 0.5 effective sets per working set.
    public var secondaryMuscles: Set<MuscleGroup>
    public var equipment: Equipment
    public var isCustom: Bool
    /// Other names for the same exercise (e.g. Spanish names, names used by other apps). Used when importing.
    public var aliases: Set<String>

    public init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: Set<MuscleGroup>,
        secondaryMuscles: Set<MuscleGroup> = [],
        equipment: Equipment = .other,
        isCustom: Bool = false,
        aliases: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.isCustom = isCustom
        self.aliases = aliases
    }

    /// Whether the exercise still needs a muscle-group mapping (e.g. an unknown name found during an import).
    public var needsMuscleMapping: Bool { primaryMuscles.isEmpty }
}

/// Unit used by an external source for weights. Overreach always stores kilograms.
public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kilograms, pounds

    public var kilogramsPerUnit: Double {
        switch self {
        case .kilograms: 1
        case .pounds: 0.45359237
        }
    }
}

import Domain

// User-facing names of domain values, shared by every presentation module.

extension MuscleGroup {
    public var displayName: String {
        switch self {
        case .chest: L10n.text("Chest")
        case .back: L10n.text("Back")
        case .shoulders: L10n.text("Shoulders")
        case .biceps: L10n.text("Biceps")
        case .triceps: L10n.text("Triceps")
        case .forearms: L10n.text("Forearms")
        case .quadriceps: L10n.text("Quadriceps")
        case .hamstrings: L10n.text("Hamstrings")
        case .glutes: L10n.text("Glutes")
        case .calves: L10n.text("Calves")
        case .core: L10n.text("Core")
        }
    }

    /// "Chest, Triceps" in catalog order, for compact rows. Empty set → empty string.
    public static func displayList(_ muscles: Set<MuscleGroup>) -> String {
        allCases.filter(muscles.contains).map(\.displayName).joined(separator: ", ")
    }
}

extension Equipment {
    public var displayName: String {
        switch self {
        case .barbell: L10n.text("Barbell")
        case .dumbbell: L10n.text("Dumbbell")
        case .machine: L10n.text("Machine")
        case .cable: L10n.text("Cable")
        case .bodyweight: L10n.text("Bodyweight")
        case .kettlebell: L10n.text("Kettlebell")
        case .band: L10n.text("Band")
        case .other: L10n.text("Other")
        }
    }
}

extension TrainingFocus {
    public var displayName: String {
        switch self {
        case .strength: L10n.text("Strength")
        case .hypertrophy: L10n.text("Hypertrophy")
        case .mixed: L10n.text("Mixed")
        case .endurance: L10n.text("Endurance")
        }
    }
}

extension SetKind {
    public var displayName: String {
        switch self {
        case .warmup: L10n.text("Warm-up")
        case .working: L10n.text("Working")
        case .dropSet: L10n.text("Drop set")
        case .failure: L10n.text("Failure")
        }
    }

    /// Short badge for set rows; `nil` for ordinary working sets.
    public var badge: String? {
        switch self {
        case .warmup: L10n.text("W")
        case .working: nil
        case .dropSet: L10n.text("D")
        case .failure: L10n.text("F")
        }
    }
}

extension ReadinessLevel {
    public var displayName: String {
        switch self {
        case .green: L10n.text("Green")
        case .amber: L10n.text("Amber")
        case .red: L10n.text("Red")
        case .unknown: L10n.text("Unknown")
        }
    }
}

extension EvidenceLevel {
    /// How strong the evidence behind a rule is, as shown next to its explanation.
    public var displayName: String {
        switch self {
        case .strong: L10n.text("strong evidence")
        case .moderate: L10n.text("moderate evidence")
        case .limited: L10n.text("limited evidence")
        case .heuristic: L10n.text("coaching heuristic")
        }
    }
}

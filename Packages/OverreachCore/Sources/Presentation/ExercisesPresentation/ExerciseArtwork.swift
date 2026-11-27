import Analytics
import Domain
import Foundation
import PresentationKit

public struct ExerciseIllustrationOption: Identifiable, Sendable {
    public let id: String
    public let name: String
}

enum ExerciseArtwork {
    static let creditURL = URL(string: "https://bryllim.github.io/workout-guide/guide/#licensing-and-attribution")

    static func illustration(for exercise: Exercise) -> String? {
        if exercise.isCustom {
            return exercise.illustrationID.flatMap { contains($0) ? $0 : nil }
        }
        guard let artwork = catalog[exercise.id], artwork.equipment == exercise.equipment else { return nil }
        return artwork.name
    }

    static func contains(_ id: String) -> Bool { identifiers.contains(id) }

    static func suggestions(for subject: Exercise) -> [ExerciseIllustrationOption] {
        ExerciseSuggestions.similar(to: subject, in: illustratedExercises).map { option(for: $0.exercise) }
    }

    static func options(matching query: String) -> [ExerciseIllustrationOption] {
        let matches = SearchText.filter(illustratedExercises, by: query)
        return Exercise.byDisplayName(matches).map(option(for:))
    }

    private static func option(for exercise: Exercise) -> ExerciseIllustrationOption {
        ExerciseIllustrationOption(id: names[exercise.name, default: ""], name: exercise.displayName)
    }

    static func symbol(for equipment: Equipment) -> String {
        switch equipment {
        case .barbell, .dumbbell, .kettlebell: "dumbbell"
        case .machine, .cable: "figure.strengthtraining.traditional"
        case .bodyweight, .band: "figure.strengthtraining.functional"
        case .other: "figure.mixed.cardio"
        }
    }

    private static let identifiers = Set(names.values)
    private static let illustratedExercises = ExerciseCatalog.builtIn.filter { names[$0.name] != nil }

    private static let catalog: [UUID: (name: String, equipment: Equipment)] = Dictionary(
        uniqueKeysWithValues: illustratedExercises.compactMap { exercise in
            names[exercise.name].map { (exercise.id, (name: $0, equipment: exercise.equipment)) }
        }
    )

    // Keys are the built-in English names. The lookup uses stable IDs and the original equipment.
    private static let names: [String: String] = [
        "Bench Press (Barbell)": "bench-press",
        "Incline Bench Press (Barbell)": "incline-bench-press",
        "Incline Bench Press (Dumbbell)": "incline-dumbbell-press",
        "Bench Press (Dumbbell)": "dumbbell-bench-press",
        "Chest Press (Machine)": "machine-chest-press",
        "Pec Deck (Machine)": "pec-deck",
        "Chest Fly (Dumbbell)": "dumbbell-fly",
        "Cable Crossover": "cable-fly",
        "Decline Bench Press (Barbell)": "decline-bench-press",
        "Bench Press - Close Grip (Barbell)": "close-grip-bench-press",
        "Incline Push Up": "incline-push-up",
        "Push Up": "push-up",
        "Bent Over Row (Barbell)": "barbell-row",
        "Bent Over One Arm Row (Dumbbell)": "one-arm-dumbbell-row",
        "Seated Row (Cable)": "seated-row",
        "Lat Pulldown (Cable)": "lat-pulldown",
        "Shrug (Dumbbell)": "dumbbell-shrug",
        "Shrug (Barbell)": "shrug",
        "Pendlay Row (Barbell)": "pendlay-row",
        "Seated Row (Machine)": "machine-row",
        "Straight Arm Pulldown (Cable)": "straight-arm-pulldown",
        "Inverted Row": "inverted-row",
        "Back Extension": "back-extension",
        "Rack Pull (Barbell)": "rack-pull",
        "Overhead Press (Barbell)": "overhead-press",
        "Seated Overhead Press (Dumbbell)": "seated-dumbbell-press",
        "Arnold Press (Dumbbell)": "arnold-press",
        "Lateral Raise (Dumbbell)": "lateral-raise",
        "Lateral Raise (Cable)": "cable-lateral-raise",
        "Face Pull (Cable)": "face-pull",
        "Reverse Fly (Machine)": "reverse-pec-deck",
        "Reverse Fly (Dumbbell)": "rear-delt-fly",
        "Shoulder Press (Machine)": "machine-shoulder-press",
        "Push Press (Barbell)": "push-press",
        "Landmine Press": "landmine-press",
        "Front Raise (Dumbbell)": "front-raise",
        "Upright Row (Barbell)": "upright-row",
        "Bicep Curl (Dumbbell)": "bicep-curl",
        "Hammer Curl (Dumbbell)": "hammer-curl",
        "Incline Curl (Dumbbell)": "incline-dumbbell-curl",
        "Bicep Curl (Cable)": "cable-curl",
        "Concentration Curl (Dumbbell)": "concentration-curl",
        "Skullcrusher (Barbell)": "skull-crusher",
        "Triceps Extension": "dumbbell-overhead-tricep-extension",
        "Triceps Pushdown (Cable - Straight Bar)": "tricep-pushdown",
        "Triceps Pushdown (Cable - Rope)": "rope-tricep-pushdown",
        "Overhead Triceps Extension (Cable)": "overhead-tricep-extension",
        "Wrist Curl (Barbell)": "wrist-curl",
        "Squat (Barbell)": "squat",
        "Front Squat (Barbell)": "front-squat",
        "Hack Squat": "hack-squat",
        "Leg Press": "leg-press",
        "Leg Extension (Machine)": "leg-extension",
        "Bulgarian Split Squat": "bulgarian-split-squat",
        "Walking Lunge (Dumbbell)": "walking-lunge",
        "Reverse Lunge (Dumbbell)": "reverse-lunge",
        "Split Squat (Dumbbell)": "split-squat",
        "Squat (Smith Machine)": "smith-machine-squat",
        "Goblet Squat (Dumbbell)": "goblet-squat",
        "Pistol Squat": "pistol-squat",
        "Air Squat": "bodyweight-squat",
        "Step Up (Dumbbell)": "step-up",
        "Deadlift (Barbell)": "deadlift",
        "Sumo Deadlift (Barbell)": "sumo-deadlift",
        "Romanian Deadlift (Barbell)": "romanian-deadlift",
        "Romanian Deadlift (Dumbbell)": "dumbbell-romanian-deadlift",
        "Single Leg Romanian Deadlift (Dumbbell)": "single-leg-romanian-deadlift",
        "Trap Bar Deadlift": "trap-bar-deadlift",
        "Good Morning (Barbell)": "good-morning",
        "Hip Thrust (Barbell)": "hip-thrust",
        "Glute Bridge": "glute-bridge",
        "Hip Abduction (Machine)": "hip-abduction-machine",
        "Hip Adduction (Machine)": "hip-adduction-machine",
        "Glute Kickback (Cable)": "cable-kickback",
        "Lying Leg Curl (Machine)": "lying-leg-curl",
        "Seated Leg Curl (Machine)": "seated-leg-curl",
        "Nordic Hamstring Curl": "nordic-hamstring-curl",
        "Kettlebell Swing": "kettlebell-swing",
        "Seated Calf Raise (Plate Loaded)": "seated-calf-raise",
        "Standing Calf Raise (Machine)": "standing-calf-raise",
        "Calf Press on Leg Press": "leg-press-calf-raise",
        "Rowing (Machine)": "rowing",
        "Farmers Walk": "farmer-carry",
        "Burpee": "burpee",
        "Pull Up": "pull-up",
        "Chin Up": "chin-up",
        "Pull Up (Assisted)": "assisted-pull-up",
        "Chest Dip": "chest-dip",
        "Triceps Dip": "bench-dip",
        "Plank": "plank",
        "Side Plank": "side-plank",
        "Hollow Body": "hollow-body-hold",
        "Dead Bug": "dead-bug",
        "Crunch": "crunch",
        "Hanging Leg Raise": "hanging-leg-raise",
        "Ab Wheel": "ab-wheel",
        "Cable Crunch": "cable-crunch",
        "Russian Twist": "russian-twist",
        "Lying Leg Raise": "lying-leg-raise",
        "Pallof Press": "pallof-press",
        "Mountain Climber": "mountain-climber",
        "Bird Dog": "bird-dog",
    ]
}

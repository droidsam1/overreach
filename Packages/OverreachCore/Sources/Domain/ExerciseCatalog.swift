import Foundation

/// Built-in exercise catalog.
///
/// - Names follow Strong's convention ("Name (Equipment)") so Strong exports match without extra mapping.
/// - Each built-in exercise has a Spanish name, shown when the app runs in Spanish or Galician (ADR-0031).
/// - Aliases hold other common Spanish names and variants, used by importers and search.
/// - Ids are stable (`UUID.stable`), so the same exercise has the same id on every install.
///
/// Users start from this list and can add custom exercises; an import adds unknown names as custom exercises
/// that still need a muscle-group mapping.
public enum ExerciseCatalog {
    public static let builtIn: [Exercise] = entries.map(\.exercise)

    /// The catalog's English name of a built-in exercise, or `nil` for any other id.
    public static func englishName(of id: UUID) -> String? { names[id]?.english }

    /// The Spanish name of a built-in exercise, or `nil` for any other id.
    public static func spanishName(of id: UUID) -> String? { names[id]?.spanish }

    private struct Entry {
        let exercise: Exercise
        let spanish: String
    }

    private static let entries: [Entry] = strength + bodyweightAndCore

    private static let names: [UUID: (english: String, spanish: String)] = Dictionary(
        entries.map { ($0.exercise.id, ($0.exercise.name, $0.spanish)) }, uniquingKeysWith: { first, _ in first }
    )

    // swiftlint:disable line_length
    private static let strength: [Entry] = [
        // Chest
        make("Bench Press (Barbell)", es: "Press de banca (barra)", [.chest], [.triceps, .shoulders], .barbell, ["press banca", "press de banca", "banca", "bench press"]),
        make("Incline Bench Press (Barbell)", es: "Press inclinado (barra)", [.chest], [.shoulders, .triceps], .barbell, ["press inclinado con barra", "press banca inclinado"]),
        make("Incline Bench Press (Dumbbell)", es: "Press inclinado (mancuernas)", [.chest], [.shoulders, .triceps], .dumbbell, ["press inclinado con mancuernas", "press inclinado mancuernas"]),
        make("Incline Bench Press (Smith Machine)", es: "Press inclinado (multipower)", [.chest], [.shoulders, .triceps], .machine, ["press inclinado en multipower", "press inclinado smith"]),
        make("Bench Press (Dumbbell)", es: "Press de banca (mancuernas)", [.chest], [.triceps, .shoulders], .dumbbell, ["press banca con mancuernas", "press plano mancuernas"]),
        make("Incline Chest Press (Machine)", es: "Press de pecho inclinado (máquina)", [.chest], [.shoulders, .triceps], .machine, ["press inclinado en maquina"]),
        make("Chest Press (Machine)", es: "Press de pecho (máquina)", [.chest], [.triceps, .shoulders], .machine, ["press de pecho en maquina"]),
        make("Pec Deck (Machine)", es: "Contractora (máquina)", [.chest], [.shoulders], .machine, ["contractora", "pec deck", "aperturas en maquina"]),
        make("Chest Fly (Dumbbell)", es: "Aperturas (mancuernas)", [.chest], [.shoulders], .dumbbell, ["aperturas con mancuernas", "aperturas"]),
        make("Incline Chest Fly (Dumbbell)", es: "Aperturas inclinadas (mancuernas)", [.chest], [.shoulders], .dumbbell, ["aperturas inclinadas"]),
        make("Cable Crossover", es: "Cruce de poleas", [.chest], [.shoulders], .cable, ["cruce de poleas", "cruces en polea"]),

        // Back
        make("Bent Over Row (Barbell)", es: "Remo inclinado (barra)", [.back], [.biceps, .forearms], .barbell, ["remo con barra", "remo inclinado con barra"]),
        make("Bent Over One Arm Row (Dumbbell)", es: "Remo a una mano (mancuerna)", [.back], [.biceps], .dumbbell, ["remo con mancuerna", "remo a una mano", "remo unilateral"]),
        make("Incline Row (Dumbbell)", es: "Remo en banco inclinado (mancuernas)", [.back], [.biceps, .shoulders], .dumbbell, ["remo en banco inclinado", "remo inclinado con mancuernas"]),
        make("Seated Row (Cable)", es: "Remo sentado (polea)", [.back], [.biceps], .cable, ["remo sentado", "remo en polea baja", "remo gironda"]),
        make("Lat Pulldown (Cable)", es: "Jalón al pecho (polea)", [.back], [.biceps], .cable, ["jalon al pecho", "jalon", "polea al pecho"]),
        make("T Bar Row", es: "Remo en T", [.back], [.biceps], .barbell, ["remo en t", "remo t"]),
        make("Shrug (Dumbbell)", es: "Encogimientos (mancuernas)", [.back], [.forearms], .dumbbell, ["encogimientos", "encogimientos de hombros"]),

        // Shoulders
        make("Strict Military Press (Barbell)", es: "Press militar estricto (barra)", [.shoulders], [.triceps, .core], .barbell, ["press militar", "press militar estricto"]),
        make("Overhead Press (Barbell)", es: "Press de hombros (barra)", [.shoulders], [.triceps, .core], .barbell, ["press de hombros con barra", "ohp"]),
        make("Seated Overhead Press (Dumbbell)", es: "Press de hombros sentado (mancuernas)", [.shoulders], [.triceps], .dumbbell, ["press de hombros con mancuernas", "press hombro sentado"]),
        make("Arnold Press (Dumbbell)", es: "Press Arnold (mancuernas)", [.shoulders], [.triceps], .dumbbell, ["press arnold"]),
        make("Lateral Raise (Dumbbell)", es: "Elevaciones laterales (mancuernas)", [.shoulders], [], .dumbbell, ["elevaciones laterales", "elevaciones laterales con mancuernas"]),
        make("Lateral Raise (Cable)", es: "Elevaciones laterales (polea)", [.shoulders], [], .cable, ["elevaciones laterales en polea"]),
        make("Face Pull (Cable)", es: "Face pull (polea)", [.shoulders], [.back], .cable, ["face pull", "tiron a la cara"]),
        make("Reverse Fly (Machine)", es: "Pájaros (máquina)", [.shoulders], [.back], .machine, ["pajaros en maquina", "contractora inversa"]),
        make("Reverse Fly (Dumbbell)", es: "Pájaros (mancuernas)", [.shoulders], [.back], .dumbbell, ["pajaros", "pajaros con mancuernas"]),

        // Arms
        make("Bicep Curl (Dumbbell)", es: "Curl de bíceps (mancuernas)", [.biceps], [.forearms], .dumbbell, ["curl de biceps", "curl con mancuernas", "curl biceps"]),
        make("Bicep Curl (Barbell)", es: "Curl de bíceps (barra)", [.biceps], [.forearms], .barbell, ["curl con barra"]),
        make("Hammer Curl (Dumbbell)", es: "Curl martillo (mancuernas)", [.biceps, .forearms], [], .dumbbell, ["curl martillo"]),
        make("Incline Curl (Dumbbell)", es: "Curl inclinado (mancuernas)", [.biceps], [], .dumbbell, ["curl inclinado"]),
        make("Preacher Curl (Barbell)", es: "Curl predicador (barra)", [.biceps], [], .barbell, ["curl predicador", "curl scott"]),
        make("French Press", es: "Press francés", [.triceps], [], .barbell, ["press frances"]),
        make("Skullcrusher (Barbell)", es: "Rompecráneos (barra)", [.triceps], [], .barbell, ["rompecraneos"]),
        make("Triceps Extension", es: "Extensión de tríceps", [.triceps], [], .dumbbell, ["extension de triceps", "extension de triceps sobre la cabeza"]),
        make("Triceps Pushdown (Cable - Straight Bar)", es: "Extensión de tríceps en polea (barra recta)", [.triceps], [], .cable, ["extension de triceps en polea", "jalon de triceps", "triceps en polea"]),
        make("Triceps Pushdown (Cable - Rope)", es: "Extensión de tríceps en polea (cuerda)", [.triceps], [], .cable, ["triceps en polea con cuerda"]),

        // Legs
        make("Squat (Barbell)", es: "Sentadilla (barra)", [.quadriceps, .glutes], [.hamstrings, .core], .barbell, ["sentadilla", "sentadilla trasera", "sentadilla con barra", "back squat"]),
        make("Front Squat (Barbell)", es: "Sentadilla frontal (barra)", [.quadriceps], [.glutes, .core], .barbell, ["sentadilla frontal", "front squat"]),
        make("Goblet Squat (Kettlebell)", es: "Sentadilla goblet (kettlebell)", [.quadriceps, .glutes], [.core], .kettlebell, ["sentadilla goblet", "sentadilla copa"]),
        make("Hack Squat", es: "Sentadilla hack", [.quadriceps], [.glutes], .machine, ["sentadilla hack", "hack"]),
        make("Leg Press", es: "Prensa de piernas", [.quadriceps, .glutes], [.hamstrings], .machine, ["prensa", "prensa de piernas"]),
        make("Leg Extension (Machine)", es: "Extensión de cuádriceps (máquina)", [.quadriceps], [], .machine, ["extension de cuadriceps", "extensiones de pierna"]),
        make("Bulgarian Split Squat", es: "Sentadilla búlgara", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["sentadilla bulgara", "bulgaras"]),
        make("Lunge (Dumbbell)", es: "Zancadas (mancuernas)", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["zancadas", "zancadas con mancuernas", "lunges"]),
        make("Step Up (Dumbbell)", es: "Subidas al cajón (mancuernas)", [.quadriceps, .glutes], [], .dumbbell, ["subidas al cajon", "step up"]),
        make("Deadlift (Barbell)", es: "Peso muerto (barra)", [.hamstrings, .glutes, .back], [.quadriceps, .forearms], .barbell, ["peso muerto", "peso muerto convencional"]),
        make("Sumo Deadlift (Barbell)", es: "Peso muerto sumo (barra)", [.glutes, .quadriceps, .hamstrings], [.back], .barbell, ["peso muerto sumo"]),
        make("Romanian Deadlift (Barbell)", es: "Peso muerto rumano (barra)", [.hamstrings, .glutes], [.back], .barbell, ["peso muerto rumano", "rumano", "rdl"]),
        make("Romanian Deadlift (Dumbbell)", es: "Peso muerto rumano (mancuernas)", [.hamstrings, .glutes], [.back], .dumbbell, ["peso muerto rumano con mancuernas"]),
        make("Good Morning (Barbell)", es: "Buenos días (barra)", [.hamstrings], [.back, .glutes], .barbell, ["buenos dias"]),
        make("Hip Thrust (Barbell)", es: "Hip thrust (barra)", [.glutes], [.hamstrings], .barbell, ["hip thrust", "empuje de cadera"]),
        make("Glute Bridge", es: "Puente de glúteos", [.glutes], [.hamstrings], .bodyweight, ["puente de gluteos", "puente"]),
        make("Hip Abduction (Machine)", es: "Abducción de cadera (máquina)", [.glutes], [], .machine, ["abductores", "abduccion de cadera"]),
        make("Lying Leg Curl (Machine)", es: "Curl femoral tumbado (máquina)", [.hamstrings], [.calves], .machine, ["curl femoral tumbado", "curl femoral"]),
        make("Seated Leg Curl (Machine)", es: "Curl femoral sentado (máquina)", [.hamstrings], [], .machine, ["curl femoral sentado"]),
        make("Kettlebell Swing", es: "Swing con kettlebell", [.glutes, .hamstrings], [.back, .core], .kettlebell, ["swing con kettlebell", "swing"]),
        make("Standing Calf Raise (Dumbbell)", es: "Elevación de talones de pie (mancuernas)", [.calves], [], .dumbbell, ["gemelos de pie", "elevacion de talones"]),
        make("Seated Calf Raise (Plate Loaded)", es: "Elevación de talones sentado (discos)", [.calves], [], .machine, ["gemelos sentado", "soleo sentado"]),
        // The tibialis anterior is attributed to the lower-leg group closest to it.
        make("Tibialis Raises", es: "Elevaciones de tibial", [.calves], [], .bodyweight, ["elevaciones de tibial", "tibial"]),

        // Conditioning
        make("Rowing (Machine)", es: "Remoergómetro", [.back], [.quadriceps, .hamstrings, .biceps], .machine, ["remo ergometro", "remoergometro"]),
    ]

    private static let bodyweightAndCore: [Entry] = [
        make("Pull Up", es: "Dominadas", [.back], [.biceps, .forearms], .bodyweight, ["dominadas", "dominadas pronas"]),
        make("Chin Up", es: "Dominadas supinas", [.back, .biceps], [.forearms], .bodyweight, ["dominadas supinas", "chin up"]),
        make("Push Up", es: "Flexiones", [.chest], [.triceps, .shoulders], .bodyweight, ["flexiones", "fondos de suelo"]),
        make("Chest Dip", es: "Fondos de pecho", [.chest], [.triceps, .shoulders], .bodyweight, ["fondos", "fondos de pecho", "fondos en paralelas"]),
        make("Triceps Dip", es: "Fondos de tríceps", [.triceps], [.chest, .shoulders], .bodyweight, ["fondos de triceps", "fondos en banco"]),
        make("Plank", es: "Plancha", [.core], [], .bodyweight, ["plancha", "plancha abdominal"]),
        make("Side Plank", es: "Plancha lateral", [.core], [], .bodyweight, ["plancha lateral"]),
        make("Hollow Body", es: "Hollow body", [.core], [], .bodyweight, ["hollow", "hollow hold"]),
        make("Dead Bug", es: "Dead bug", [.core], [], .bodyweight, ["bicho muerto"]),
        make("Crunch", es: "Crunch abdominal", [.core], [], .bodyweight, ["abdominales", "crunch abdominal"]),
        make("Hanging Leg Raise", es: "Elevación de piernas colgado", [.core], [.forearms], .bodyweight, ["elevaciones de piernas colgado", "elevacion de piernas"]),
        make("Ab Wheel", es: "Rueda abdominal", [.core], [.shoulders], .other, ["rueda abdominal", "rueda"]),
    ]
    // swiftlint:enable line_length

    private static func make(
        _ name: String,
        es spanish: String,
        _ primary: Set<MuscleGroup>,
        _ secondary: Set<MuscleGroup>,
        _ equipment: Equipment,
        _ aliases: Set<String>
    ) -> Entry {
        let exercise = Exercise(
            id: .stable("builtin-exercise|\(name)"),
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            equipment: equipment,
            isCustom: false,
            aliases: aliases
        )
        return Entry(exercise: exercise, spanish: spanish)
    }
}

extension Exercise {
    /// Every name the exercise answers to, for matching and search: its name, the catalog's Spanish name of a
    /// built-in exercise and its aliases.
    public var knownNames: [String] {
        [name] + (ExerciseCatalog.spanishName(of: id).map { [$0] } ?? []) + aliases.sorted()
    }
}

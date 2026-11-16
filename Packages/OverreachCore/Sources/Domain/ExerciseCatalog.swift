import Foundation

/// Built-in exercise catalog.
///
/// - Names follow Strong's convention ("Name (Equipment)") so Strong exports match without extra mapping.
/// - Aliases hold common Spanish names and variants, used by importers and search.
/// - Ids are stable (`UUID.stable`), so the same exercise has the same id on every install.
///
/// Users start from this list and can add custom exercises; an import adds unknown names as custom exercises
/// that still need a muscle-group mapping.
public enum ExerciseCatalog {
    public static let builtIn: [Exercise] = strength + bodyweightAndCore

    // swiftlint:disable line_length
    private static let strength: [Exercise] = [
        // Chest
        make("Bench Press (Barbell)", [.chest], [.triceps, .shoulders], .barbell, ["press banca", "press de banca", "banca", "bench press"]),
        make("Incline Bench Press (Barbell)", [.chest], [.shoulders, .triceps], .barbell, ["press inclinado con barra", "press banca inclinado"]),
        make("Incline Bench Press (Dumbbell)", [.chest], [.shoulders, .triceps], .dumbbell, ["press inclinado con mancuernas", "press inclinado mancuernas"]),
        make("Incline Bench Press (Smith Machine)", [.chest], [.shoulders, .triceps], .machine, ["press inclinado en multipower", "press inclinado smith"]),
        make("Bench Press (Dumbbell)", [.chest], [.triceps, .shoulders], .dumbbell, ["press banca con mancuernas", "press plano mancuernas"]),
        make("Incline Chest Press (Machine)", [.chest], [.shoulders, .triceps], .machine, ["press inclinado en maquina"]),
        make("Chest Press (Machine)", [.chest], [.triceps, .shoulders], .machine, ["press de pecho en maquina"]),
        make("Pec Deck (Machine)", [.chest], [.shoulders], .machine, ["contractora", "pec deck", "aperturas en maquina"]),
        make("Chest Fly (Dumbbell)", [.chest], [.shoulders], .dumbbell, ["aperturas con mancuernas", "aperturas"]),
        make("Incline Chest Fly (Dumbbell)", [.chest], [.shoulders], .dumbbell, ["aperturas inclinadas"]),
        make("Cable Crossover", [.chest], [.shoulders], .cable, ["cruce de poleas", "cruces en polea"]),

        // Back
        make("Bent Over Row (Barbell)", [.back], [.biceps, .forearms], .barbell, ["remo con barra", "remo inclinado con barra"]),
        make("Bent Over One Arm Row (Dumbbell)", [.back], [.biceps], .dumbbell, ["remo con mancuerna", "remo a una mano", "remo unilateral"]),
        make("Incline Row (Dumbbell)", [.back], [.biceps, .shoulders], .dumbbell, ["remo en banco inclinado", "remo inclinado con mancuernas"]),
        make("Seated Row (Cable)", [.back], [.biceps], .cable, ["remo sentado", "remo en polea baja", "remo gironda"]),
        make("Lat Pulldown (Cable)", [.back], [.biceps], .cable, ["jalon al pecho", "jalon", "polea al pecho"]),
        make("T Bar Row", [.back], [.biceps], .barbell, ["remo en t", "remo t"]),
        make("Shrug (Dumbbell)", [.back], [.forearms], .dumbbell, ["encogimientos", "encogimientos de hombros"]),

        // Shoulders
        make("Strict Military Press (Barbell)", [.shoulders], [.triceps, .core], .barbell, ["press militar", "press militar estricto"]),
        make("Overhead Press (Barbell)", [.shoulders], [.triceps, .core], .barbell, ["press de hombros con barra", "ohp"]),
        make("Seated Overhead Press (Dumbbell)", [.shoulders], [.triceps], .dumbbell, ["press de hombros con mancuernas", "press hombro sentado"]),
        make("Arnold Press (Dumbbell)", [.shoulders], [.triceps], .dumbbell, ["press arnold"]),
        make("Lateral Raise (Dumbbell)", [.shoulders], [], .dumbbell, ["elevaciones laterales", "elevaciones laterales con mancuernas"]),
        make("Lateral Raise (Cable)", [.shoulders], [], .cable, ["elevaciones laterales en polea"]),
        make("Face Pull (Cable)", [.shoulders], [.back], .cable, ["face pull", "tiron a la cara"]),
        make("Reverse Fly (Machine)", [.shoulders], [.back], .machine, ["pajaros en maquina", "contractora inversa"]),
        make("Reverse Fly (Dumbbell)", [.shoulders], [.back], .dumbbell, ["pajaros", "pajaros con mancuernas"]),

        // Arms
        make("Bicep Curl (Dumbbell)", [.biceps], [.forearms], .dumbbell, ["curl de biceps", "curl con mancuernas", "curl biceps"]),
        make("Bicep Curl (Barbell)", [.biceps], [.forearms], .barbell, ["curl con barra"]),
        make("Hammer Curl (Dumbbell)", [.biceps, .forearms], [], .dumbbell, ["curl martillo"]),
        make("Incline Curl (Dumbbell)", [.biceps], [], .dumbbell, ["curl inclinado"]),
        make("Preacher Curl (Barbell)", [.biceps], [], .barbell, ["curl predicador", "curl scott"]),
        make("French Press", [.triceps], [], .barbell, ["press frances"]),
        make("Skullcrusher (Barbell)", [.triceps], [], .barbell, ["rompecraneos"]),
        make("Triceps Extension", [.triceps], [], .dumbbell, ["extension de triceps", "extension de triceps sobre la cabeza"]),
        make("Triceps Pushdown (Cable - Straight Bar)", [.triceps], [], .cable, ["extension de triceps en polea", "jalon de triceps", "triceps en polea"]),
        make("Triceps Pushdown (Cable - Rope)", [.triceps], [], .cable, ["triceps en polea con cuerda"]),

        // Legs
        make("Squat (Barbell)", [.quadriceps, .glutes], [.hamstrings, .core], .barbell, ["sentadilla", "sentadilla trasera", "sentadilla con barra", "back squat"]),
        make("Front Squat (Barbell)", [.quadriceps], [.glutes, .core], .barbell, ["sentadilla frontal", "front squat"]),
        make("Goblet Squat (Kettlebell)", [.quadriceps, .glutes], [.core], .kettlebell, ["sentadilla goblet", "sentadilla copa"]),
        make("Hack Squat", [.quadriceps], [.glutes], .machine, ["sentadilla hack", "hack"]),
        make("Leg Press", [.quadriceps, .glutes], [.hamstrings], .machine, ["prensa", "prensa de piernas"]),
        make("Leg Extension (Machine)", [.quadriceps], [], .machine, ["extension de cuadriceps", "extensiones de pierna"]),
        make("Bulgarian Split Squat", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["sentadilla bulgara", "bulgaras"]),
        make("Lunge (Dumbbell)", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["zancadas", "zancadas con mancuernas", "lunges"]),
        make("Step Up (Dumbbell)", [.quadriceps, .glutes], [], .dumbbell, ["subidas al cajon", "step up"]),
        make("Deadlift (Barbell)", [.hamstrings, .glutes, .back], [.quadriceps, .forearms], .barbell, ["peso muerto", "peso muerto convencional"]),
        make("Sumo Deadlift (Barbell)", [.glutes, .quadriceps, .hamstrings], [.back], .barbell, ["peso muerto sumo"]),
        make("Romanian Deadlift (Barbell)", [.hamstrings, .glutes], [.back], .barbell, ["peso muerto rumano", "rumano", "rdl"]),
        make("Romanian Deadlift (Dumbbell)", [.hamstrings, .glutes], [.back], .dumbbell, ["peso muerto rumano con mancuernas"]),
        make("Good Morning (Barbell)", [.hamstrings], [.back, .glutes], .barbell, ["buenos dias"]),
        make("Hip Thrust (Barbell)", [.glutes], [.hamstrings], .barbell, ["hip thrust", "empuje de cadera"]),
        make("Glute Bridge", [.glutes], [.hamstrings], .bodyweight, ["puente de gluteos", "puente"]),
        make("Hip Abduction (Machine)", [.glutes], [], .machine, ["abductores", "abduccion de cadera"]),
        make("Lying Leg Curl (Machine)", [.hamstrings], [.calves], .machine, ["curl femoral tumbado", "curl femoral"]),
        make("Seated Leg Curl (Machine)", [.hamstrings], [], .machine, ["curl femoral sentado"]),
        make("Kettlebell Swing", [.glutes, .hamstrings], [.back, .core], .kettlebell, ["swing con kettlebell", "swing"]),
        make("Standing Calf Raise (Dumbbell)", [.calves], [], .dumbbell, ["gemelos de pie", "elevacion de talones"]),
        make("Seated Calf Raise (Plate Loaded)", [.calves], [], .machine, ["gemelos sentado", "soleo sentado"]),
        // The tibialis anterior is attributed to the lower-leg group closest to it.
        make("Tibialis Raises", [.calves], [], .bodyweight, ["elevaciones de tibial", "tibial"]),

        // Conditioning
        make("Rowing (Machine)", [.back], [.quadriceps, .hamstrings, .biceps], .machine, ["remo ergometro", "remoergometro"]),
    ]

    private static let bodyweightAndCore: [Exercise] = [
        make("Pull Up", [.back], [.biceps, .forearms], .bodyweight, ["dominadas", "dominadas pronas"]),
        make("Chin Up", [.back, .biceps], [.forearms], .bodyweight, ["dominadas supinas", "chin up"]),
        make("Push Up", [.chest], [.triceps, .shoulders], .bodyweight, ["flexiones", "fondos de suelo"]),
        make("Chest Dip", [.chest], [.triceps, .shoulders], .bodyweight, ["fondos", "fondos de pecho", "fondos en paralelas"]),
        make("Triceps Dip", [.triceps], [.chest, .shoulders], .bodyweight, ["fondos de triceps", "fondos en banco"]),
        make("Plank", [.core], [], .bodyweight, ["plancha", "plancha abdominal"]),
        make("Side Plank", [.core], [], .bodyweight, ["plancha lateral"]),
        make("Hollow Body", [.core], [], .bodyweight, ["hollow", "hollow hold"]),
        make("Dead Bug", [.core], [], .bodyweight, ["bicho muerto"]),
        make("Crunch", [.core], [], .bodyweight, ["abdominales", "crunch abdominal"]),
        make("Hanging Leg Raise", [.core], [.forearms], .bodyweight, ["elevaciones de piernas colgado", "elevacion de piernas"]),
        make("Ab Wheel", [.core], [.shoulders], .other, ["rueda abdominal", "rueda"]),
    ]
    // swiftlint:enable line_length

    private static func make(
        _ name: String,
        _ primary: Set<MuscleGroup>,
        _ secondary: Set<MuscleGroup>,
        _ equipment: Equipment,
        _ aliases: Set<String>
    ) -> Exercise {
        Exercise(
            id: .stable("builtin-exercise|\(name)"),
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            equipment: equipment,
            isCustom: false,
            aliases: aliases
        )
    }
}

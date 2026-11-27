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

    /// The current definition for an exercise with a stable built-in id.
    static func exercise(withID id: UUID) -> Exercise? { definitions[id] }

    /// The Spanish name of a built-in exercise, or `nil` for any other id.
    public static func spanishName(of id: UUID) -> String? { names[id]?.spanish }

    private struct Entry {
        let exercise: Exercise
        let spanish: String
    }

    private static let entries: [Entry] = strength + bodyweightAndCore

    private static let definitions = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })

    private static let names: [UUID: (english: String, spanish: String)] = Dictionary(
        entries.map { ($0.exercise.id, ($0.exercise.name, $0.spanish)) }, uniquingKeysWith: { first, _ in first }
    )

    // swiftlint:disable line_length
    private static let strength: [Entry] = [
        // Chest
        make("Bench Press (Barbell)", es: "Press de banca (barra)", [.chest], [.triceps, .frontDelts], .barbell, ["press banca", "press de banca", "banca", "bench press"], pattern: .horizontalPush),
        make("Incline Bench Press (Barbell)", es: "Press inclinado (barra)", [.chest], [.frontDelts, .triceps], .barbell, ["press inclinado con barra", "press banca inclinado"], pattern: .horizontalPush),
        make("Incline Bench Press (Dumbbell)", es: "Press inclinado (mancuernas)", [.chest], [.frontDelts, .triceps], .dumbbell, ["press inclinado con mancuernas", "press inclinado mancuernas"], pattern: .horizontalPush),
        make("Incline Bench Press (Smith Machine)", es: "Press inclinado (multipower)", [.chest], [.frontDelts, .triceps], .machine, ["press inclinado en multipower", "press inclinado smith"], pattern: .horizontalPush),
        make("Bench Press (Dumbbell)", es: "Press de banca (mancuernas)", [.chest], [.triceps, .frontDelts], .dumbbell, ["press banca con mancuernas", "press plano mancuernas"], pattern: .horizontalPush),
        make("Incline Chest Press (Machine)", es: "Press de pecho inclinado (máquina)", [.chest], [.frontDelts, .triceps], .machine, ["press inclinado en maquina"], pattern: .horizontalPush),
        make("Chest Press (Machine)", es: "Press de pecho (máquina)", [.chest], [.triceps, .frontDelts], .machine, ["press de pecho en maquina"], pattern: .horizontalPush),
        make("Pec Deck (Machine)", es: "Contractora (máquina)", [.chest], [.frontDelts], .machine, ["contractora", "pec deck", "aperturas en maquina"]),
        make("Chest Fly (Dumbbell)", es: "Aperturas (mancuernas)", [.chest], [.frontDelts], .dumbbell, ["aperturas con mancuernas", "aperturas"]),
        make("Incline Chest Fly (Dumbbell)", es: "Aperturas inclinadas (mancuernas)", [.chest], [.frontDelts], .dumbbell, ["aperturas inclinadas"]),
        make("Cable Crossover", es: "Cruce de poleas", [.chest], [.frontDelts], .cable, ["cruce de poleas", "cruces en polea"]),
        make("Decline Bench Press (Barbell)", es: "Press declinado (barra)", [.chest], [.triceps, .frontDelts], .barbell, ["press declinado", "press banca declinado"], pattern: .horizontalPush),
        make("Bench Press - Close Grip (Barbell)", es: "Press de banca agarre cerrado (barra)", [.triceps, .chest], [.frontDelts], .barbell, ["press cerrado", "press de banca agarre estrecho", "close grip bench press"], pattern: .horizontalPush),
        make("Incline Push Up", es: "Flexiones inclinadas", [.chest], [.triceps, .frontDelts], .bodyweight, ["flexiones inclinadas", "flexiones con las manos en el banco"], pattern: .horizontalPush),

        // Back
        make("Bent Over Row (Barbell)", es: "Remo inclinado (barra)", [.upperBack], [.biceps, .forearms], .barbell, ["remo con barra", "remo inclinado con barra"], pattern: .horizontalPull),
        make("Bent Over One Arm Row (Dumbbell)", es: "Remo a una mano (mancuerna)", [.lats], [.biceps], .dumbbell, ["remo con mancuerna", "remo a una mano", "remo unilateral"], pattern: .horizontalPull),
        make("Incline Row (Dumbbell)", es: "Remo en banco inclinado (mancuernas)", [.upperBack], [.biceps, .rearDelts], .dumbbell, ["remo en banco inclinado", "remo inclinado con mancuernas"], pattern: .horizontalPull),
        make("Seated Row (Cable)", es: "Remo sentado (polea)", [.upperBack], [.biceps], .cable, ["remo sentado", "remo en polea baja", "remo gironda"], pattern: .horizontalPull),
        make("Lat Pulldown (Cable)", es: "Jalón al pecho (polea)", [.lats], [.biceps], .cable, ["jalon al pecho", "jalon", "polea al pecho"], pattern: .verticalPull),
        make("T Bar Row", es: "Remo en T", [.upperBack], [.biceps], .barbell, ["remo en t", "remo t"], pattern: .horizontalPull),
        make("Shrug (Dumbbell)", es: "Encogimientos (mancuernas)", [.upperBack], [.forearms], .dumbbell, ["encogimientos", "encogimientos de hombros"]),
        make("Shrug (Barbell)", es: "Encogimientos (barra)", [.upperBack], [.forearms], .barbell, ["encogimientos con barra"]),
        make("Pendlay Row (Barbell)", es: "Remo Pendlay (barra)", [.upperBack], [.biceps, .hamstrings], .barbell, ["remo pendlay", "pendlay row"], pattern: .horizontalPull),
        make("Seated Row (Machine)", es: "Remo sentado (máquina)", [.upperBack], [.biceps], .machine, ["remo en maquina", "remo sentado en maquina"], pattern: .horizontalPull),
        make("Lat Pulldown (Machine)", es: "Jalón al pecho (máquina)", [.lats], [.biceps], .machine, ["jalon en maquina", "jalon al pecho en maquina"], pattern: .verticalPull),
        make("Straight Arm Pulldown (Cable)", es: "Pullover en polea (brazos rectos)", [.lats], [.triceps], .cable, ["pullover en polea", "jalon con brazos rectos", "straight arm pulldown"], pattern: .verticalPull),
        make("Inverted Row", es: "Remo invertido", [.upperBack], [.biceps, .core], .bodyweight, ["remo invertido", "remo australiano", "dominadas australianas"], pattern: .horizontalPull),
        make("Back Extension", es: "Hiperextensiones lumbares", [.back, .glutes], [.hamstrings], .bodyweight, ["hiperextensiones", "extensiones lumbares", "hiperextension"], pattern: .hinge),
        make("Rack Pull (Barbell)", es: "Peso muerto desde soportes (barra)", [.upperBack, .glutes], [.hamstrings, .forearms], .barbell, ["rack pull", "peso muerto parcial"], pattern: .hinge),

        // Shoulders
        make("Strict Military Press (Barbell)", es: "Press militar estricto (barra)", [.frontDelts], [.sideDelts, .triceps, .core], .barbell, ["press militar", "press militar estricto"], pattern: .verticalPush),
        make("Overhead Press (Barbell)", es: "Press de hombros (barra)", [.frontDelts], [.sideDelts, .triceps, .core], .barbell, ["press de hombros con barra", "ohp"], pattern: .verticalPush),
        make("Seated Overhead Press (Dumbbell)", es: "Press de hombros sentado (mancuernas)", [.frontDelts], [.sideDelts, .triceps], .dumbbell, ["press de hombros con mancuernas", "press hombro sentado"], pattern: .verticalPush),
        make("Arnold Press (Dumbbell)", es: "Press Arnold (mancuernas)", [.frontDelts], [.sideDelts, .triceps], .dumbbell, ["press arnold"], pattern: .verticalPush),
        make("Lateral Raise (Dumbbell)", es: "Elevaciones laterales (mancuernas)", [.sideDelts], [], .dumbbell, ["elevaciones laterales", "elevaciones laterales con mancuernas"]),
        make("Lateral Raise (Cable)", es: "Elevaciones laterales (polea)", [.sideDelts], [], .cable, ["elevaciones laterales en polea"]),
        make("Face Pull (Cable)", es: "Face pull (polea)", [.rearDelts], [.upperBack], .cable, ["face pull", "tiron a la cara"]),
        make("Reverse Fly (Machine)", es: "Pájaros (máquina)", [.rearDelts], [.upperBack], .machine, ["pajaros en maquina", "contractora inversa"]),
        make("Reverse Fly (Dumbbell)", es: "Pájaros (mancuernas)", [.rearDelts], [.upperBack], .dumbbell, ["pajaros", "pajaros con mancuernas"]),
        make("Shoulder Press (Machine)", es: "Press de hombros (máquina)", [.frontDelts], [.sideDelts, .triceps], .machine, ["press de hombros en maquina"], pattern: .verticalPush),
        make("Push Press (Barbell)", es: "Push press (barra)", [.frontDelts], [.sideDelts, .triceps, .quadriceps, .core], .barbell, ["push press", "press con impulso"], pattern: .verticalPush),
        make("Landmine Press", es: "Press landmine", [.frontDelts], [.chest, .triceps, .core], .barbell, ["press landmine", "press en mina", "landmine"], pattern: .verticalPush),
        make("Front Raise (Dumbbell)", es: "Elevaciones frontales (mancuernas)", [.frontDelts], [], .dumbbell, ["elevaciones frontales", "elevaciones frontales con mancuernas"]),
        make("Upright Row (Barbell)", es: "Remo al mentón (barra)", [.sideDelts], [.upperBack, .biceps], .barbell, ["remo al menton", "remo vertical", "upright row"]),

        // Arms
        make("Bicep Curl (Dumbbell)", es: "Curl de bíceps (mancuernas)", [.biceps], [.forearms], .dumbbell, ["curl de biceps", "curl con mancuernas", "curl biceps"]),
        make("Bicep Curl (Barbell)", es: "Curl de bíceps (barra)", [.biceps], [.forearms], .barbell, ["curl con barra"]),
        make("Hammer Curl (Dumbbell)", es: "Curl martillo (mancuernas)", [.biceps, .forearms], [], .dumbbell, ["curl martillo"]),
        make("Incline Curl (Dumbbell)", es: "Curl inclinado (mancuernas)", [.biceps], [], .dumbbell, ["curl inclinado"]),
        make("Preacher Curl (Barbell)", es: "Curl predicador (barra)", [.biceps], [], .barbell, ["curl predicador", "curl scott"]),
        make("Preacher Curl (Dumbbell)", es: "Curl predicador (mancuernas)", [.biceps], [], .dumbbell, ["curl scott con mancuerna", "curl predicador con mancuerna"]),
        make("Bicep Curl (Cable)", es: "Curl de bíceps (polea)", [.biceps], [.forearms], .cable, ["curl en polea", "curl de biceps en polea"]),
        make("Concentration Curl (Dumbbell)", es: "Curl concentrado (mancuerna)", [.biceps], [], .dumbbell, ["curl concentrado"]),
        make("French Press", es: "Press francés", [.triceps], [], .barbell, ["press frances"]),
        make("Skullcrusher (Barbell)", es: "Rompecráneos (barra)", [.triceps], [], .barbell, ["rompecraneos"]),
        make("Triceps Extension", es: "Extensión de tríceps", [.triceps], [], .dumbbell, ["extension de triceps", "extension de triceps sobre la cabeza"]),
        make("Triceps Pushdown (Cable - Straight Bar)", es: "Extensión de tríceps en polea (barra recta)", [.triceps], [], .cable, ["extension de triceps en polea", "jalon de triceps", "triceps en polea"]),
        make("Triceps Pushdown (Cable - Rope)", es: "Extensión de tríceps en polea (cuerda)", [.triceps], [], .cable, ["triceps en polea con cuerda"]),
        make("Overhead Triceps Extension (Cable)", es: "Extensión de tríceps sobre la cabeza (polea)", [.triceps], [], .cable, ["extension de triceps sobre la cabeza en polea", "triceps tras nuca en polea"]),
        make("Wrist Curl (Barbell)", es: "Curl de muñeca (barra)", [.forearms], [], .barbell, ["curl de muneca", "curl de antebrazo"]),

        // Legs
        make("Squat (Barbell)", es: "Sentadilla (barra)", [.quadriceps, .glutes], [.hamstrings, .core], .barbell, ["sentadilla", "sentadilla trasera", "sentadilla con barra", "back squat"], pattern: .squat),
        make("Front Squat (Barbell)", es: "Sentadilla frontal (barra)", [.quadriceps], [.glutes, .core], .barbell, ["sentadilla frontal", "front squat"], pattern: .squat),
        make("Goblet Squat (Kettlebell)", es: "Sentadilla goblet (kettlebell)", [.quadriceps, .glutes], [.core], .kettlebell, ["sentadilla goblet", "sentadilla copa"], pattern: .squat),
        make("Hack Squat", es: "Sentadilla hack", [.quadriceps], [.glutes], .machine, ["sentadilla hack", "hack"], pattern: .squat),
        make("Leg Press", es: "Prensa de piernas", [.quadriceps, .glutes], [.hamstrings], .machine, ["prensa", "prensa de piernas"], pattern: .squat),
        make("Leg Extension (Machine)", es: "Extensión de cuádriceps (máquina)", [.quadriceps], [], .machine, ["extension de cuadriceps", "extensiones de pierna"]),
        make("Bulgarian Split Squat", es: "Sentadilla búlgara", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["sentadilla bulgara", "bulgaras"], pattern: .squat),
        make("Lunge (Dumbbell)", es: "Zancadas (mancuernas)", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["zancadas", "zancadas con mancuernas", "lunges"], pattern: .squat),
        make("Lunge (Barbell)", es: "Zancadas (barra)", [.quadriceps, .glutes], [.hamstrings, .core], .barbell, ["zancadas con barra", "zancada con barra", "barbell lunge"], pattern: .squat),
        make("Walking Lunge (Dumbbell)", es: "Zancadas caminando (mancuernas)", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["zancadas caminando", "zancadas andando", "walking lunge"], pattern: .squat),
        make("Reverse Lunge (Dumbbell)", es: "Zancadas hacia atrás (mancuernas)", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["zancadas hacia atras", "zancada inversa", "reverse lunge"], pattern: .squat),
        make("Split Squat (Dumbbell)", es: "Sentadilla dividida (mancuernas)", [.quadriceps, .glutes], [.hamstrings], .dumbbell, ["sentadilla dividida", "split squat", "zancada estatica"], pattern: .squat),
        make("Bulgarian Split Squat (Barbell)", es: "Sentadilla búlgara (barra)", [.quadriceps, .glutes], [.hamstrings, .core], .barbell, ["sentadilla bulgara con barra", "bulgaras con barra"], pattern: .squat),
        make("Squat (Smith Machine)", es: "Sentadilla (multipower)", [.quadriceps, .glutes], [.hamstrings], .machine, ["sentadilla en multipower", "sentadilla smith"], pattern: .squat),
        make("Box Squat (Barbell)", es: "Sentadilla al cajón (barra)", [.quadriceps, .glutes], [.hamstrings, .core], .barbell, ["sentadilla al cajon", "box squat"], pattern: .squat),
        make("Goblet Squat (Dumbbell)", es: "Sentadilla goblet (mancuerna)", [.quadriceps, .glutes], [.core], .dumbbell, ["sentadilla goblet con mancuerna", "sentadilla copa con mancuerna"], pattern: .squat),
        make("Pistol Squat", es: "Sentadilla pistol", [.quadriceps, .glutes], [.core], .bodyweight, ["sentadilla pistol", "sentadilla a una pierna", "pistol"], pattern: .squat),
        make("Air Squat", es: "Sentadilla sin peso", [.quadriceps, .glutes], [], .bodyweight, ["sentadilla con peso corporal", "air squat"], pattern: .squat),
        make("Step Up (Dumbbell)", es: "Subidas al cajón (mancuernas)", [.quadriceps, .glutes], [], .dumbbell, ["subidas al cajon", "step up"], pattern: .squat),
        make("Deadlift (Barbell)", es: "Peso muerto (barra)", [.hamstrings, .glutes, .back], [.quadriceps, .forearms], .barbell, ["peso muerto", "peso muerto convencional"], pattern: .hinge),
        make("Sumo Deadlift (Barbell)", es: "Peso muerto sumo (barra)", [.glutes, .quadriceps, .hamstrings], [.back], .barbell, ["peso muerto sumo"], pattern: .hinge),
        make("Romanian Deadlift (Barbell)", es: "Peso muerto rumano (barra)", [.hamstrings, .glutes], [.back], .barbell, ["peso muerto rumano", "rumano", "rdl"], pattern: .hinge),
        make("Romanian Deadlift (Dumbbell)", es: "Peso muerto rumano (mancuernas)", [.hamstrings, .glutes], [.back], .dumbbell, ["peso muerto rumano con mancuernas"], pattern: .hinge),
        make("Single Leg Romanian Deadlift (Dumbbell)", es: "Peso muerto rumano a una pierna (mancuerna)", [.hamstrings, .glutes], [.core], .dumbbell, ["peso muerto a una pierna", "peso muerto unilateral", "single leg rdl"], pattern: .hinge),
        make("Trap Bar Deadlift", es: "Peso muerto con barra hexagonal", [.quadriceps, .glutes, .hamstrings], [.back, .forearms], .barbell, ["peso muerto hexagonal", "barra hexagonal", "trap bar"], pattern: .hinge),
        make("Stiff Leg Deadlift (Barbell)", es: "Peso muerto piernas rígidas (barra)", [.hamstrings, .glutes], [.back], .barbell, ["peso muerto piernas rigidas", "peso muerto piernas rectas"], pattern: .hinge),
        make("Good Morning (Barbell)", es: "Buenos días (barra)", [.hamstrings], [.back, .glutes], .barbell, ["buenos dias"], pattern: .hinge),
        make("Hip Thrust (Barbell)", es: "Hip thrust (barra)", [.glutes], [.hamstrings], .barbell, ["hip thrust", "empuje de cadera"]),
        make("Glute Bridge", es: "Puente de glúteos", [.glutes], [.hamstrings], .bodyweight, ["puente de gluteos", "puente"]),
        make("Hip Abduction (Machine)", es: "Abducción de cadera (máquina)", [.glutes], [], .machine, ["abductores", "abduccion de cadera"]),
        make("Hip Adduction (Machine)", es: "Aducción de cadera (máquina)", [.quadriceps], [.glutes], .machine, ["aductores", "aduccion de cadera"]),
        make("Glute Kickback (Cable)", es: "Patada de glúteo (polea)", [.glutes], [.hamstrings], .cable, ["patada de gluteo", "patada trasera en polea"]),
        make("Hip Thrust (Machine)", es: "Hip thrust (máquina)", [.glutes], [.hamstrings], .machine, ["hip thrust en maquina"]),
        make("Lying Leg Curl (Machine)", es: "Curl femoral tumbado (máquina)", [.hamstrings], [.calves], .machine, ["curl femoral tumbado", "curl femoral"]),
        make("Seated Leg Curl (Machine)", es: "Curl femoral sentado (máquina)", [.hamstrings], [], .machine, ["curl femoral sentado"]),
        make("Nordic Hamstring Curl", es: "Curl nórdico", [.hamstrings], [], .bodyweight, ["curl nordico", "nordicos", "nordic curl"]),
        make("Kettlebell Swing", es: "Swing con kettlebell", [.glutes, .hamstrings], [.back, .core], .kettlebell, ["swing con kettlebell", "swing"], pattern: .hinge),
        make("Standing Calf Raise (Dumbbell)", es: "Elevación de talones de pie (mancuernas)", [.calves], [], .dumbbell, ["gemelos de pie", "elevacion de talones"]),
        make("Seated Calf Raise (Plate Loaded)", es: "Elevación de talones sentado (discos)", [.calves], [], .machine, ["gemelos sentado", "soleo sentado"]),
        make("Standing Calf Raise (Machine)", es: "Elevación de talones de pie (máquina)", [.calves], [], .machine, ["gemelos en maquina", "gemelos de pie en maquina"]),
        make("Calf Press on Leg Press", es: "Gemelos en prensa", [.calves], [], .machine, ["gemelos en prensa", "calf press"]),
        // The tibialis anterior is attributed to the lower-leg group closest to it.
        make("Tibialis Raises", es: "Elevaciones de tibial", [.calves], [], .bodyweight, ["elevaciones de tibial", "tibial"]),

        // Conditioning
        make("Rowing (Machine)", es: "Remoergómetro", [.upperBack], [.quadriceps, .hamstrings, .biceps], .machine, ["remo ergometro", "remoergometro"]),
        make("Power Clean", es: "Cargada de potencia", [.quadriceps, .glutes, .hamstrings], [.upperBack, .frontDelts], .barbell, ["cargada", "cargada de potencia", "power clean"]),
        make("Box Jump", es: "Saltos al cajón", [.quadriceps, .glutes], [.calves], .bodyweight, ["saltos al cajon", "salto al cajon", "box jump"]),
        make("Farmers Walk", es: "Paseo del granjero", [.forearms, .core], [.upperBack, .glutes], .dumbbell, ["paseo del granjero", "farmer walk", "farmer carry"]),
        make("Sled Push", es: "Empuje de trineo", [.quadriceps, .glutes], [.calves, .core], .other, ["empuje de trineo", "trineo", "prowler"]),
        make("Burpee", es: "Burpees", [.quadriceps, .chest], [.frontDelts, .core], .bodyweight, ["burpees"]),
    ]

    private static let bodyweightAndCore: [Entry] = [
        make("Pull Up", es: "Dominadas", [.lats], [.biceps, .forearms], .bodyweight, ["dominadas", "dominadas pronas"], pattern: .verticalPull),
        make("Chin Up", es: "Dominadas supinas", [.lats, .biceps], [.forearms], .bodyweight, ["dominadas supinas", "chin up"], pattern: .verticalPull),
        make("Pull Up (Assisted)", es: "Dominadas asistidas", [.lats], [.biceps], .machine, ["dominadas asistidas", "dominadas con goma", "assisted pull up"], pattern: .verticalPull),
        make("Push Up", es: "Flexiones", [.chest], [.triceps, .frontDelts], .bodyweight, ["flexiones", "fondos de suelo"], pattern: .horizontalPush),
        make("Chest Dip", es: "Fondos de pecho", [.chest], [.triceps, .frontDelts], .bodyweight, ["fondos", "fondos de pecho", "fondos en paralelas"], pattern: .verticalPush),
        make("Triceps Dip", es: "Fondos de tríceps", [.triceps], [.chest, .frontDelts], .bodyweight, ["fondos de triceps", "fondos en banco"], pattern: .verticalPush),
        make("Plank", es: "Plancha", [.core], [], .bodyweight, ["plancha", "plancha abdominal"]),
        make("Side Plank", es: "Plancha lateral", [.core], [], .bodyweight, ["plancha lateral"]),
        make("Hollow Body", es: "Hollow body", [.core], [], .bodyweight, ["hollow", "hollow hold"]),
        make("Dead Bug", es: "Dead bug", [.core], [], .bodyweight, ["bicho muerto"]),
        make("Crunch", es: "Crunch abdominal", [.core], [], .bodyweight, ["abdominales", "crunch abdominal"]),
        make("Hanging Leg Raise", es: "Elevación de piernas colgado", [.core], [.forearms], .bodyweight, ["elevaciones de piernas colgado", "elevacion de piernas"]),
        make("Ab Wheel", es: "Rueda abdominal", [.core], [.frontDelts], .other, ["rueda abdominal", "rueda"]),
        make("Cable Crunch", es: "Crunch en polea", [.core], [], .cable, ["crunch en polea", "abdominales en polea"]),
        make("Russian Twist", es: "Giro ruso", [.core], [], .bodyweight, ["giro ruso", "russian twist"]),
        make("Lying Leg Raise", es: "Elevación de piernas tumbado", [.core], [], .bodyweight, ["elevaciones de piernas tumbado", "elevacion de piernas en el suelo"]),
        make("Pallof Press", es: "Press Pallof", [.core], [], .cable, ["press pallof", "antirrotacion"]),
        make("Mountain Climber", es: "Escaladores", [.core], [.frontDelts, .quadriceps], .bodyweight, ["escaladores", "mountain climbers"]),
        make("Bird Dog", es: "Bird dog", [.core], [.glutes, .back], .bodyweight, ["perro de muestra", "cuadrupedia"]),
    ]
    // swiftlint:enable line_length

    private static func make(
        _ name: String,
        es spanish: String,
        _ primary: Set<MuscleGroup>,
        _ secondary: Set<MuscleGroup>,
        _ equipment: Equipment,
        _ aliases: Set<String>,
        pattern: MovementPattern? = nil
    ) -> Entry {
        let exercise = Exercise(
            id: .stable("builtin-exercise|\(name)"),
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            equipment: equipment,
            isCustom: false,
            aliases: aliases,
            movementPattern: pattern
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

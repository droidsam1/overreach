import Domain
import Foundation

/// A generated, anonymised training history the size of a real Strong export (~600 sessions, ~12k sets),
/// for performance tests. Deterministic: the same `seed` always gives the same sessions and CSV.
///
/// Four years of an upper/lower split with rotating strength and hypertrophy blocks, warm-ups, slow load
/// progression with occasional resets, RPE on some sets, and a few custom exercises missing from the catalog.
public struct LargeHistory: Sendable {
    public let sessions: [StrengthSession]
    /// The built-in catalog plus the custom exercises used.
    public let exercises: [Exercise]
    /// The same sessions in Strong's CSV layout (UTC dates, kilograms).
    public let csv: String

    public var setCount: Int { sessions.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.sets.count } } }

    /// UTC calendar the CSV dates are written in.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    public init(sessionCount: Int = 600, endingAt end: Date = Date(timeIntervalSince1970: 1_790_000_000), seed: UInt64 = 42) {
        var random = SplitMix64(seed: seed)
        let custom = Self.customNames.map { name in
            Exercise(id: .stable("fixture-custom|\(name)"), name: name, primaryMuscles: [], isCustom: true)
        }
        let catalog = ExerciseCatalog.builtIn + custom
        let byName = Dictionary(catalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var loads: [String: Double] = [:]
        var sessions: [StrengthSession] = []
        // About 2.4 days between sessions on average.
        var start = end.addingTimeInterval(-Double(sessionCount) * 2.4 * 86_400)

        for index in 0..<sessionCount {
            let template = Self.templates[index % Self.templates.count]
            let isStrengthBlock = (index / 24) % 2 == 0
            var entries: [ExerciseEntry] = []
            var clock = start
            for (position, name) in template.exercises.enumerated() {
                guard let exercise = byName[name] else { continue }
                let isMain = position < 2
                let reps = isMain && isStrengthBlock ? 5 : (isMain ? 8 : 12)
                let base = loads[name] ?? Self.startingLoad(isMain: isMain, random: &random)
                // Slow progression with a reset now and then.
                let load = random.next(upTo: 20) == 0 ? (base * 0.9).rounded(to: 2.5) : base
                loads[name] = load + (random.next(upTo: 3) == 0 ? 2.5 : 0)
                let working = isStrengthBlock && isMain ? load * 1.15 : load

                var sets: [WorkoutSet] = []
                if isMain {
                    for fraction in [0.5, 0.75] {
                        clock += 120
                        sets.append(WorkoutSet(kind: .warmup, weightKg: (working * fraction).rounded(to: 2.5), reps: 5, completedAt: clock))
                    }
                }
                for _ in 0..<(3 + Int(random.next(upTo: 2))) {
                    clock += 150
                    let done = max(1, reps - Int(random.next(upTo: 3)))
                    let rpe: Double? = random.next(upTo: 2) == 0 ? 7 + Double(random.next(upTo: 6)) / 2 : nil
                    sets.append(WorkoutSet(weightKg: working.rounded(to: 2.5), reps: done, rpe: rpe, completedAt: clock))
                }
                entries.append(ExerciseEntry(exerciseID: exercise.id, sets: sets))
            }
            sessions.append(StrengthSession(
                id: .stable("fixture-session|\(seed)|\(index)"),
                name: template.name,
                startedAt: start,
                endedAt: clock.addingTimeInterval(120),
                entries: entries,
                source: .strongImport
            ))
            start += Double(1 + random.next(upTo: 3)) * 86_400 + Double(random.next(upTo: 7_200))
            start = start.rounded()
        }

        self.sessions = sessions
        self.exercises = catalog
        self.csv = Self.strongCSV(sessions, names: Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }))
    }

    // MARK: Templates

    private struct Template {
        let name: String
        let exercises: [String]
    }

    private static let customNames = ["Zercher Squat", "Jefferson Curl", "Copenhagen Plank"]

    private static let templates: [Template] = [
        Template(name: "Upper A", exercises: [
            "Bench Press (Barbell)", "Bent Over Row (Barbell)", "Seated Overhead Press (Dumbbell)",
            "Lat Pulldown (Cable)", "Lateral Raise (Dumbbell)", "Bicep Curl (Dumbbell)",
        ]),
        Template(name: "Lower A", exercises: [
            "Squat (Barbell)", "Romanian Deadlift (Barbell)", "Leg Press", "Lying Leg Curl (Machine)",
            "Standing Calf Raise (Dumbbell)", "Zercher Squat",
        ]),
        Template(name: "Upper B", exercises: [
            "Overhead Press (Barbell)", "Pull Up", "Incline Bench Press (Dumbbell)", "Seated Row (Cable)",
            "Triceps Pushdown (Cable - Rope)", "Jefferson Curl",
        ]),
        Template(name: "Lower B", exercises: [
            "Deadlift (Barbell)", "Front Squat (Barbell)", "Bulgarian Split Squat", "Hip Thrust (Barbell)",
            "Seated Leg Curl (Machine)", "Copenhagen Plank",
        ]),
    ]

    private static func startingLoad(isMain: Bool, random: inout SplitMix64) -> Double {
        (isMain ? 60 : 20) + Double(random.next(upTo: 8)) * 2.5
    }

    // MARK: CSV

    private static func strongCSV(_ sessions: [StrengthSession], names: [UUID: String]) -> String {
        var lines = ["Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE"]
        lines.reserveCapacity(sessions.count * 25)
        for session in sessions {
            let date = format(session.startedAt)
            let minutes = Int((session.durationSeconds ?? 0) / 60)
            let duration = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
            for entry in session.entries {
                let name = names[entry.exerciseID] ?? "Unknown"
                var order = 0
                for set in entry.sets {
                    let setOrder: String
                    if set.kind == .warmup {
                        setOrder = "W"
                    } else {
                        order += 1
                        setOrder = String(order)
                    }
                    let rpe = set.rpe.map { String($0) } ?? ""
                    lines.append(
                        "\(date),\"\(session.name)\",\(duration),\"\(name)\",\(setOrder),"
                            + "\(set.weightKg ?? 0),\(Double(set.reps ?? 0)),0,0.0,\(rpe)"
                    )
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func format(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String {
            let value = value ?? 0
            return value < 10 ? "0\(value)" : String(value)
        }
        return "\(parts.year ?? 0)-\(pad(parts.month))-\(pad(parts.day)) \(pad(parts.hour)):\(pad(parts.minute)):\(pad(parts.second))"
    }
}

/// Small deterministic generator (SplitMix64), so fixtures are identical on every platform.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func next(upTo bound: UInt64) -> UInt64 {
        next() % bound
    }
}

private extension Double {
    func rounded(to step: Double) -> Double {
        (self / step).rounded() * step
    }
}

private extension Date {
    /// Whole seconds, so dates survive the CSV round trip.
    func rounded() -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded())
    }
}

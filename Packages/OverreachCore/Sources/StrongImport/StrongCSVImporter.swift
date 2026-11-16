import Domain
import Foundation

/// Imports a Strong CSV export, or any CSV using the same columns (the notes-conversion prompt in
/// `docs/import.md` produces this format too).
///
/// Columns, matched by header name and in any order:
/// - Required: `Date`, `Exercise Name`, `Set Order`, `Weight`, `Reps`.
/// - Optional: `Workout Name`, `Duration`, `Distance`, `Seconds`, `RPE`, `Notes`, `Workout Notes`.
///
/// Rows are grouped into sessions by `Date` + `Workout Name`. `Set Order` is a number for working sets,
/// `W` for warm-up, `F` for failure and `D` for drop sets. Ids are stable, so importing the same file again
/// yields the same sessions (the app can skip ones it already has).
public enum StrongCSVImporter {
    public enum ImportError: Error, Sendable, Equatable {
        case emptyFile
        case missingColumns([String])
    }

    public enum DistanceUnit: String, Sendable, CaseIterable {
        case kilometers, miles

        var metersPerUnit: Double {
            switch self {
            case .kilometers: 1000
            case .miles: 1609.344
            }
        }
    }

    public struct Options: Sendable {
        /// Strong exports weights in the unit configured in the app; the file does not say which.
        public var weightUnit: WeightUnit
        public var distanceUnit: DistanceUnit
        /// Calendar (and time zone) the dates in the file were written in.
        public var calendar: Calendar

        public init(
            weightUnit: WeightUnit = .kilograms,
            distanceUnit: DistanceUnit = .kilometers,
            calendar: Calendar = .current
        ) {
            self.weightUnit = weightUnit
            self.distanceUnit = distanceUnit
            self.calendar = calendar
        }
    }

    public struct Result: Sendable {
        /// Sessions sorted by start date.
        public var sessions: [StrengthSession]
        /// Exercises not found in the catalog, created as custom exercises without muscle groups.
        public var newExercises: [Exercise]
        /// 1-based line numbers of rows that could not be read.
        public var skippedLines: [Int]

        public var setCount: Int {
            sessions.reduce(0) { total, session in total + session.entries.reduce(0) { $0 + $1.sets.count } }
        }
    }

    static let requiredColumns = ["date", "exercise name", "set order", "weight", "reps"]

    public static func parse(_ csv: String, catalog: [Exercise], options: Options = Options()) throws -> Result {
        let rows = CSVReader.rows(from: csv)
        guard let header = rows.first else { throw ImportError.emptyFile }

        let columns = Columns(header: header)
        let missing = requiredColumns.filter { !columns.has($0) }
        guard missing.isEmpty else { throw ImportError.missingColumns(missing) }

        var matcher = ExerciseMatcher(catalog: catalog)
        var builders: [String: SessionBuilder] = [:]
        var order: [String] = []
        var skipped: [Int] = []

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard let dateText = columns.value(row, "date"),
                  let start = parseDate(dateText, calendar: options.calendar),
                  let exerciseName = columns.value(row, "exercise name"),
                  let setOrder = columns.value(row, "set order"),
                  let kind = setKind(setOrder)
            else {
                skipped.append(line)
                continue
            }

            let workoutName = columns.value(row, "workout name") ?? "Workout"
            let key = "\(dateText)|\(workoutName)"
            if builders[key] == nil {
                order.append(key)
                builders[key] = SessionBuilder(
                    key: key,
                    name: workoutName,
                    start: start,
                    durationSeconds: columns.value(row, "duration").flatMap(parseDuration),
                    notes: columns.value(row, "workout notes")
                )
            }

            let exercise = matcher.resolve(exerciseName)
            let set = makeSet(row: row, columns: columns, kind: kind, options: options)
            builders[key]?.add(set, exerciseID: exercise.id, notes: columns.value(row, "notes"))
        }

        let sessions = order.compactMap { builders[$0]?.build() }.sorted { $0.startedAt < $1.startedAt }
        return Result(sessions: sessions, newExercises: matcher.created, skippedLines: skipped)
    }

    // MARK: - Row parsing

    private static func makeSet(row: [String], columns: Columns, kind: SetKind, options: Options) -> WorkoutSet {
        // Zero means "not recorded" in Strong exports (e.g. weight 0 for bodyweight sets).
        func positive(_ name: String) -> Double? {
            columns.double(row, name).flatMap { $0 > 0 ? $0 : nil }
        }
        let weight = positive("weight").map { $0 * options.weightUnit.kilogramsPerUnit }
        let reps = positive("reps").map { Int($0.rounded()) }
        let seconds = positive("seconds")
        let distance = positive("distance").map { $0 * options.distanceUnit.metersPerUnit }
        let rpe = positive("rpe")
        return WorkoutSet(
            kind: kind,
            weightKg: weight,
            reps: reps,
            rpe: rpe,
            durationSeconds: seconds,
            distanceMeters: distance
        )
    }

    static func setKind(_ value: String) -> SetKind? {
        switch value.uppercased() {
        case "W": .warmup
        case "F": .failure
        case "D": .dropSet
        default: Int(value) != nil ? .working : nil
        }
    }

    /// Parses `yyyy-MM-dd HH:mm:ss` (seconds optional) or `yyyy-MM-dd` in `calendar`'s time zone.
    static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "T" })
        guard let datePart = parts.first else { return nil }
        let ymd = datePart.split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3 else { return nil }
        var components = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2])
        if parts.count > 1 {
            let hms = parts[1].split(separator: ":").compactMap { Int($0) }
            guard hms.count >= 2 else { return nil }
            components.hour = hms[0]
            components.minute = hms[1]
            components.second = hms.count > 2 ? hms[2] : 0
        }
        return calendar.date(from: components)
    }

    /// Parses Strong durations such as `1h 6m`, `37m`, `2h`, `45s` into seconds.
    static func parseDuration(_ text: String) -> Double? {
        var total = 0.0
        var matched = false
        for token in text.lowercased().split(separator: " ") {
            guard let unit = token.last, let amount = Double(token.dropLast()) else { continue }
            switch unit {
            case "h": total += amount * 3600; matched = true
            case "m": total += amount * 60; matched = true
            case "s": total += amount; matched = true
            default: continue
            }
        }
        return matched ? total : nil
    }
}

// MARK: - Helpers

private struct Columns {
    private var indexByName: [String: Int] = [:]

    init(header: [String]) {
        for (index, name) in header.enumerated() {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if indexByName[key] == nil {
                indexByName[key] = index
            }
        }
    }

    func has(_ name: String) -> Bool { indexByName[name] != nil }

    func value(_ row: [String], _ name: String) -> String? {
        guard let index = indexByName[name], index < row.count else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Accepts both `.` and `,` as decimal separator.
    func double(_ row: [String], _ name: String) -> Double? {
        value(row, name).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }
}

private struct SessionBuilder {
    let key: String
    let name: String
    let start: Date
    let durationSeconds: Double?
    let notes: String?
    private var entryOrder: [UUID] = []
    private var setsByExercise: [UUID: [WorkoutSet]] = [:]
    private var notesByExercise: [UUID: String] = [:]

    init(key: String, name: String, start: Date, durationSeconds: Double?, notes: String?) {
        self.key = key
        self.name = name
        self.start = start
        self.durationSeconds = durationSeconds
        self.notes = notes
    }

    mutating func add(_ set: WorkoutSet, exerciseID: UUID, notes: String?) {
        if setsByExercise[exerciseID] == nil {
            entryOrder.append(exerciseID)
        }
        let index = setsByExercise[exerciseID, default: []].count
        let stableSet = WorkoutSet(
            id: .stable("strong-set|\(key)|\(exerciseID)|\(index)"),
            kind: set.kind,
            weightKg: set.weightKg,
            reps: set.reps,
            rpe: set.rpe,
            durationSeconds: set.durationSeconds,
            distanceMeters: set.distanceMeters
        )
        setsByExercise[exerciseID, default: []].append(stableSet)
        if let notes, notesByExercise[exerciseID] == nil {
            notesByExercise[exerciseID] = notes
        }
    }

    func build() -> StrengthSession {
        let entries = entryOrder.map { exerciseID in
            ExerciseEntry(
                id: .stable("strong-entry|\(key)|\(exerciseID)"),
                exerciseID: exerciseID,
                sets: setsByExercise[exerciseID] ?? [],
                notes: notesByExercise[exerciseID]
            )
        }
        return StrengthSession(
            id: .stable("strong-session|\(key)"),
            name: name,
            startedAt: start,
            endedAt: durationSeconds.map { start.addingTimeInterval($0) },
            entries: entries,
            notes: notes,
            source: .strongImport
        )
    }
}

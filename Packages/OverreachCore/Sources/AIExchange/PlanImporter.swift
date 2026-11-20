import Analytics
import Domain
import Foundation

/// Something in an AI reply that stops the import. Each one is explained to the user and, in English, to the AI.
public enum PlanIssue: Hashable, Sendable {
    case unreadable(PlanMessageReader.Failure)
    case empty
    case unnamedRoutine(index: Int)
    case emptyRoutine(name: String)
    case duplicateRoutine(id: String)
    case unknownExercise(name: String, closest: String?)
    case missingExercise(index: Int)
    case invalidValue(field: String, value: String, expected: String)
    /// A block names a routine that is neither in the plan nor in the app.
    case unknownRoutine(name: String)
    /// A routine prescribes an exercise it does not have.
    case prescriptionOutsideRoutine(routine: String, exercise: String)
}

/// Something in an AI reply that the app leaves out without stopping the import.
public enum PlanWarning: Hashable, Sendable {
    /// A field the format does not have, or one that does not apply (e.g. `reps` in a double progression).
    case ignoredField(String)
}

/// What importing an AI reply would change, computed before anything is saved.
public struct PlanImport: Hashable, Sendable {
    public struct RoutineChange: Hashable, Sendable {
        public let routine: Routine
        /// Replaces a routine that already exists (same id from an earlier import, or the same name).
        public let isUpdate: Bool
        /// The routine's exercises, in order.
        public let exercises: [Exercise]

        public var exerciseNames: [String] { exercises.map(\.name) }
    }

    public struct SettingsChange: Hashable, Sendable {
        public let exercise: Exercise
        public let settings: ProgressionSettings
        /// The exercise already had its own settings.
        public let isUpdate: Bool
    }

    public var routines: [RoutineChange] = []
    public var settings: [SettingsChange] = []
    /// Declared blocks of the plan, one after another, with their routines.
    public var blocks: [TrainingBlock] = []
    public var issues: [PlanIssue] = []
    public var warnings: [PlanWarning] = []

    /// Imports are all or nothing: any issue blocks them, so a half-applied plan never happens.
    public var canImport: Bool { issues.isEmpty && !(routines.isEmpty && settings.isEmpty && blocks.isEmpty) }

    public init(
        routines: [RoutineChange] = [], settings: [SettingsChange] = [], blocks: [TrainingBlock] = [],
        issues: [PlanIssue] = [], warnings: [PlanWarning] = []
    ) {
        self.routines = routines
        self.settings = settings
        self.blocks = blocks
        self.issues = issues
        self.warnings = warnings
    }

    /// Declared blocks after the import: blocks that start before the plan are kept, later ones are replaced.
    public func applying(to declared: [TrainingBlock]) -> [TrainingBlock] {
        guard let start = blocks.first?.start else { return declared }
        return declared.filter { !$0.isDeclared || $0.start < start } + blocks
    }
}

/// Turns an `overreach.plan` message into changes against the user's data (ADR-0017). Pure.
public enum PlanImporter {
    static let focusValues = "strength, hypertrophy, mixed or endurance"
    static let setRange = 1...10
    static let repRange = 1...50
    static let rpeRange = 5.0...10.0
    static let incrementRange = 0.0...20.0
    static let weekRange = 1...52
    static let sessionsPerWeekRange = 1...14

    public static func failed(_ failure: PlanMessageReader.Failure) -> PlanImport {
        PlanImport(issues: [.unreadable(failure)])
    }

    /// - Parameter today: the first day of the plan when it gives no `startDate`.
    public static func plan(
        _ message: PlanMessage, exercises: [Exercise], routines: [Routine], settings: [UUID: ProgressionSettings],
        today: CalendarDay = CalendarDay(Date()), calendar: Calendar = .current
    ) -> PlanImport {
        let lookup = ExerciseLookup(exercises)
        var result = PlanImport(warnings: message.ignoredFields.map(PlanWarning.ignoredField))
        var keys = Set<String>()
        var routineIndex = RoutineIndex(existing: routines)
        for (index, proposal) in (message.routines ?? []).enumerated() {
            for (item, prescription) in (proposal.prescriptions ?? []).enumerated() {
                let field = "routines[\(index)].prescriptions[\(item)].scheme"
                result.warnings += inapplicableFields(of: prescription.scheme, field: field)
            }
            if let change = routine(proposal, index: index, lookup: lookup, existing: routines, keys: &keys,
                                    issues: &result.issues) {
                result.routines.append(change)
                routineIndex.add(proposal, id: change.routine.id)
            }
        }
        if !(message.blocks ?? []).isEmpty {
            let start = firstDay(message.startDate, today: today, issues: &result.issues)
            result.blocks = blocks(
                message.blocks ?? [], from: start, routines: routineIndex, calendar: calendar, issues: &result.issues
            )
        }
        for (index, proposal) in (message.exerciseSettings ?? []).enumerated() {
            result.warnings += inapplicableFields(of: proposal.scheme, field: "exerciseSettings[\(index)].scheme")
            if let change = exerciseSettings(proposal, index: index, lookup: lookup, stored: settings,
                                             issues: &result.issues) {
                result.settings.removeAll { $0.exercise.id == change.exercise.id }  // the last one wins
                result.settings.append(change)
            }
        }
        if (message.routines ?? []).isEmpty && (message.exerciseSettings ?? []).isEmpty
            && (message.blocks ?? []).isEmpty {
            result.issues.append(.empty)
        }
        return result
    }

    // MARK: - Routines

    private static func routine(
        _ proposal: PlanMessage.RoutineProposal, index: Int, lookup: ExerciseLookup, existing: [Routine],
        keys: inout Set<String>, issues: inout [PlanIssue]
    ) -> PlanImport.RoutineChange? {
        let name = proposal.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            issues.append(.unnamedRoutine(index: index))
            return nil
        }
        let explicitID = proposal.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = explicitID.isEmpty ? ExerciseLookup.normalize(name) : explicitID
        guard keys.insert(key).inserted else {
            issues.append(.duplicateRoutine(id: key))
            return nil
        }
        let focus = self.focus(proposal.focus, field: "routines[\(index)].focus", issues: &issues)
        let names = proposal.exercises ?? []
        guard !names.isEmpty else {
            issues.append(.emptyRoutine(name: name))
            return nil
        }
        let resolved = names.compactMap { lookup.resolve($0, issues: &issues) }
        guard resolved.count == names.count else { return nil }

        guard let prescriptions = prescriptions(
            proposal.prescriptions ?? [], in: (name, resolved), field: "routines[\(index)]", lookup: lookup,
            issues: &issues
        ) else { return nil }

        let stableID = UUID.stable("ai-routine|\(key)")
        let match = existing.first { $0.id == stableID }
            ?? existing.first { $0.id.uuidString == explicitID.uppercased() }  // an id from the context pack
            ?? existing.first { ExerciseLookup.normalize($0.name) == ExerciseLookup.normalize(name) }
        let routine = Routine(
            id: match?.id ?? stableID, name: name, focus: focus, exerciseIDs: resolved.map(\.id),
            prescriptions: prescriptions
        )
        let ordered = routine.exerciseIDs.compactMap { id in resolved.first { $0.id == id } }
        return .init(routine: routine, isUpdate: match != nil, exercises: ordered)
    }

    // MARK: - Exercise settings

    private static func exerciseSettings(
        _ proposal: PlanMessage.SettingsProposal, index: Int, lookup: ExerciseLookup,
        stored: [UUID: ProgressionSettings], issues: inout [PlanIssue]
    ) -> PlanImport.SettingsChange? {
        guard let name = proposal.exercise, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            issues.append(.missingExercise(index: index))
            return nil
        }
        guard let exercise = lookup.resolve(name, issues: &issues) else { return nil }
        let field = "exerciseSettings[\(index)]"
        let before = issues.count
        var settings = stored[exercise.id] ?? ProgressionSettings(for: exercise)
        if proposal.focus != nil, let focus = self.focus(proposal.focus, field: "\(field).focus", issues: &issues) {
            settings = settings.declaring(focus)
        }
        if let scheme = proposal.scheme {
            if let parsed = self.scheme(scheme, field: "\(field).scheme", issues: &issues) {
                settings.scheme = parsed
            }
        }
        if let increment = proposal.incrementKg {
            if incrementRange.contains(increment) {
                settings.incrementKg = increment
            } else {
                issues.append(.invalidValue(field: "\(field).incrementKg", value: "\(increment)", expected: "0 to 20"))
            }
        }
        if let isMainLift = proposal.isMainLift {
            settings.isMainLift = isMainLift
        }
        guard issues.count == before else { return nil }
        return .init(exercise: exercise, settings: settings, isUpdate: stored[exercise.id] != nil)
    }

    private static func focus(_ value: String?, field: String, issues: inout [PlanIssue]) -> TrainingFocus? {
        guard let value else { return nil }
        guard let focus = TrainingFocus(rawValue: value.lowercased()) else {
            issues.append(.invalidValue(field: field, value: value, expected: focusValues))
            return nil
        }
        return focus
    }

    private static func scheme(
        _ proposal: PlanMessage.SchemeProposal, field: String, issues: inout [PlanIssue]
    ) -> ProgressionScheme? {
        let before = issues.count
        let check = { (name: String, value: Int?, range: ClosedRange<Int>, issues: inout [PlanIssue]) -> Int in
            guard let value, range.contains(value) else {
                issues.append(.invalidValue(field: "\(field).\(name)", value: value.map(String.init) ?? "missing",
                                            expected: "\(range.lowerBound) to \(range.upperBound)"))
                return range.lowerBound
            }
            return value
        }
        let sets = check("sets", proposal.sets, setRange, &issues)
        let rpe = proposal.targetRPE ?? 8
        if !rpeRange.contains(rpe) {
            issues.append(.invalidValue(field: "\(field).targetRPE", value: "\(rpe)", expected: "5 to 10"))
        }
        let scheme: ProgressionScheme?
        switch proposal.type {
        case "doubleProgression":
            let minReps = check("minReps", proposal.minReps, repRange, &issues)
            let maxReps = check("maxReps", proposal.maxReps, repRange, &issues)
            if minReps > maxReps {
                issues.append(.invalidValue(field: "\(field).minReps", value: "\(minReps)",
                                            expected: "at most maxReps (\(maxReps))"))
            }
            scheme = .doubleProgression(sets: sets, minReps: minReps, maxReps: maxReps, targetRPE: rpe)
        case "linearLoad":
            scheme = .linearLoad(sets: sets, reps: check("reps", proposal.reps, repRange, &issues), targetRPE: rpe)
        case "rpeBased":
            scheme = .rpeBased(sets: sets, reps: check("reps", proposal.reps, repRange, &issues), targetRPE: rpe)
        case "repCycle":
            let blocks = proposal.repBlocks ?? []
            if blocks.isEmpty || !blocks.allSatisfy(repRange.contains) {
                issues.append(.invalidValue(field: "\(field).repBlocks", value: "\(blocks)",
                                            expected: "a list of reps from 1 to 50"))
            }
            scheme = .repCycle(sets: sets, repBlocks: blocks, targetRPE: rpe)
        default:
            issues.append(.invalidValue(field: "\(field).type", value: proposal.type ?? "missing",
                                        expected: "doubleProgression, linearLoad, repCycle or rpeBased"))
            scheme = nil
        }
        return issues.count == before ? scheme : nil
    }

    /// Fields of a scheme that its type does not use.
    private static func inapplicableFields(of scheme: PlanMessage.SchemeProposal?, field: String) -> [PlanWarning] {
        guard let scheme else { return [] }
        let present: [(String, Bool)] = [
            ("minReps", scheme.minReps != nil), ("maxReps", scheme.maxReps != nil), ("reps", scheme.reps != nil),
            ("repBlocks", scheme.repBlocks != nil),
        ]
        let used: Set<String> = switch scheme.type {
        case "doubleProgression": ["minReps", "maxReps"]
        case "linearLoad", "rpeBased": ["reps"]
        case "repCycle": ["repBlocks"]
        default: ["minReps", "maxReps", "reps", "repBlocks"]  // the type itself is reported as an issue
        }
        return present.filter { $0.1 && !used.contains($0.0) }.map { .ignoredField("\(field).\($0.0)") }
    }

    // MARK: - Correction for the AI

    /// The text the user pastes back into the chat to get a fixed reply. English, for the AI. With only warnings,
    /// it asks to remove the ignored fields.
    public static func correctionPrompt(for issues: [PlanIssue], warnings: [PlanWarning] = []) -> String {
        var lines: [String] = []
        if issues.isEmpty {
            lines.append("Overreach can import your plan (overreach.plan v1), but it ignored some fields. Please send "
                + "the whole JSON again without them, or with the information in supported fields:")
        } else {
            lines.append("Overreach could not import your plan (overreach.plan v1). Please fix these problems and "
                + "send the whole JSON again:")
            lines += issues.map { "- " + explanation(of: $0) }
            if !warnings.isEmpty {
                lines.append("Also remove these fields, which the format does not have:")
            }
        }
        lines += warnings.map { "- " + explanation(of: $0) }
        lines.append("The reply must validate against the overreach.plan v1 JSON Schema: \(PlanMessage.schemaURL)")
        lines.append("Use exercise names exactly as listed in the \"catalog\" of my Overreach context.")
        return lines.joined(separator: "\n")
    }

    static func explanation(of warning: PlanWarning) -> String {
        switch warning {
        case let .ignoredField(path): "\(path) is not part of the format and was ignored."
        }
    }

    static func explanation(of issue: PlanIssue) -> String {
        switch issue {
        case .unreadable(.noJSON):
            "I could not find a JSON code block in your reply."
        case let .unreadable(.notAPlan(format)):
            "The JSON has format \"\(format ?? "none")\"; it must be \"overreach.plan\"."
        case let .unreadable(.newerVersion(version)), let .unreadable(.unsupportedVersion(version)):
            "The JSON has version \(version); use version 1."
        case let .unreadable(.invalid(detail)):
            "The JSON could not be read: \(detail)."
        case .empty:
            "There are no routines or exercise settings."
        case let .unnamedRoutine(index):
            "routines[\(index)] has no name."
        case let .emptyRoutine(name):
            "Routine \"\(name)\" has no exercises."
        case let .duplicateRoutine(id):
            "Two routines use the id \"\(id)\"."
        case let .unknownExercise(name, closest):
            "\"\(name)\" is not in the catalog" + (closest.map { "; the closest is \"\($0)\"" } ?? "") + "."
        case let .missingExercise(index):
            "exerciseSettings[\(index)] does not say which exercise."
        case let .invalidValue(field, value, expected):
            "\(field) is \(value); expected \(expected)."
        case let .unknownRoutine(name):
            "Block routine \"\(name)\" is not the id or name of a routine in this plan or in my routines."
        case let .prescriptionOutsideRoutine(routine, exercise):
            "Routine \"\(routine)\" has a prescription for \"\(exercise)\", which is not one of its exercises."
        }
    }
}

// MARK: - Per-routine prescriptions and blocks (issue #34, ADR-0019)

extension PlanImporter {
    /// The routine's own schemes, or `nil` if any of them is wrong.
    fileprivate static func prescriptions(
        _ proposals: [PlanMessage.PrescriptionProposal], in routine: (name: String, exercises: [Exercise]),
        field: String, lookup: ExerciseLookup, issues: inout [PlanIssue]
    ) -> [RoutinePrescription]? {
        let before = issues.count
        var result: [RoutinePrescription] = []
        for (item, proposal) in proposals.enumerated() {
            let path = "\(field).prescriptions[\(item)]"
            guard let name = proposal.exercise else {
                issues.append(.invalidValue(field: "\(path).exercise", value: "missing", expected: "an exercise"))
                continue
            }
            guard let exercise = lookup.resolve(name, issues: &issues) else { continue }
            guard routine.exercises.contains(where: { $0.id == exercise.id }) else {
                issues.append(.prescriptionOutsideRoutine(routine: routine.name, exercise: exercise.name))
                continue
            }
            guard let proposed = proposal.scheme else {
                issues.append(.invalidValue(field: "\(path).scheme", value: "missing", expected: "a scheme"))
                continue
            }
            if let parsed = scheme(proposed, field: "\(path).scheme", issues: &issues) {
                result.append(RoutinePrescription(exerciseID: exercise.id, scheme: parsed))
            }
        }
        return issues.count == before ? result : nil
    }

    /// The plan's `startDate`, or `today` when it has none.
    fileprivate static func firstDay(_ text: String?, today: CalendarDay, issues: inout [PlanIssue]) -> CalendarDay {
        guard let text else { return today }
        guard let day = day(text) else {
            issues.append(.invalidValue(field: "startDate", value: text, expected: "a date like 2027-01-04"))
            return today
        }
        return day
    }

    /// Blocks one after another from `start`.
    fileprivate static func blocks(
        _ proposals: [PlanMessage.BlockProposal], from start: CalendarDay, routines: RoutineIndex,
        calendar: Calendar, issues: inout [PlanIssue]
    ) -> [TrainingBlock] {
        var start = start
        var result: [TrainingBlock] = []
        for (index, proposal) in proposals.enumerated() {
            let field = "blocks[\(index)]"
            let before = issues.count
            let focus = self.focus(proposal.focus, field: "\(field).focus", issues: &issues)
            if proposal.focus == nil {
                issues.append(.invalidValue(field: "\(field).focus", value: "missing", expected: focusValues))
            }
            let weeks = proposal.weeks ?? 0
            if !weekRange.contains(weeks) {
                let value = proposal.weeks.map(String.init) ?? "missing"
                issues.append(.invalidValue(field: "\(field).weeks", value: value, expected: "1 to 52"))
            }
            if let perWeek = proposal.sessionsPerWeek, !sessionsPerWeekRange.contains(perWeek) {
                let path = "\(field).sessionsPerWeek"
                issues.append(.invalidValue(field: path, value: "\(perWeek)", expected: "1 to 14"))
            }
            let routineIDs = (proposal.routines ?? []).compactMap { routines.id(for: $0, issues: &issues) }
            guard issues.count == before, let focus else { continue }
            let name = proposal.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(TrainingBlock(
                focus: focus, start: start, plannedWeeks: weeks, isDeclared: true,
                name: name?.isEmpty == false ? name : nil, routineIDs: routineIDs,
                sessionsPerWeek: proposal.sessionsPerWeek
            ))
            start = start.adding(days: weeks * 7, calendar: calendar)
        }
        return result
    }

    /// `2027-01-04` as a calendar day.
    static func day(_ text: String) -> CalendarDay? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return CalendarDay(year: parts[0], month: parts[1], day: parts[2])
    }
}

/// Routines a block can name: those of the plan (by id or name), then those already in the app (imported with that
/// id, its id from the context pack, or its name).
struct RoutineIndex {
    let existing: [Routine]
    private var byKey: [String: UUID] = [:]

    init(existing: [Routine]) {
        self.existing = existing
    }

    mutating func add(_ proposal: PlanMessage.RoutineProposal, id: UUID) {
        let keys = [proposal.id, proposal.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for key in keys { byKey[ExerciseLookup.normalize(key)] = id }
    }

    func id(for reference: String, issues: inout [PlanIssue]) -> UUID? {
        let key = ExerciseLookup.normalize(reference)
        if let id = byKey[key] { return id }
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let imported = UUID.stable("ai-routine|\(trimmed)")
        let contextID = UUID(uuidString: trimmed)
        if let routine = existing.first(where: {
            $0.id == imported || $0.id == contextID || ExerciseLookup.normalize($0.name) == key
        }) {
            return routine.id
        }
        issues.append(.unknownRoutine(name: reference))
        return nil
    }
}

/// Exercises by name or alias, ignoring case, accents and extra spaces. Unknown names suggest the closest one.
struct ExerciseLookup {
    private var byKey: [String: Exercise] = [:]
    private let catalog: [Exercise]

    init(_ exercises: [Exercise]) {
        catalog = exercises
        for exercise in exercises {
            for name in exercise.knownNames where byKey[Self.normalize(name)] == nil {
                byKey[Self.normalize(name)] = exercise
            }
        }
    }

    func resolve(_ name: String, issues: inout [PlanIssue]) -> Exercise? {
        if let exercise = byKey[Self.normalize(name)] {
            return exercise
        }
        let probe = Exercise(name: name, primaryMuscles: [])
        let closest = ExerciseSuggestions.similar(to: probe, in: catalog, limit: 1).first?.exercise.name
        issues.append(.unknownExercise(name: name, closest: closest))
        return nil
    }

    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

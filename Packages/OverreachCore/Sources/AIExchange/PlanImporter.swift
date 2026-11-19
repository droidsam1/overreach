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
}

/// What importing an AI reply would change, computed before anything is saved.
public struct PlanImport: Hashable, Sendable {
    public struct RoutineChange: Hashable, Sendable {
        public let routine: Routine
        /// Replaces a routine that already exists (same id from an earlier import, or the same name).
        public let isUpdate: Bool
        public let exerciseNames: [String]
    }

    public struct SettingsChange: Hashable, Sendable {
        public let exercise: Exercise
        public let settings: ProgressionSettings
        /// The exercise already had its own settings.
        public let isUpdate: Bool
    }

    public var routines: [RoutineChange] = []
    public var settings: [SettingsChange] = []
    public var issues: [PlanIssue] = []

    /// Imports are all or nothing: any issue blocks them, so a half-applied plan never happens.
    public var canImport: Bool { issues.isEmpty && !(routines.isEmpty && settings.isEmpty) }

    public init(routines: [RoutineChange] = [], settings: [SettingsChange] = [], issues: [PlanIssue] = []) {
        self.routines = routines
        self.settings = settings
        self.issues = issues
    }
}

/// Turns an `overreach.plan` message into changes against the user's data (ADR-0017). Pure.
public enum PlanImporter {
    static let focusValues = "strength, hypertrophy, mixed or endurance"
    static let setRange = 1...10
    static let repRange = 1...50
    static let rpeRange = 5.0...10.0
    static let incrementRange = 0.0...20.0

    public static func failed(_ failure: PlanMessageReader.Failure) -> PlanImport {
        PlanImport(issues: [.unreadable(failure)])
    }

    public static func plan(
        _ message: PlanMessage, exercises: [Exercise], routines: [Routine], settings: [UUID: ProgressionSettings]
    ) -> PlanImport {
        let lookup = ExerciseLookup(exercises)
        var result = PlanImport()
        var keys = Set<String>()
        for (index, proposal) in (message.routines ?? []).enumerated() {
            if let change = routine(proposal, index: index, lookup: lookup, existing: routines, keys: &keys,
                                    issues: &result.issues) {
                result.routines.append(change)
            }
        }
        for (index, proposal) in (message.exerciseSettings ?? []).enumerated() {
            if let change = exerciseSettings(proposal, index: index, lookup: lookup, stored: settings,
                                             issues: &result.issues) {
                result.settings.removeAll { $0.exercise.id == change.exercise.id }  // the last one wins
                result.settings.append(change)
            }
        }
        if (message.routines ?? []).isEmpty && (message.exerciseSettings ?? []).isEmpty {
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

        let stableID = UUID.stable("ai-routine|\(key)")
        let match = existing.first { $0.id == stableID }
            ?? existing.first { ExerciseLookup.normalize($0.name) == ExerciseLookup.normalize(name) }
        let routine = Routine(id: match?.id ?? stableID, name: name, focus: focus, exerciseIDs: resolved.map(\.id))
        let orderedNames = routine.exerciseIDs.compactMap { id in resolved.first { $0.id == id }?.name }
        return .init(routine: routine, isUpdate: match != nil, exerciseNames: orderedNames)
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

    // MARK: - Correction for the AI

    /// The text the user pastes back into the chat to get a fixed reply. English, for the AI.
    public static func correctionPrompt(for issues: [PlanIssue]) -> String {
        var lines = [
            "Overreach could not import your plan (overreach.plan v1). Please fix these problems and send the whole "
                + "JSON again:",
        ]
        lines += issues.map { "- " + explanation(of: $0) }
        lines.append("Use exercise names exactly as listed in the \"catalog\" of my Overreach context.")
        return lines.joined(separator: "\n")
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
        }
    }
}

/// Exercises by name or alias, ignoring case, accents and extra spaces. Unknown names suggest the closest one.
struct ExerciseLookup {
    private var byKey: [String: Exercise] = [:]
    private let catalog: [Exercise]

    init(_ exercises: [Exercise]) {
        catalog = exercises
        for exercise in exercises {
            for name in [exercise.name] + exercise.aliases.sorted() where byKey[Self.normalize(name)] == nil {
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

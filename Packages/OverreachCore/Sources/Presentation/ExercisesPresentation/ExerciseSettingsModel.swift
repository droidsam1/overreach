import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// The progression schemes the user can choose from.
public enum SchemeKind: String, CaseIterable, Hashable, Sendable {
    case doubleProgression, linearLoad, repCycle, rpeBased

    var displayName: String {
        switch self {
        case .doubleProgression: L10n.text("Double progression")
        case .linearLoad: L10n.text("Linear load")
        case .repCycle: L10n.text("Rep cycle")
        case .rpeBased: L10n.text("RPE-based")
        }
    }

    var explanation: String {
        switch self {
        case .doubleProgression:
            L10n.text("Add reps until every set reaches the top of the range, then add load and start again.")
        case .linearLoad:
            L10n.text("Add load after each successful session. Repeat after a miss; reduce it after three.")
        case .repCycle:
            L10n.text("Rotate through the rep blocks. The load comes from your estimated 1RM.")
        case .rpeBased:
            L10n.text("Fixed reps at a target RPE. The load comes from your estimated 1RM.")
        }
    }
}

/// How one exercise progresses (issue #14). Nothing is stored until `save()`. Settings equal to the defaults are
/// not stored, so the exercise keeps following the session focus and the equipment.
@MainActor
@Observable
public final class ExerciseSettingsModel {
    public var schemeKind: SchemeKind = .doubleProgression
    public var sets = 3
    public var minReps = 8
    public var maxReps = 12
    /// Reps of the fixed-rep schemes (linear load, RPE-based).
    public var reps = 5
    /// Rep blocks of the rep cycle, e.g. "12, 8, 5".
    public var repBlocksText = "12, 8, 5"
    public var targetRPE = 8.0
    public var incrementKg: Double
    public var isMainLift = false
    /// `nil` = automatic. While the scheme is the suggested one, it follows the focus.
    public var focus: TrainingFocus? {
        didSet {
            if scheme == Self.suggestedScheme(for: oldValue) {
                apply(Self.suggestedScheme(for: focus))
            }
        }
    }

    public private(set) var isLoaded = false
    public private(set) var errorMessage: String?

    public let schemeOptions: [Option<SchemeKind>] = SchemeKind.allCases.map { Option(value: $0, name: $0.displayName) }
    public let focusOptions: [Option<TrainingFocus>] = Option.trainingFocuses
    public let setsBounds = 1...10
    public let repsBounds = 1...ExerciseSettingsModel.maxRepsAllowed

    private static let maxRepsAllowed = 50
    private static let rpeChoices = Array(stride(from: 6.0, through: 10.0, by: 0.5))
    /// Common jumps, including microplates.
    private static let incrementChoices = [0, 0.25, 0.5, 1, 1.25, 2, 2.5, 4, 5, 10]

    private let exercise: Exercise
    private let repository: any ProgressionSettingsRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date
    private let format: Format

    init(
        exercise: Exercise,
        repository: any ProgressionSettingsRepository,
        backup: (any BackupService)?,
        clock: @escaping @Sendable () -> Date,
        format: Format
    ) {
        self.exercise = exercise
        self.repository = repository
        self.backup = backup
        self.clock = clock
        self.format = format
        incrementKg = ProgressionSettings.defaultIncrement(for: exercise.equipment)
    }

    // MARK: Screen state

    public var title: String { exercise.name }
    public var showsRepRange: Bool { schemeKind == .doubleProgression }
    public var showsReps: Bool { schemeKind == .linearLoad || schemeKind == .rpeBased }
    public var showsRepBlocks: Bool { schemeKind == .repCycle }
    public var schemeExplanation: String { schemeKind.explanation }

    public var minRepsBounds: ClosedRange<Int> { 1...max(1, maxReps) }
    public var maxRepsBounds: ClosedRange<Int> { minReps...max(minReps, Self.maxRepsAllowed) }

    public var rpeOptions: [Option<Double>] {
        Set(Self.rpeChoices + [targetRPE]).sorted().map { Option(value: $0, name: format.number($0)) }
    }

    public var incrementOptions: [Option<Double>] {
        Set(Self.incrementChoices + [incrementKg, defaults.incrementKg]).sorted().map { value in
            Option(value: value, name: value > 0 ? format.kilograms(value) : L10n.text("No added load"))
        }
    }

    public var repBlocksMessage: String? {
        guard showsRepBlocks, repBlocks == nil else { return nil }
        return L10n.format("Enter rep counts from 1 to {1}, separated by commas.", Self.maxRepsAllowed)
    }

    /// "Suggested for Strength: 4 × 4 @ RPE 8 · +2.5 kg · rest 3:00–5:00"
    public var suggestionLine: String {
        let suggested = Self.suggestedScheme(for: focus)
        let increment = defaults.incrementKg > 0
            ? "+" + format.kilograms(defaults.incrementKg)
            : L10n.text("no added load")
        var parts = [describe(suggested), increment]
        var label = L10n.text("Default:")
        if let focus {
            let rest = FocusPrescription.for(focus).restSeconds
            parts.append(L10n.format(
                "rest {1}–{2}", format.minutesAndSeconds(rest.lowerBound), format.minutesAndSeconds(rest.upperBound)
            ))
            label = L10n.format("Suggested for {1}:", focus.displayName)
        }
        return label + " " + parts.joined(separator: " · ")
    }

    public var canSave: Bool { isLoaded && scheme != nil }

    public var canUseDefaults: Bool { isLoaded && settings != defaults }

    // MARK: Intents

    public func load() async {
        guard !isLoaded else { return }
        do {
            apply(try await repository.progressionSettings(for: exercise.id) ?? defaults)
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = L10n.text("Could not load the settings.")
        }
    }

    /// Fills the form with the defaults. Saving then returns the exercise to automatic settings.
    public func useDefaults() { apply(defaults) }

    /// Saves the settings. Returns true when the screen can close.
    public func save() async -> Bool {
        guard canSave, let settings else { return false }
        do {
            if settings == defaults {
                try await repository.deleteProgressionSettings(for: exercise.id)
            } else {
                try await repository.save(settings, for: exercise.id)
            }
        } catch {
            errorMessage = L10n.text("Could not save the settings.")
            return false
        }
        errorMessage = nil
        await backup?.backUpIfConfigured(now: clock())
        return true
    }

    // MARK: Helpers

    private var defaults: ProgressionSettings { ProgressionSettings(for: exercise) }

    private static func suggestedScheme(for focus: TrainingFocus?) -> ProgressionScheme {
        focus.map { FocusPrescription.for($0).defaultScheme } ?? .default
    }

    private var settings: ProgressionSettings? {
        scheme.map { ProgressionSettings(scheme: $0, incrementKg: incrementKg, isMainLift: isMainLift, focus: focus) }
    }

    /// The scheme in the form; `nil` while the rep blocks are invalid.
    private var scheme: ProgressionScheme? {
        switch schemeKind {
        case .doubleProgression:
            .doubleProgression(sets: sets, minReps: minReps, maxReps: maxReps, targetRPE: targetRPE)
        case .linearLoad:
            .linearLoad(sets: sets, reps: reps, targetRPE: targetRPE)
        case .repCycle:
            repBlocks.map { .repCycle(sets: sets, repBlocks: $0, targetRPE: targetRPE) }
        case .rpeBased:
            .rpeBased(sets: sets, reps: reps, targetRPE: targetRPE)
        }
    }

    private var repBlocks: [Int]? {
        let entries = repBlocksText.split { $0 == "," || $0.isWhitespace }
        let blocks = entries.compactMap { Int($0) }.filter { repsBounds.contains($0) }
        return !blocks.isEmpty && blocks.count == entries.count ? blocks : nil
    }

    private func apply(_ settings: ProgressionSettings) {
        focus = settings.focus  // First: changing it can replace the scheme.
        apply(settings.scheme)
        incrementKg = settings.incrementKg
        isMainLift = settings.isMainLift
    }

    private func apply(_ scheme: ProgressionScheme) {
        sets = scheme.sets
        targetRPE = scheme.targetRPE
        switch scheme {
        case let .doubleProgression(_, low, high, _):
            schemeKind = .doubleProgression
            minReps = max(1, min(low, high))
            maxReps = max(1, low, high)
        case let .linearLoad(_, value, _):
            schemeKind = .linearLoad
            reps = max(1, value)
        case let .repCycle(_, blocks, _):
            schemeKind = .repCycle
            repBlocksText = blocks.map(String.init).joined(separator: ", ")
        case let .rpeBased(_, value, _):
            schemeKind = .rpeBased
            reps = max(1, value)
        }
    }

    /// "3 × 8–12 @ RPE 8"
    private func describe(_ scheme: ProgressionScheme) -> String {
        let reps: String
        switch scheme {
        case let .doubleProgression(_, low, high, _): reps = "\(low)–\(high)"
        case let .linearLoad(_, value, _), let .rpeBased(_, value, _): reps = String(value)
        case let .repCycle(_, blocks, _): reps = blocks.map(String.init).joined(separator: "/")
        }
        return "\(scheme.sets) × \(reps) @ RPE \(format.number(scheme.targetRPE))"
    }
}

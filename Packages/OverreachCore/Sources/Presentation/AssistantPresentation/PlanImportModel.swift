import AIExchange
import Domain
import Foundation
import Observation
import PresentationKit

/// Brings an AI reply back (ADR-0017): reads an `overreach.plan` message from pasted text or a file, previews the
/// routines and exercise settings it would change, and saves them only when the user confirms.
@MainActor
@Observable
public final class PlanImportModel {
    public struct RoutineRow: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        /// "Strength · Bench Press, Row".
        public let detail: String
        public let isUpdate: Bool
    }

    public struct SettingsRow: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let exercise: String
        /// "Strength · 4 × 4 @ RPE 8 · +2.5 kg · main lift".
        public let detail: String
        public let isUpdate: Bool
    }

    public struct Preview: Hashable, Sendable {
        public let routines: [RoutineRow]
        public let settings: [SettingsRow]
        /// Why it cannot be imported, in the user's language.
        public let issues: [String]
        /// Parts of the answer the app leaves out ("Ignored: routines[0].reps"). They do not block the import.
        public let warnings: [String]
        /// The issues and warnings as a message for the AI, to paste back into the chat.
        public let correction: String?
        public let canImport: Bool
    }

    public private(set) var preview: Preview?
    /// "Imported 2 routines and 3 exercise settings."
    public private(set) var resultMessage: String?
    public private(set) var errorMessage: String?
    /// The format, an example and the rules, for the user to paste into the chat.
    public let formatGuide = PlanMessage.formatGuide

    /// Drives the preview sheet; dismissing it cancels the import.
    public var isShowingPreview: Bool {
        get { preview != nil }
        set { if !newValue { cancel() } }
    }

    private var pending: PlanImport?
    private let exercises: any ExerciseRepository
    private let routines: any RoutineRepository
    private let progression: any ProgressionSettingsRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date
    private let format: Format

    public init(
        exercises: any ExerciseRepository,
        routines: any RoutineRepository,
        progression: any ProgressionSettingsRepository,
        backup: (any BackupService)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        format: Format = Format()
    ) {
        self.exercises = exercises
        self.routines = routines
        self.progression = progression
        self.backup = backup
        self.clock = clock
        self.format = format
    }

    /// Reads pasted text (the AI's whole answer is fine).
    public func read(text: String) async {
        resultMessage = nil
        errorMessage = nil
        let planned: PlanImport
        switch PlanMessageReader.read(text) {
        case let .failure(failure):
            planned = PlanImporter.failed(failure)
        case let .success(message):
            do {
                planned = PlanImporter.plan(
                    message,
                    exercises: try await exercises.allExercises(),
                    routines: try await routines.allRoutines(),
                    settings: try await progression.allProgressionSettings()
                )
            } catch {
                errorMessage = L10n.text("Could not read your exercises and routines. Try again.")
                return
            }
        }
        pending = planned
        preview = makePreview(planned)
    }

    /// Reads what a paste button delivers.
    public func read(pasted texts: [String]) async {
        await read(text: texts.joined(separator: "\n"))
    }

    public func read(fileData: Data) async {
        guard let text = String(data: fileData, encoding: .utf8) else {
            fileCouldNotBeOpened()
            return
        }
        await read(text: text)
    }

    public func fileCouldNotBeOpened() {
        errorMessage = L10n.text("Could not open that file.")
    }

    /// Saves the previewed changes. Returns `false` if there was nothing valid to save or saving failed.
    @discardableResult
    public func confirm() async -> Bool {
        guard let pending, pending.canImport else { return false }
        do {
            for change in pending.routines {
                try await routines.save(change.routine)
            }
            for change in pending.settings {
                try await progression.save(change.settings, for: change.exercise.id)
            }
        } catch {
            errorMessage = L10n.text("Could not save everything. Import the answer again to finish.")
            return false
        }
        await backup?.backUpIfConfigured(now: clock())
        resultMessage = L10n.format(
            "Imported {1} routines and {2} exercise settings.", pending.routines.count, pending.settings.count
        )
        cancel()
        return true
    }

    public func cancel() {
        pending = nil
        preview = nil
    }

    // MARK: - Texts

    private func makePreview(_ planned: PlanImport) -> Preview {
        Preview(
            routines: planned.routines.map { change in
                let names = change.exerciseNames.joined(separator: ", ")
                return RoutineRow(
                    id: change.routine.id,
                    name: change.routine.name,
                    detail: change.routine.focus.map { "\($0.displayName) · \(names)" } ?? names,
                    isUpdate: change.isUpdate
                )
            },
            settings: planned.settings.map { change in
                SettingsRow(id: change.exercise.id, exercise: change.exercise.name,
                            detail: detail(of: change.settings), isUpdate: change.isUpdate)
            },
            issues: planned.issues.map(text),
            warnings: planned.warnings.map(text),
            correction: planned.issues.isEmpty && planned.warnings.isEmpty
                ? nil : PlanImporter.correctionPrompt(for: planned.issues, warnings: planned.warnings),
            canImport: planned.canImport
        )
    }

    private func detail(of settings: ProgressionSettings) -> String {
        var parts: [String] = []
        if let focus = settings.focus {
            parts.append(focus.displayName)
        }
        parts.append(scheme(settings.scheme))
        if settings.incrementKg > 0 {
            parts.append("+" + format.kilograms(settings.incrementKg))
        }
        if settings.isMainLift {
            parts.append(L10n.text("main lift"))
        }
        return parts.joined(separator: " · ")
    }

    private func scheme(_ scheme: ProgressionScheme) -> String {
        switch scheme {
        case let .doubleProgression(sets, minReps, maxReps, rpe):
            "\(sets) × \(minReps)–\(maxReps) @ RPE \(format.number(rpe))"
        case let .linearLoad(sets, reps, rpe), let .rpeBased(sets, reps, rpe):
            "\(sets) × \(reps) @ RPE \(format.number(rpe))"
        case let .repCycle(sets, blocks, rpe):
            "\(sets) × \(blocks.map(String.init).joined(separator: "/")) @ RPE \(format.number(rpe))"
        }
    }

    private func text(_ warning: PlanWarning) -> String {
        switch warning {
        case let .ignoredField(path): L10n.format("Ignored: {1}. The app does not use this field.", path)
        }
    }

    private func text(_ issue: PlanIssue) -> String {
        switch issue {
        case .unreadable(.noJSON):
            L10n.text("No plan found. Copy the reply format into the chat and ask again.")
        case .unreadable(.notAPlan):
            L10n.text("This is not an Overreach plan.")
        case .unreadable(.newerVersion):
            L10n.text("This plan needs a newer version of the app.")
        case .unreadable(.unsupportedVersion):
            L10n.text("This plan uses a version the app does not know.")
        case let .unreadable(.invalid(detail)):
            L10n.format("The plan could not be read: {1}.", detail)
        case .empty:
            L10n.text("The plan has no routines or exercise settings.")
        case .unnamedRoutine:
            L10n.text("A routine has no name.")
        case let .emptyRoutine(name):
            L10n.format("Routine “{1}” has no exercises.", name)
        case let .duplicateRoutine(id):
            L10n.format("Two routines share the id “{1}”.", id)
        case let .unknownExercise(name, closest?):
            L10n.format("Unknown exercise “{1}”. Closest: {2}.", name, closest)
        case let .unknownExercise(name, nil):
            L10n.format("Unknown exercise “{1}”.", name)
        case .missingExercise:
            L10n.text("Some exercise settings do not say which exercise.")
        case let .invalidValue(field, value, _):
            L10n.format("Invalid value in {1}: {2}.", field, value)
        }
    }
}

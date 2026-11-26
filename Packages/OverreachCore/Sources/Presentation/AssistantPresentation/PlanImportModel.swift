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

    public struct BlockRow: Identifiable, Hashable, Sendable {
        public let id: Int
        /// "Strength"
        public let name: String
        /// "6 weeks from 4 Jan 2027 · Upper A, Lower A".
        public let detail: String
    }

    public struct Preview: Hashable, Sendable {
        public let routines: [RoutineRow]
        public let settings: [SettingsRow]
        /// The plan's blocks, in order. They replace declared blocks from the plan's start on.
        public let blocks: [BlockRow]
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
    private let profiles: (any ProfileRepository)?
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private var format: Format

    /// - Parameter profiles: where a plan's blocks are saved. Without it, plans with blocks cannot be imported.
    public init(
        exercises: any ExerciseRepository,
        routines: any RoutineRepository,
        progression: any ProgressionSettingsRepository,
        profiles: (any ProfileRepository)? = nil,
        backup: (any BackupService)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        format: Format = Format()
    ) {
        self.exercises = exercises
        self.routines = routines
        self.progression = progression
        self.profiles = profiles
        self.backup = backup
        self.clock = clock
        self.calendar = calendar
        self.format = format
    }

    /// Reads pasted text (the AI's whole answer is fine).
    public func read(text: String) async {
        resultMessage = nil
        errorMessage = nil
        var planned: PlanImport
        switch PlanMessageReader.read(text) {
        case let .failure(failure):
            planned = PlanImporter.failed(failure)
        case let .success(message):
            do {
                planned = PlanImporter.plan(
                    message,
                    exercises: try await exercises.allExercises(),
                    routines: try await routines.allRoutines(),
                    settings: try await progression.allProgressionSettings(),
                    today: CalendarDay(clock(), calendar: calendar),
                    calendar: calendar
                )
                routineNames = Dictionary(
                    (try await routines.allRoutines()).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
                ).merging(planned.routines.map { ($0.routine.id, $0.routine.name) }) { _, new in new }
            } catch {
                errorMessage = L10n.text("Could not read your exercises and routines. Try again.")
                return
            }
        }
        if !planned.blocks.isEmpty, profiles == nil {
            planned.issues.append(.invalidValue(field: "blocks", value: "present", expected: "no blocks"))
        }
        if let profile = try? await profiles?.profile() { format.weightUnit = profile.weightUnit }
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
            if !pending.blocks.isEmpty, let profiles {
                var profile = try await profiles.profile()
                profile.declaredBlocks = pending.applying(to: profile.declaredBlocks)
                try await profiles.save(profile)
            }
        } catch {
            errorMessage = L10n.text("Could not save everything. Import the answer again to finish.")
            return false
        }
        await backup?.backUpIfConfigured(now: clock())
        resultMessage = pending.blocks.isEmpty
            ? L10n.format(
                "Imported {1} routines and {2} exercise settings.", pending.routines.count, pending.settings.count
            )
            : L10n.format(
                "Imported {1} routines, {2} exercise settings and a plan of {3} blocks.",
                pending.routines.count, pending.settings.count, pending.blocks.count
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
                let names = change.exercises.map { exercise in
                    guard let prescription = change.routine.prescriptionDetails(for: exercise.id) else {
                        return exercise.displayName
                    }
                    var detail = scheme(prescription.scheme)
                    if let rest = prescription.restSeconds {
                        detail += " · " + L10n.format("rest {1}", format.minutesAndSeconds(rest))
                    }
                    return "\(exercise.displayName) (\(detail))"
                }.joined(separator: ", ")
                return RoutineRow(
                    id: change.routine.id,
                    name: change.routine.name,
                    detail: change.routine.focus.map { "\($0.displayName) · \(names)" } ?? names,
                    isUpdate: change.isUpdate
                )
            },
            settings: planned.settings.map { change in
                SettingsRow(id: change.exercise.id, exercise: change.exercise.displayName,
                            detail: detail(of: change.settings), isUpdate: change.isUpdate)
            },
            blocks: planned.blocks.enumerated().map { index, block in
                BlockRow(id: index, name: block.name ?? block.focus.displayName, detail: detail(of: block))
            },
            issues: planned.issues.map(text),
            warnings: planned.warnings.map(text),
            correction: planned.issues.isEmpty && planned.warnings.isEmpty
                ? nil : PlanImporter.correctionPrompt(for: planned.issues, warnings: planned.warnings),
            canImport: planned.canImport
        )
    }

    /// Names of the routines a block can rotate through: the app's and the plan's.
    private var routineNames: [UUID: String] = [:]

    private func detail(of block: TrainingBlock) -> String {
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let start = block.start.startDate(in: calendar).formatted(style.day().month(.abbreviated).year())
        var parts = [L10n.format("{1} weeks from {2}", block.plannedWeeks ?? 0, start)]
        if !block.routineIDs.isEmpty {
            let sessions = block.plannedSessionsPerWeek
            let schedule = sessions == 1
                ? L10n.text("1 session per week") : L10n.format("{1} sessions per week", sessions)
            parts.append(schedule)
        }
        if block.name != nil {
            parts.insert(block.focus.displayName, at: 0)
        }
        let names = block.routineIDs.compactMap { routineNames[$0] }
        if !names.isEmpty {
            parts.append(names.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func detail(of settings: ProgressionSettings) -> String {
        var parts: [String] = []
        if let focus = settings.focus {
            parts.append(focus.displayName)
        }
        parts.append(scheme(settings.scheme))
        if settings.incrementKg > 0 {
            parts.append("+" + format.weight(settings.incrementKg))
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
        case let .unreducedDeload(block):
            L10n.format(
                "Deload “{1}” has no reduction in weekly working sets or RPE compared with the previous block.", block
            )
        case let .sessionDuration(routine, minutes, limit):
            L10n.format(
                "“{1}” takes about {2} min including rests. Your limit is {3} min.", routine, minutes, limit
            )
        case let .weeklyVolume(block, muscle, sets, guide):
            L10n.format("“{1}” reaches {2} weekly fractional sets for {3}. The guide is {4}.",
                        block, format.number(sets), muscle.displayName, format.number(guide))
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
        case let .unknownRoutine(name):
            L10n.format("A block uses the routine “{1}”, which is not in the plan or in your routines.", name)
        case let .prescriptionOutsideRoutine(routine, exercise):
            L10n.format("Routine “{1}” gives sets and reps for “{2}”, which it does not include.", routine, exercise)
        }
    }
}

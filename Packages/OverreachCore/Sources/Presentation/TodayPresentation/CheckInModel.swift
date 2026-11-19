import Domain
import Foundation
import Observation
import PresentationKit

/// The daily check-in sheet (about 10 seconds): sick, energy, soreness and a note. It feeds the readiness light
/// (`readiness-subjective`, `illness-return` in `docs/evidence.md`). Opened from Today, which reloads after saving.
@MainActor
@Observable
public final class CheckInModel: Identifiable {
    public var isSick: Bool
    /// 1 (exhausted) … 5 (great); `nil` = not answered.
    public var energy: Int?
    /// 0 (none) … 3 (very sore); `nil` = not answered.
    public var soreness: Int?
    public var note: String
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    public let day: CalendarDay
    private let original: CheckIn?
    private let checkIns: any CheckInRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date

    public init(
        day: CalendarDay, existing: CheckIn?, checkIns: any CheckInRepository, backup: (any BackupService)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.day = day
        self.original = existing
        self.isSick = existing?.isSick ?? false
        self.energy = existing?.energy
        self.soreness = existing?.soreness
        self.note = existing?.note ?? ""
        self.checkIns = checkIns
        self.backup = backup
        self.clock = clock
    }

    public var energyOptions: [Option<Int>] {
        [
            Option(value: 1, name: L10n.text("Exhausted")),
            Option(value: 2, name: L10n.text("Tired")),
            Option(value: 3, name: L10n.text("So-so")),
            Option(value: 4, name: L10n.text("Good")),
            Option(value: 5, name: L10n.text("Great")),
        ]
    }

    public var sorenessOptions: [Option<Int>] {
        [
            Option(value: 0, name: L10n.text("Not sore")),
            Option(value: 1, name: L10n.text("Mild")),
            Option(value: 2, name: L10n.text("Sore")),
            Option(value: 3, name: L10n.text("Very sore")),
        ]
    }

    /// The check-in as it would be saved.
    public var draft: CheckIn {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return CheckIn(
            day: day, isSick: isSick, energy: energy, soreness: soreness, note: trimmed.isEmpty ? nil : trimmed
        )
    }

    /// Something to save: a changed check-in, or a first one with at least one answer.
    public var canSave: Bool {
        guard !isSaving else { return false }
        if let original { return draft != original }
        return isSick || energy != nil || soreness != nil || draft.note != nil
    }

    /// Saves and returns `true`; on failure keeps the sheet open with `errorMessage`.
    public func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await checkIns.save(draft)
            errorMessage = nil
            await backup?.backUpIfConfigured(now: clock())
            return true
        } catch {
            errorMessage = L10n.text("Could not save your check-in.")
            return false
        }
    }
}

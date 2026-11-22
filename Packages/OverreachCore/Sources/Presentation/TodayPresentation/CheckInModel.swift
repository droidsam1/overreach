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
    public var hasExerciseWarningSigns: Bool
    /// 1 (exhausted) … 5 (great); `nil` = not answered.
    public var energy: Int?
    /// 0 (none) … 3 (very sore); `nil` = not answered.
    public var soreness: Int?
    public var note: String
    public var contextAnswer: CheckIn.Context.Answer?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    public let day: CalendarDay
    private let original: CheckIn?
    private let contextQuestion: CheckIn.Context.Question?
    private let checkIns: any CheckInRepository
    private let backup: (any BackupService)?
    private let clock: @Sendable () -> Date

    public init(
        day: CalendarDay, existing: CheckIn?, checkIns: any CheckInRepository, backup: (any BackupService)? = nil,
        contextQuestion: CheckIn.Context.Question? = nil, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.day = day
        self.original = existing
        self.contextQuestion = existing?.context?.question ?? contextQuestion
        self.contextAnswer = existing?.context?.answer
        self.isSick = existing?.isSick ?? false
        self.hasExerciseWarningSigns = existing?.exerciseWarningSigns ?? false
        self.energy = existing?.energy
        self.soreness = existing?.soreness
        self.note = existing?.note ?? ""
        self.checkIns = checkIns
        self.backup = backup
        self.clock = clock
    }

    public var contextQuestionTitle: String? { Self.title(for: contextQuestion) }

    static func title(for question: CheckIn.Context.Question?) -> String? {
        switch question {
        case .symptoms: L10n.text("Do new symptoms make you feel too unwell to train today?")
        case .stress: L10n.text("Have you felt more stressed than usual lately?")
        case .fatigue: L10n.text("Do you feel more fatigued than usual today?")
        case .runningPain: L10n.text("Did the pain get worse or change your stride on your last run?")
        case nil: nil
        }
    }

    public var contextOptions: [Option<CheckIn.Context.Answer>] {
        [
            Option(value: .yes, name: L10n.text("Yes")),
            Option(value: .no, name: contextQuestion == .symptoms
                ? L10n.text("No symptoms affecting training") : L10n.text("No")),
            Option(value: .unsure, name: L10n.text("Not sure")),
            Option(value: .skipped, name: L10n.text("Skip for today")),
        ]
    }

    public var energyOptions: [Option<Int>] { Self.energyScale }

    /// The feeling scale, 1 (exhausted) … 5 (great); shared with the one-tap prompt on Today.
    static var energyScale: [Option<Int>] {
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
        let context = contextQuestion.flatMap { question in
            contextAnswer.map { CheckIn.Context(question: question, answer: $0) }
        }
        let warningSigns: Bool? = if hasExerciseWarningSigns || original?.exerciseWarningSigns != nil {
            hasExerciseWarningSigns
        } else {
            nil
        }
        return CheckIn(
            day: day, isSick: isSick, energy: energy, soreness: soreness, note: trimmed.isEmpty ? nil : trimmed,
            context: context, exerciseWarningSigns: warningSigns
        )
    }

    /// Something to save: a changed check-in, or a first one with at least one answer.
    public var canSave: Bool {
        guard !isSaving else { return false }
        if let original { return draft != original }
        return isSick || hasExerciseWarningSigns || energy != nil || soreness != nil
            || draft.note != nil || draft.context != nil
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

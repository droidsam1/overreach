import Analytics
import Domain
import Foundation
import PresentationKit

public struct StrengthOption: Hashable, Sendable {
    public struct ExerciseRow: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let title: String
        public let reference: String
        public let suggestion: String
    }

    public let heading: String?
    public let exerciseRows: [ExerciseRow]
    public let guidance: String
    public let evidence: String

    static func make(
        routine: Routine?, isDated: Bool, sessions: [StrengthSession], exercises: [Exercise],
        settings: [UUID: ProgressionSettings], historyStart: Date, familiarityStart: Date
    ) -> StrengthOption {
        let context = StrengthOptionContext(
            progressionSessions: sessions.filter { $0.startedAt >= historyStart },
            exercises: exercises, settings: settings, familiarityStart: familiarityStart
        )
        if let routine {
            let rows = Array(routine.exerciseIDs.lazy.compactMap { context.row(for: $0, routine: routine) }
                .prefix(EasyStrengthAdjustment.maximumExercises))
            if isDated { return option(heading: nil, rows: rows, isDated: true) }
            if !rows.isEmpty {
                return option(heading: L10n.format("Up next in your plan · {1}", routine.name), rows: rows)
            }
        }
        // Pick a recent session with enough recorded work to offer a familiar alternative.
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) where session.startedAt >= familiarityStart {
            var seen: Set<UUID> = []
            let entries = session.entries.filter { seen.insert($0.exerciseID).inserted }
            let rows = Array(entries.lazy.compactMap {
                context.row(for: $0.exerciseID, previous: session)
            }.prefix(EasyStrengthAdjustment.maximumExercises))
            if !rows.isEmpty {
                return option(heading: L10n.format("Based on a recent session · {1}", session.name), rows: rows)
            }
        }
        return option(heading: nil, rows: [])
    }

    private static func option(heading: String?, rows: [ExerciseRow], isDated: Bool = false) -> StrengthOption {
        let guidance: String
        if rows.isEmpty && isDated {
            guidance = L10n.text(
                "Use familiar exercises from this routine and finish each set with at least four reps left."
            )
        } else if rows.isEmpty {
            guidance = L10n.text("Choose a familiar exercise and a light load. Finish each set with at least four reps left.")
        } else {
            guidance = L10n.text("Use a lighter load or an easier version if you need it to keep the effort light.")
        }
        return StrengthOption(heading: heading, exerciseRows: rows, guidance: guidance,
                              evidence: EasyStrengthAdjustment.evidence.level.displayName)
    }
}

private struct StrengthOptionContext {
    let progressionSessions: [StrengthSession]
    let exercises: [Exercise]
    let settings: [UUID: ProgressionSettings]
    let familiarityStart: Date

    func row(for id: UUID, routine: Routine) -> StrengthOption.ExerciseRow? {
        guard let exercise = exercises.first(where: { $0.id == id }) else { return nil }
        let history = ExerciseExposure.history(of: id, in: progressionSessions)
        guard let recent = history.last, recent.date >= familiarityStart else { return nil }
        let stored = settings[id]
        let resolved = ProgressionTargets.settings(for: exercise, stored: stored, focus: stored?.focus ?? routine.focus,
                                                   prescription: routine.prescription(for: id))
        let target = ProgressionTargets.next(history: history, settings: resolved)
        return row(exercise: exercise, referenceReps: target.sets.map(\.reps), referenceRPE: resolved.scheme.targetRPE,
                   recent: recent, fromPlan: true)
    }

    func row(for id: UUID, previous: StrengthSession) -> StrengthOption.ExerciseRow? {
        guard let exercise = exercises.first(where: { $0.id == id }),
              let exposure = ExerciseExposure.history(of: id, in: [previous]).last else { return nil }
        let reps = exposure.sets.compactMap(\.reps)
        let easiest = exposure.sets.compactMap(\.rpe).filter(\.isFinite).min()
        return row(exercise: exercise, referenceReps: reps, referenceRPE: easiest, recent: exposure, fromPlan: false)
    }

    private func row(
        exercise: Exercise, referenceReps: [Int], referenceRPE: Double?, recent: ExerciseExposure, fromPlan: Bool
    ) -> StrengthOption.ExerciseRow? {
        guard let adjustment = EasyStrengthAdjustment.suggest(referenceReps: referenceReps, referenceRPE: referenceRPE,
                                                              recent: recent) else { return nil }
        let range = adjustment.referenceReps
        let reps = range.lowerBound == range.upperBound ? String(range.lowerBound) : "\(range.lowerBound)–\(range.upperBound)"
        let count = String(adjustment.referenceSets)
        let reference = fromPlan ? L10n.format("Usual target · {1} × {2}", count, reps)
            : L10n.format("Last session · {1} × {2}", count, reps)
        return StrengthOption.ExerciseRow(
            id: exercise.id, title: exercise.name, reference: reference,
            suggestion: L10n.format("Easy option · {1} × {2}, with at least {3} reps left",
                                    String(adjustment.sets), String(adjustment.reps), String(adjustment.repsInReserve))
        )
    }
}

import Analytics
import Domain
import Foundation
import PresentationKit

/// A workout the athlete can say they will do next (Today, when there is no plan).
public struct StrengthChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public var isSelected = false
}

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

    /// The workout the example is based on when there is no plan: the next one of a detected rotation, or the one
    /// the athlete chose.
    enum Basis: Hashable {
        case rotation(SessionRotation.Slot)
        case chosen(SessionRotation.Slot)

        var slot: SessionRotation.Slot {
            switch self {
            case let .rotation(slot), let .chosen(slot): slot
            }
        }
    }

    static func make(
        routine: Routine?, isDated: Bool, sessions: [StrengthSession], exercises: [Exercise],
        settings: [UUID: ProgressionSettings], historyStart: Date, familiarityStart: Date, format: Format,
        basis: Basis? = nil
    ) -> StrengthOption {
        let context = StrengthOptionContext(
            progressionSessions: sessions.filter { $0.startedAt >= historyStart },
            exercises: exercises, settings: settings, familiarityStart: familiarityStart, format: format
        )
        if let routine {
            let rows = Array(routine.exerciseIDs.lazy.compactMap { context.row(for: $0, routine: routine) }
                .prefix(EasyStrengthAdjustment.maximumExercises))
            if isDated { return option(heading: nil, rows: rows, isDated: true) }
            if !rows.isEmpty {
                return option(heading: L10n.format("Up next in your plan · {1}", routine.name), rows: rows)
            }
        }
        if let basis, let session = sessions.filter({
            $0.startedAt >= familiarityStart && SessionRotation.slot(for: $0).id == basis.slot.id
        })
            .max(by: { $0.startedAt < $1.startedAt }) {
            var seen: Set<UUID> = []
            let entries = session.entries.filter { seen.insert($0.exerciseID).inserted }
            let rows = Array(entries.lazy.compactMap {
                context.row(for: $0.exerciseID, previous: session)
            }.prefix(EasyStrengthAdjustment.maximumExercises))
            if !rows.isEmpty {
                let heading = switch basis {
                case .rotation: L10n.format("Next in your rotation · {1}", session.name)
                case .chosen: L10n.format("Your choice · {1}", session.name)
                }
                return option(heading: heading, rows: rows)
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
    let format: Format

    func row(for id: UUID, routine: Routine) -> StrengthOption.ExerciseRow? {
        guard let exercise = exercises.first(where: { $0.id == id }) else { return nil }
        let history = ExerciseExposure.history(of: id, in: progressionSessions)
        guard let recent = history.last, recent.date >= familiarityStart else { return nil }
        let stored = settings[id]
        let resolved = ProgressionTargets.settings(
            for: exercise, stored: stored, focus: stored?.focus ?? routine.focus,
            prescription: routine.prescription(for: id), weightUnit: format.weightUnit
        )
        let target = ProgressionTargets.next(history: history, settings: resolved, weightUnit: format.weightUnit)
        return row(exercise: exercise, referenceSets: target.sets, recent: recent, history: history, fromPlan: true)
    }

    func row(for id: UUID, previous: StrengthSession) -> StrengthOption.ExerciseRow? {
        guard let exercise = exercises.first(where: { $0.id == id }),
              let exposure = ExerciseExposure.history(of: id, in: [previous]).last else { return nil }
        let easiest = exposure.sets.compactMap(\.rpe).filter(\.isFinite).min()
        let sets = exposure.sets.compactMap { set in
            set.reps.map { PlannedSet(weightKg: set.weightKg, reps: $0, targetRPE: easiest ?? 6) }
        }
        let history = ExerciseExposure.history(of: id, in: progressionSessions)
        return row(exercise: exercise, referenceSets: sets, recent: exposure, history: history, fromPlan: false)
    }

    private func row(
        exercise: Exercise, referenceSets: [PlannedSet], recent: ExerciseExposure, history: [ExerciseExposure],
        fromPlan: Bool
    ) -> StrengthOption.ExerciseRow? {
        guard let adjustment = EasyStrengthAdjustment.suggest(
            referenceReps: referenceSets.map(\.reps), referenceRPE: referenceSets.map(\.targetRPE).min(), recent: recent
        ) else { return nil }
        let range = adjustment.referenceReps
        let reps = range.lowerBound == range.upperBound ? String(range.lowerBound) : "\(range.lowerBound)–\(range.upperBound)"
        let count = String(adjustment.referenceSets)
        let weights = referenceSets.compactMap(\.weightKg).filter { $0.isFinite && $0 > 0 }
        let referenceLoad = weights.count == referenceSets.count ? weights.min() : nil
        var reference = fromPlan ? L10n.format("Usual target · {1} × {2}", count, reps)
            : L10n.format("Last session · {1} × {2}", count, reps)
        if let lower = referenceLoad, let upper = weights.max() {
            let load = lower == upper ? format.weight(lower)
                : "\(format.weightNumber(lower))–\(format.weight(upper))"
            reference = L10n.format("{1} at {2}", reference, load)
        }
        let easyLoad = adjustment.startingLoad(referenceLoadKg: referenceLoad, recent: history.filter {
            $0.date >= familiarityStart
        })
        let sets = String(adjustment.sets)
        let easyReps = String(adjustment.reps)
        let reserve = String(adjustment.repsInReserve)
        let suggestion = if let easyLoad {
            L10n.format("Easy option · {1} × {2}, start at {3} with at least {4} reps left",
                        sets, easyReps, format.weight(easyLoad), reserve)
        } else {
            L10n.format("Easy option · {1} × {2}, with at least {3} reps left", sets, easyReps, reserve)
        }
        return StrengthOption.ExerciseRow(
            id: exercise.id, title: exercise.displayName, reference: reference, suggestion: suggestion
        )
    }
}

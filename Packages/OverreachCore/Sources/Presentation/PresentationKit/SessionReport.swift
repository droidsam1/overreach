import Analytics
import Domain
import Foundation

/// What the app says about a finished session (right after finishing it, or later from History): totals, plan adherence, records and what comes
/// next. Facts from `SessionReviewer`; no advice beyond the engine's next targets.
public struct SessionReport: Identifiable, Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case above, onTarget, below, unfinished, noTarget
    }

    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        public let outcome: Outcome
        /// "Above target: 75 kg × 10/10/9 vs 9/9/9".
        public let outcomeText: String
        /// Effort, record, status change and next target, one line each.
        public let details: [String]
    }

    public let id: UUID
    public let title: String
    /// "58 min · 18 working sets · 6240 kg".
    public let headline: String
    /// "On target or better in 4 of 5 exercises."
    public let adherence: String?
    /// "Volume +6 % compared with the last “Push A” (12 Nov)."
    public let comparison: String?
    /// "Effective sets: Chest 6 · Triceps 3".
    public let muscles: String?
    public let rows: [Row]
    /// The same summary as plain text, to discuss it with an AI assistant.
    public let shareText: String
}

extension SessionReport {
    public init(review: SessionReview, effortScale: EffortScale, format: Format) {
        let session = review.session
        let minutes = Int(((session.durationSeconds ?? 0) / 60).rounded())
        let headline = L10n.format(
            "{1} min · {2} working sets · {3}", minutes, review.workingSets,
            format.number(review.tonnageKg, maxFractionDigits: 0) + " kg"
        )
        let adherence = review.exercisesWithTarget == 0 ? nil : L10n.format(
            "On target or better in {1} of {2} exercises.", review.exercisesOnTarget, review.exercisesWithTarget
        )
        var comparison: String?
        if let previous = review.previous, let before = review.previousTonnageKg, before > 0 {
            let change = (review.tonnageKg - before) / before * 100
            let sign = change >= 0 ? "+" : "−"
            comparison = L10n.format(
                "Volume {1} compared with the last “{2}” ({3}).",
                sign + format.number(abs(change), maxFractionDigits: 0) + " %", previous.name,
                previous.startedAt.formatted(.dateTime.day().month(.abbreviated).locale(format.locale))
            )
        }
        let sets = review.effectiveSets
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .map { "\($0.key.displayName) \(format.number($0.value, maxFractionDigits: 1))" }
        let rows = review.exercises.map { Self.row($0, effortScale: effortScale, format: format) }
        let muscles = sets.isEmpty ? nil : L10n.format("Effective sets: {1}", sets.joined(separator: " · "))

        var share = [session.name, headline]
        share += [adherence, comparison, muscles].compactMap { $0 }
        for row in rows {
            share.append("• \(row.name): \(row.outcomeText)")
            share += row.details.map { "  – \($0)" }
        }
        self.init(
            id: session.id, title: session.name, headline: headline, adherence: adherence, comparison: comparison,
            muscles: muscles, rows: rows, shareText: share.joined(separator: "\n")
        )
    }

    private static func row(_ review: ExerciseReview, effortScale: EffortScale, format: Format) -> Row {
        let done = setsText(weight: review.done.workingWeightKg, reps: review.done.sets.compactMap(\.reps),
                            format: format)
        let planned = review.target.map { target in
            setsText(weight: target.sets.first?.weightKg ?? 0, reps: target.sets.map(\.reps), format: format)
        } ?? "–"
        let outcome: Outcome
        let outcomeText: String
        switch review.outcome {
        case .exceeded:
            outcome = .above
            outcomeText = L10n.format("Above target: {1} vs {2}", done, planned)
        case .met:
            outcome = .onTarget
            outcomeText = L10n.format("On target: {1}", done)
        case .below:
            outcome = .below
            outcomeText = L10n.format("Below target: {1} vs {2}", done, planned)
        case .unfinished:
            outcome = .unfinished
            outcomeText = L10n.text("Unfinished: not counted for progression")
        case .noTarget:
            outcome = .noTarget
            outcomeText = L10n.format("Done: {1}", done)
        }
        return Row(
            id: review.exercise.id, name: review.exercise.name, outcome: outcome, outcomeText: outcomeText,
            details: details(of: review, effortScale: effortScale, format: format)
        )
    }

    private static func details(of review: ExerciseReview, effortScale: EffortScale, format: Format) -> [String] {
        var lines: [String] = []
        if let average = review.averageRPE, let planned = review.target?.sets.first?.targetRPE {
            let rounded = (average * 2).rounded() / 2
            if average - planned >= 1 {
                lines.append(L10n.format(
                    "Harder than planned: {1} vs {2}.", effortScale.text(rpe: rounded, format: format),
                    effortScale.text(rpe: planned, format: format)
                ))
            } else if planned - average >= 1 {
                lines.append(L10n.format(
                    "Easier than planned: {1} vs {2}.", effortScale.text(rpe: rounded, format: format),
                    effortScale.text(rpe: planned, format: format)
                ))
            }
        }
        switch review.record {
        case let .estimatedOneRepMax(kg, previous):
            lines.append(L10n.format(
                "New best estimated 1RM: {1} (before {2}).", format.kilograms((kg * 10).rounded() / 10),
                format.kilograms((previous * 10).rounded() / 10)
            ))
        case let .repsAtWeight(weight, reps, previous):
            lines.append(L10n.format(
                "Most reps ever with {1}: {2} (before {3}).", format.kilograms(weight), reps, previous
            ))
        case nil:
            break
        }
        if review.statusAfter.isStalled && !review.statusBefore.isStalled {
            lines.append(L10n.text("Now stalled: next time, open its target to see why and what to try."))
        } else if review.statusBefore.isStalled && review.statusAfter == .progressing {
            lines.append(L10n.text("No longer stalled."))
        }
        if review.outcome != .unfinished, let first = review.nextTarget.sets.first {
            let next = setsText(weight: first.weightKg ?? 0, reps: review.nextTarget.sets.map(\.reps), format: format)
            lines.append(L10n.format(
                "Next time: {1} @ {2}.", next, effortScale.text(rpe: first.targetRPE, format: format)
            ))
        }
        return lines
    }

    /// "75 kg × 10/10/9", or "10/10/9" without load.
    private static func setsText(weight: Double, reps: [Int], format: Format) -> String {
        let repsText = reps.map(String.init).joined(separator: "/")
        return weight > 0 ? "\(format.kilograms(weight)) × \(repsText)" : repsText
    }
}

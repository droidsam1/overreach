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
    public let duration: String?
    public let workingSets: Int?
    public let volume: String?
    /// "On target or better in 4 of 5 exercises."
    public let adherence: String?
    /// "Volume +6 % compared with the last “Push A” (12 Nov)."
    public let comparison: String?
    /// "Effective sets: Chest 6 · Triceps 3".
    public let muscles: String?
    /// Every record of the session, in exercise order: "Bench Press: New best estimated 1RM: 82.5 kg (before 80 kg).".
    /// Empty without one. Only real records against the athlete's own history, never streaks, points or badges.
    public let achievements: [String]
    public let rows: [Row]
    /// The same summary as plain text, to discuss it with an AI assistant.
    public let shareText: String
}

extension SessionReport {
    public init(review: SessionReview, effortScale: EffortScale, format: Format) {
        let session = review.session
        let minutes = Self.durationMinutes(session.durationSeconds)
        let volume = format.weight(review.tonnageKg, maxFractionDigits: 0)
        let headline = L10n.format(
            "{1} min · {2} working sets · {3}", minutes ?? 0, review.workingSets, volume
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
        let achievements = review.exercises.flatMap { exercise in
            exercise.records.map { "\(exercise.exercise.displayName): \(Self.recordText($0, format: format))" }
        }
        self.init(
            id: session.id, title: session.name, headline: headline,
            duration: minutes.map { L10n.format("{1} min", $0) },
            workingSets: review.workingSets > 0 ? review.workingSets : nil,
            volume: review.tonnageKg > 0 ? volume : nil, adherence: adherence, comparison: comparison,
            muscles: muscles, achievements: achievements, rows: rows, shareText: share.joined(separator: "\n")
        )
    }

    public static func durationText(_ seconds: Double?) -> String? {
        durationMinutes(seconds).map { L10n.format("{1} min", $0) }
    }

    private static func durationMinutes(_ seconds: Double?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        return Int(exactly: (seconds / 60).rounded())
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
            id: review.exercise.id, name: review.exercise.displayName, outcome: outcome, outcomeText: outcomeText,
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
        lines += review.records.map { recordText($0, format: format) }
        if review.statusAfter.isStalled && !review.statusBefore.isStalled {
            lines.append(L10n.text("Now stalled: next time, open its target to see why and what to try."))
        } else if review.statusBefore.isStalled && review.statusAfter == .progressing {
            lines.append(L10n.text("No longer stalled."))
        }
        if review.outcome != .unfinished, let first = review.nextTarget.sets.first {
            let sets = review.nextTarget.sets
            let next = sets.contains { $0.weightKg != first.weightKg }
                ? format.groupedSets(sets)
                : setsText(weight: first.weightKg ?? 0, reps: sets.map(\.reps), format: format)
            lines.append(L10n.format(
                "Next time: {1} @ {2}.", next, effortScale.text(rpe: first.targetRPE, format: format)
            ))
        }
        return lines
    }

    private static func recordText(_ record: SessionRecord, format: Format) -> String {
        switch record {
        case let .estimatedOneRepMax(kg, previous):
            L10n.format(
                "New best estimated 1RM: {1} (before {2}).", format.weight((kg * 10).rounded() / 10),
                format.weight((previous * 10).rounded() / 10)
            )
        case let .repsAtWeight(weight, reps, previous):
            L10n.format("Most reps ever with {1}: {2} (before {3}).", format.weight(weight), reps, previous)
        case let .volume(kg, previous):
            L10n.format(
                "Most volume ever in one session: {1} (before {2}).",
                format.weight(kg, maxFractionDigits: 0), format.weight(previous, maxFractionDigits: 0)
            )
        }
    }

    /// "75 kg × 10/10/9", or "10/10/9" without load.
    private static func setsText(weight: Double, reps: [Int], format: Format) -> String {
        let repsText = reps.map(String.init).joined(separator: "/")
        return weight > 0 ? "\(format.weight(weight)) × \(repsText)" : repsText
    }
}

extension Format {
    /// Group adjacent identical prescriptions so mixed loads and reps remain visible in logging order.
    public func groupedSets(_ sets: [PlannedSet]) -> String {
        var groups: [(set: PlannedSet, count: Int)] = []
        for set in sets {
            if groups.last?.set == set {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((set, 1))
            }
        }
        return groups.map { set, count in
            if let weight = set.weightKg, weight > 0 {
                return L10n.format("{1} × {2} at {3}", count, set.reps, self.weight(weight))
            }
            return L10n.format("{1} × {2} reps", count, set.reps)
        }.joined(separator: " · ")
    }
}

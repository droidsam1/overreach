import Foundation

/// Why an edited session cannot be saved as it is.
public enum SessionEditIssue: Hashable, Sendable {
    /// The name is empty.
    case missingName
    /// No set with any value is left. Delete the session instead.
    case noSets
    /// The end time is before the start time.
    case endsBeforeStart
    /// A set has a negative weight or reps, or an RPE outside 1–10.
    case invalidValues
}

extension WorkoutSet {
    /// Whether the set records anything (weight, reps, time or distance). Empty sets are dropped on save.
    public var hasValues: Bool {
        weightKg != nil || reps != nil || durationSeconds != nil || distanceMeters != nil
    }

    /// Whether the values that are present are plausible.
    public var hasValidValues: Bool {
        (weightKg ?? 0) >= 0 && (reps ?? 0) >= 0 && (durationSeconds ?? 0) >= 0 && (distanceMeters ?? 0) >= 0
            && (rpe.map { (1...10).contains($0) } ?? true)
    }
}

extension StrengthSession {
    /// The session moved to `newStart`, keeping its duration and the relative times of its sets.
    public func movingStart(to newStart: Date) -> StrengthSession {
        let delta = newStart.timeIntervalSince(startedAt)
        var moved = self
        moved.startedAt = newStart
        moved.endedAt = endedAt?.addingTimeInterval(delta)
        for entryIndex in moved.entries.indices {
            for setIndex in moved.entries[entryIndex].sets.indices {
                moved.entries[entryIndex].sets[setIndex].completedAt =
                    moved.entries[entryIndex].sets[setIndex].completedAt?.addingTimeInterval(delta)
            }
        }
        return moved
    }

    /// The session as it would be saved after editing: trimmed texts (empty notes become `nil`), sets without
    /// any value removed, and exercises left without sets removed.
    public func cleanedForSaving() -> StrengthSession {
        var cleaned = self
        cleaned.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.notes = Self.trimmedOrNil(notes)
        cleaned.entries = entries.compactMap { entry in
            var entry = entry
            entry.sets = entry.sets.filter(\.hasValues)
            entry.notes = Self.trimmedOrNil(entry.notes)
            return entry.sets.isEmpty ? nil : entry
        }
        return cleaned
    }

    /// What prevents saving the session after `cleanedForSaving()`. Empty when it can be saved.
    public var editIssues: [SessionEditIssue] {
        let cleaned = cleanedForSaving()
        var issues: [SessionEditIssue] = []
        if cleaned.name.isEmpty { issues.append(.missingName) }
        if cleaned.entries.isEmpty { issues.append(.noSets) }
        if let endedAt, endedAt < startedAt { issues.append(.endsBeforeStart) }
        if cleaned.entries.contains(where: { $0.sets.contains { !$0.hasValidValues } }) {
            issues.append(.invalidValues)
        }
        return issues
    }

    private static func trimmedOrNil(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
